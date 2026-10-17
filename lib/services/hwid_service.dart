import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'api_session_service.dart';

class PremiumStatus {
  final bool isPremium;
  final DateTime? expiresAt;
  final bool isExpired;

  const PremiumStatus({
    required this.isPremium,
    this.expiresAt,
    this.isExpired = false,
  });

  String get expiryLabel {
    if (expiresAt == null) return isPremium ? 'Lifetime' : 'Not Premium';
    return _formatDate(expiresAt!);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

/// Service for HWID generation and premium status checking
class HwidService {
  static const _channel = MethodChannel('com.lokinetwork.mm/hwid');
  static const _fallbackHwidKey = 'fallback_hwid';
  final _apiSession = ApiSessionService.instance;

  /// Gets the device HWID via platform channel (Android ID formatted as XXXX-XXXX-XXXX-XXXX)
  Future<String> getHwid() async {
    try {
      final hwid = await _channel.invokeMethod<String>('getHwid');
      final normalized = _normalizeHwid(hwid);
      if (normalized != null) return normalized;
    } catch (e) {
      // MissingPluginException can happen outside Android or before the
      // platform channel is available, so keep a stable non-zero fallback.
    }
    return _getFallbackHwid();
  }

  /// Fetches the premium HWID list and checks if this device is premium
  Future<bool> checkPremiumStatus() async {
    final status = await getPremiumStatus();
    return status.isPremium;
  }

  /// Fetches the premium HWID list and returns expiry-aware status.
  Future<PremiumStatus> getPremiumStatus() async {
    try {
      final hwid = await getHwid();
      final response = await http.post(
        ApiConfig.uri('/api/v1/auth/status'),
        headers: await _apiSession.authorizedJsonHeaders(hwid),
        body: jsonEncode({'hwid': hwid}),
      );
      if (response.statusCode != 200) {
        return const PremiumStatus(isPremium: false);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return PremiumStatus(
        isPremium: data['premium'] as bool? ?? false,
        expiresAt: _parseExpiryDate(data['expiresAt'] as String? ?? ''),
        isExpired: data['expired'] as bool? ?? false,
      );
    } catch (e) {
      return const PremiumStatus(isPremium: false);
    }
  }

  /// Fetches the raw premium list (for debugging/display)
  Future<List<String>> fetchPremiumList() async {
    return [];
  }

  String? _normalizeHwid(String? value) {
    if (value == null) return null;
    final hex = value
        .replaceAll('-', '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length < 16 || RegExp(r'^0+$').hasMatch(hex)) return null;
    final id = hex.substring(0, 16);
    return '${id.substring(0, 4)}-${id.substring(4, 8)}-'
        '${id.substring(8, 12)}-${id.substring(12, 16)}';
  }

  DateTime? _parseExpiryDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  Future<String> _getFallbackHwid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _normalizeHwid(prefs.getString(_fallbackHwidKey));
      if (existing != null) return existing;

      final generated = _generateFallbackHwid();
      await prefs.setString(_fallbackHwidKey, generated);
      return generated;
    } catch (_) {
      return _generateFallbackHwid();
    }
  }

  String _generateFallbackHwid() {
    final random = Random.secure();
    final hex = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join().toUpperCase();
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-'
        '${hex.substring(8, 12)}-${hex.substring(12, 16)}';
  }
}
