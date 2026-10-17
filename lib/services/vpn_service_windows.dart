import 'dart:async';
import 'dart:io';

import 'package:flutter_vless/flutter_vless.dart';

import 'windows_system_proxy.dart';
import 'vpn_types.dart';
import 'windows_vpn_configuration.dart';

/// Windows-only runtime backed by flutter_vless proxy or tunnel mode.
class WindowsVpnService implements VpnRuntimeService {
  final _controller = StreamController<VpnStatusData>.broadcast();
  @override
  Stream<VpnStatusData> get statusStream => _controller.stream;

  FlutterVless? _vless;
  bool _initialized = false;
  bool _ready = false;
  Future<void>? _nativeStart;
  Future<void>? _cleanup;
  static const int _localSocksPort = 10808;
  static const int _localHttpPort = 10809;
  static const Duration _connectTimeout = Duration(seconds: 45);
  final _systemProxy = const WindowsSystemProxy(
    httpPort: _localHttpPort,
    socksPort: _localSocksPort,
  );

  VpnStatusData _current = VpnStatusData(status: VpnStatus.disconnected);
  Timer? _connectTimer;
  int _connectAttempt = 0;
  bool _ignoreNextDisconnected = false;

  @override
  VpnStatusData get current => _current;

  void _emit(VpnStatusData data) {
    if (_controller.isClosed) return;
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
            if (!_ready) return;
            _finishConnectAttempt();
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
            if (_ignoreNextDisconnected) return;
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
            if (_ignoreNextDisconnected) {
              return;
            }
            if (_ready) {
              _ready = false;
              unawaited(
                _failConnectAttempt(
                  'Windows VPN stopped. Restoring network settings.',
                ),
              );
              return;
            }
            if (_current.status == VpnStatus.connecting &&
                _connectTimer != null) {
              unawaited(
                _failConnectAttempt(
                  'VPN stopped before the connection was ready. Please check the server config and try again.',
                ),
              );
              return;
            }
            _finishConnectAttempt();
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

    await _systemProxy.restore();
    await _vless!.initializeVless();
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
  Future<void> connect(
    String link, {
    VpnConnectionMode mode = VpnConnectionMode.proxy,
  }) async {
    await _cleanup;
    if (!_initialized) await initialize();
    _beginConnectAttempt();
    _ready = false;
    final attempt = _connectAttempt;
    _emit(
      VpnStatusData(status: VpnStatus.connecting, message: 'Connecting...'),
    );

    try {
      final missingRuntime = _missingRuntimeFiles();
      if (missingRuntime.isNotEmpty) {
        _finishConnectAttempt();
        _emit(
          VpnStatusData(
            status: VpnStatus.error,
            message:
                'Windows VPN runtime missing: ${missingRuntime.join(', ')}. Put these files beside the app in the xray folder.',
          ),
        );
        return;
      }

      final parser = FlutterVless.parseFromURL(link);
      final config = _buildWindowsVpnConfiguration(
        parser.getFullConfiguration(),
        mode: mode,
      );
      if (mode == VpnConnectionMode.tunnel) {
        final hasPermission = await _vless!.requestPermission().timeout(
          _connectTimeout,
          onTimeout: () => false,
        );
        if (!hasPermission) {
          _finishConnectAttempt();
          _emit(
            VpnStatusData(
              status: VpnStatus.error,
              message: 'Run as administrator to start Windows tunnel mode.',
            ),
          );
          return;
        }
      }

      if (attempt != _connectAttempt) return;
      _nativeStart = _vless!
          .startVless(
            remark: parser.remark,
            config: config,
            proxyOnly: mode == VpnConnectionMode.proxy,
          )
          .timeout(_connectTimeout);
      await _nativeStart;
      if (attempt != _connectAttempt) return;

      if (mode == VpnConnectionMode.proxy) {
        await _verifyProxyTraffic(await _systemProxy.enabledHttpProxy());
      }
      if (attempt != _connectAttempt) return;
      _ready = true;
      _finishConnectAttempt();
      _emit(VpnStatusData(status: VpnStatus.connected, message: 'Connected'));
    } catch (e) {
      if (attempt == _connectAttempt) {
        await _failConnectAttempt('Windows connection failed.', error: e);
      }
    } finally {
      _nativeStart = null;
    }
  }

  @override
  Future<int> getServerDelayFromLink(String link) async {
    if (!_initialized) await initialize();
    if (link.trim().isEmpty) return -1;
    try {
      final parser = FlutterVless.parseFromURL(link);
      final config = _buildWindowsVpnConfiguration(
        parser.getFullConfiguration(),
      );
      return await _vless!.getServerDelay(config: config);
    } catch (_) {
      return -1;
    }
  }

  String _buildWindowsVpnConfiguration(
    String rawConfig, {
    VpnConnectionMode mode = VpnConnectionMode.proxy,
  }) => buildWindowsVpnConfiguration(rawConfig, mode: mode);

  Future<void> _verifyProxyTraffic(String endpoint) async {
    for (final url in [
      'https://www.gstatic.com/generate_204',
      'https://www.cloudflare.com/cdn-cgi/trace',
    ]) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..findProxy = (_) => 'PROXY $endpoint';
      try {
        final valid = await (() async {
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode ==
              (url.endsWith('generate_204') ? 204 : 200);
        })().timeout(const Duration(seconds: 8));
        if (valid) return;
      } catch (_) {
        // Try an independent endpoint before rejecting the server.
      } finally {
        client.close(force: true);
      }
    }
    throw StateError(
      'Windows proxy started, but HTTPS traffic cannot reach the internet through this server. Try another server.',
    );
  }

