import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../widgets/artwork.dart';
import 'profile_screen.dart';

/// Follower and following lists for a user; rows navigate to that user's
/// profile.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.username,
  });

  final NewfmApi api;
  final AuthController auth;
  final String username;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  Friends? _friends;
  String? _error;
  bool _showFollowers = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final friends = await widget.api.friends(widget.username);
      if (!mounted) return;
      setState(() => _friends = friends);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load friends.';
      });
    }
  }

  void _openProfile(UserProfile user) {
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
    final friends = _friends;
    final users =
        friends == null
            ? const <UserProfile>[]
            : _showFollowers
            ? friends.followers
            : friends.following;

    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('Followers (${friends?.followers.length ?? 0})'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Following (${friends?.following.length ?? 0})'),
                ),
              ],
              selected: {_showFollowers},
              onSelectionChanged:
                  (selection) =>
                      setState(() => _showFollowers = selection.first),
            ),
          ),
          Expanded(
            child:
                _error != null
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
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
                    )
                    : friends == null
                    ? const Center(child: CircularProgressIndicator())
                    : users.isEmpty
                    ? Center(
                      child: Text(
                        _showFollowers
                            ? 'No followers yet.'
                            : 'Not following anyone yet.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                    : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final user = users[i];
                          return ListTile(
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
                            subtitle: Text(
                              '@${user.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openProfile(user),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
