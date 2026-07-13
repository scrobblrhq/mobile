/// Secure persistence of the signed-in identity.
///
/// Both engines read this: the UI engine (session token for reads) and the
/// background engine (API token for scrobbling). flutter_secure_storage is
/// registered on both via `GeneratedPluginRegistrant`.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Credentials {
  const Credentials({
    required this.serverUrl,
    required this.sessionToken,
    required this.apiToken,
    required this.apiTokenId,
    required this.username,
    required this.userId,
  });

  final String serverUrl;

  /// Session UUID — used by the UI (works on `optional_auth` routes, e.g.
  /// viewing one's own private profile).
  final String sessionToken;

  /// Long-lived scoped token — used by the background scrobbler.
  final String apiToken;

  /// Id of [apiToken], kept so sign-out can revoke it server-side.
  final String apiTokenId;

  final String username;
  final int userId;

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'sessionToken': sessionToken,
    'apiToken': apiToken,
    'apiTokenId': apiTokenId,
    'username': username,
    'userId': userId,
  };

  static Credentials? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final serverUrl = raw['serverUrl'];
    final sessionToken = raw['sessionToken'];
    final apiToken = raw['apiToken'];
    final username = raw['username'];
    final userId = raw['userId'];
    if (serverUrl is! String ||
        sessionToken is! String ||
        apiToken is! String ||
        username is! String ||
        userId is! int) {
      return null;
    }
    return Credentials(
      serverUrl: serverUrl,
      sessionToken: sessionToken,
      apiToken: apiToken,
      apiTokenId: raw['apiTokenId'] as String? ?? '',
      username: username,
      userId: userId,
    );
  }
}

class CredentialsStore {
  const CredentialsStore();

  static const _key = 'scrobblr.credentials';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<Credentials?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return Credentials.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Credentials credentials) =>
      _storage.write(key: _key, value: jsonEncode(credentials.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
