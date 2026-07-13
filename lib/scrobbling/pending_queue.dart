/// Disk-backed queue for scrobbles that failed to submit (offline, server
/// down). Survives process death; the background service retries with
/// exponential backoff. Pure Dart (`dart:io`), unit-testable with a temp
/// file.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class PendingScrobble {
  PendingScrobble({
    required this.artist,
    required this.track,
    required this.playedAtMs,
    this.album,
    this.durationMs,
    this.listenedMs,
    required this.source,
    this.attempts = 0,
    this.nextAttemptAtMs = 0,
  });

  final String artist;
  final String track;
  final String? album;
  final int playedAtMs;
  final int? durationMs;
  final int? listenedMs;
  final String source;

  int attempts;
  int nextAttemptAtMs;

  Map<String, Object?> toJson() => {
    'artist': artist,
    'track': track,
    'album': album,
    'playedAtMs': playedAtMs,
    'durationMs': durationMs,
    'listenedMs': listenedMs,
    'source': source,
    'attempts': attempts,
    'nextAttemptAtMs': nextAttemptAtMs,
  };

  static PendingScrobble? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artist = raw['artist'];
    final track = raw['track'];
    final playedAtMs = raw['playedAtMs'];
    if (artist is! String || track is! String || playedAtMs is! int) {
      return null;
    }
    return PendingScrobble(
      artist: artist,
      track: track,
      album: raw['album'] as String?,
      playedAtMs: playedAtMs,
      durationMs: raw['durationMs'] as int?,
      listenedMs: raw['listenedMs'] as int?,
      source: raw['source'] as String? ?? 'android',
      attempts: raw['attempts'] as int? ?? 0,
      nextAttemptAtMs: raw['nextAttemptAtMs'] as int? ?? 0,
    );
  }

  /// Backoff: 30 s · 2^attempts, capped at 30 min.
  void scheduleRetry(int nowMs) {
    attempts += 1;
    final delayMs = math.min(
      30000 * math.pow(2, attempts - 1).toInt(),
      30 * 60 * 1000,
    );
    nextAttemptAtMs = nowMs + delayMs;
  }
}

class PendingQueue {
  PendingQueue(this._file, {this.cap = 500});

  final File _file;

  /// Oldest entries are evicted beyond this, so a long offline stretch
  /// can't grow the file unboundedly.
  final int cap;

  final List<PendingScrobble> _items = [];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  Future<void> load() async {
    _items.clear();
    try {
      if (!await _file.exists()) return;
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! List) return;
      for (final entry in raw) {
        final item = PendingScrobble.fromJson(entry);
        if (item != null) _items.add(item);
      }
    } catch (_) {
      // Corrupt queue file: start over rather than wedge the service.
      _items.clear();
    }
  }

  Future<void> add(PendingScrobble item) async {
    _items.add(item);
    if (_items.length > cap) {
      _items.removeRange(0, _items.length - cap);
    }
    await _save();
  }

  /// Items whose backoff has elapsed, oldest first.
  List<PendingScrobble> due(int nowMs) =>
      _items.where((i) => i.nextAttemptAtMs <= nowMs).toList();

  Future<void> remove(PendingScrobble item) async {
    _items.remove(item);
    await _save();
  }

  /// Persist attempt bookkeeping after [PendingScrobble.scheduleRetry].
  Future<void> persist() => _save();

  /// Epoch ms of the earliest retry, or null when empty.
  int? nextAttemptAtMs() {
    int? soonest;
    for (final item in _items) {
      if (soonest == null || item.nextAttemptAtMs < soonest) {
        soonest = item.nextAttemptAtMs;
      }
    }
    return soonest;
  }

  Future<void> _save() async {
    try {
      await _file.writeAsString(
        jsonEncode([for (final i in _items) i.toJson()]),
        flush: true,
      );
    } on IOException {
      // Best effort: an unwritable queue must not crash the pipeline.
    }
  }
}
