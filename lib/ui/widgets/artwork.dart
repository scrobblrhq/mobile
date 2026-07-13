import 'package:flutter/material.dart';

import '../format.dart';

/// Artwork with a deliberate fallback chain, because enrichment is
/// asynchronous: a scrobble can appear seconds after first listen while the
/// worker is still resolving MusicBrainz/Cover Art Archive/Deezer.
///
///  1. Enriched image URL from the backend, when present.
///  2. While loading or on error: a placeholder derived from the *dynamic*
///     color scheme (gradient of primary/tertiary containers) so empty
///     states still look intentional and Material-You-themed —
///     with artist initials when we have a name, else a music-note glyph.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.url,
    this.size = 56,
    this.circle = false,
    this.initialsSource,
    this.icon = Icons.music_note,
  });

  final String? url;
  final double size;
  final bool circle;

  /// Name to derive placeholder initials from (used for artists).
  final String? initialsSource;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(circle ? size / 2 : size * 0.2);
    final placeholder = _Placeholder(
      size: size,
      radius: radius,
      icon: icon,
      initials: initialsSource == null ? null : initialsFor(initialsSource!),
    );

    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => placeholder,
        loadingBuilder:
            (context, child, progress) =>
                progress == null ? child : placeholder,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.size,
    required this.radius,
    required this.icon,
    this.initials,
  });

  final double size;
  final BorderRadius radius;
  final IconData icon;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      alignment: Alignment.center,
      child:
          initials != null
              ? Text(
                initials!,
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: size * 0.34,
                ),
              )
              : Icon(icon, size: size * 0.45, color: scheme.onPrimaryContainer),
    );
  }
}
