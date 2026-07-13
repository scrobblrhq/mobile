import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../format.dart';
import 'artwork.dart';

/// Self-contained comments block for a catalog entity: loads the thread, lets
/// the signed-in user post, and delete their own. Entity-agnostic — the host
/// screen wires the load/add/delete calls to the right API endpoints.
class CommentsSection extends StatefulWidget {
  const CommentsSection({
    super.key,
    required this.load,
    required this.add,
    required this.remove,
    required this.currentUserId,
  });

  final Future<List<Comment>> Function() load;
  final Future<Comment> Function(String body) add;
  final Future<void> Function(int id) remove;
  final int? currentUserId;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final TextEditingController _controller = TextEditingController();
  List<Comment>? _comments;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await widget.load();
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      if (mounted) setState(() => _comments = const []);
    }
  }

  Future<void> _post() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final created = await widget.add(body);
      if (!mounted) return;
      setState(() {
        _comments = [created, ...?_comments];
        _controller.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.isEmpty ? 'Could not post' : e.message),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post the comment.')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(Comment comment) async {
    // Optimistic: drop it locally, restore on failure.
    final previous = _comments;
    setState(
      () => _comments = _comments?.where((c) => c.id != comment.id).toList(),
    );
    try {
      await widget.remove(comment.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _comments = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the comment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final comments = _comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Add a comment…',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _posting ? null : _post,
              icon:
                  _posting
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.send),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (comments == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (comments.isEmpty)
          Text(
            'No comments yet. Be the first!',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          for (final comment in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(
                    url: comment.imageUrl,
                    size: 36,
                    circle: true,
                    initialsSource: comment.displayName ?? comment.username,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                comment.displayName ?? comment.username,
                                style: text.labelLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              relativeTime(comment.createdAt),
                              style: text.labelSmall?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                            if (comment.userId == widget.currentUserId)
                              InkWell(
                                onTap: () => unawaited(_delete(comment)),
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(comment.body, style: text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
