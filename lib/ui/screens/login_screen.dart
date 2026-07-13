import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../../background/service_client.dart';
import '../../core/config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, required this.service});

  final AuthController auth;
  final ScrobbleServiceClient service;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Debug builds keep the dev-server flow of old: advanced section open,
  // emulator URL pre-filled. Release builds default to the hosted instance.
  final _server = TextEditingController(
    text: kDebugMode ? defaultServerUrl : '',
  );
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _displayName = TextEditingController();

  bool _showAdvanced = kDebugMode;
  bool _createAccount = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLastServer());
  }

  /// Self-hosters who signed in to a custom server before keep it: the
  /// advanced section re-opens pre-filled instead of silently falling back
  /// to the hosted instance.
  Future<void> _restoreLastServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(prefLastServerUrl);
      if (!mounted || last == null || last.isEmpty) return;
      if (last == hostedServerUrl) return;
      setState(() {
        _server.text = last;
        _showAdvanced = true;
      });
    } catch (_) {
      // No stored preference: defaults stand.
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _email.dispose();
    _displayName.dispose();
    super.dispose();
  }

  /// The server the form will talk to: the advanced override when set,
  /// otherwise the hosted instance.
  String get _effectiveServer {
    final custom = _server.text.trim();
    return _showAdvanced && custom.isNotEmpty ? custom : hostedServerUrl;
  }

  Future<void> _submit() async {
    final server = _effectiveServer;
    final username = _username.text.trim();
    final password = _password.text;
    final email = _email.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    if (_createAccount && email.isEmpty) {
      setState(() => _error = 'Email is required to create an account.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.signIn(
        serverUrl: server,
        username: username,
        password: password,
        createAccount: _createAccount,
        email: email,
        displayName: _displayName.text.trim(),
      );
      // Boot the pipeline and hand it the fresh API token.
      await widget.service.ensureServiceRunning();
      widget.service.notifyCredentialsChanged();
      // ScrobblrApp swaps to the Shell via the AuthController listener.
    } on ApiException catch (e) {
      setState(() => _error = e.message.isEmpty ? 'Request failed' : e.message);
    } catch (_) {
      setState(
        () =>
            _error =
                server == hostedServerUrl
                    ? "Can't reach the Scrobblr server right now. Check your "
                        'connection and try again in a moment.'
                    : 'Could not reach $server. Check the URL.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.music_note,
                      size: 36,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(child: Text('Scrobblr', style: text.headlineMedium)),
                Center(
                  child: Text(
                    'Scrobble what you play',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _username,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_createAccount) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayName,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                    ),
                  ),
                ],
                if (_showAdvanced) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      helperText:
                          kDebugMode
                              ? '10.0.2.2 reaches the host from the emulator'
                              : 'Your self-hosted server. Leave empty to use '
                                  'the hosted instance.',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child:
                      _busy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(_createAccount ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed:
                      _busy
                          ? null
                          : () => setState(() {
                            _createAccount = !_createAccount;
                            _error = null;
                          }),
                  child: Text(
                    _createAccount
                        ? 'I already have an account'
                        : 'Create an account',
                  ),
                ),
                const SizedBox(height: 4),
                // Kept low-key but visible: this is how self-hosters find
                // their way to a custom server URL.
                TextButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : () =>
                              setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(
                    _showAdvanced ? Icons.expand_less : Icons.tune,
                    size: 18,
                  ),
                  label: Text(
                    _showAdvanced
                        ? 'Hide advanced options'
                        : 'Advanced options · self-hosting',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
