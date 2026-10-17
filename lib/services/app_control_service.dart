import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_session_service.dart';
import 'hwid_service.dart';

class AppControlService {
  final _hwidService = HwidService();
  final _apiSession = ApiSessionService.instance;

  Future<AppControl> fetchAppControl({String appVersion = ''}) async {
    final hwid = await _hwidService.getHwid();
    final response = await http.post(
      ApiConfig.uri('/api/v1/app-control'),
      headers: await _apiSession.authorizedJsonHeaders(hwid),
      body: jsonEncode({'platform': platformName(), 'appVersion': appVersion}),
    );
    if (response.statusCode != 200) {
      throw const AppControlException();
    }
    return AppControl.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

String platformName() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return Platform.operatingSystem;
}

class AppControl {
  final AppAnnouncement announcement;
  final AppUpdate update;

  const AppControl({required this.announcement, required this.update});

  factory AppControl.fromJson(Map<String, dynamic> json) {
    return AppControl(
      announcement: AppAnnouncement.fromJson(
        json['announcement'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
      update: AppUpdate.fromJson(
        json['update'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
    );
  }
}

class AppAnnouncement {
  final bool enabled;
  final String title;
  final String message;

  const AppAnnouncement({
    required this.enabled,
    required this.title,
    required this.message,
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) {
    return AppAnnouncement(
      enabled: json['enabled'] as bool? ?? false,
      title: json['title'] as String? ?? 'Notice',
      message: json['message'] as String? ?? '',
    );
  }
}

class AppUpdate {
  final bool enabled;
  final String latestVersion;
  final String minVersion;
  final bool required;
  final String url;
  final String message;

  const AppUpdate({
    required this.enabled,
    required this.latestVersion,
    required this.minVersion,
    required this.required,
    required this.url,
    required this.message,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> json) {
    return AppUpdate(
      enabled: json['enabled'] as bool? ?? false,
      latestVersion: json['latestVersion'] as String? ?? '',
      minVersion: json['minVersion'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      url: json['url'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  bool shouldShowFor(String currentVersion) {
    if (!enabled) return false;
    if (required && minVersion.isNotEmpty) {
      return _compareVersions(currentVersion, minVersion) < 0;
    }
    if (latestVersion.isEmpty) return false;
    return _compareVersions(currentVersion, latestVersion) < 0;
  }
}

class AppControlException implements Exception {
  const AppControlException();
}

int _compareVersions(String left, String right) {
  final leftParts = left
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final rightParts = right
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var i = 0; i < length; i++) {
    final leftValue = i < leftParts.length ? leftParts[i] : 0;
    final rightValue = i < rightParts.length ? rightParts[i] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}
