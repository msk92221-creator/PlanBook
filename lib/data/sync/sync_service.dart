/// 동기화 실행 — 판단([decideSyncAction])과 통신([GraphClient])을 엮는다.
///
/// **자동으로 데이터를 버리지 않는다**: 양쪽이 갈라졌으면 [SyncOutcome.conflict]
/// 를 돌려주고 멈춘다. 어느 쪽을 살릴지는 사용자가 고르고, 그때도 버려지는
/// 쪽을 먼저 백업 파일로 남긴다([SyncService.resolveConflict]).
library;

import 'dart:io';

import '../plan_export_import.dart';
import '../plan_repository.dart';
import '../plan_store.dart';
import 'graph_client.dart';
import 'sync_decision.dart';
import 'sync_state.dart';

/// 동기화 1회의 결과.
enum SyncOutcome {
  /// 이미 최신이라 할 일이 없었다.
  upToDate,

  /// 이 기기 내용을 올렸다.
  uploaded,

  /// 원격 내용을 받아 적용했다.
  downloaded,

  /// 양쪽이 갈라져 사용자의 선택이 필요하다(아무 것도 바꾸지 않았다).
  conflict,
}

class SyncResult {
  final SyncOutcome outcome;

  /// 충돌일 때, 원격에 있던 내용(사용자에게 규모를 보여주기 위해 파싱해둔다).
  final PlanSnapshot? remoteSnapshot;

  const SyncResult(this.outcome, {this.remoteSnapshot});
}

class SyncService {
  final PlanStore store;
  final GraphClient graph;

  /// 동기화 상태(eTag/해시)를 둘 기기 로컬 디렉터리.
  final Directory localDir;

  SyncService({
    required this.store,
    required this.graph,
    required this.localDir,
  });

  /// 현재 이 기기 내용(원격에 올릴 형태 그대로).
  String get _localContent =>
      exportSnapshotToJsonString(store.exportableSnapshot());

  /// 한 번 동기화한다.
  Future<SyncResult> sync() async {
    final state = await loadSyncState(localDir);
    final local = _localContent;

    final info = await graph.fetchInfo();
    final action = decideSyncAction(
      remoteTag: info?.eTag,
      syncedTag: state.lastSyncedETag,
      localChanged: state.hasLocalChanges(local),
    );

    switch (action) {
      case SyncAction.upToDate:
        return const SyncResult(SyncOutcome.upToDate);

      case SyncAction.upload:
        await _uploadLocal(local, ifMatchETag: info?.eTag);
        return const SyncResult(SyncOutcome.uploaded);

      case SyncAction.download:
        final applied = await _downloadAndApply();
        return SyncResult(SyncOutcome.downloaded, remoteSnapshot: applied);

      case SyncAction.conflict:
        final remote = await graph.download();
        final parsed =
            remote == null ? null : parseImportJson(remote.body).snapshot;
        return SyncResult(SyncOutcome.conflict, remoteSnapshot: parsed);
    }
  }

  /// 충돌을 사용자가 고른 대로 해소한다.
  ///
  /// **버려지는 쪽을 먼저 파일로 남긴다.** 동기화 때문에 사용자가 쓴 내용이
  /// 흔적 없이 사라지는 일은 없어야 한다.
  Future<SyncOutcome> resolveConflict(ConflictResolution choice) async {
    switch (choice) {
      case ConflictResolution.keepLocal:
        // 원격을 덮어쓰므로, 사라질 원격 내용을 먼저 백업한다.
        final remote = await graph.download();
        if (remote != null) {
          await _writeConflictBackup('remote', remote.body);
        }
        // 방금 읽은 eTag 로 If-Match — 그 사이 또 바뀌었으면 다시 충돌난다.
        await _uploadLocal(_localContent, ifMatchETag: remote?.eTag);
        return SyncOutcome.uploaded;

      case ConflictResolution.keepRemote:
        // 이 기기 내용이 사라지므로 먼저 백업한다.
        await _writeConflictBackup('local', _localContent);
        await _downloadAndApply();
        return SyncOutcome.downloaded;
    }
  }

  Future<void> _uploadLocal(String content, {String? ifMatchETag}) async {
    final newTag = await graph.upload(content, ifMatchETag: ifMatchETag);
    await saveSyncState(
      localDir,
      SyncState(
        lastSyncedETag: newTag,
        lastSyncedContentHash: hashContent(content),
        lastSyncedAt: DateTime.now(),
      ),
    );
  }

  Future<PlanSnapshot?> _downloadAndApply() async {
    final remote = await graph.download();
    if (remote == null) return null;
    final parsed = parseImportJson(remote.body);
    if (!parsed.isSuccess) {
      throw GraphException('원격 파일을 해석할 수 없습니다: ${parsed.error}');
    }
    await store.importSnapshot(parsed.snapshot!);
    await saveSyncState(
      localDir,
      SyncState(
        lastSyncedETag: remote.eTag,
        // 받은 내용을 그대로 적용했으므로, 적용 후 내보낸 형태로 해시를 잡는다
        // (직렬화 차이 때문에 곧바로 "변경됨" 으로 오판하지 않도록).
        lastSyncedContentHash: hashContent(_localContent),
        lastSyncedAt: DateTime.now(),
      ),
    );
    return parsed.snapshot;
  }

  /// 충돌로 버려지는 쪽을 로컬에 남긴다. 실패해도 동기화 자체를 막지는 않는다
  /// (백업은 최선의 노력이고, 여기서 예외를 던지면 사용자는 어느 쪽도 못 고른다).
  Future<void> _writeConflictBackup(String side, String content) async {
    try {
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }
      final now = DateTime.now();
      String p2(int n) => n.toString().padLeft(2, '0');
      final name = 'conflict_${side}_${now.year}${p2(now.month)}${p2(now.day)}'
          '_${p2(now.hour)}${p2(now.minute)}${p2(now.second)}.json';
      await File('${localDir.path}${Platform.pathSeparator}$name')
          .writeAsString(content);
    } catch (_) {
      // 무시 — 백업 실패가 충돌 해소를 막아서는 안 된다.
    }
  }
}
