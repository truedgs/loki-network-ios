import 'dart:async';
import 'dart:convert';

import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_types.dart';

/// iOS implementation backed by flutter_vless.
///
/// Full tunnel mode requires the native XrayTunnel Network Extension target,
/// App Groups, and signing to be configured in Xcode on macOS.
class IosVpnService implements VpnRuntimeService {
  final _controller = StreamController<VpnStatusData>.broadcast();
  @override
  Stream<VpnStatusData> get statusStream => _controller.stream;

  static const _bundleId = 'com.lokinetwork.v2rayVpn';
  static const _appGroupId = 'group.com.lokinetwork.v2rayVpn';
  static const int _localSocksPort = 10808;
  static const Duration _connectTimeout = Duration(seconds: 45);

  FlutterVless? _vless;
  bool _initialized = false;
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
    _vless = FlutterVless(
      onStatusChanged: (status) {
        switch (status.connectionState) {
          case VlessConnectionState.connected:
            _emit(
              VpnStatusData(
                status: VpnStatus.connected,
                message: 'Connected',
                duration: _formatDuration(status.duration),
                uploadSpeed: status.uploadSpeed,
                downloadSpeed: status.downloadSpeed,
                upload: status.upload,
                download: status.download,
              ),
            );
            break;
          case VlessConnectionState.connecting:
            _emit(
              VpnStatusData(
                status: VpnStatus.connecting,
                message: 'Connecting...',
              ),
            );
            break;
          case VlessConnectionState.disconnecting:
            _emit(
              VpnStatusData(
                status: VpnStatus.disconnecting,
                message: 'Disconnecting...',
              ),
            );
            break;
          case VlessConnectionState.disconnected:
          case VlessConnectionState.unknown:
            _emit(
              VpnStatusData(
                status: VpnStatus.disconnected,
                message: 'Disconnected',
              ),
            );
            break;
        }
      },
    );

    await _vless!.initializeVless(
      providerBundleIdentifier: _bundleId,
      groupIdentifier: _appGroupId,
      keychainAccessGroup: _appGroupId,
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    return await _vless!.requestPermission();
  }

  @override
  Future<int> getServerDelay(String configJson) async {
    if (!_initialized) await initialize();
    try {
      return await _vless!.getServerDelay(config: configJson);
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<int> getServerDelayFromLink(String link) async {
    if (!_initialized) await initialize();
    if (link.trim().isEmpty) return -1;
    try {
      final parser = FlutterVless.parseFromURL(link);
      final config = _buildIosVpnConfiguration(parser.getFullConfiguration());
      return await _vless!.getServerDelay(config: config);
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
      final parser = FlutterVless.parseFromURL(link);
      final config = _buildIosVpnConfiguration(parser.getFullConfiguration());

      {
        final hasPermission = await _vless!.requestPermission().timeout(
          _connectTimeout,
          onTimeout: () => false,
        );
        if (!hasPermission) {
          _emit(
            VpnStatusData(
              status: VpnStatus.error,
              message:
                  'iOS VPN permission denied. Check signing, App Group, and XrayTunnel setup.',
            ),
          );
          return;
        }
      }

      await _vless!
          .startVless(remark: parser.remark, config: config, proxyOnly: false)
          .timeout(_connectTimeout);
    } catch (e) {
      _emit(
        VpnStatusData(
          status: VpnStatus.error,
          message: 'Connection failed: $e',
        ),
      );
    }
  }

  String _buildIosVpnConfiguration(String rawConfig) {
    final config = jsonDecode(rawConfig) as Map<String, dynamic>;

    config['dns'] = {
      'servers': ['1.1.1.1', '8.8.8.8'],
    };

    config['inbounds'] = [
      {
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': _localSocksPort,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': false,
        },
      },
    ];

    config['routing'] = {'domainStrategy': 'IPIfNonMatch', 'rules': []};

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  @override
  Future<void> disconnect() async {
    if (!_initialized) await initialize();
    _emit(
      VpnStatusData(
        status: VpnStatus.disconnecting,
        message: 'Disconnecting...',
      ),
    );
    try {
      await _vless!.stopVless();
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

  String _formatDuration(Object value) {
    final seconds = value is int ? value : int.tryParse(value.toString()) ?? 0;
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }
}
