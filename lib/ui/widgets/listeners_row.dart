import 'package:flutter/material.dart';

import '../../api/models.dart';
import 'artwork.dart';

/// Horizontal strip of a catalog entity's top listeners (users). Each entry
/// taps through to that user's profile.
class ListenersRow extends StatelessWidget {
  const ListenersRow({
    super.key,
    required this.listeners,
    required this.onOpenUser,
  });

  final List<TopListener> listeners;
  final void Function(String username) onOpenUser;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: listeners.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final listener = listeners[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpenUser(listener.username),
            child: SizedBox(
              width: 80,
              child: Column(
                children: [
                  Artwork(
                    url: listener.imageUrl,
                    size: 64,
                    circle: true,
                    initialsSource: listener.displayName ?? listener.username,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listener.displayName ?? listener.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium,
                  ),
                  Text(
                    '${listener.playCount} plays',
                    style: text.labelSmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
