import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../format.dart';
import 'artwork.dart';

/// The single now-playing surface: merges the server's live state (SSE
/// `/user/{name}/live`) with the local pipeline snapshot from the
/// background engine, so there is exactly one card and one progress bar.
///
/// The bar shows scrobble progress (listened / threshold) whenever the
/// local pipeline is tracking; otherwise it falls back to time progress
/// interpolated from the server's `started_at`/`expires_at`.
class NowPlayingCard extends StatefulWidget {
  const NowPlayingCard({
    super.key,
    required this.nowPlaying,
    required this.pipeline,
  });

  final NowPlayingRich? nowPlaying;
  final Map<Object?, Object?>? pipeline;

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  double? get _timeProgress {
    final np = widget.nowPlaying;
    if (np == null) return null;
    final total = np.expiresAt.difference(np.startedAt).inMilliseconds;
    if (total <= 0) return null;
    final elapsed =
        DateTime.now().toUtc().difference(np.startedAt).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final np = widget.nowPlaying;
    final snap = widget.pipeline;
    final active = snap?['active'] as Map<Object?, Object?>?;
    final queueLength = (snap?['queueLength'] as num?)?.toInt() ?? 0;
    final enabled = snap?['enabled'] != false;

    if (np == null && active == null) {
      return _idleCard(context, snap, enabled, queueLength);
    }

    // Track identity: the server view carries artwork and clean album
    // metadata; the local pipeline is faster and works offline.
    final title = np?.trackTitle ?? active?['title'] as String? ?? '';
    final artist = np?.artistName ?? active?['artist'] as String? ?? '';
    final album = np?.albumTitle ?? active?['album'] as String?;
    final source = np?.source ?? active?['source'] as String? ?? '';
    final confident = active?['confident'] != false;

    final subtitle = album == null ? artist : '$artist • $album';

    // Pipeline status + the one progress bar.
    String? status;
    IconData statusIcon = Icons.music_note;
    double? progress = _timeProgress;

    switch (active?['phase']) {
      case 'settling':
        final settleMs = (active?['settledInMs'] as num?)?.toInt() ?? 0;
        statusIcon = Icons.av_timer;
        status =
            'Accepting in ${(settleMs / 1000).ceil()}s'
            '${confident ? '' : ' (guessed)'}';
      case 'tracking':
        final listened = (active?['listenedMs'] as num?)?.toInt() ?? 0;
        final threshold = (active?['thresholdMs'] as num?)?.toInt() ?? 1;
        final eligible = active?['eligible'] != false;
        final playing = active?['playing'] == true;
        if (!eligible) {
          statusIcon = Icons.timer_off_outlined;
          status = 'Too short to scrobble';
        } else if (playing) {
          statusIcon = Icons.schedule;
          status =
              'Scrobbles in '
              '${formatDuration((threshold - listened).clamp(0, threshold).toInt())}';
          progress = (listened / threshold).clamp(0.0, 1.0).toDouble();
        } else {
          statusIcon = Icons.pause;
          status = 'Paused';
        }
      case 'scrobbled':
        statusIcon = Icons.check_circle;
        status = 'Scrobbled';
        final listened = (active?['listenedMs'] as num?)?.toInt();
        final duration = (active?['durationMs'] as num?)?.toInt();
        if (listened != null && duration != null && duration > 0) {
          progress = (listened / duration).clamp(0.0, 1.0).toDouble();
        }
      default:
        break;
    }

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Now playing',
                  style: text.labelMedium?.copyWith(color: scheme.primary),
                ),
                const Spacer(),
                if (queueLength > 0) ...[
                  _Tag(
                    label: '$queueLength queued',
                    background: scheme.tertiaryContainer,
                    foreground: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 6),
                ],
                _Tag(
                  label: sourceLabel(source),
                  background: scheme.secondaryContainer,
                  foreground: scheme.onSecondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Artwork(url: np?.artworkUrl, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              statusIcon,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                status,
                                style: text.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: progress),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Nothing playing: compact status of what the scrobbler is doing.
  Widget _idleCard(
    BuildContext context,
    Map<Object?, Object?>? snap,
    bool enabled,
    int queueLength,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (icon, message) =
        snap == null
            ? (Icons.hourglass_empty, 'Waiting for the scrobbler…')
            : !enabled
            ? (Icons.pause_circle, 'Scrobbling paused')
            : (Icons.radar, 'Listening for players…');

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: text.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (queueLength > 0)
              _Tag(
                label: '$queueLength queued',
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
