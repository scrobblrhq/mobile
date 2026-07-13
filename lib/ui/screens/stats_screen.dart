import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../widgets/artwork.dart';
import 'artist_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.api, required this.auth});

  final NewfmApi api;
  final AuthController auth;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _period = 'overall';
  List<TopArtist>? _artists;
  List<TopTrack>? _tracks;
  String? _error;

  String get _username => widget.auth.credentials?.username ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _artists = null;
      _tracks = null;
      _error = null;
    });
    try {
      final artists = await widget.api.topArtists(_username, period: _period);
      final tracks = await widget.api.topTracks(
        _username,
        period: _period,
        limit: 25,
      );
      if (!mounted) return;
      setState(() {
        _artists = artists;
        _tracks = tracks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load stats.';
      });
    }
  }

  void _openArtist(int id, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ArtistScreen(
              api: widget.api,
              auth: widget.auth,
              artistId: id,
              artistName: name,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '7days', label: Text('Week')),
                  ButtonSegment(value: '1month', label: Text('Month')),
                  ButtonSegment(value: '1year', label: Text('Year')),
                  ButtonSegment(value: 'overall', label: Text('All')),
                ],
                selected: {_period},
                onSelectionChanged: (selection) {
                  setState(() => _period = selection.first);
                  unawaited(_load());
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
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
            else if (_artists == null || _tracks == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text('Top artists', style: text.titleMedium),
              const SizedBox(height: 12),
              if (_artists!.isEmpty)
                Text(
                  'No listens in this period.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                SizedBox(
                  height: 128,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _artists!.length,
                    separatorBuilder:
                        (context, index) => const SizedBox(width: 16),
                    itemBuilder: (context, i) {
                      final artist = _artists![i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap:
                            () =>
                                _openArtist(artist.artistId, artist.artistName),
                        child: SizedBox(
                          width: 84,
                          child: Column(
                            children: [
                              Artwork(
                                url: artist.imageUrl,
                                size: 72,
                                circle: true,
                                initialsSource: artist.artistName,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                artist.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium,
                              ),
                              Text(
                                '${artist.playCount} plays',
                                style: text.labelSmall?.copyWith(
                                  color: scheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              Text('Top tracks', style: text.titleMedium),
              const SizedBox(height: 4),
              if (_tracks!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No listens in this period.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final (index, track) in _tracks!.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 76,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: text.labelLarge?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Artwork(url: track.albumImage, size: 48),
                        ],
                      ),
                    ),
                    title: Text(
                      track.trackTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '${track.playCount}×',
                      style: text.labelMedium,
                    ),
                    onTap: () => _openArtist(track.artistId, track.artistName),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
