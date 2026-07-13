import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefThemeMode = 'newfm.theme_mode';

/// App-wide theme mode preference (system/light/dark), persisted in
/// SharedPreferences and applied by `NewfmApp` via [ListenableBuilder].
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    value = switch (prefs.getString(_prefThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
