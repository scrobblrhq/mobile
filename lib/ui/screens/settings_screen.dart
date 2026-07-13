import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../../background/protocol.dart';
import '../../background/service_client.dart';
import '../../core/theme_controller.dart';
import '../../scrobbling/source_parsers.dart';

/// Settings, grouped into sections: Account, Appearance, Scrobbling,
/// Sources and Advanced.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.service,
    required this.theme,
  });

  final AuthController auth;
  final ScrobbleServiceClient service;
  final ThemeController theme;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _scrobblingEnabled = true;
  Set<String> _disabled = {};
  List<String> _customSources = [];
  bool _catchAll = true;
  bool _listenerEnabled = false;
  bool _ignoringBattery = false;

  /// Loose Android package-name shape: dot-separated identifiers.
  static final RegExp _packageName = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPrefs());
    unawaited(_refreshStatuses());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatuses());
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _scrobblingEnabled = prefs.getBool(prefScrobblingEnabled) ?? true;
      _disabled =
          (prefs.getStringList(prefDisabledSources) ?? const []).toSet();
      _customSources = prefs.getStringList(prefCustomSources) ?? [];
      _catchAll = prefs.getBool(prefCatchAllEnabled) ?? true;
    });
  }

  Future<void> _refreshStatuses() async {
    final listener = await widget.service.isListenerEnabled();
    final battery = await widget.service.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _listenerEnabled = listener;
      _ignoringBattery = battery;
    });
  }

  // Writes fetch the (cached) instance themselves so a toggle flipped
  // before _loadPrefs finishes is never silently dropped.
  Future<void> _setScrobbling(bool value) async {
    setState(() => _scrobblingEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefScrobblingEnabled, value);
    widget.service.notifyConfigChanged();
  }

  Future<void> _setSourceEnabled(String packageName, bool enabled) async {
    setState(() {
      if (enabled) {
        _disabled.remove(packageName);
      } else {
        _disabled.add(packageName);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefDisabledSources, _disabled.toList());
    widget.service.notifyConfigChanged();
  }

  Future<void> _setCatchAll(bool value) async {
    setState(() => _catchAll = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefCatchAllEnabled, value);
    widget.service.notifyConfigChanged();
  }

  Future<void> _addCustomSource() async {
    final added = await showDialog<String>(
      context: context,
      builder: (context) => const _AddSourceDialog(),
    );
    if (added == null || added.isEmpty || !mounted) return;

    if (!_packageName.hasMatch(added)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not a valid package name (e.g. com.example.player).'),
        ),
      );
      return;
    }
    final alreadyKnown =
        knownSources.any((s) => s.packageName == added) ||
        _customSources.contains(added);
    if (alreadyKnown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That app is already listed.')),
      );
      return;
    }

    setState(() => _customSources = [..._customSources, added]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefCustomSources, _customSources);
    widget.service.notifyConfigChanged();
  }

  Future<void> _removeCustomSource(String packageName) async {
    setState(() {
      _customSources = _customSources.where((p) => p != packageName).toList();
      _disabled.remove(packageName);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefCustomSources, _customSources);
    await prefs.setStringList(prefDisabledSources, _disabled.toList());
    widget.service.notifyConfigChanged();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'Stops scrobbling from this device and revokes its API token. '
              'Queued offline scrobbles are discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await widget.auth.signOut();
    widget.service.notifyCredentialsChanged();
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creds = widget.auth.credentials;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(creds?.username ?? ''),
            subtitle: const Text('Signed in'),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Sign out', style: TextStyle(color: scheme.error)),
            onTap: () => unawaited(_signOut()),
          ),
          _sectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: widget.theme,
                builder:
                    (context, mode, _) => SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged:
                          (selection) =>
                              unawaited(widget.theme.setMode(selection.first)),
                    ),
              ),
            ),
          ),
          _sectionHeader('Scrobbling'),
          SwitchListTile(
            title: const Text('Scrobble what I play'),
            subtitle: const Text('Master switch for the background listener'),
            value: _scrobblingEnabled,
            onChanged: (v) => unawaited(_setScrobbling(v)),
          ),
          ListTile(
            leading: Icon(
              _listenerEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              color: _listenerEnabled ? scheme.primary : scheme.error,
            ),
            title: const Text('Notification access'),
            subtitle: Text(
              _listenerEnabled
                  ? 'Granted — players are being detected'
                  : 'Required to detect playing music',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(widget.service.openListenerSettings()),
          ),
          ListTile(
            leading: Icon(
              _ignoringBattery
                  ? Icons.battery_charging_full
                  : Icons.battery_alert,
              color: _ignoringBattery ? scheme.primary : scheme.tertiary,
            ),
            title: const Text('Battery optimization'),
            subtitle: Text(
              _ignoringBattery
                  ? 'Unrestricted — the listener survives standby'
                  : 'Recommended: allow unrestricted background use',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                _ignoringBattery
                    ? null
                    : () => unawaited(
                      widget.service.requestIgnoreBatteryOptimizations(),
                    ),
          ),
          _sectionHeader('Sources'),
          for (final source in knownSources)
            SwitchListTile(
              title: Text(source.label),
              subtitle: Text(
                source.packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              value: !_disabled.contains(source.packageName),
              onChanged:
                  (v) => unawaited(_setSourceEnabled(source.packageName, v)),
            ),
          for (final packageName in _customSources)
            SwitchListTile(
              secondary: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(_removeCustomSource(packageName)),
              ),
              title: Text(
                packageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Added by you · generic parser'),
              value: !_disabled.contains(packageName),
              onChanged: (v) => unawaited(_setSourceEnabled(packageName, v)),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add app by package name'),
            subtitle: const Text(
              'Scrobble another player the listener should watch',
            ),
            onTap: () => unawaited(_addCustomSource()),
          ),
          SwitchListTile(
            title: const Text('Scrobble from any app'),
            subtitle: Text(
              _catchAll
                  ? 'Apps not listed above are picked up via the generic '
                      'parser (source: "Android")'
                  : 'Off — only the apps listed above are scrobbled',
            ),
            value: _catchAll,
            onChanged: (v) => unawaited(_setCatchAll(v)),
          ),
          _sectionHeader('Advanced'),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Server'),
            subtitle: Text(creds?.serverUrl ?? ''),
          ),
        ],
      ),
    );
  }
}

/// Owns its [TextEditingController] so its lifetime matches the dialog
/// route (disposing it from the caller races the pop animation).
class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add app by package name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.text,
        decoration: const InputDecoration(
          labelText: 'Package name',
          hintText: 'com.example.player',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
