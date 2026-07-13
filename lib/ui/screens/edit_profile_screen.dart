import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../widgets/artwork.dart';

/// Edits the signed-in user's profile: display name, bio, avatar and
/// privacy. The avatar can be uploaded from the gallery or set by URL;
/// clearing the URL clears it server-side. Pops `true` after a successful
/// save.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.api,
    required this.profile,
  });

  final ScrobblrApi api;
  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _displayName = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio ?? '',
  );
  late final TextEditingController _imageUrl = TextEditingController(
    text: widget.profile.imageUrl ?? '',
  );
  late bool _isPrivate = widget.profile.isPrivate;
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  /// Picks an image from the gallery and uploads it; the returned URL
  /// replaces the avatar field (and is what Save persists).
  Future<void> _pickAndUpload() async {
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
      final updated = await widget.api.uploadAvatar(bytes);
      if (!mounted) return;
      setState(() => _imageUrl.text = updated.imageUrl ?? '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avatar uploaded.')));
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

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.updateProfile(
        displayName: _displayName.text.trim(),
        bio: _bio.text.trim(),
        imageUrl: _imageUrl.text.trim(),
        isPrivate: _isPrivate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message.isEmpty ? 'Save failed' : e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach the server.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child:
                _busy
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: _imageUrl,
                  builder:
                      (context, _) => Artwork(
                        url: _imageUrl.text.trim(),
                        size: 96,
                        circle: true,
                        initialsSource: widget.profile.username,
                      ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _uploading ? null : _pickAndUpload,
                  icon:
                      _uploading
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(_uploading ? 'Uploading…' : 'Upload photo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _displayName,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            maxLength: 1000,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'Bio',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imageUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Avatar URL',
              hintText: 'https://…',
              helperText: 'Link to an image; leave empty for initials.',
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private profile'),
            subtitle: Text(
              'Only you can see your listening history',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
          ),
        ],
      ),
    );
  }
}
