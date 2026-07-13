import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/auth_controller.dart';
import '../../background/service_client.dart';
import '../widgets/now_playing_card.dart';
import '../widgets/scrobble_tile.dart';
import 'artist_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.service,
  });

  final NewfmApi api;
  final AuthController auth;
  final ScrobbleServiceClient service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _pageSize = 50;

  final ScrollController _scroll = ScrollController();

  StreamSubscription<NowPlayingRich?>? _liveSub;
  StreamSubscription<Map<Object?, Object?>>? _pipelineSub;
  Timer? _snapshotTicker;

  NowPlayingRich? _nowPlaying;
  Map<Object?, Object?>? _pipeline;
  List<ScrobbleRich>? _scrobbles;
  String? _error;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  bool _listenerEnabled = true;

  String get _username => widget.auth.credentials?.username ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _liveSub = widget.api.liveNowPlaying(_username).listen((np) {
      if (mounted) setState(() => _nowPlaying = np);
    });
    _pipelineSub = widget.service.pipelineSnapshots().listen((snap) {
      if (mounted) setState(() => _pipeline = snap);
    });
    _snapshotTicker = Timer.periodic(
      const Duration(seconds: 3),
      (_) => widget.service.requestSnapshot(),
    );
    _scroll.addListener(_maybeLoadMore);

    unawaited(_refresh());
    unawaited(_checkListener());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_liveSub?.cancel());
    unawaited(_pipelineSub?.cancel());
    _snapshotTicker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back from the notification-access settings screen.
      unawaited(_checkListener());
      unawaited(widget.service.ensureServiceRunning());
    }
  }

  Future<void> _checkListener() async {
    final enabled = await widget.service.isListenerEnabled();
    if (mounted) setState(() => _listenerEnabled = enabled);
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.api.recentScrobbles(
        _username,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _scrobbles = page;
        _reachedEnd = page.length < _pageSize;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            e is ApiException
                ? e.message
                : 'Could not load scrobbles. Is the server reachable?';
      });
    }
  }

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter < 400) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    final current = _scrobbles;
    if (current == null || current.isEmpty || _loadingMore || _reachedEnd) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await widget.api.recentScrobbles(
        _username,
        limit: _pageSize,
        before: current.last.playedAt,
      );
      if (!mounted) return;
      setState(() {
        current.addAll(page);
        _reachedEnd = page.length < _pageSize;
      });
    } catch (_) {
      // Silent: scroll again to retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openArtist(int artistId, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ArtistScreen(
              api: widget.api,
              auth: widget.auth,
              artistId: artistId,
              artistName: name,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final scrobbles = _scrobbles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('newfm'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => SearchScreen(api: widget.api, auth: widget.auth),
                  ),
                ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_refresh(), _checkListener()]);
        },
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!_listenerEnabled) ...[
              _PermissionBanner(
                onGrant: () async {
                  await widget.service.openListenerSettings();
                },
              ),
              const SizedBox(height: 12),
            ],
            NowPlayingCard(nowPlaying: _nowPlaying, pipeline: _pipeline),
            const SizedBox(height: 20),
            Text('Recent scrobbles', style: text.titleMedium),
            const SizedBox(height: 4),
            if (scrobbles == null && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
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
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (scrobbles!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.library_music_outlined,
                      size: 40,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nothing scrobbled yet.\nPlay something in any music app!',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              for (final s in scrobbles)
                ScrobbleTile(
                  scrobble: s,
                  onTap: () => _openArtist(s.artistId, s.artistName),
                ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onGrant});

  final Future<void> Function() onGrant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card.filled(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_off, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notification access needed',
                    style: text.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'newfm reads media sessions through the notification listener '
              'to detect what you play. Nothing is scrobbled until you '
              'grant it.',
              style: text.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => onGrant(),
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
