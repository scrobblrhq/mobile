/// The background scrobbler.
///
/// Runs in a headless FlutterEngine owned by `BackgroundEngineHolder`
/// (Kotlin), which the NotificationListenerService boots — so this isolate
/// lives whenever the listener is bound, with or without the UI. It consumes
/// raw player events, drives the pure [ScrobbleEngine], and submits
/// now-playing + scrobbles with an offline retry queue.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/credentials.dart';
import '../scrobbling/pending_queue.dart';
import '../scrobbling/player_event.dart';
import '../scrobbling/scrobble_engine.dart';
import '../scrobbling/source_parsers.dart';
import 'protocol.dart';

Future<void> runScrobbleService() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScrobbleService().start();
}

class _LastSubmission {
  _LastSubmission(this.key, this.atMs);
  final String key;
  final int atMs;
}

class ScrobbleService {
  ScrobbleService({ScrobbleEngine? engine})
    : _engine = engine ?? ScrobbleEngine();

  static const _channel = MethodChannel(backgroundChannelName);

  final ScrobbleEngine _engine;
  final CredentialsStore _store = const CredentialsStore();

  PendingQueue? _queue;
  ScrobblrApi? _api;
  Timer? _engineTimer;
  Timer? _queueTimer;
  ReceivePort? _controlPort;
  Set<String> _disabledPackages = {};
  Set<String> _customPackages = {};
  bool _catchAll = true;
  bool _enabled = true;
  _LastSubmission? _lastScrobble;
  String? _notifiedTrackKey;

