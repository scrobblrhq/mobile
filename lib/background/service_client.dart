/// UI-side facade over the native control channel and the background
/// isolate's ports.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'protocol.dart';

class ScrobbleServiceClient {
  const ScrobbleServiceClient();

  static const _control = MethodChannel(controlChannelName);

  Future<bool> isListenerEnabled() async {
    try {
      return await _control.invokeMethod<bool>('isListenerEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openListenerSettings() => _invokeSafe('openListenerSettings');

  /// Boots the background engine and asks the system to rebind the
  /// notification listener if needed.
  Future<void> ensureServiceRunning() => _invokeSafe('ensureServiceRunning');

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _control.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invokeSafe('requestIgnoreBatteryOptimizations');

  Future<void> _invokeSafe(String method) async {
    try {
      await _control.invokeMethod<void>(method);
    } on PlatformException {
      // Native side missing (non-Android host): ignore.
    } on MissingPluginException {
      // ditto
    }
  }

  /// Nudges the background isolate (if running) to re-read state.
  void notifyCredentialsChanged() => _ping('credentialsChanged');
  void notifyConfigChanged() => _ping('configChanged');

  /// Asks for a fresh pipeline snapshot (progress advances silently between
  /// events, so the monitor polls while visible).
  void requestSnapshot() => _ping('snapshotRequest');

  void _ping(String type) {
    IsolateNameServer.lookupPortByName(bgControlPortName)?.send({'type': type});
  }

  /// Live pipeline snapshots from the background engine. Single subscriber
  /// (the snapshot port name is exclusive); subscribing requests an
  /// immediate snapshot.
  Stream<Map<Object?, Object?>> pipelineSnapshots() {
    late StreamController<Map<Object?, Object?>> controller;
    ReceivePort? port;

    controller = StreamController<Map<Object?, Object?>>(
      onListen: () {
        IsolateNameServer.removePortNameMapping(uiSnapshotPortName);
        port = ReceivePort();
        IsolateNameServer.registerPortWithName(
          port!.sendPort,
          uiSnapshotPortName,
        );
        port!.listen((message) {
          if (message is Map && message['type'] == 'pipeline') {
            controller.add(message.cast<Object?, Object?>());
          }
        });
        _ping('snapshotRequest');
      },
      onCancel: () {
        IsolateNameServer.removePortNameMapping(uiSnapshotPortName);
        port?.close();
        port = null;
      },
    );

    return controller.stream;
  }
}
