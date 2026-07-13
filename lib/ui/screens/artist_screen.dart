import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/comments_section.dart';
import '../widgets/image_candidates_row.dart';
import '../widgets/listeners_row.dart';
import 'profile_screen.dart';
import 'track_screen.dart';

/// Artist detail: worker-enriched metadata (Deezer image, Last.fm bio,
/// MusicBrainz link) with fallbacks and a "refresh metadata" action, plus
/// social sections (top tracks, top listeners) and community-art upload.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.artistId,
    this.artistName,
  });

  final ScrobblrApi api;
  final AuthController auth;
  final int artistId;
  final String? artistName;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  List<TopTrack>? _topTracks;
  List<TopListener>? _listeners;
  List<ImageCandidate>? _images;
  String? _error;
  bool _refreshQueued = false;
  bool _uploading = false;
  int _refreshEpoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final artist = await widget.api.artist(widget.artistId);
      final results = await Future.wait([
        widget.api.artistTopTracks(widget.artistId),
        widget.api.artistListeners(widget.artistId),
        widget.api.artistImages(widget.artistId),
      ]);
      if (!mounted) return;
      setState(() {
        _artist = artist;
        _topTracks = results[0] as List<TopTrack>;
        _listeners = results[1] as List<TopListener>;
        _images = results[2] as List<ImageCandidate>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load artist.';
      });
    }
  }

  Future<void> _toggleVote(ImageCandidate candidate) async {
    try {
      final images =
          candidate.hasVoted
              ? await widget.api.unvoteImage(candidate.id)
              : await widget.api.voteImage(candidate.id);
      if (!mounted) return;
      setState(() => _images = images);
      // A vote may have promoted a new default image; refresh the header.
      final artist = await widget.api.artist(widget.artistId);
      if (mounted) setState(() => _artist = artist);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not register the vote.')),
      );
    }
  }

  Future<void> _queueRefresh() async {
    try {
      await widget.api.refreshArtist(widget.artistId);
      if (!mounted) return;
      setState(() => _refreshQueued = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refresh queued — this page updates automatically.'),
        ),
      );
      unawaited(_reloadAfterRefresh());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not queue the refresh.')),
      );
    }
  }

  /// The worker claims refresh jobs within ~5 s and they run in about a
  /// second; reload shortly after, once more for slow providers, then
  /// re-enable the refresh action.
  Future<void> _reloadAfterRefresh() async {
    final epoch = ++_refreshEpoch;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || epoch != _refreshEpoch) return;
    await _load();
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!mounted || epoch != _refreshEpoch) return;
    await _load();
    if (!mounted || epoch != _refreshEpoch) return;
    setState(() => _refreshQueued = false);
  }

  /// Proposes community artwork for this artist. The upload becomes a
  /// candidate; it only replaces the shown image once it wins the vote.
  Future<void> _uploadImage() async {
    try {
      // Inside the try so picker failures (PlatformException, denied
      // access) surface through the same error handling as the upload.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final images = await widget.api.uploadArtistImage(widget.artistId, bytes);
      if (!mounted) return;
      setState(() => _images = images);
      // Might have won immediately on a tiny community; refresh the header.
      final artist = await widget.api.artist(widget.artistId);
      if (!mounted) return;
      setState(() => _artist = artist);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image proposed — it wins once it gets enough likes.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.isEmpty ? 'Upload failed' : e.message),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload the image.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openTrack(TopTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => TrackScreen(
              api: widget.api,
              auth: widget.auth,
              trackId: track.trackId,
              trackTitle: track.trackTitle,
              artistName: track.artistName,
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
    final artist = _artist;

    return Scaffold(
      appBar: AppBar(
        title: Text(artist?.name ?? widget.artistName ?? 'Artist'),
        actions: [
          IconButton(
            tooltip: 'Upload image',
            icon:
                _uploading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.add_photo_alternate_outlined),
            onPressed: artist == null || _uploading ? null : _uploadImage,
          ),
          IconButton(
            tooltip: 'Refresh metadata',
            icon: const Icon(Icons.auto_awesome),
            onPressed: artist == null || _refreshQueued ? null : _queueRefresh,
          ),
        ],
      ),
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
              : artist == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: Artwork(
                        url: artist.imageUrl,
                        size: 112,
                        circle: true,
                        initialsSource: artist.name,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(child: Text(artist.name, style: text.headlineSmall)),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '${artist.scrobbleCount} scrobbles · '
                        '${artist.listenerCount} listeners',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (artist.mbid != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'MusicBrainz linked',
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('About', style: text.titleMedium),
                    const SizedBox(height: 8),
                    if (artist.bio != null && artist.bio!.isNotEmpty)
                      Text(artist.bio!, style: text.bodyMedium)
                    else
                      _MetadataPendingCard(
                        artist: artist,
                        refreshQueued: _refreshQueued,
                        onRefresh: _queueRefresh,
                      ),
                    if ((_topTracks ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Top tracks', style: text.titleMedium),
                      const SizedBox(height: 4),
                      for (final (index, track) in _topTracks!.indexed)
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
                          trailing: Text(
                            '${track.playCount}×',
                            style: text.labelMedium,
                          ),
                          onTap: () => _openTrack(track),
                        ),
                    ],
                    if ((_listeners ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Listeners', style: text.titleMedium),
                      const SizedBox(height: 12),
                      ListenersRow(
                        listeners: _listeners!,
                        onOpenUser: _openUser,
                      ),
                    ],
                    if ((_images ?? const []).isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Images', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Community uploads — the most-liked becomes the '
                        'default. Tap the heart to vote.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ImageCandidatesRow(
                        candidates: _images!,
                        onToggleVote: (c) => unawaited(_toggleVote(c)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Comments', style: text.titleMedium),
                    const SizedBox(height: 12),
                    CommentsSection(
                      load: () => widget.api.artistComments(widget.artistId),
                      add:
                          (body) => widget.api.addArtistComment(
                            widget.artistId,
                            body,
                          ),
                      remove: (id) => widget.api.deleteComment(id),
                      currentUserId: widget.auth.credentials?.userId,
                    ),
                  ],
                ),
              ),
    );
  }
}

class _MetadataPendingCard extends StatelessWidget {
  const _MetadataPendingCard({
    required this.artist,
    required this.refreshQueued,
    required this.onRefresh,
  });

  final Artist artist;
  final bool refreshQueued;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Image or MBID present means the enrichment worker has already run —
    // the bio just isn't available.
    final enriched = artist.imageUrl != null || artist.mbid != null;

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  enriched ? 'No bio available' : 'Metadata pending',
                  style: text.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              enriched
                  ? 'The providers returned no bio for this artist. Bios '
                      'come from Last.fm — the server needs a Last.fm API '
                      'key configured for them to appear.'
                  : 'No bio yet. The enrichment worker fills in images, bios '
                      'and MusicBrainz links in the background — or trigger '
                      'it now.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: refreshQueued ? null : () => onRefresh(),
              icon: const Icon(Icons.refresh),
              label: Text(refreshQueued ? 'Queued…' : 'Refresh metadata'),
            ),
          ],
        ),
      ),
    );
  }
}
