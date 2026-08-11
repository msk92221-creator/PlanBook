import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/sync/sync_decision.dart';

void main() {
  group('원격에 파일이 없을 때', () {
    test('첫 실행(동기화 이력 없음, 로컬 변경 없음)이면 할 일 없음', () {
      expect(
        decideSyncAction(remoteTag: null, syncedTag: null, localChanged: false),
        SyncAction.upToDate,
      );
    });

    test('로컬에 변경이 있으면 올린다', () {
      expect(
        decideSyncAction(remoteTag: null, syncedTag: null, localChanged: true),
        SyncAction.upload,
      );
    });

    test('한 번 동기화했는데 원격 파일이 사라졌으면, 로컬이 안 바뀌었어도 다시 올린다(복구 우선)', () {
      expect(
        decideSyncAction(remoteTag: null, syncedTag: 'e1', localChanged: false),
        SyncAction.upload,
      );
    });
  });

  group('원격에 파일이 있을 때', () {
    test('원격이 그대로고 로컬도 안 바뀌었으면 최신 상태', () {
      expect(
        decideSyncAction(remoteTag: 'e1', syncedTag: 'e1', localChanged: false),
        SyncAction.upToDate,
      );
    });

    test('원격이 그대로고 로컬만 바뀌었으면 올린다', () {
      expect(
        decideSyncAction(remoteTag: 'e1', syncedTag: 'e1', localChanged: true),
        SyncAction.upload,
      );
    });

    test('다른 기기가 올려서 원격만 바뀌었으면 내려받는다', () {
      expect(
        decideSyncAction(remoteTag: 'e2', syncedTag: 'e1', localChanged: false),
        SyncAction.download,
      );
    });

    test('양쪽 다 바뀌었으면 자동 처리하지 않고 충돌로 넘긴다', () {
      expect(
        decideSyncAction(remoteTag: 'e2', syncedTag: 'e1', localChanged: true),
        SyncAction.conflict,
      );
    });

    test('동기화 이력이 없는데 원격에 파일이 있으면(다른 기기가 먼저 씀) 내려받는다', () {
      expect(
        decideSyncAction(remoteTag: 'e1', syncedTag: null, localChanged: false),
        SyncAction.download,
      );
    });

    test('동기화 이력이 없고 원격에도 있고 로컬도 바뀌었으면 충돌 — 어느 쪽도 버리지 않는다', () {
      expect(
        decideSyncAction(remoteTag: 'e1', syncedTag: null, localChanged: true),
        SyncAction.conflict,
        reason: '기기 두 대에서 각각 쓰기 시작한 상황이라 사용자가 골라야 한다',
      );
    });
  });
}
