import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'auth/auth_controller.dart';
import 'background/service_client.dart';
import 'core/theme_controller.dart';
import 'ui/screens/login_screen.dart';
import 'ui/shell.dart';

/// Brand seed, used when the platform provides no wallpaper-derived palette
/// (pre-Android 12, tests, first frame).
const Color scrobblrSeed = Color(0xFFC51224);

class ScrobblrApp extends StatefulWidget {
  const ScrobblrApp({super.key});

  @override
  State<ScrobblrApp> createState() => _ScrobblrAppState();
}

class _ScrobblrAppState extends State<ScrobblrApp> {
  final AuthController _auth = AuthController();
  final ThemeController _theme = ThemeController();
  static const ScrobbleServiceClient _service = ScrobbleServiceClient();

  late final Future<void> _restore = _restoreSession();

  Future<void> _restoreSession() async {
    await _theme.restore();
    await _auth.restore();
    if (_auth.signedIn) {
      // Re-arm the pipeline on every app start; harmless when already up.
      await _service.ensureServiceRunning();
    }
  }

  ThemeData _themeData(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final light =
            lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: scrobblrSeed);
        final dark =
            darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(
              seedColor: scrobblrSeed,
              brightness: Brightness.dark,
            );

        return ListenableBuilder(
          listenable: _theme,
          builder:
              (context, _) => MaterialApp(
                title: 'Scrobblr',
                debugShowCheckedModeBanner: false,
                theme: _themeData(light),
                darkTheme: _themeData(dark),
                themeMode: _theme.value,
                home: FutureBuilder<void>(
                  future: _restore,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return ListenableBuilder(
                      listenable: _auth,
                      builder:
                          (context, _) =>
                              _auth.signedIn
                                  ? Shell(
                                    auth: _auth,
                                    service: _service,
                                    theme: _theme,
                                  )
                                  : LoginScreen(auth: _auth, service: _service),
                    );
                  },
                ),
              ),
        );
      },
    );
  }
}
