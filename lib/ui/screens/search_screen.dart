import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../widgets/artwork.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';
import 'track_screen.dart';

/// Search across artists, tracks and users. The query is debounced; results
/// are grouped into sections that navigate to the matching detail screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, required this.auth});

  final NewfmApi api;
  final AuthController auth;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  SearchResults? _results;
  bool _loading = false;
  String? _error;
  // Guards against out-of-order responses when queries fire quickly.
  int _queryEpoch = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_run(query));
    });
  }

  Future<void> _run(String query) async {
    final epoch = ++_queryEpoch;
    try {
      final results = await widget.api.search(query);
      if (!mounted || epoch != _queryEpoch) return;
      setState(() {
        _results = results;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _queryEpoch) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Search failed.';
        _loading = false;
      });
    }
  }

  void _openArtist(Artist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ArtistScreen(
              api: widget.api,
              auth: widget.auth,
              artistId: artist.id,
              artistName: artist.name,
            ),
      ),
    );
  }

  void _openTrack(Track track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => TrackScreen(
              api: widget.api,
              auth: widget.auth,
              trackId: track.id,
              trackTitle: track.title,
            ),
      ),
    );
  }

  void _openUser(UserProfile user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ProfileScreen(
              api: widget.api,
              auth: widget.auth,
              username: user.username,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Artists, tracks, people…',
            border: InputBorder.none,
            suffixIcon:
                _controller.text.isEmpty
                    ? null
                    : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
          ),
        ),
      ),
      body:
          _error != null
              ? Center(
                child: Text(
                  _error!,
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              )
              : results == null
              ? Center(
                child: Text(
                  _loading ? 'Searching…' : 'Type to search.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
              : results.isEmpty
              ? Center(
                child: Text(
                  'No results.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
              : ListView(
                children: [
                  if (results.artists.isNotEmpty) ...[
                    _SectionHeader('Artists'),
                    for (final artist in results.artists)
                      ListTile(
                        leading: Artwork(
                          url: artist.imageUrl,
                          size: 44,
                          circle: true,
                          initialsSource: artist.name,
                        ),
                        title: Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${artist.scrobbleCount} scrobbles'),
                        onTap: () => _openArtist(artist),
                      ),
                  ],
                  if (results.tracks.isNotEmpty) ...[
                    _SectionHeader('Tracks'),
                    for (final track in results.tracks)
                      ListTile(
                        leading: const Artwork(url: null, size: 44),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${track.scrobbleCount} scrobbles'),
                        onTap: () => _openTrack(track),
                      ),
                  ],
                  if (results.users.isNotEmpty) ...[
                    _SectionHeader('People'),
                    for (final user in results.users)
                      ListTile(
                        leading: Artwork(
                          url: user.imageUrl,
                          size: 44,
                          circle: true,
                          initialsSource: user.displayName ?? user.username,
                        ),
                        title: Text(
                          user.displayName ?? user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('@${user.username}'),
                        onTap: () => _openUser(user),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
