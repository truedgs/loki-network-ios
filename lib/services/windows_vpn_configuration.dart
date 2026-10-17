import 'dart:convert';

import 'vpn_types.dart';

String buildWindowsVpnConfiguration(
  String rawConfig, {
  required VpnConnectionMode mode,
}) {
  final config = jsonDecode(rawConfig) as Map<String, dynamic>;
  final proxy = (config['outbounds'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (outbound) =>
            !['freedom', 'blackhole', 'dns'].contains(outbound['protocol']),
        orElse: () => throw StateError('The server has no VPN outbound.'),
      );
  proxy['tag'] ??= 'proxy';
  config['dns'] = {
    'servers': ['1.1.1.1', '8.8.8.8'],
  };
  config['inbounds'] = [
    if (mode == VpnConnectionMode.proxy)
      {
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': 10809,
        'protocol': 'http',
        'settings': <String, dynamic>{},
      },
    {
      'tag': 'socks-in',
      'listen': '127.0.0.1',
      'port': 10808,
      'protocol': 'socks',
      'settings': {'auth': 'noauth', 'udp': true},
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
        'routeOnly': true,
      },
    },
  ];
  config['routing'] = {
    'domainStrategy': 'AsIs',
    'rules': [
      {
        'type': 'field',
        'inboundTag': ['http-in', 'socks-in'],
        'outboundTag': proxy['tag'],
      },
    ],
  };
  return jsonEncode(config);
}
