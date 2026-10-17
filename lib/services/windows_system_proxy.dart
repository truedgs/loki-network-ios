import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class WindowsSystemProxy {
  static const _registryPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _activeKey = 'windows_proxy_restore_active';
  static const _proxyEnableKey = 'windows_proxy_restore_proxy_enable';
  static const _proxyServerKey = 'windows_proxy_restore_proxy_server';
  static const _proxyServerExistsKey =
      'windows_proxy_restore_proxy_server_exists';

  final int httpPort;
  final int socksPort;

  const WindowsSystemProxy({required this.httpPort, required this.socksPort});

  Future<String> enabledHttpProxy() async {
    if (await _readDword('ProxyEnable') != 1) {
      throw StateError('Windows system proxy was not enabled.');
    }
    final server = await _readString('ProxyServer') ?? '';
    for (final entry in server.split(';')) {
      if (!entry.startsWith('http=')) continue;
      final endpoint = Uri.tryParse('http://${entry.substring(5)}');
      if (endpoint != null &&
          endpoint.host == '127.0.0.1' &&
          endpoint.hasPort) {
        return '${endpoint.host}:${endpoint.port}';
      }
    }
    throw StateError('Windows HTTP proxy listener was not configured.');
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_activeKey) != true) {
      final proxyServer = await _readString('ProxyServer') ?? '';
      final isLokiProxy = _isLegacyLokiProxy(proxyServer);
      if (isLokiProxy) {
        await _regAdd('ProxyEnable', 'REG_DWORD', '0');
        await _regDelete('ProxyServer');
        await _notifyWindowsProxyChanged();
      }
      return;
    }

    var previousEnable = prefs.getInt(_proxyEnableKey) ?? 0;
    final hadProxyServer = prefs.getBool(_proxyServerExistsKey) ?? false;
    final previousServer = prefs.getString(_proxyServerKey);
    // Older Dart snapshots were taken after the plugin enabled its own proxy.
    // Restoring that stopped listener would leave Windows without internet.
    if (_isLegacyLokiProxy(previousServer ?? '')) previousEnable = 0;

    await _regAdd('ProxyEnable', 'REG_DWORD', previousEnable.toString());
    if (hadProxyServer && previousServer != null) {
      await _regAdd('ProxyServer', 'REG_SZ', previousServer);
    } else {
      await _regDelete('ProxyServer');
    }

    await prefs.remove(_activeKey);
    await prefs.remove(_proxyEnableKey);
    await prefs.remove(_proxyServerExistsKey);
    await prefs.remove(_proxyServerKey);
    await _notifyWindowsProxyChanged();
  }

  Future<int?> _readDword(String name) async {
    final value = await _readRegistryValue(name);
    if (value == null) return null;
    if (value.startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16);
    }
    return int.tryParse(value);
  }

  bool _isLegacyLokiProxy(String value) => RegExp(
    '(?:^|[=;])(?:127\\.0\\.0\\.1|localhost):(?:$httpPort|$socksPort)(?:;|\$)',
    caseSensitive: false,
  ).hasMatch(value);

  Future<String?> _readString(String name) => _readRegistryValue(name);

  Future<String?> _readRegistryValue(String name) async {
    final result = await Process.run('reg', [
      'query',
      _registryPath,
      '/v',
      name,
    ]);
    if (result.exitCode != 0) return null;
    final lines = result.stdout.toString().split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith(name)) continue;
      final parts = trimmed.split(RegExp(r'\s{2,}'));
      if (parts.length >= 3) return parts.sublist(2).join('  ').trim();
    }
    return null;
  }

  Future<void> _regAdd(String name, String type, String value) async {
    final result = await Process.run('reg', [
      'add',
      _registryPath,
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Unable to update Windows proxy setting: $name');
    }
  }

  Future<void> _regDelete(String name) async {
    await Process.run('reg', ['delete', _registryPath, '/v', name, '/f']);
  }

  Future<void> _notifyWindowsProxyChanged() async {
    const script = '''
\$signature = @"
using System;
using System.Runtime.InteropServices;
public static class WinInetProxyNotify {
  [DllImport("wininet.dll", SetLastError = true)]
  public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
Add-Type -TypeDefinition \$signature -ErrorAction SilentlyContinue
[WinInetProxyNotify]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[WinInetProxyNotify]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
''';
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
