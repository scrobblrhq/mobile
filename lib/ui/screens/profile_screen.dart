import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../widgets/activity_heatmap.dart';
import '../widgets/artwork.dart';
import '../widgets/scrobble_tile.dart';
import 'artist_screen.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';

/// A user profile: identity header (avatar, bio, follower counts),
/// GitHub-style activity heatmap, recent scrobbles and all-time tops.
///
/// With no [username] it shows the signed-in user's own profile (the tab)
/// with an edit action; with one it shows that user's public profile with a
/// follow/unfollow button, honoring private profiles.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.auth,
    this.username,
  });

  final NewfmApi api;
  final AuthController auth;
  final String? username;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  Friends? _friends;
  List<ActivityDay>? _activity;
  List<ScrobbleRich>? _recent;
  List<TopArtist>? _topArtists;
  List<TopTrack>? _topTracks;
  String? _error;
  bool _private = false;
  bool? _isFollowing;
  bool _followBusy = false;

  bool get _isOwn =>
      widget.username == null ||
      widget.username == widget.auth.credentials?.username;

  String get _username =>
      widget.username ?? widget.auth.credentials?.username ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _private = false;
    });
    try {
      // Profile first: it carries the visibility verdict (403 = private).
      final profile =
          _isOwn
              ? await widget.api.me()
              : await widget.api.userProfile(_username);
      final results = await Future.wait([
        widget.api.heatmap(_username),
        widget.api.recentScrobbles(_username, limit: 8),
        widget.api.topArtists(_username, limit: 10),
        widget.api.topTracks(_username, limit: 5),
        widget.api.friends(_username),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isFollowing = profile.isFollowing;
        _activity = results[0] as List<ActivityDay>;
        _recent = results[1] as List<ScrobbleRich>;
        _topArtists = results[2] as List<TopArtist>;
        _topTracks = results[3] as List<TopTrack>;
        _friends = results[4] as Friends;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 403) {
          _private = true;
        } else {
          _error = e.message.isEmpty ? 'Could not load profile.' : e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load profile.');
    }
  }

  Future<void> _toggleFollow() async {
    final following = _isFollowing ?? false;
    setState(() => _followBusy = true);
    try {
      if (following) {
        await widget.api.unfollowUser(_username);
      } else {
        await widget.api.followUser(_username);
      }
      if (!mounted) return;
      setState(() => _isFollowing = !following);
      // Refresh the counts shown in the header.
      final friends = await widget.api.friends(_username);
      if (mounted) setState(() => _friends = friends);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update follow state.')),
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _edit() async {
    final profile = _profile;
    if (profile == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(api: widget.api, profile: profile),
      ),
    );
    if (saved == true) unawaited(_load());
  }

  void _openFriends() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => FriendsScreen(
              api: widget.api,
              auth: widget.auth,
              username: _username,
            ),
      ),
    );
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

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOwn ? 'Profile' : '@$_username'),
        actions: [
          if (_isOwn && profile != null)
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => unawaited(_edit()),
            ),
        ],
      ),
      body:
          _private
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 48, color: scheme.outline),
                      const SizedBox(height: 12),
                      Text('@$_username', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'This profile is private.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: _load,
                // A failed refresh keeps showing the data we already have; the
                // error/retry view is only for the initial load.
                child:
                    _error != null && profile == null
                        ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 64),
                              child: Column(
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: text.bodyMedium?.copyWith(
                                      color: scheme.error,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: _load,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                        : profile == null
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _Header(
                              profile: profile,
                              friends: _friends,
                              isOwn: _isOwn,
                              isFollowing: _isFollowing,
                              followBusy: _followBusy,
                              onToggleFollow: () => unawaited(_toggleFollow()),
                              onOpenFriends: _openFriends,
                            ),
                            _section('Activity'),
                            Card.outlined(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: ActivityHeatmap(
                                  days: _activity ?? const [],
                                ),
                              ),
                            ),
                            _section('Recent scrobbles'),
                            if ((_recent ?? const []).isEmpty)
                              Text(
                                'Nothing scrobbled yet.',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            else
                              for (final scrobble in _recent!)
                                ScrobbleTile(
                                  scrobble: scrobble,
                                  onTap:
                                      () => _openArtist(
                                        scrobble.artistId,
                                        scrobble.artistName,
                                      ),
                                ),
                            _section('Top artists'),
                            if ((_topArtists ?? const []).isEmpty)
                              Text(
                                'No listens yet.',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            else
                              SizedBox(
                                height: 128,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _topArtists!.length,
                                  separatorBuilder:
                                      (context, index) =>
                                          const SizedBox(width: 16),
                                  itemBuilder: (context, i) {
                                    final artist = _topArtists![i];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap:
                                          () => _openArtist(
                                            artist.artistId,
                                            artist.artistName,
                                          ),
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
                            _section('Top tracks'),
                            if ((_topTracks ?? const []).isEmpty)
                              Text(
                                'No listens yet.',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            else
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
                                        Artwork(
                                          url: track.albumImage,
                                          size: 48,
                                        ),
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
                                  onTap:
                                      () => _openArtist(
                                        track.artistId,
                                        track.artistName,
                                      ),
                                ),
                          ],
                        ),
              ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.friends,
    required this.isOwn,
    required this.isFollowing,
    required this.followBusy,
    required this.onToggleFollow,
    required this.onOpenFriends,
  });

  final UserProfile profile;
  final Friends? friends;
  final bool isOwn;
  final bool? isFollowing;
  final bool followBusy;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenFriends;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final following = isFollowing ?? false;
    final bio = profile.bio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Artwork(
              url: profile.imageUrl,
              size: 64,
              circle: true,
              initialsSource: profile.displayName ?? profile.username,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName ?? profile.username,
                    style: text.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${profile.username}',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${profile.scrobbleCount} scrobbles',
                    style: text.labelMedium?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ),
            if (!isOwn)
              following
                  ? OutlinedButton(
                    onPressed: followBusy ? null : onToggleFollow,
                    child: const Text('Following'),
                  )
                  : FilledButton(
                    onPressed: followBusy ? null : onToggleFollow,
                    child: const Text('Follow'),
                  ),
          ],
        ),
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(bio, style: text.bodyMedium),
        ],
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
          ),
          onPressed: onOpenFriends,
          child: Text(
            '${friends?.followers.length ?? 0} followers · '
            '${friends?.following.length ?? 0} following',
            style: text.labelMedium,
          ),
        ),
      ],
    );
  }
}
