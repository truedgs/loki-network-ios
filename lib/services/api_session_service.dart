import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class ApiSessionService {
  ApiSessionService._()
    : _client = http.Client(),
      usesReliableRequests = Platform.isAndroid,
      _requestTimeout = const Duration(seconds: 12),
      _retryDelay = const Duration(milliseconds: 400);

  @visibleForTesting
  ApiSessionService.forTesting({
    required this._client,
    this.usesReliableRequests = true,
    this._requestTimeout = const Duration(seconds: 12),
    this._retryDelay = const Duration(milliseconds: 400),
  });

  final http.Client _client;
  final bool usesReliableRequests;
  final Duration _requestTimeout;
  final Duration _retryDelay;
  Future<void> _sessionQueue = Future<void>.value();

  static final instance = ApiSessionService._();

  static const _accessTokenKey = 'api_access_token';
  static const _refreshTokenKey = 'api_refresh_token';
  static const _configKeyKey = 'api_config_key';
  static const _hwidKey = 'api_session_hwid';

  String? _accessToken;
  String? _refreshToken;
  String? _configKey;
  String? _hwid;
  bool _loaded = false;

  String? get configKey => _configKey;

  Future<Map<String, String>> authorizedJsonHeaders(String hwid) async {
    if (usesReliableRequests) {
      final session = await _credentials(hwid);
      return ApiConfig.jsonHeaders(accessToken: session.accessToken);
    }
    await ensureSession(hwid);
    return ApiConfig.jsonHeaders(accessToken: _accessToken);
  }

  Future<String> requireConfigKey(String hwid) async {
    await ensureSession(hwid);
    final key = _configKey;
    if (key == null || key.isEmpty) {
      throw const ApiSessionException('Missing config decryption key');
    }
    return key;
  }

  Future<void> ensureSession(String hwid) async {
    if (usesReliableRequests) {
      return _serialize(() => _ensureSession(hwid));
    }
    return _ensureSession(hwid);
  }

  Future<void> _ensureSession(String hwid) async {
    await _load();
    if (_hwid != hwid) {
      await _openSession(hwid);
      return;
    }
    if (_hasFreshAccessToken() &&
        (!usesReliableRequests || (_configKey?.isNotEmpty == true))) {
      return;
    }
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      try {
        await _refreshSession();
        return;
      } catch (_) {
        await _clear();
      }
    }
    await _openSession(hwid);
  }

  Future<void> clear() async {
    if (usesReliableRequests) return _serialize(_clear);
    return _clear();
  }

  Future<void> _clear() async {
    _accessToken = null;
    _refreshToken = null;
    _configKey = null;
    _hwid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_configKeyKey);
    await prefs.remove(_hwidKey);
  }

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _configKey = prefs.getString(_configKeyKey);
    _hwid = prefs.getString(_hwidKey);
    _loaded = true;
  }

  Future<void> _openSession(String hwid) async {
    final response = await _post(
      ApiConfig.uri('/api/v1/auth/session'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'hwid': hwid,
        'platform': _platformName(),
        'appVersion': ApiConfig.appVersion,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiSessionException(
        'Unable to open app session',
        response.statusCode,
      );
    }
    await _saveSession(hwid, jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _refreshSession() async {
    final response = await _post(
      ApiConfig.uri('/api/v1/auth/refresh'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({'refreshToken': _refreshToken}),
    );
    if (response.statusCode != 200) {
      throw ApiSessionException(
        'Unable to refresh app session',
        response.statusCode,
      );
    }
    await _saveSession(
      _hwid ?? '',
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _saveSession(String hwid, Map<String, dynamic> json) async {
    if (usesReliableRequests &&
        (json['accessToken'] is! String ||
            (json['accessToken'] as String).isEmpty ||
            json['refreshToken'] is! String ||
            (json['refreshToken'] as String).isEmpty ||
            json['configKey'] is! String ||
            (json['configKey'] as String).isEmpty ||
            (json['hwid'] != null && json['hwid'] != hwid))) {
      throw const ApiSessionException('Invalid app session response');
    }
    _accessToken = json['accessToken'] as String? ?? '';
    _refreshToken = json['refreshToken'] as String? ?? _refreshToken;
    _configKey = json['configKey'] as String? ?? '';
    _hwid = json['hwid'] as String? ?? hwid;

    if (_accessToken!.isEmpty ||
        _refreshToken!.isEmpty ||
        _configKey!.isEmpty) {
      throw const ApiSessionException('Invalid app session response');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, _accessToken!);
    await prefs.setString(_refreshTokenKey, _refreshToken!);
    await prefs.setString(_configKeyKey, _configKey!);
    await prefs.setString(_hwidKey, _hwid!);
  }

  bool _hasFreshAccessToken() {
    final token = _accessToken;
    if (token == null || token.isEmpty) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = payload['exp'] as int? ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return exp - now > 60;
    } catch (_) {
      return false;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _sessionQueue.then((_) => operation());
    _sessionQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<_SessionCredentials> _credentials(
    String hwid, {
    String? rejectedToken,
  }) {
    return _serialize(() async {
      await _load();
      // A concurrent caller may already have rotated this rejected token.
      if (rejectedToken != null && _accessToken == rejectedToken) {
        _accessToken = null;
      }
      await _ensureSession(hwid);
      return _SessionCredentials(_accessToken!, _configKey!);
    });
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    final request = _client.post(uri, headers: headers, body: body);
    return usesReliableRequests ? request.timeout(_requestTimeout) : request;
  }

  /// Android read endpoints only: bounded recovery and a key bound to the JWT
  /// used for this response, even if another request rotates the session.
  Future<SessionResponse> postRead(
    String hwid,
    String path,
    Map<String, dynamic> body,
  ) async {
    String? rejectedToken;
    var recoveredUnauthorized = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final session = await _credentials(hwid, rejectedToken: rejectedToken);
        rejectedToken = null;
        final response = await _post(
          ApiConfig.uri(path),
          headers: ApiConfig.jsonHeaders(accessToken: session.accessToken),
          body: jsonEncode(body),
        );
        if (response.statusCode == 401 &&
            !recoveredUnauthorized &&
            attempt < 2) {
          recoveredUnauthorized = true;
          rejectedToken = session.accessToken;
          continue;
        }
        if (response.statusCode >= 500 && attempt < 2) {
          await Future<void>.delayed(_retryDelay * (attempt + 1));
          continue;
        }
        return SessionResponse(response, session.configKey);
      } catch (error) {
        final retryable =
            error is TimeoutException ||
            error is SocketException ||
            error is http.ClientException ||
            (error is ApiSessionException && (error.statusCode ?? 0) >= 500);
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(_retryDelay * (attempt + 1));
      }
    }
    throw const ApiSessionException('Unable to load account data');
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }
}

class ApiSessionException implements Exception {
  final String message;
  final int? statusCode;

  const ApiSessionException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class _SessionCredentials {
  const _SessionCredentials(this.accessToken, this.configKey);
  final String accessToken;
  final String configKey;
}

class SessionResponse {
  const SessionResponse(this.response, this.configKey);
  final http.Response response;
  final String configKey;
}
