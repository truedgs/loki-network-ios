class ApiConfig {
  static const appVersion = '2.0.0';

  static const baseUrl = String.fromEnvironment(
    'VPN_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const clientApiToken = String.fromEnvironment(
    'VPN_CLIENT_API_TOKEN',
    defaultValue: '',
  );

  static Map<String, String> jsonHeaders({String? accessToken}) {
    return {
      'content-type': 'application/json',
      if (clientApiToken.isNotEmpty) 'x-client-token': clientApiToken,
      if (accessToken != null && accessToken.isNotEmpty)
        'authorization': 'Bearer $accessToken',
    };
  }

  static Uri uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }
}
