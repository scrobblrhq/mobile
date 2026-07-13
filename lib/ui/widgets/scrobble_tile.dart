import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../format.dart';
import 'artwork.dart';

class ScrobbleTile extends StatelessWidget {
  const ScrobbleTile({super.key, required this.scrobble, this.onTap});

  final ScrobbleRich scrobble;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final subtitle =
        scrobble.albumTitle == null
            ? scrobble.artistName
            : '${scrobble.artistName} • ${scrobble.albumTitle}';

    return ListTile(
      leading: Artwork(url: scrobble.albumImage, size: 48),
      title: Text(
        scrobble.trackTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(relativeTime(scrobble.playedAt), style: text.labelSmall),
          const SizedBox(height: 2),
          Text(
            sourceLabel(scrobble.source),
            style: text.labelSmall?.copyWith(color: scheme.outline),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
