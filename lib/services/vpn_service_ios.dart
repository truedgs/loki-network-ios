import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_types.dart';

/// iOS implementation backed by flutter_vless.
///
/// Full tunnel mode requires the native XrayTunnel Network Extension target,
/// App Groups, and signing to be configured in Xcode on macOS.
class IosVpnService implements VpnRuntimeService {
  IosVpnService({this._connectTimeout = const Duration(seconds: 45)});

  final _controller = StreamController<VpnStatusData>.broadcast();
  @override
  Stream<VpnStatusData> get statusStream => _controller.stream;

  static const _bundleId = 'com.lokinetwork.v2rayVpn';
  static const _appGroupId = 'group.com.lokinetwork.v2rayVpn';
  static const int _localSocksPort = 10808;
  static const _setupChannel = MethodChannel(
    'com.lokinetwork.mm/ios_vpn_setup',
  );
  final Duration _connectTimeout;

  FlutterVless? _vless;
  bool _initialized = false;
  Future<void>? _initializing;
  Completer<void>? _ready;
  bool _disposed = false;
  bool _suppressStatus = false;
  bool _sawConnecting = false;
  bool _connectInFlight = false;
  int _generation = 0;
  VpnStatusData _current = VpnStatusData(status: VpnStatus.disconnected);

  @override
  VpnStatusData get current => _current;

  void _emit(VpnStatusData data) {
    if (_disposed) return;
    _current = data;
    _controller.add(data);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final operation = _initialize();
    _initializing = operation;
    try {
      await operation;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    _vless = FlutterVless(
      onStatusChanged: (status) {
        if (_disposed || _suppressStatus) return;
        switch (status.connectionState) {
          case VlessConnectionState.connected:
            if (_ready != null && !_ready!.isCompleted) _ready!.complete();
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
            _sawConnecting = true;
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
            if (_ready != null && !_ready!.isCompleted) {
              if (_sawConnecting) {
                _ready!.completeError(
                  StateError(
                    'The iOS VPN extension stopped before the tunnel became ready.',
                  ),
                );
              }
              return;
            }
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
    final setup = await _setupChannel
        .invokeMapMethod<String, dynamic>('checkVpnSetup')
        .timeout(_connectTimeout);
    if (setup?['bundleId'] != _bundleId ||
        setup?['groupIdentifier'] != _appGroupId ||
        setup?['keychainAccessGroup'] != _appGroupId) {
      throw PlatformException(
        code: 'IOS_VPN_CONFIGURATION',
        message:
            'App and VPN extension identifiers do not match this build. Rebuild and sign both targets together.',
      );
    }
    return await _vless!.requestPermission().timeout(_connectTimeout);
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
    if (_connectInFlight || _disposed) return;
    _connectInFlight = true;
    final generation = ++_generation;
    var startAttempted = false;
    _suppressStatus = true;
    _emit(
      VpnStatusData(status: VpnStatus.connecting, message: 'Connecting...'),
    );

    try {
      if (!_initialized) await initialize();
      final parser = FlutterVless.parseFromURL(link);
      final config = _buildIosVpnConfiguration(parser.getFullConfiguration());
      final hasPermission = await requestPermission();
      if (generation != _generation || _disposed) return;
      if (!hasPermission) {
        throw PlatformException(
          code: 'IOS_VPN_PERMISSION',
          message:
              'iOS did not allow saving the VPN profile. Allow the system VPN prompt. If no prompt appears, check Network Extension provisioning, Screen Time or device-management restrictions.',
        );
      }
      _sawConnecting = false;
      _suppressStatus = false;
      final ready = Completer<void>();
      _ready = ready;
      // Observe immediately: native status can arrive before startVless returns.
      unawaited(ready.future.catchError((Object _) {}));
      startAttempted = true;
      await Future.wait<void>([
        _vless!.startVless(
          remark: parser.remark,
          config: config,
          proxyOnly: false,
        ),
        ready.future,
      ], eagerError: true).timeout(_connectTimeout);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      _suppressStatus = true;
      var cleanupFailed = false;
      if (startAttempted) {
        try {
          await _vless!.stopVless().timeout(const Duration(seconds: 10));
        } catch (_) {
          cleanupFailed = true;
        }
      }
      if (generation != _generation || _disposed) return;
      final message = e is TimeoutException
          ? (startAttempted
                ? 'iOS VPN did not become ready before the timeout.'
                : 'Timed out waiting for the iOS VPN setup or permission prompt. Unlock the phone and retry.')
          : e is PlatformException
          ? '${e.code}: ${e.message ?? 'iOS VPN setup failed.'}'
          : 'Connection failed: $e';
      _emit(
        VpnStatusData(
          status: VpnStatus.error,
          message:
              '$message${cleanupFailed ? ' Stop the VPN in iOS Settings before retrying; automatic cleanup failed.' : ''}',
        ),
      );
    } finally {
      if (generation == _generation) {
        _connectInFlight = false;
        _ready = null;
      }
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
    ++_generation;
    _connectInFlight = false;
    _suppressStatus = true;
    if (_ready != null && !_ready!.isCompleted) {
      _ready!.completeError(StateError('Connection canceled.'));
    }
    _ready = null;
    _emit(
      VpnStatusData(
        status: VpnStatus.disconnecting,
        message: 'Disconnecting...',
      ),
    );
    try {
      if (_vless != null) {
        await _vless!.stopVless().timeout(const Duration(seconds: 10));
      }
      _emit(
        VpnStatusData(status: VpnStatus.disconnected, message: 'Disconnected'),
      );
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
    _disposed = true;
    ++_generation;
    if (_ready != null && !_ready!.isCompleted) {
      _ready!.completeError(StateError('Service disposed.'));
    }
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
