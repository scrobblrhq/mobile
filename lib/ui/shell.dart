import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../background/service_client.dart';
import '../core/theme_controller.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';

/// Signed-in scaffold: bottom navigation over Home / Profile / Stats /
/// Settings. Owns the session-token API client used by all tabs and detail
/// screens.
class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.auth,
    required this.service,
    required this.theme,
  });

  final AuthController auth;
  final ScrobbleServiceClient service;
  final ThemeController theme;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final ScrobblrApi _api = widget.auth.api();
  int _index = 0;

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(api: _api, auth: widget.auth, service: widget.service),
          ProfileScreen(api: _api, auth: widget.auth),
          StatsScreen(api: _api, auth: widget.auth),
          SettingsScreen(
            auth: widget.auth,
            service: widget.service,
            theme: widget.theme,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
