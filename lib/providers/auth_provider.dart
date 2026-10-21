import 'package:flutter/foundation.dart';
import '../services/hwid_service.dart';

/// Provider for HWID authentication and premium status
class AuthProvider extends ChangeNotifier {
  AuthProvider({HwidService? hwidService})
    : _hwidService = hwidService ?? HwidService();

  final HwidService _hwidService;
  Future<void>? _pendingInitialization;
  bool _hasPremiumStatus = false;

  String _hwid = '';
  bool _isPremium = false;
  DateTime? _premiumExpiresAt;
  bool _isPremiumExpired = false;
  bool _isLoading = true;
  String _error = '';

  String get hwid => _hwid;
  bool get isPremium => _isPremium;
  DateTime? get premiumExpiresAt => _premiumExpiresAt;
  bool get isPremiumExpired => _isPremiumExpired;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get hasPremiumStatus => _hasPremiumStatus;
  bool get isAccountVerified => _hasPremiumStatus && _error.isEmpty;
  String get premiumExpiryLabel {
    if (_premiumExpiresAt == null) {
      return _isPremium ? 'Lifetime' : 'Not Premium';
    }
    final month = _premiumExpiresAt!.month.toString().padLeft(2, '0');
    final day = _premiumExpiresAt!.day.toString().padLeft(2, '0');
    return '${_premiumExpiresAt!.year}-$month-$day';
  }

  /// Initialize: get HWID and check premium status
  Future<void> initialize() async {
    if (!_hwidService.usesReliableRequests) return _initialize();
    final pending = _pendingInitialization;
    if (pending != null) return pending;
    final operation = _initialize();
    _pendingInitialization = operation;
    try {
      await operation;
    } finally {
      _pendingInitialization = null;
    }
  }

  Future<void> _initialize() async {
    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      _hwid = await _hwidService.getHwid();
      final premiumStatus = await _hwidService.getPremiumStatus();
      _isPremium = premiumStatus.isPremium;
      _premiumExpiresAt = premiumStatus.expiresAt;
      _isPremiumExpired = premiumStatus.isExpired;
      _hasPremiumStatus = true;
    } catch (e) {
      _error = _hwidService.usesReliableRequests
          ? 'Unable to verify account status. Check your connection and retry.'
          : e.toString();
      if (!_hwidService.usesReliableRequests) {
        _isPremium = false;
        _premiumExpiresAt = null;
        _isPremiumExpired = false;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Re-check premium status
  Future<void> refreshPremium() async {
    if (_hwidService.usesReliableRequests) return initialize();
    final premiumStatus = await _hwidService.getPremiumStatus();
    _isPremium = premiumStatus.isPremium;
    _premiumExpiresAt = premiumStatus.expiresAt;
    _isPremiumExpired = premiumStatus.isExpired;
    _hasPremiumStatus = true;
    notifyListeners();
  }
}
