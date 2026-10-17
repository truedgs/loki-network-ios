import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class ConfigCryptoService {
  static final _algorithm = AesGcm.with256bits();

  Future<String> decryptString(
    Map<String, dynamic> envelope,
    String configKey,
  ) async {
    if (envelope['algorithm'] != 'AES-256-GCM') {
      throw const ConfigCryptoException('Unsupported config encryption');
    }

    final keyBytes = base64Decode(configKey);
    final iv = base64Decode(envelope['iv'] as String? ?? '');
    final tag = base64Decode(envelope['tag'] as String? ?? '');
    final data = base64Decode(envelope['data'] as String? ?? '');

    final clearBytes = await _algorithm.decrypt(
      SecretBox(data, nonce: iv, mac: Mac(tag)),
      secretKey: SecretKey(keyBytes),
    );

    return utf8.decode(clearBytes);
  }
}

class ConfigCryptoException implements Exception {
  final String message;

  const ConfigCryptoException(this.message);

  @override
  String toString() => message;
}
