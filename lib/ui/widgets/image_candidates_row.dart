import 'package:flutter/material.dart';

import '../../api/models.dart';

/// Horizontal gallery of community image candidates with a like toggle and
/// vote count. The default (winning) candidate is badged. Stateless — the
/// host screen owns the list and handles vote toggles.
class ImageCandidatesRow extends StatelessWidget {
  const ImageCandidatesRow({
    super.key,
    required this.candidates,
    required this.onToggleVote,
  });

  final List<ImageCandidate> candidates;
  final void Function(ImageCandidate candidate) onToggleVote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: candidates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final candidate = candidates[i];
          return SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        candidate.url,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stack) => Container(
                              width: 104,
                              height: 104,
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: scheme.outline,
                              ),
                            ),
                      ),
                    ),
                    if (candidate.isDefault)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Default',
                            style: text.labelSmall?.copyWith(
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    InkWell(
                      onTap: () => onToggleVote(candidate),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          candidate.hasVoted
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                          color:
                              candidate.hasVoted
                                  ? scheme.primary
                                  : scheme.outline,
                        ),
                      ),
                    ),
                    Text('${candidate.voteCount}', style: text.labelMedium),
                  ],
                ),
                Text(
                  'by ${candidate.uploadedBy}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
