import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/server_model.dart';
import 'api_config.dart';
import 'api_session_service.dart';
import 'config_crypto_service.dart';
import 'hwid_service.dart';

/// Service for fetching and managing VPN server configurations
class ServerService {
  ServerService({ApiSessionService? apiSession, HwidService? hwidService})
    : _apiSession = apiSession ?? ApiSessionService.instance,
      _hwidService = hwidService ?? HwidService(apiSession: apiSession);

  final HwidService _hwidService;
  final ApiSessionService _apiSession;
  bool get usesReliableRequests => _apiSession.usesReliableRequests;
  final _crypto = ConfigCryptoService();

  /// Fetches the full server list from the backend
  Future<ServerListResponse> fetchServers() async {
    try {
      final hwid = await _hwidService.getHwid();
      if (_apiSession.usesReliableRequests) {
        final result = await _apiSession.postRead(hwid, '/api/v1/servers', {
          'hwid': hwid,
        });
        if (result.response.statusCode != 200) {
          throw const ServerServiceException(
            'Unable to load servers. Please retry.',
          );
        }
        final json = jsonDecode(result.response.body) as Map<String, dynamic>;
        if (json['servers'] is! List) {
          throw const ServerServiceException(
            'Invalid server list response. Please retry.',
          );
        }
        return await _parseEncryptedResponse(json, result.configKey);
      }
      final response = await http.post(
        ApiConfig.uri('/api/v1/servers'),
        headers: await _apiSession.authorizedJsonHeaders(hwid),
        body: jsonEncode({'hwid': hwid}),
      );
      if (response.statusCode != 200) {
        throw const ServerServiceException(
          'Server is temporarily unavailable. Please try again later.',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final configKey = await _apiSession.requireConfigKey(hwid);
      return _parseEncryptedResponse(json, configKey);
    } catch (e) {
      if (e is ServerServiceException) rethrow;
      throw const ServerServiceException(
        'Unable to load servers. Check your internet connection and try again.',
      );
    }
  }

  Future<ServerListResponse> _parseEncryptedResponse(
    Map<String, dynamic> json,
    String configKey,
  ) async {
    final rawServers = json['servers'] as List<dynamic>? ?? [];
    final servers = <ServerModel>[];

    for (final raw in rawServers) {
      final serverJson = Map<String, dynamic>.from(raw as Map);
      final encryptedUri = serverJson['encryptedUri'];
      final hasPlainUri = (serverJson['uri'] as String? ?? '').isNotEmpty;
      final locked = serverJson['locked'] as bool? ?? false;

      if (!hasPlainUri && !locked && encryptedUri is Map) {
        serverJson['uri'] = await _crypto.decryptString(
          Map<String, dynamic>.from(encryptedUri),
          configKey,
        );
      }

      servers.add(ServerModel.fromJson(serverJson));
    }

    return ServerListResponse(
      version: json['version'] as int? ?? 2,
      updatedAt: json['updatedAt'] as String? ?? '',
      servers: servers,
    );
  }
}

class ServerServiceException implements Exception {
  final String message;

  const ServerServiceException(this.message);

  @override
  String toString() => message;
}
