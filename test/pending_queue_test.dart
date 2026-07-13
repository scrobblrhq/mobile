import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrobblr_mobile/scrobbling/pending_queue.dart';

PendingScrobble item(String track, {int playedAtMs = 0}) => PendingScrobble(
  artist: 'Artist',
  track: track,
  playedAtMs: playedAtMs,
  source: 'spotify',
  listenedMs: 120000,
  durationMs: 240000,
);

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('Scrobblr_queue_test');
    file = File('${dir.path}/queue.json');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('persists and reloads items', () async {
    final queue = PendingQueue(file);
    await queue.load();
    await queue.add(item('One'));
    await queue.add(item('Two', playedAtMs: 1000));

    final reloaded = PendingQueue(file);
    await reloaded.load();
    expect(reloaded.length, 2);
    expect(reloaded.due(0).map((i) => i.track), ['One', 'Two']);
  });

  test('evicts oldest items beyond the cap', () async {
    final queue = PendingQueue(file, cap: 3);
    await queue.load();
    for (var i = 0; i < 5; i++) {
      await queue.add(item('Track $i', playedAtMs: i));
    }
    expect(queue.length, 3);
    expect(queue.due(0).first.track, 'Track 2');
  });

  test('backoff schedules retries with exponential delay', () {
    final entry = item('One');
    entry.scheduleRetry(0);
    expect(entry.attempts, 1);
    expect(entry.nextAttemptAtMs, 30000);

    entry.scheduleRetry(30000);
    expect(entry.nextAttemptAtMs, 30000 + 60000);

    // Cap at 30 minutes.
    for (var i = 0; i < 10; i++) {
      entry.scheduleRetry(0);
    }
    expect(entry.nextAttemptAtMs, lessThanOrEqualTo(30 * 60 * 1000));
  });

  test('due() respects nextAttemptAtMs', () async {
    final queue = PendingQueue(file);
    await queue.load();
    final entry = item('One');
    entry.scheduleRetry(0); // next attempt at 30 s
    await queue.add(entry);

    expect(queue.due(0), isEmpty);
    expect(queue.due(30000), hasLength(1));
    expect(queue.nextAttemptAtMs(), 30000);
  });

  test('survives a corrupt file', () async {
    file.writeAsStringSync('{not json[');
    final queue = PendingQueue(file);
    await queue.load();
    expect(queue.isEmpty, isTrue);
  });
}