  List<String> _missingRuntimeFiles() {
    final runtimeDir = _findRuntimeDir();
    if (runtimeDir == null) {
      return const [
        'xray.exe',
        'tun2socks.exe',
        'wintun.dll',
        'geoip.dat',
        'geosite.dat',
      ];
    }

    return [
      'xray.exe',
      'tun2socks.exe',
      'wintun.dll',
      'geoip.dat',
      'geosite.dat',
    ].where((name) => !File('${runtimeDir.path}\\$name').existsSync()).toList();
  }

  Directory? _findRuntimeDir() {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      appDir,
      Directory('${appDir.path}\\xray'),
      Directory('${appDir.path}\\data\\flutter_assets\\xray'),
      Directory('${appDir.path}\\data\\flutter_assets\\windows\\xray'),
    ];

    for (final candidate in candidates) {
      if (File('${candidate.path}\\xray.exe').existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String> _diagnosticSuffix() async {
    try {
      final snapshot = await _vless!.getProviderDebugSnapshot();
      final compact = snapshot
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map(_sanitizeDiagnosticLine)
          .take(8)
          .join('\n');
      if (compact.isNotEmpty) return '\n\nDiagnostics:\n$compact';
    } catch (_) {}
    return '';
  }

  @override
  Future<void> disconnect() async {
    if (!_initialized) await initialize();
    _finishConnectAttempt();
    _connectAttempt++;
    _ready = false;
    _ignoreNextDisconnected = true;
    _emit(
      VpnStatusData(
        status: VpnStatus.disconnecting,
        message: 'Disconnecting...',
      ),
    );
    try {
      try {
        await _nativeStart;
      } catch (_) {}
      await _vless!.stopVless();
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
    _ready = false;
    _connectAttempt++;
    _finishConnectAttempt();
    unawaited(_stopAfterFailedAttempt());
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

  void _beginConnectAttempt() {
    _connectAttempt++;
    _ignoreNextDisconnected = false;
    _connectTimer?.cancel();
    final attempt = _connectAttempt;
    _connectTimer = Timer(_connectTimeout, () {
      if (attempt != _connectAttempt ||
          _current.status != VpnStatus.connecting) {
        return;
      }
      unawaited(
        _failConnectAttempt(
          'Windows connection timed out. Try another server; Tunnel mode requires administrator rights.',
        ),
      );
    });
  }

  void _finishConnectAttempt() {
    _connectTimer?.cancel();
    _connectTimer = null;
  }

  Future<void> _failConnectAttempt(
    String message, {
    Object? error,
    bool includeDiagnostics = true,
  }) async {
    _finishConnectAttempt();
    _connectAttempt++;
    _ignoreNextDisconnected = true;
    _ready = false;
    final failedAttempt = _connectAttempt;
    final diagnostics = includeDiagnostics ? await _diagnosticSuffix() : '';
    await _stopAfterFailedAttempt();
    if (failedAttempt != _connectAttempt) return;
    _emit(
      VpnStatusData(
        status: VpnStatus.error,
        message: '$message${_safeErrorDetails(error)}$diagnostics',
      ),
    );
  }

  Future<void> _stopAfterFailedAttempt() async {
    if (_cleanup != null) return _cleanup;
    _cleanup = (() async {
      try {
        await _vless?.stopVless();
      } catch (_) {}
    })();
    try {
      await _cleanup;
    } finally {
      _cleanup = null;
    }
  }

  String _safeErrorDetails(Object? error) {
    if (error == null) return '';
    final sanitized = _sanitizeDiagnosticLine(error.toString()).trim();
    if (sanitized.isEmpty) return '';
    return '\nDetails: $sanitized';
  }

  String _sanitizeDiagnosticLine(String value) {
    return value
        .replaceAll(RegExp(r'https?://\S+'), '[hidden URL]')
        .replaceAll(
          RegExp(r"Failed host lookup: '[^']+'"),
          'Failed host lookup',
        )
        .replaceAll(RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b'), '[hidden IP]');
  }
}
