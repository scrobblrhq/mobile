/// Small display formatting helpers.
library;

String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now().toUtc();
  final delta = reference.difference(time.toUtc());
  if (delta.inSeconds < 60) return 'now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String formatDuration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Human label for a scrobble `source` slug.
String sourceLabel(String source) => switch (source) {
  'spotify' => 'Spotify',
  'youtube-music' => 'YouTube Music',
  'youtube' => 'YouTube',
  'tidal' => 'Tidal',
  'deezer' => 'Deezer',
  'apple-music' => 'Apple Music',
  'amazon-music' => 'Amazon Music',
  'vlc' => 'VLC',
  'poweramp' => 'Poweramp',
  'android' => 'Android',
  'extension' => 'Web',
  '' => 'Unknown',
  _ => source,
};

/// Initials for artwork placeholders ("Radiohead" → "R",
/// "Boards of Canada" → "BC").
String initialsFor(String name) {
  final words =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first[0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}
