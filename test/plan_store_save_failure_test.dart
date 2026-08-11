import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';

/// 저장을 실패시킬 수 있는 저장소. 종료 직전 저장 실패를 재현한다.
class _FlakyRepo implements PlanRepository {
  PlanSnapshot? _snap;
  bool failNextSave = false;
  int saveCount = 0;

  @override
  Future<PlanSnapshot?> load() async => _snap;

  @override
  Future<void> save(PlanSnapshot snapshot) async {
    saveCount++;
    if (failNextSave) {
      throw StateError('디스크 쓰기 실패(테스트)');
    }
    _snap = snapshot;
  }
}

Future<PlanStore> _store(_FlakyRepo repo) async {
  final store = PlanStore(
    repository: repo,
    nowProvider: () => DateTime(2026, 8, 11),
    // 일부러 길게 — 명시적 flush 만으로 저장되는지 보기 위해.
    autosaveDelay: const Duration(seconds: 30),
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

void main() {
  group('flush 의 성공/실패 보고', () {
    test('저장할 게 없으면 true(성공)', () async {
      final repo = _FlakyRepo();
      final store = await _store(repo);
      expect(await store.flush(), isTrue);
    });

    test('정상 저장되면 true 이고 미저장 표시가 사라진다', () async {
      final repo = _FlakyRepo();
      final store = await _store(repo);
      store.addNode(title: '작성한 내용');
      expect(store.hasUnsavedChanges, isTrue);

      expect(await store.flush(), isTrue);
      expect(store.hasUnsavedChanges, isFalse);
      expect(store.lastSaveError, isNull);
    });

    test('저장이 실패하면 false 를 돌려준다 — 호출부가 종료를 막을 수 있어야 한다', () async {
      final repo = _FlakyRepo()..failNextSave = true;
      final store = await _store(repo);
      store.addNode(title: '사라지면 안 되는 내용');

      expect(await store.flush(), isFalse,
          reason: '실패를 조용히 삼키면 종료 훅이 그대로 앱을 닫아 데이터가 사라진다');
    });

    test('저장 실패 사유가 릴리스 빌드에서도 조회 가능하다', () async {
      final repo = _FlakyRepo()..failNextSave = true;
      final store = await _store(repo);
      store.addNode(title: 'x');
      await store.flush();

      expect(store.lastSaveError, isA<StateError>());
    });

    test('저장이 실패하면 변경이 남아 있는 것으로 유지돼 다음에 다시 시도된다', () async {
      final repo = _FlakyRepo()..failNextSave = true;
      final store = await _store(repo);
      store.addNode(title: '재시도 대상');
      await store.flush();
      expect(store.hasUnsavedChanges, isTrue);

      // 디스크가 회복되면 같은 내용이 그대로 저장된다.
      repo.failNextSave = false;
      expect(await store.flush(), isTrue);
      expect(store.hasUnsavedChanges, isFalse);
      final saved = await repo.load();
      expect(saved!.nodes.single.title, '재시도 대상');
    });

    test('실패 후 성공하면 오류 표시가 지워진다', () async {
      final repo = _FlakyRepo()..failNextSave = true;
      final store = await _store(repo);
      store.addNode(title: 'x');
      await store.flush();
      expect(store.lastSaveError, isNotNull);

      repo.failNextSave = false;
      await store.flush();
      expect(store.lastSaveError, isNull);
    });
  });

  group('종료 직전 저장 시나리오', () {
    test('작성 직후 바로 flush 하면(=창 닫기) 내용이 저장소에 남는다', () async {
      final repo = _FlakyRepo();
      final store = await _store(repo);

      // (load 시 기본 프로젝트 시드로 이미 한 번 저장돼 있으므로 증가분만 본다)
      final before = repo.saveCount;

      // autosaveDelay 가 30초라 debounce 저장은 아직 일어나지 않은 상태.
      store.addNode(title: '닫기 직전에 쓴 것');
      expect(repo.saveCount, before, reason: 'debounce 라 아직 저장 전이다');

      // 종료 훅이 await 로 기다리는 상황.
      expect(await store.flush(), isTrue);

      final saved = await repo.load();
      expect(saved!.nodes.single.title, '닫기 직전에 쓴 것',
          reason: '창을 닫아도 마지막 작성분까지 저장돼야 한다');
    });
  });
}
