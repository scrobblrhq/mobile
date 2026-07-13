import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../format.dart';
import '../widgets/artwork.dart';
import '../widgets/comments_section.dart';
import '../widgets/listeners_row.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';

/// Track detail: catalog metadata plus a social section of the users who
/// scrobble this track the most.
class TrackScreen extends StatefulWidget {
  const TrackScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.trackId,
    this.trackTitle,
    this.artistName,
  });

  final NewfmApi api;
  final AuthController auth;
  final int trackId;
  final String? trackTitle;
  final String? artistName;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  Track? _track;
  Artist? _artist;
  List<TopListener>? _listeners;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final track = await widget.api.track(widget.trackId);
      final results = await Future.wait([
        widget.api.artist(track.artistId),
        widget.api.trackListeners(widget.trackId),
      ]);
      if (!mounted) return;
      setState(() {
        _track = track;
        _artist = results[0] as Artist;
        _listeners = results[1] as List<TopListener>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load track.';
      });
    }
  }

  void _openArtist() {
    final track = _track;
    if (track == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ArtistScreen(
              api: widget.api,
              auth: widget.auth,
              artistId: track.artistId,
              artistName: _artist?.name ?? widget.artistName,
            ),
      ),
    );
  }

  void _openUser(String username) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ProfileScreen(
              api: widget.api,
              auth: widget.auth,
              username: username,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final track = _track;
    final listeners = _listeners ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(track?.title ?? widget.trackTitle ?? 'Track')),
      body:
          _error != null
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : track == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: Artwork(
                        url: _artist?.imageUrl,
                        size: 112,
                        initialsSource: _artist?.name ?? widget.artistName,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        track.title,
                        style: text.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: _openArtist,
                        child: Text(
                          _artist?.name ?? widget.artistName ?? 'Artist',
                          style: text.titleMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        [
                          '${track.scrobbleCount} scrobbles',
                          if (track.durationMs != null)
                            formatDuration(track.durationMs!),
                        ].join(' · '),
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Top listeners', style: text.titleMedium),
                    const SizedBox(height: 12),
                    if (listeners.isEmpty)
                      Text(
                        'No listeners yet.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ListenersRow(listeners: listeners, onOpenUser: _openUser),
                    const SizedBox(height: 28),
                    Text('Comments', style: text.titleMedium),
                    const SizedBox(height: 12),
                    CommentsSection(
                      load: () => widget.api.trackComments(widget.trackId),
                      add:
                          (body) =>
                              widget.api.addTrackComment(widget.trackId, body),
                      remove: (id) => widget.api.deleteComment(id),
                      currentUserId: widget.auth.credentials?.userId,
                    ),
                  ],
                ),
              ),
    );
  }
}
