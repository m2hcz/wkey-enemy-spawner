import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Connection settings for the VPS, persisted in the platform keystore
/// (Android Keystore / iOS Keychain) so credentials never sit in plain text.
class VpsConfig {
  const VpsConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
    this.autoConnect = true,
    this.fontSize = 13,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;
  final String passphrase;
  final bool autoConnect;
  final double fontSize;

  bool get usesKey => privateKey.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
        'passphrase': passphrase,
        'autoConnect': autoConnect,
        'fontSize': fontSize,
      };

  factory VpsConfig.fromJson(Map<String, dynamic> json) => VpsConfig(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        privateKey: json['privateKey'] as String? ?? '',
        passphrase: json['passphrase'] as String? ?? '',
        autoConnect: json['autoConnect'] as bool? ?? true,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13,
      );
}

class ConfigStore {
  static const _storage = FlutterSecureStorage();
  static const _configKey = 'vps_config';
  static const _hostKeyPrefix = 'known_host:';

  static Future<VpsConfig?> load() async {
    final raw = await _storage.read(key: _configKey);
    if (raw == null) return null;
    try {
      return VpsConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(VpsConfig config) =>
      _storage.write(key: _configKey, value: jsonEncode(config.toJson()));

  static Future<void> clear() => _storage.delete(key: _configKey);

  /// Fingerprint of the server host key we trusted on first connection.
  static Future<String?> knownHostKey(String host, int port) =>
      _storage.read(key: '$_hostKeyPrefix$host:$port');

  static Future<void> trustHostKey(String host, int port, String fp) =>
      _storage.write(key: '$_hostKeyPrefix$host:$port', value: fp);

  static Future<void> forgetHostKey(String host, int port) =>
      _storage.delete(key: '$_hostKeyPrefix$host:$port');
}
