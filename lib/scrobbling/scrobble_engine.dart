/// The dedupe/debounce state machine between raw player events and API
/// submissions.
///
/// Pure and deterministic: no timers, no clocks, no I/O. Callers feed it
/// events plus the current epoch-ms and drive time by calling [tick] at
/// [nextDeadlineMs]. That makes the whole lifecycle — debounce, play-time
/// accounting, scrobble thresholds, replays — testable with a fake clock.
///
/// Per media session:
///
///   raw event → parser → candidate ──(settles [ScrobbleRules.settleMs]
///   while playing)──> current play → NowPlayingAction, then accumulates
///   wall-clock listen time while playing → ScrobbleAction at threshold.
///
/// Dedupe guarantees:
///  * A track change only counts after it survives the settle window —
///    skipping through a playlist emits nothing.
///  * One scrobble per play session; a replay (position back near zero
///    after a scrobble) starts a fresh session.
///  * Quick A→B→A flips within the settle window keep A's accumulated
///    listen time (B was never accepted, A was never abandoned).
///  * The submitter additionally drops identical submissions within 30 s,
///    mirroring the server's dedupe rule.
library;

import 'parsed_track.dart';
import 'player_event.dart';
import 'scrobble_rules.dart';
import 'source_parsers.dart';

sealed class EngineAction {
  const EngineAction();
}

/// Announce the accepted track as now playing.
class NowPlayingAction extends EngineAction {
  const NowPlayingAction(this.track);
  final ParsedTrack track;
}

/// Submit a scrobble. [playedAtMs] is when the listen *started*
/// (last.fm semantics).
class ScrobbleAction extends EngineAction {
  const ScrobbleAction({
    required this.track,
    required this.playedAtMs,
    required this.listenedMs,
  });

  final ParsedTrack track;
  final int playedAtMs;
  final int listenedMs;
}

/// A not-yet-accepted track change, waiting out the settle window.
class _Candidate {
  _Candidate(this.track, {required this.sinceMs, required this.playing});

  ParsedTrack track;
  int sinceMs;
  bool playing;
}

/// An accepted play session.
class _Play {
  _Play(this.track, {required this.startedAtMs, required int nowMs})
    : accumulatedMs = nowMs - startedAtMs,
      playingSinceMs = nowMs;

  ParsedTrack track;

  /// Wall-clock start of the listen (candidate first seen).
  final int startedAtMs;

  /// Listened time banked while previous playing stretches were open.
  int accumulatedMs;

  /// Set while playing; null while paused.
  int? playingSinceMs;

  bool scrobbled = false;

  int listenedMs(int nowMs) {
    final since = playingSinceMs;
    return accumulatedMs + (since == null ? 0 : nowMs - since);
  }

  void stopClock(int nowMs) {
    final since = playingSinceMs;
    if (since != null) {
      accumulatedMs += nowMs - since;
      playingSinceMs = null;
    }
  }

  void startClock(int nowMs) {
    playingSinceMs ??= nowMs;
  }
}

class _SessionState {
  _SessionState(this.packageName);

  final String packageName;
  _Candidate? candidate;
  _Play? current;
}

class ScrobbleEngine {
  ScrobbleEngine({this.rules = const ScrobbleRules(), ParserRegistry? registry})
    : _registry = registry ?? ParserRegistry();

  final ScrobbleRules rules;
  final ParserRegistry _registry;
  final Map<String, _SessionState> _sessions = {};

  List<EngineAction> handleEvent(PlayerEvent event, int nowMs) {
    if (event.origin == PlayerEventOrigin.sessionEnded) {
      // Nothing retroactive: an unreached threshold means no scrobble.
      _sessions.remove(event.sessionKey);
      return _tickInternal(nowMs);
    }

    final session = _sessions.putIfAbsent(
      event.sessionKey,
      () => _SessionState(event.packageName),
    );

    final parsed = _registry.parserFor(event.packageName).parse(event);
    if (parsed == null) {
      // Junk (ad break, metadata-less state): freeze accounting, drop any
      // pending candidate. The current play survives so a resume of the
      // same track keeps its banked listen time.
      session.candidate = null;
      session.current?.stopClock(nowMs);
      return _tickInternal(nowMs);
    }

    final current = session.current;
    if (current != null && parsed.key == current.track.key) {
      session.candidate = null;
      // Late metadata refinements (duration often arrives on a later event).
      current.track = current.track.copyWith(
        durationMs: parsed.durationMs,
        album: parsed.album,
      );

      final isReplay =
          event.playing &&
          current.scrobbled &&
          event.positionMs != null &&
          event.positionMs! <= rules.replayPositionMs;
      if (isReplay) {
        session.current = _Play(
          current.track,
          startedAtMs: nowMs,
          nowMs: nowMs,
        );
        return [NowPlayingAction(current.track), ..._tickInternal(nowMs)];
      }

      if (event.playing) {
        current.startClock(nowMs);
      } else {
        current.stopClock(nowMs);
      }
      return _tickInternal(nowMs);
    }

    final candidate = session.candidate;
    if (candidate != null && parsed.key == candidate.track.key) {
      candidate.track = parsed;
      if (event.playing && !candidate.playing) {
        // Was paused mid-settle: restart the window from the resume.
        candidate.sinceMs = nowMs;
      }
      candidate.playing = event.playing;
      return _tickInternal(nowMs);
    }

    // A different track: it becomes the candidate. The current play's clock
    // stops but the play itself is kept until the candidate settles, so a
    // quick skip-away-and-back does not lose accumulated time.
    session.current?.stopClock(nowMs);
    session.candidate = _Candidate(
      parsed,
      sinceMs: nowMs,
      playing: event.playing,
    );
    return _tickInternal(nowMs);
  }

