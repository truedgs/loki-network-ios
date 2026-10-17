import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_session_service.dart';
import 'app_control_service.dart';
import 'hwid_service.dart';

class AnalyticsService {
  static const _platform = MethodChannel('com.lokinetwork.mm/hwid');

  final _hwidService = HwidService();
  final _apiSession = ApiSessionService.instance;

  Future<void> sendDeviceHeartbeat() async {
    try {
      final hwid = await _hwidService.getHwid();
      final deviceInfo = await _getDeviceInfo();

      await http
          .post(
            ApiConfig.uri('/api/v1/devices/heartbeat'),
            headers: await _apiSession.authorizedJsonHeaders(hwid),
            body: jsonEncode({
              'hwid': hwid,
              'platform': platformName(),
              'appVersion': ApiConfig.appVersion,
              'manufacturer': deviceInfo['manufacturer'] ?? '',
              'model': deviceInfo['model'] ?? '',
              'sdkVersion': deviceInfo['sdkVersion'] ?? '',
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Analytics must never block app startup or VPN usage.
    }
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    try {
      final raw = await _platform.invokeMapMethod<String, String>(
        'getDeviceInfo',
      );
      if (raw != null) return raw;
    } catch (_) {}

    return {
      'manufacturer': Platform.operatingSystem,
      'model': Platform.localHostname,
      'sdkVersion': Platform.operatingSystemVersion,
    };
  }
}
