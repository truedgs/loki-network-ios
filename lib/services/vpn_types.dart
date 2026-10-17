import 'dart:async';

/// Connection status enum.
enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

/// Runtime mode for desktop clients.
enum VpnConnectionMode { proxy, tunnel }

/// VPN connection state data.
class VpnStatusData {
  final VpnStatus status;
  final String message;
  final String duration;
  final int uploadSpeed;
  final int downloadSpeed;
  final int upload;
  final int download;

  VpnStatusData({
    required this.status,
    this.message = '',
    this.duration = '00:00:00',
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.upload = 0,
    this.download = 0,
  });
}

abstract class VpnRuntimeService {
  Stream<VpnStatusData> get statusStream;
  VpnStatusData get current;

  Future<void> initialize();
  Future<bool> requestPermission();
  Future<int> getServerDelay(String configJson);
  Future<int> getServerDelayFromLink(String link);
  Future<void> connect(
    String link, {
    VpnConnectionMode mode = VpnConnectionMode.tunnel,
  });
  Future<void> disconnect();
  void dispose();
}
