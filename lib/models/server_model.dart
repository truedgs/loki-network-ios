/// Server model representing a VPN server entry from servers.json
class ServerModel {
  final String id;
  final String name;
  final String country;
  final String protocol;
  final String tier; // "free" or "premium"
  final String uri;
  final bool locked;

  ServerModel({
    required this.id,
    required this.name,
    required this.country,
    required this.protocol,
    required this.tier,
    required this.uri,
    this.locked = false,
  });

  bool get isPremium => tier.toLowerCase() == 'premium';
  bool get isLocked => locked || (isPremium && uri.isEmpty);

  factory ServerModel.fromJson(Map<String, dynamic> json) {
    final uri = json['uri'] as String? ?? '';
    return ServerModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      country: json['country'] as String? ?? '🌐',
      protocol:
          _protocolFromUri(uri) ?? (json['protocol'] as String? ?? 'vless'),
      tier: json['tier'] as String? ?? 'free',
      uri: uri,
      locked: json['locked'] as bool? ?? false,
    );
  }

  static String? _protocolFromUri(String uri) {
    final schemeSeparator = uri.indexOf('://');
    if (schemeSeparator <= 0) return null;
    final scheme = uri.substring(0, schemeSeparator).toLowerCase();
    return switch (scheme) {
      'ss' => 'ss',
      'vless' => 'vless',
      'vmess' => 'vmess',
      'trojan' => 'trojan',
      'socks' => 'socks',
      _ => null,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'country': country,
      'protocol': protocol,
      'tier': tier,
      'uri': uri,
      'locked': locked,
    };
  }
}

/// Container for the full servers.json response
class ServerListResponse {
  final int version;
  final String updatedAt;
  final List<ServerModel> servers;

  ServerListResponse({
    required this.version,
    required this.updatedAt,
    required this.servers,
  });

  factory ServerListResponse.fromJson(Map<String, dynamic> json) {
    return ServerListResponse(
      version: json['version'] as int? ?? 1,
      updatedAt: json['updatedAt'] as String? ?? '',
      servers: (json['servers'] as List<dynamic>?)
              ?.map((e) => ServerModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
