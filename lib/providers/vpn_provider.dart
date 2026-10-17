import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/vpn_service.dart';

/// Provider for VPN connection state management
class VpnProvider extends ChangeNotifier {
  VpnProvider({VpnRuntimeService? vpnService, bool? supportsConnectionModes})
    : _vpnService = vpnService ?? VpnService(),
      supportsConnectionModes = supportsConnectionModes ?? Platform.isWindows {
    _mode = this.supportsConnectionModes
        ? VpnConnectionMode.proxy
        : VpnConnectionMode.tunnel;
  }

  final VpnRuntimeService _vpnService;
  static const _modeKey = 'windows_vpn_connection_mode';
  StreamSubscription<VpnStatusData>? _statusSubscription;
  final bool supportsConnectionModes;

  VpnStatusData _status = VpnStatusData(status: VpnStatus.disconnected);
  VpnConnectionMode _mode = Platform.isWindows
      ? VpnConnectionMode.proxy
      : VpnConnectionMode.tunnel;
  VpnStatusData get status => _status;
  VpnStatus get connectionStatus => _status.status;
  bool get isConnected => _status.status == VpnStatus.connected;
  bool get isConnecting => _status.status == VpnStatus.connecting;
  String get statusMessage => _status.message;
  String get duration => _status.duration;
  int get uploadSpeed => _status.uploadSpeed;
  int get downloadSpeed => _status.downloadSpeed;
  VpnConnectionMode get mode => _mode;
  bool get isProxyMode => _mode == VpnConnectionMode.proxy;
  String get modeLabel => isProxyMode ? 'Proxy Mode' : 'Tunnel Mode';

  String? _currentLink;
  String? get currentLink => _currentLink;

  /// Initialize the VPN service and start listening to status
  Future<void> initialize() async {
    await _loadMode();
    await _vpnService.initialize();
    _statusSubscription = _vpnService.statusStream.listen((data) {
      _status = data;
      notifyListeners();
    });
  }

  Future<void> _loadMode() async {
    if (!supportsConnectionModes) {
      _mode = VpnConnectionMode.tunnel;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getString(_modeKey) ?? prefs.getString('vpn_connection_mode');
    _mode = saved == VpnConnectionMode.tunnel.name
        ? VpnConnectionMode.tunnel
        : VpnConnectionMode.proxy;
  }

  Future<void> setMode(VpnConnectionMode mode) async {
    if (!supportsConnectionModes) return;
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    notifyListeners();
  }

  /// Connect to a server using its V2Ray link
  Future<void> connect(String link) async {
    _currentLink = link;
    await _vpnService.connect(link, mode: _mode);
    notifyListeners();
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    await _vpnService.disconnect();
    _currentLink = null;
    notifyListeners();
  }

  /// Get server delay for a config
  Future<int> getServerDelay(String configJson) async {
    return await _vpnService.getServerDelay(configJson);
  }

  Future<int> getServerDelayFromLink(String link) async {
    return await _vpnService.getServerDelayFromLink(link);
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    _vpnService.dispose();
    super.dispose();
  }
}
