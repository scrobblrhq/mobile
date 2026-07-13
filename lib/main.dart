import 'package:flutter/material.dart';

import 'app.dart';
import 'background/scrobble_service.dart';

void main() {
  runApp(const NewfmApp());
}

/// Entrypoint executed by the headless background FlutterEngine that
/// `BackgroundEngineHolder` (Kotlin) creates when the notification listener
/// binds. Must live in the root library so `DartEntrypoint` can resolve it
/// by name; `vm:entry-point` keeps it from being tree-shaken in release
/// builds.
@pragma('vm:entry-point')
Future<void> scrobbleServiceMain() => runScrobbleService();
