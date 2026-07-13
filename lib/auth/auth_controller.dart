/// Sign-in/out flow.
///
/// Sign-in performs two steps: authenticate for a session token, then
/// provision a named long-lived API token (scope `scrobble`) for the
/// background service — the raw token is only returned once, at creation.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../core/config.dart';
import 'credentials.dart';

class AuthController extends ChangeNotifier {
  AuthController({CredentialsStore? store})
    : _store = store ?? const CredentialsStore();

  final CredentialsStore _store;

  Credentials? _credentials;
  Credentials? get credentials => _credentials;
  bool get signedIn => _credentials != null;

  /// Session-token client for UI reads. Callers must not cache it across
  /// sign-outs.
  NewfmApi api() {
    final creds = _credentials;
    if (creds == null) {
      throw StateError('not signed in');
    }
    return NewfmApi(baseUrl: creds.serverUrl, token: creds.sessionToken);
  }

  Future<void> restore() async {
    _credentials = await _store.read();
    notifyListeners();
  }

  Future<void> signIn({
    required String serverUrl,
    required String username,
    required String password,
    bool createAccount = false,
    String? email,
    String? displayName,
  }) async {
    final anon = NewfmApi(baseUrl: serverUrl);
    final AuthResponse auth;
    try {
      auth =
          createAccount
              ? await anon.register(
                username: username,
                email: email ?? '',
                password: password,
                displayName: displayName,
              )
              : await anon.login(username, password);
    } finally {
      anon.close();
    }

    final sessioned = NewfmApi(baseUrl: serverUrl, token: auth.token);
    final CreatedApiToken deviceToken;
    try {
      deviceToken = await sessioned.createApiToken(apiTokenName);
    } finally {
      sessioned.close();
    }

    final creds = Credentials(
      serverUrl: serverUrl,
      sessionToken: auth.token,
      apiToken: deviceToken.token,
      apiTokenId: deviceToken.id,
      username: auth.username,
      userId: auth.userId,
    );
    await _store.write(creds);
    await _rememberServer(serverUrl);
    _credentials = creds;
    notifyListeners();
  }

  /// Remembers the server for the next login screen, so self-hosters don't
  /// silently fall back to the hosted instance after signing out.
  Future<void> _rememberServer(String serverUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefLastServerUrl, serverUrl);
    } catch (_) {
      // Preference is a convenience; sign-in/out must not fail on it.
    }
  }

  /// Clears local state; best-effort revocation of the device API token and
  /// the session server-side (logout invalidates *all* sessions, matching
  /// the API's semantics).
  Future<void> signOut() async {
    final creds = _credentials;
    if (creds != null) {
      // Users who signed in before the URL was remembered (or on an older
      // version) still keep their server across this sign-out.
      await _rememberServer(creds.serverUrl);
      final client = NewfmApi(
        baseUrl: creds.serverUrl,
        token: creds.sessionToken,
      );
      try {
        if (creds.apiTokenId.isNotEmpty) {
          await client.deleteApiToken(creds.apiTokenId);
        }
      } catch (_) {}
      try {
        await client.logout();
      } catch (_) {}
      client.close();
    }
    await _store.clear();
    _credentials = null;
    notifyListeners();
  }
}
