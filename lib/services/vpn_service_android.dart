import 'dart:async';
import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'vpn_types.dart';

/// Android implementation backed by flutter_v2ray.
class AndroidVpnService implements VpnRuntimeService {
  final _controller = StreamController<VpnStatusData>.broadcast();
  @override
  Stream<VpnStatusData> get statusStream => _controller.stream;

  FlutterV2ray? _v2ray;
  bool _initialized = false;
  static const int _localSocksPort = 10808;
  static const List<String> _vpnRoutes = ['0.0.0.0/0'];

  VpnStatusData _current = VpnStatusData(status: VpnStatus.disconnected);
  @override
  VpnStatusData get current => _current;

  void _emit(VpnStatusData data) {
    _current = data;
    _controller.add(data);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        final state = status.state.toUpperCase();
        if (state == 'CONNECTED') {
          _emit(
            VpnStatusData(
              status: VpnStatus.connected,
              message: 'Connected',
              duration: status.duration,
              uploadSpeed: status.uploadSpeed,
              downloadSpeed: status.downloadSpeed,
              upload: status.upload,
              download: status.download,
            ),
          );
        } else if (state == 'CONNECTING') {
          _emit(
            VpnStatusData(
              status: VpnStatus.connecting,
              message: 'Connecting...',
            ),
          );
        } else if (state == 'DISCONNECTING') {
          _emit(
            VpnStatusData(
              status: VpnStatus.disconnecting,
              message: 'Disconnecting...',
            ),
          );
        } else {
          _emit(
            VpnStatusData(
              status: VpnStatus.disconnected,
              message: 'Disconnected',
            ),
          );
        }
      },
    );
    await _v2ray!.initializeV2Ray();
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    return await _v2ray!.requestPermission();
  }

  @override
  Future<int> getServerDelay(String configJson) async {
    if (!_initialized) await initialize();
    try {
      return await _v2ray!.getServerDelay(config: configJson);
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<void> connect(
    String link, {
    VpnConnectionMode mode = VpnConnectionMode.tunnel,
  }) async {
    if (!_initialized) await initialize();
    _emit(
      VpnStatusData(status: VpnStatus.connecting, message: 'Connecting...'),
    );
    try {
      final parser = FlutterV2ray.parseFromURL(link);
      final config = _buildVpnConfiguration(parser.getFullConfiguration());
      final hasPermission = await _v2ray!.requestPermission();
      if (!hasPermission) {
        _emit(
          VpnStatusData(
            status: VpnStatus.error,
            message: 'VPN permission denied',
          ),
        );
        return;
      }
      await _v2ray!.startV2Ray(
        remark: parser.remark,
        config: config,
        blockedApps: null,
        bypassSubnets: _vpnRoutes,
        proxyOnly: false,
      );
    } catch (e) {
      _emit(
        VpnStatusData(
          status: VpnStatus.error,
          message: 'Connection failed: $e',
        ),
      );
    }
  }

  @override
  Future<int> getServerDelayFromLink(String link) async {
    if (!_initialized) await initialize();
    if (link.trim().isEmpty) return -1;
    try {
      final parser = FlutterV2ray.parseFromURL(link);
      final config = _buildVpnConfiguration(parser.getFullConfiguration());
      return await _v2ray!.getServerDelay(config: config);
    } catch (_) {
      return -1;
    }
  }

  String _buildVpnConfiguration(String rawConfig) {
    final config = jsonDecode(rawConfig) as Map<String, dynamic>;

    config['dns'] = {
      'servers': ['1.1.1.1', '8.8.8.8'],
    };

    final inbounds = config['inbounds'];
    if (inbounds is List && inbounds.isNotEmpty && inbounds.first is Map) {
      final inbound = Map<String, dynamic>.from(inbounds.first as Map);
      final settings = Map<String, dynamic>.from(
        inbound['settings'] as Map? ?? const {},
      );
      settings['udp'] = true;
      inbound['port'] = _localSocksPort;
      inbound['listen'] = '127.0.0.1';
      inbound['protocol'] = 'socks';
      inbound['settings'] = settings;
      inbounds[0] = inbound;
    }

    config['routing'] = {'domainStrategy': 'IPIfNonMatch', 'rules': []};

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  @override
  Future<void> disconnect() async {
    if (!_initialized) return;
    _emit(
      VpnStatusData(
        status: VpnStatus.disconnecting,
        message: 'Disconnecting...',
      ),
    );
    try {
      _v2ray!.stopV2Ray();
    } catch (e) {
      _emit(
        VpnStatusData(
          status: VpnStatus.error,
          message: 'Disconnect failed: $e',
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