  /// Advances time-based transitions. Call at [nextDeadlineMs].
  List<EngineAction> tick(int nowMs) => _tickInternal(nowMs);

  List<EngineAction> _tickInternal(int nowMs) {
    final actions = <EngineAction>[];

    for (final session in _sessions.values) {
      final candidate = session.candidate;
      if (candidate != null &&
          candidate.playing &&
          nowMs - candidate.sinceMs >= rules.settleMs) {
        // Accepted: the previous play is abandoned, the candidate becomes
        // the current play. Listen time starts at first sight, so the
        // settle window itself counts as listened.
        session.current = _Play(
          candidate.track,
          startedAtMs: candidate.sinceMs,
          nowMs: nowMs,
        );
        session.candidate = null;
        actions.add(NowPlayingAction(candidate.track));
      }

      final play = session.current;
      if (play != null &&
          !play.scrobbled &&
          play.playingSinceMs != null &&
          rules.isEligible(play.track.durationMs)) {
        final threshold = rules.thresholdFor(play.track.durationMs);
        if (play.listenedMs(nowMs) >= threshold) {
          play.scrobbled = true;
          actions.add(
            ScrobbleAction(
              track: play.track,
              playedAtMs: play.startedAtMs,
              listenedMs: play.listenedMs(nowMs),
            ),
          );
        }
      }
    }

    return actions;
  }

  /// Epoch ms of the next pending transition, or null when idle.
  /// The driver schedules a single timer for this instant.
  int? nextDeadlineMs() {
    int? soonest;
    void consider(int deadline) {
      if (soonest == null || deadline < soonest!) soonest = deadline;
    }

    for (final session in _sessions.values) {
      final candidate = session.candidate;
      if (candidate != null && candidate.playing) {
        consider(candidate.sinceMs + rules.settleMs);
      }
      final play = session.current;
      if (play != null &&
          !play.scrobbled &&
          play.playingSinceMs != null &&
          rules.isEligible(play.track.durationMs)) {
        final remaining =
            rules.thresholdFor(play.track.durationMs) - play.accumulatedMs;
        consider(play.playingSinceMs! + remaining);
      }
    }
    return soonest;
  }

  /// SendPort-safe snapshot for the UI pipeline monitor.
  Map<String, Object?> snapshot(int nowMs) {
    Map<String, Object?>? active;

    for (final entry in _sessions.entries) {
      final session = entry.value;
      final play = session.current;
      final candidate = session.candidate;

      Map<String, Object?>? described;
      if (candidate != null) {
        described = {
          'phase': 'settling',
          'artist': candidate.track.artist,
          'title': candidate.track.title,
          'album': candidate.track.album,
          'source': candidate.track.sourceSlug,
          'confident': candidate.track.confident,
          'playing': candidate.playing,
          'settledInMs': (candidate.sinceMs + rules.settleMs - nowMs).clamp(
            0,
            1 << 31,
          ),
        };
      } else if (play != null) {
        final threshold = rules.thresholdFor(play.track.durationMs);
        described = {
          'phase': play.scrobbled ? 'scrobbled' : 'tracking',
          'artist': play.track.artist,
          'title': play.track.title,
          'album': play.track.album,
          'source': play.track.sourceSlug,
          'confident': play.track.confident,
          'playing': play.playingSinceMs != null,
          'listenedMs': play.listenedMs(nowMs),
          'thresholdMs': threshold,
          'eligible': rules.isEligible(play.track.durationMs),
          'durationMs': play.track.durationMs,
        };
      }

      if (described != null) {
        described['package'] = session.packageName;
        // Prefer an actively playing session for the monitor.
        if (active == null || described['playing'] == true) {
          active = described;
        }
      }
    }

    return {'active': active, 'atMs': nowMs};
  }
}