  static final Set<String> _knownPackages = {
    for (final s in knownSources) s.packageName,
  };

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  Future<void> start() async {
    _channel.setMethodCallHandler(_onMethodCall);

    // Handshake: tells the native holder we can receive buffered events and
    // hands us process paths (avoids needing path_provider here).
    final init = await _channel.invokeMethod<Map<Object?, Object?>>('ready');
    final filesDir = init?['filesDir'] as String? ?? Directory.systemTemp.path;

    final queue = PendingQueue(File('$filesDir/pending_scrobbles.json'));
    await queue.load();
    _queue = queue;

    await _reloadCredentials();
    await _reloadConfig();
    _registerControlPort();
    _scheduleQueueFlush(immediately: true);
    _publishSnapshot();
  }

  Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method == 'playerEvent' && call.arguments is Map) {
      _handlePlayerEvent(
        PlayerEvent.fromMap((call.arguments as Map).cast<Object?, Object?>()),
      );
    }
    return null;
  }

  void _handlePlayerEvent(PlayerEvent event) {
    if (!_allowedSource(event.packageName)) return;
    final now = _nowMs;
    _dispatch(_engine.handleEvent(event, now));
    _rescheduleEngineTimer();
    _publishSnapshot();
  }

  /// A package may scrobble when scrobbling is on, it isn't individually
  /// disabled, and it is either a listed source (known or user-added) or the
  /// catch-all for unlisted apps is enabled.
  bool _allowedSource(String packageName) {
    if (!_enabled || _disabledPackages.contains(packageName)) return false;
    return _catchAll ||
        _knownPackages.contains(packageName) ||
        _customPackages.contains(packageName);
  }

  void _onEngineTimer() {
    _dispatch(_engine.tick(_nowMs));
    _rescheduleEngineTimer();
    _publishSnapshot();
  }

  void _rescheduleEngineTimer() {
    _engineTimer?.cancel();
    _engineTimer = null;
    final deadline = _engine.nextDeadlineMs();
    if (deadline == null) return;
    final delayMs = (deadline - _nowMs).clamp(50, 1 << 31).toInt();
    _engineTimer = Timer(Duration(milliseconds: delayMs), _onEngineTimer);
  }

  void _dispatch(List<EngineAction> actions) {
    for (final action in actions) {
      switch (action) {
        case final NowPlayingAction nowPlaying:
          unawaited(_sendNowPlaying(nowPlaying));
        case final ScrobbleAction scrobble:
          unawaited(_submitScrobble(scrobble));
      }
    }
  }

  Future<void> _sendNowPlaying(NowPlayingAction action) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.updateNowPlaying(
        artist: action.track.artist,
        track: action.track.title,
        album: action.track.album,
        durationMs: action.track.durationMs,
        source: action.track.sourceSlug,
      );
    } catch (_) {
      // Now-playing is ephemeral: no retry, next track corrects it.
    }
  }

  Future<void> _submitScrobble(ScrobbleAction action) async {
    // Not signed in: drop rather than queue — tracking-before-consent is
    // not something a scrobbler should do.
    final api = _api;
    final queue = _queue;
    if (api == null || queue == null) return;

    // Mirror of the server's dedupe (same track within 30 s → 400).
    final key = action.track.key;
    final last = _lastScrobble;
    if (last != null &&
        last.key == key &&
        (action.playedAtMs - last.atMs).abs() < 30000) {
      return;
    }
    _lastScrobble = _LastSubmission(key, action.playedAtMs);

    final item = PendingScrobble(
      artist: action.track.artist,
      track: action.track.title,
      album: action.track.album,
      playedAtMs: action.playedAtMs,
      durationMs: action.track.durationMs,
      listenedMs: action.listenedMs,
      source: action.track.sourceSlug,
    );

    try {
      await _post(api, item);
    } on ApiException catch (e) {
      if (!e.isPermanent) {
        await queue.add(item);
        _scheduleQueueFlush();
      }
    } catch (_) {
      await queue.add(item);
      _scheduleQueueFlush();
    }
    _publishSnapshot();
  }

  Future<void> _post(ScrobblrApi api, PendingScrobble item) {
    return api.submitScrobble(
      artist: item.artist,
      track: item.track,
      album: item.album,
      playedAt: DateTime.fromMillisecondsSinceEpoch(
        item.playedAtMs,
        isUtc: true,
      ),
      durationMs: item.durationMs,
      listenedMs: item.listenedMs,
      source: item.source,
    );
  }

  Future<void> _flushQueue() async {
    final api = _api;
    final queue = _queue;
    if (api == null || queue == null) return;

    for (final item in queue.due(_nowMs)) {
      try {
        await _post(api, item);
        await queue.remove(item);
      } on ApiException catch (e) {
        if (e.isPermanent) {
          // Rejected for good (validation/duplicate): never retry.
          await queue.remove(item);
        } else {
          item.scheduleRetry(_nowMs);
          await queue.persist();
        }
      } catch (_) {
        // Network is down; stop sweeping, everything else would fail too.
        item.scheduleRetry(_nowMs);
        await queue.persist();
        break;
      }
    }
    _scheduleQueueFlush();
    _publishSnapshot();
  }

  void _scheduleQueueFlush({bool immediately = false}) {
    _queueTimer?.cancel();
    _queueTimer = null;
    final queue = _queue;
    if (queue == null || queue.isEmpty || _api == null) return;
    final at = immediately ? _nowMs : (queue.nextAttemptAtMs() ?? _nowMs);
    final delayMs = (at - _nowMs).clamp(1000, 30 * 60 * 1000).toInt();
    _queueTimer = Timer(Duration(milliseconds: delayMs), _flushQueue);
  }

  Future<void> _reloadCredentials() async {
    final creds = await _store.read();
    _api?.close();
    _api =
        creds == null
            ? null
            : ScrobblrApi(baseUrl: creds.serverUrl, token: creds.apiToken);
  }

  Future<void> _reloadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _disabledPackages =
          (prefs.getStringList(prefDisabledSources) ?? const []).toSet();
      _customPackages =
          (prefs.getStringList(prefCustomSources) ?? const []).toSet();
      _catchAll = prefs.getBool(prefCatchAllEnabled) ?? true;
      _enabled = prefs.getBool(prefScrobblingEnabled) ?? true;
    } catch (_) {
      // Defaults stand.
    }
  }

  void _registerControlPort() {
    _controlPort?.close();
    IsolateNameServer.removePortNameMapping(bgControlPortName);
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, bgControlPortName);
    port.listen((message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'credentialsChanged':
          unawaited(
            _reloadCredentials().then((_) {
              _scheduleQueueFlush(immediately: true);
              _publishSnapshot();
            }),
          );
        case 'configChanged':
          unawaited(_reloadConfig().then((_) => _publishSnapshot()));
        case 'snapshotRequest':
          _publishSnapshot();
      }
    });
    _controlPort = port;
  }

  void _publishSnapshot() {
    final snap = _engine.snapshot(_nowMs);
    _syncNowPlayingNotification(snap);

    final port = IsolateNameServer.lookupPortByName(uiSnapshotPortName);
    if (port == null) return;
    port.send({
      'type': 'pipeline',
      ...snap,
      'queueLength': _queue?.length ?? 0,
      'authed': _api != null,
      'enabled': _enabled,
    });
  }

  /// Mirrors the actively playing track into the silent persistent
  /// notification (native side); cleared on pause/stop/disable. Snapshot
  /// publishing runs on every event and engine tick, so this stays fresh
  /// without its own timer.
  void _syncNowPlayingNotification(Map<String, Object?> snap) {
    final active = snap['active'] as Map<Object?, Object?>?;
    final playing = _enabled && active != null && active['playing'] == true;

    if (!playing) {
      if (_notifiedTrackKey != null) {
        _notifiedTrackKey = null;
        unawaited(
          _channel
              .invokeMethod<void>('clearNowPlayingNotification')
              .catchError((_) {}),
        );
      }
      return;
    }

    final title = active['title'] as String? ?? '';
    final artist = active['artist'] as String? ?? '';
    final album = active['album'] as String?;
    final key = '$artist $title';
    if (key == _notifiedTrackKey) return;
    _notifiedTrackKey = key;
    unawaited(
      _channel
          .invokeMethod<void>('nowPlayingNotification', {
            'title': title,
            'artist': artist,
            'album': album,
          })
          .catchError((_) {}),
    );
  }
}
