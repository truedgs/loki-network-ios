import 'dart:async';
import 'dart:io';

import 'vpn_service_android.dart';
import 'vpn_service_ios.dart';
import 'vpn_service_windows.dart';
import 'vpn_types.dart';

export 'vpn_types.dart';

/// Public VPN service facade. Android keeps flutter_v2ray; Windows uses
/// flutter_vless full VPN mode so the platform code stays isolated.
class VpnService implements VpnRuntimeService {
  late final VpnRuntimeService _delegate = Platform.isWindows
      ? WindowsVpnService()
      : Platform.isIOS
      ? IosVpnService()
      : AndroidVpnService();

  @override
  Stream<VpnStatusData> get statusStream => _delegate.statusStream;

  @override
  VpnStatusData get current => _delegate.current;

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<bool> requestPermission() => _delegate.requestPermission();

  @override
  Future<int> getServerDelay(String configJson) =>
      _delegate.getServerDelay(configJson);

  @override
  Future<int> getServerDelayFromLink(String link) =>
      _delegate.getServerDelayFromLink(link);

  @override
  Future<void> connect(
    String link, {
    VpnConnectionMode mode = VpnConnectionMode.tunnel,
  }) => _delegate.connect(link, mode: mode);

  @override
  Future<void> disconnect() => _delegate.disconnect();

  @override
  void dispose() => _delegate.dispose();
}
