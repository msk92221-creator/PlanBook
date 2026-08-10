import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/project.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _emptyStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

void main() {
  group('exportableSnapshot / importSnapshot', () {
    test('exportableSnapshot 은 현재 트리/프로젝트/태그/설정을 그대로 담는다', () async {
      final store = await _emptyStore();
      final p = store.createProject('연구소');
      store.addNode(title: '작업', projectId: p.id);
      await store.flush();

      final snap = store.exportableSnapshot();
      expect(snap.nodes.length, 1);
      expect(snap.projects.any((x) => x.name == '연구소'), isTrue);
      store.dispose();
    });

    test('importSnapshot 은 기존 데이터를 완전히 교체한다', () async {
      final store = await _emptyStore();
      store.addNode(title: '지워질 작업');
      await store.flush();
      expect(store.tree.allNodes.length, 1);

      await store.importSnapshot(PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: const [],
        projects: const [Project(id: 'imported-p', name: '가져온 프로젝트')],
      ));

      expect(store.tree.allNodes, isEmpty,
          reason: '가져오기는 기존 노드를 전부 교체(제거)해야 한다');
      expect(store.projects.any((p) => p.name == '가져온 프로젝트'), isTrue);
      store.dispose();
    });

    test('importSnapshot 이후 store.flush() 없이도 즉시 repository 에 저장된다(별도 저장 경로 없음)',
        () async {
      final repo = _MemoryRepo();
      final store = PlanStore(
        repository: repo,
        nowProvider: () => DateTime(2026, 8, 11),
        autosaveDelay: const Duration(seconds: 30), // 일부러 길게.
      );
      await store.load();
      await store.flush();

      await store.importSnapshot(PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: const [],
        projects: const [Project(id: 'p1', name: '즉시저장 확인용')],
      ));

      // importSnapshot 내부에서 flush() 를 직접 호출하므로, autosaveDelay 가
      // 길어도 repository.save() 가 이미 실행돼 있어야 한다.
      final saved = await repo.load();
      expect(saved!.projects.any((p) => p.name == '즉시저장 확인용'), isTrue);
      store.dispose();
    });

    test('가져오기 트리 교체는 undo 가능하다(한 스텝)', () async {
      final store = await _emptyStore();
      store.addNode(title: '원래 작업');
      await store.flush();

      await store.importSnapshot(PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: const [],
      ));
      expect(store.tree.allNodes, isEmpty);

      store.undo();
      expect(store.tree.allNodes.map((n) => n.title), ['원래 작업']);
      store.dispose();
    });
  });
}
