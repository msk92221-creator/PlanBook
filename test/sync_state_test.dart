import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/sync/sync_state.dart';

Directory _tmp() {
  final d = Directory.systemTemp.createTempSync('planbook_sync_state');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

void main() {
  group('hashContent', () {
    test('같은 내용은 같은 해시', () {
      expect(hashContent('{"a":1}'), hashContent('{"a":1}'));
    });

    test('다른 내용은 다른 해시', () {
      expect(hashContent('{"a":1}'), isNot(hashContent('{"a":2}')));
    });

    test('한글이 섞여도 안정적이다', () {
      expect(hashContent('착수회의'), hashContent('착수회의'));
      expect(hashContent('착수회의'), isNot(hashContent('착수 회의')));
    });
  });

  group('hasLocalChanges', () {
    test('한 번도 동기화 안 했으면 변경으로 본다', () {
      expect(SyncState.never.hasLocalChanges('{"nodes":[]}'), isTrue);
    });

    test('마지막 동기화 내용과 같으면 변경 없음', () {
      const content = '{"nodes":[]}';
      final s = SyncState(lastSyncedContentHash: hashContent(content));
      expect(s.hasLocalChanges(content), isFalse);
    });

    test('내용이 바뀌면 변경으로 본다', () {
      final s = SyncState(lastSyncedContentHash: hashContent('{"nodes":[]}'));
      expect(s.hasLocalChanges('{"nodes":[{"id":"a"}]}'), isTrue);
    });
  });

  group('저장/복원 (실제 파일 I/O)', () {
    test('파일이 없으면 never', () async {
      expect(await loadSyncState(_tmp()), SyncState.never);
    });

    test('저장 후 다시 읽으면 같은 값', () async {
      final dir = _tmp();
      final state = SyncState(
        lastSyncedETag: 'e42',
        lastSyncedContentHash: hashContent('x'),
        lastSyncedAt: DateTime.utc(2026, 8, 12, 9, 30),
      );
      await saveSyncState(dir, state);

      final back = await loadSyncState(dir);
      expect(back.lastSyncedETag, 'e42');
      expect(back.lastSyncedContentHash, hashContent('x'));
      expect(back.lastSyncedAt, DateTime.utc(2026, 8, 12, 9, 30));
    });

    test('디렉터리가 없어도 만들어서 저장한다', () async {
      final base = _tmp();
      final dir = Directory(
          '${base.path}${Platform.pathSeparator}nested${Platform.pathSeparator}PlanBook');
      await saveSyncState(dir, const SyncState(lastSyncedETag: 'e1'));

      expect((await loadSyncState(dir)).lastSyncedETag, 'e1');
    });

    test('손상된 파일은 never 로 처리한다(앱이 죽지 않는다)', () async {
      final dir = _tmp();
      await File('${dir.path}${Platform.pathSeparator}sync_state.json')
          .writeAsString('{ broken json ,,');

      expect(await loadSyncState(dir), SyncState.never);
    });
  });
}
