import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class ApiSessionService {
  ApiSessionService._();

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
    await _load();
    if (_hwid != hwid) {
      await _openSession(hwid);
      return;
    }
    if (_hasFreshAccessToken()) return;
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      try {
        await _refreshSession();
        return;
      } catch (_) {
        await clear();
      }
    }
    await _openSession(hwid);
  }

  Future<void> clear() async {
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
    final response = await http.post(
      ApiConfig.uri('/api/v1/auth/session'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({
        'hwid': hwid,
        'platform': _platformName(),
        'appVersion': ApiConfig.appVersion,
      }),
    );
    if (response.statusCode != 200) {
      throw const ApiSessionException('Unable to open app session');
    }
    await _saveSession(hwid, jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _refreshSession() async {
    final response = await http.post(
      ApiConfig.uri('/api/v1/auth/refresh'),
      headers: ApiConfig.jsonHeaders(),
      body: jsonEncode({'refreshToken': _refreshToken}),
    );
    if (response.statusCode != 200) {
      throw const ApiSessionException('Unable to refresh app session');
    }
    await _saveSession(
      _hwid ?? '',
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _saveSession(String hwid, Map<String, dynamic> json) async {
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

  const ApiSessionException(this.message);

  @override
  String toString() => message;
}
