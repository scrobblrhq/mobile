/// Scrobbling thresholds (last.fm-style), kept strictly within what the
/// backend accepts (`shared::scrobble::validate`: listened >= 30 s OR >= 50%
/// of duration).
library;

import 'dart:math' as math;

class ScrobbleRules {
  const ScrobbleRules({
    this.settleMs = 5000,
    this.minTrackMs = 30000,
    this.absoluteScrobbleMs = 240000,
    this.replayPositionMs = 5000,
  });

  /// Debounce window: a track change must survive this long, playing, with no
  /// further change before we accept it (skipping through a playlist neither
  /// spams now-playing nor starts play accounting).
  final int settleMs;

  /// Tracks shorter than this never scrobble (last.fm rule; also the
  /// server's absolute minimum listen time).
  final int minTrackMs;

  /// Cap: anything counts as scrobbled after this much listening,
  /// regardless of duration. Also the threshold when duration is unknown.
  final int absoluteScrobbleMs;

  /// A position report below this while the same track keeps playing after a
  /// scrobble is treated as a replay (repeat-one, manual restart).
  final int replayPositionMs;

  /// Listened milliseconds required before submitting.
  ///
  /// Known duration: half the track, clamped to [minTrackMs,
  /// absoluteScrobbleMs] — the 30 s floor guarantees the server's absolute
  /// rule is always met. Unknown duration: the 4-minute cap.
  int thresholdFor(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return absoluteScrobbleMs;
    return math.max(minTrackMs, math.min(durationMs ~/ 2, absoluteScrobbleMs));
  }

  /// Tracks with a known duration under [minTrackMs] are never scrobbled.
  bool isEligible(int? durationMs) =>
      durationMs == null || durationMs >= minTrackMs;
}
