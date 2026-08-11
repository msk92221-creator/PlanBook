import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planbook/data/plan_export_import.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/data/sync/graph_client.dart';
import 'package:planbook/data/sync/sync_decision.dart';
import 'package:planbook/data/sync/sync_service.dart';
import 'package:planbook/data/sync/sync_state.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

/// 아주 단순한 가짜 OneDrive: 내용 하나와 eTag 하나를 들고 있다.
class _FakeDrive {
  String? content;
  String eTag = 'e1';
  int uploadCount = 0;
  bool rejectNextIfMatch = false;

  http.Client get client => MockClient((req) async {
        final isContent = req.url.path.endsWith('/content');

        if (req.method == 'PUT') {
          if (rejectNextIfMatch) {
            rejectNextIfMatch = false;
            return http.Response('', 412);
          }
          uploadCount++;
          content = utf8.decode(req.bodyBytes);
          eTag = 'e${uploadCount + 1}';
          return http.Response(jsonEncode({'eTag': eTag}), 200);
        }

        if (content == null) return http.Response('', 404);
        if (isContent) {
          return http.Response.bytes(utf8.encode(content!), 200);
        }
        return http.Response(jsonEncode({'eTag': eTag}), 200);
      });
}

Future<PlanStore> _store() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 12),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Directory _tmp() {
  final d = Directory.systemTemp.createTempSync('planbook_sync_svc');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

({SyncService svc, _FakeDrive drive, Directory dir}) _wire(PlanStore store) {
  final drive = _FakeDrive();
  final dir = _tmp();
  final svc = SyncService(
    store: store,
    graph: GraphClient(
      accessToken: () async => 'tok',
      httpClient: drive.client,
    ),
    localDir: dir,
  );
  return (svc: svc, drive: drive, dir: dir);
}

void main() {
  test('원격이 비어 있고 로컬에 내용이 있으면 올린다', () async {
    final store = await _store();
    store.addNode(title: 'PA장비');
    final w = _wire(store);

    final r = await w.svc.sync();

    expect(r.outcome, SyncOutcome.uploaded);
    expect(w.drive.content, isNotNull);
    expect(jsonDecode(w.drive.content!)['nodes'], hasLength(1));
  });

  test('올린 직후 다시 동기화하면 할 일이 없다', () async {
    final store = await _store();
    store.addNode(title: 'PA장비');
    final w = _wire(store);
    await w.svc.sync();

    expect((await w.svc.sync()).outcome, SyncOutcome.upToDate);
    expect(w.drive.uploadCount, 1, reason: '바뀐 게 없으면 다시 올리지 않는다');
  });

  test('로컬에서 수정하면 다시 올린다', () async {
    final store = await _store();
    store.addNode(title: 'PA장비');
    final w = _wire(store);
    await w.svc.sync();

    store.addNode(title: '추가 작업');
    expect((await w.svc.sync()).outcome, SyncOutcome.uploaded);
    expect(jsonDecode(w.drive.content!)['nodes'], hasLength(2));
  });

  test('다른 기기가 올린 내용은 받아서 적용한다', () async {
    final store = await _store();
    final w = _wire(store);

    // 다른 기기가 먼저 올려둔 상황.
    w.drive.content = exportSnapshotToJsonString(PlanSnapshot(
      schemaVersion: PlanSnapshot.currentSchemaVersion,
      nodes: const [],
    ));
    w.drive.eTag = 'remote-1';
    // 이 기기는 아직 아무 것도 안 썼다(로컬 변경 없음).
    await saveSyncState(
      w.dir,
      SyncState(
        lastSyncedETag: 'old',
        lastSyncedContentHash:
            hashContent(exportSnapshotToJsonString(store.exportableSnapshot())),
        lastSyncedAt: DateTime.now(),
      ),
    );

    final r = await w.svc.sync();
    expect(r.outcome, SyncOutcome.downloaded);
  });

  test('양쪽 다 바뀌었으면 충돌 — 아무 것도 덮어쓰지 않는다', () async {
    final store = await _store();
    store.addNode(title: '이 기기에서 쓴 것');
    final w = _wire(store);
    await w.svc.sync();

    // 다른 기기가 올린 것처럼 원격을 바꾸고,
    w.drive.content = exportSnapshotToJsonString(PlanSnapshot(
      schemaVersion: PlanSnapshot.currentSchemaVersion,
      nodes: const [],
    ));
    w.drive.eTag = 'other-device';
    // 이 기기에서도 추가로 수정한다.
    store.addNode(title: '이 기기에서 더 쓴 것');

    final before = w.drive.content;
    final r = await w.svc.sync();

    expect(r.outcome, SyncOutcome.conflict);
    expect(w.drive.content, before, reason: '충돌 시 원격을 건드리면 안 된다');
    expect(store.tree.allNodes, hasLength(2), reason: '충돌 시 로컬도 건드리면 안 된다');
  });

  group('충돌 해소', () {
    Future<({SyncService svc, _FakeDrive drive, Directory dir, PlanStore store})>
        conflicted() async {
      final store = await _store();
      store.addNode(title: '로컬 내용');
      final w = _wire(store);
      await w.svc.sync();

      w.drive.content = exportSnapshotToJsonString(PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: const [],
        projects: const [],
      ));
      w.drive.eTag = 'other-device';
      store.addNode(title: '로컬에서 더 씀');

      expect((await w.svc.sync()).outcome, SyncOutcome.conflict);
      return (svc: w.svc, drive: w.drive, dir: w.dir, store: store);
    }

    test('로컬 유지를 고르면 로컬 내용이 올라간다', () async {
      final c = await conflicted();
      final outcome = await c.svc.resolveConflict(ConflictResolution.keepLocal);

      expect(outcome, SyncOutcome.uploaded);
      expect(jsonDecode(c.drive.content!)['nodes'], hasLength(2));
    });

    test('로컬 유지를 고르면 사라지는 원격 내용을 백업으로 남긴다', () async {
      final c = await conflicted();
      await c.svc.resolveConflict(ConflictResolution.keepLocal);

      final backups = c.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('conflict_remote_'));
      expect(backups, isNotEmpty, reason: '버려지는 쪽은 흔적을 남겨야 한다');
    });

    test('원격 유지를 고르면 원격 내용이 로컬에 적용된다', () async {
      final c = await conflicted();
      final outcome = await c.svc.resolveConflict(ConflictResolution.keepRemote);

      expect(outcome, SyncOutcome.downloaded);
      expect(c.store.tree.allNodes, isEmpty);
    });

    test('원격 유지를 고르면 사라지는 로컬 내용을 백업으로 남긴다', () async {
      final c = await conflicted();
      await c.svc.resolveConflict(ConflictResolution.keepRemote);

      final backups = c.dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('conflict_local_'));
      expect(backups, isNotEmpty);
      expect(backups.first.readAsStringSync(), contains('로컬에서 더 씀'));
    });

    test('해소 후에는 다시 동기화해도 할 일이 없다', () async {
      final c = await conflicted();
      await c.svc.resolveConflict(ConflictResolution.keepLocal);

      expect((await c.svc.sync()).outcome, SyncOutcome.upToDate);
    });
  });

  test('업로드 도중 다른 기기가 먼저 올리면(412) 조용히 덮어쓰지 않고 실패한다', () async {
    final store = await _store();
    store.addNode(title: 'x');
    final w = _wire(store);
    await w.svc.sync();

    store.addNode(title: 'y');
    w.drive.rejectNextIfMatch = true;

    await expectLater(
      w.svc.sync(),
      throwsA(isA<GraphException>().having((e) => e.isConflict, 'isConflict', isTrue)),
    );
  });

  test('한글 내용이 왕복해도 깨지지 않는다', () async {
    final store = await _store();
    store.addNode(title: '착수회의 및 PA장비 도입');
    final w = _wire(store);
    await w.svc.sync();

    expect(w.drive.content, contains('착수회의 및 PA장비 도입'));
  });
}
