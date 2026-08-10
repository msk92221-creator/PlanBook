import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_tree.dart' show InsertPosition;

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
  group('PlanStore undo/redo', () {
    test('초기 상태는 undo/redo 둘 다 불가', () async {
      final store = await _emptyStore();
      expect(store.canUndo, isFalse);
      expect(store.canRedo, isFalse);
      store.dispose();
    });

    test('addNode 를 undo 하면 노드가 사라지고, redo 하면 되돌아온다', () async {
      final store = await _emptyStore();
      final node = store.addNode(title: '작업');
      expect(store.tree.contains(node.id), isTrue);
      expect(store.canUndo, isTrue);

      store.undo();
      expect(store.tree.contains(node.id), isFalse);
      expect(store.canUndo, isFalse);
      expect(store.canRedo, isTrue);

      store.redo();
      expect(store.tree.contains(node.id), isTrue);
      expect(store.canRedo, isFalse);
      store.dispose();
    });

    test('status 변경(완료 체크) 도 undo 대상이다', () async {
      final store = await _emptyStore();
      final node = store.addNode(title: '작업');
      store.setNodeDone(node.id, true);
      expect(store.tree[node.id]!.status, TaskStatus.done);

      store.undo(); // "완료 체크" 만 되돌림.
      expect(store.tree[node.id]!.status, TaskStatus.notStarted);
      expect(store.tree.contains(node.id), isTrue, reason: '노드 자체는 살아있어야 함');
      store.dispose();
    });

    test('날짜 이동(리사이즈에 해당하는 updateNode) 도 undo 된다', () async {
      final store = await _emptyStore();
      final node = store.addNode(
        title: '작업',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      store.updateNode(node.id, (n) => n.copyWith(endDate: PlanDate(2026, 8, 10)));
      expect(store.tree[node.id]!.endDate, PlanDate(2026, 8, 10));

      store.undo();
      expect(store.tree[node.id]!.endDate, PlanDate(2026, 8, 5));
      store.dispose();
    });

    test('트리 재정렬(reorderSibling) 도 undo 된다', () async {
      final store = await _emptyStore();
      final a = store.addNode(title: 'a');
      final b = store.addNode(title: 'b');
      expect(store.tree.childrenOf(null).map((n) => n.id), [a.id, b.id]);

      store.reorderSibling(b.id,
          referenceSiblingId: a.id, position: InsertPosition.before);
      expect(store.tree.childrenOf(null).map((n) => n.id), [b.id, a.id]);

      store.undo();
      expect(store.tree.childrenOf(null).map((n) => n.id), [a.id, b.id]);
      store.dispose();
    });

    test('reparent(moveNode) 도 undo 된다', () async {
      final store = await _emptyStore();
      final oldParent = store.addNode(title: '옛 부모');
      final newParent = store.addNode(title: '새 부모');
      final child = store.addNode(parentId: oldParent.id, title: '자식');

      store.moveNode(child.id, newParent.id);
      expect(store.tree[child.id]!.parentId, newParent.id);

      store.undo();
      expect(store.tree[child.id]!.parentId, oldParent.id);
      store.dispose();
    });

    test('삭제(deleteCascade) 도 undo 하면 복원된다', () async {
      final store = await _emptyStore();
      final parent = store.addNode(title: '부모');
      final child = store.addNode(parentId: parent.id, title: '자식');

      store.deleteCascade(parent.id);
      expect(store.tree.contains(parent.id), isFalse);
      expect(store.tree.contains(child.id), isFalse);

      store.undo();
      expect(store.tree.contains(parent.id), isTrue);
      expect(store.tree.contains(child.id), isTrue);
      expect(store.tree[child.id]!.parentId, parent.id);
      store.dispose();
    });

    test('새 mutation 이 일어나면 redo 스택이 비워진다', () async {
      final store = await _emptyStore();
      final a = store.addNode(title: 'a');
      store.undo();
      expect(store.canRedo, isTrue);

      store.addNode(title: 'b'); // 새 동작 → redo 히스토리 폐기.
      expect(store.canRedo, isFalse);
      expect(store.tree.contains(a.id), isFalse);
      store.dispose();
    });

    test('project/tag/settings 변경은 undo 대상이 아니다(트리를 안 건드리므로)',
        () async {
      final store = await _emptyStore();
      store.createProject('새 프로젝트');
      expect(store.canUndo, isFalse,
          reason: 'Project 변경은 트리 스냅샷에 영향이 없어 undo 엔트리가 안 생겨야 함');
      store.dispose();
    });

    test('undo 스택이 비어있을 때 undo() 를 불러도 안전하다(no-op)', () async {
      final store = await _emptyStore();
      store.undo(); // 예외 없이 그냥 무시.
      expect(store.canUndo, isFalse);
      store.dispose();
    });

    test('중첩된 mutate(createSampleData) 는 한 번의 undo 로 전부 되돌아간다', () async {
      final store = await _emptyStore();
      expect(store.isEmpty, isTrue);
      store.createSampleData();
      expect(store.isEmpty, isFalse);

      store.undo();
      expect(store.isEmpty, isTrue,
          reason: '샘플 생성 전체가 addNode 개별 undo 가 아니라 한 번에 되돌아가야 함');
      store.dispose();
    });

    test('setAllCollapsed 는 자식이 있는 노드에만 적용되고 한 번의 undo 로 되돌아간다',
        () async {
      final store = await _emptyStore();
      final parent = store.addNode(title: '부모');
      final leaf = store.addNode(parentId: parent.id, title: '자식');
      final rootLeaf = store.addNode(title: '독립 리프');

      store.setAllCollapsed(true);
      expect(store.tree[parent.id]!.isCollapsed, isTrue);
      expect(store.tree[leaf.id]!.isCollapsed, isFalse,
          reason: '자식이 없는 노드는 접을 대상이 아니다');
      expect(store.tree[rootLeaf.id]!.isCollapsed, isFalse);

      store.undo();
      expect(store.tree[parent.id]!.isCollapsed, isFalse);
      store.dispose();
    });

    test('undo 스택은 최대 크기(50)를 넘지 않는다', () async {
      final store = await _emptyStore();
      for (var i = 0; i < 60; i++) {
        store.addNode(title: 'n$i');
      }
      expect(store.canUndo, isTrue);
      // 60번 undo 를 시도해도 예외 없이 안전하게 끝나야 한다(가장 오래된 것부터
      // 잘려나갔으므로 실제로는 50번만 undo 가능).
      var count = 0;
      while (store.canUndo && count < 100) {
        store.undo();
        count++;
      }
      expect(count, 50);
      store.dispose();
    });
  });
}
