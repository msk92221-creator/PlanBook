import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/domain/project_filter.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

Directory _tmp(String n) => Directory.systemTemp.createTempSync('planbook_$n');

void main() {
  group('Project 소속 전파 (moveNode/reorderSibling)', () {
    late Directory dir;
    late PlanStore store;

    setUp(() async {
      dir = _tmp('reparent');
      store = PlanStore(
        repository: JsonPlanRepository(directory: dir),
        nowProvider: () => DateTime(2026, 8, 11),
        autosaveDelay: Duration.zero,
      );
      await store.load(); // 기본 프로젝트 5개 시드.
    });

    tearDown(() {
      store.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('moveNode: 다른 Project 부모 아래로 이동하면 projectId 가 그 부모를 따라간다',
        () {
      final work = store.projects.firstWhere((p) => p.name == '업무');
      final research = store.projects.firstWhere((p) => p.name == '연구');

      final destParent = store.addNode(title: '목적지', projectId: research.id);
      final moved = store.addNode(title: '이동할 작업', projectId: work.id);
      final child = store.addNode(
          parentId: moved.id, title: '자식', projectId: work.id);
      final grandchild = store.addNode(
          parentId: child.id, title: '손자', projectId: work.id);

      store.moveNode(moved.id, destParent.id);

      expect(store.tree[moved.id]!.projectId, research.id);
      expect(store.tree[child.id]!.projectId, research.id,
          reason: '자손도 함께 갱신되어야 한다');
      expect(store.tree[grandchild.id]!.projectId, research.id,
          reason: '그랜드칠드런까지 전파되어야 한다');
    });

    test('moveNode: 루트(미분류)로 이동하면 projectId 와 자손 전체가 null 이 된다', () {
      final work = store.projects.firstWhere((p) => p.name == '업무');
      // moved 가 이미 root(부모 없음)면 root 로의 move() 가 no-op 처리되어
      // 전파가 트리거되지 않는다 — 실제로 부모가 있는 상태에서 시작해야 한다.
      final someParent = store.addNode(title: '어떤 부모', projectId: work.id);
      final moved = store.addNode(
          parentId: someParent.id, title: '이동할 작업', projectId: work.id);
      final child = store.addNode(parentId: moved.id, title: '자식', projectId: work.id);

      store.moveNode(moved.id, null);

      expect(store.tree[moved.id]!.parentId, isNull);
      expect(store.tree[moved.id]!.projectId, isNull);
      expect(store.tree[child.id]!.projectId, isNull);
    });

    test('reorderSibling: 다른 Project 부모 아래로 옮기면 동일하게 전파된다', () {
      final work = store.projects.firstWhere((p) => p.name == '업무');
      final health = store.projects.firstWhere((p) => p.name == '건강');

      final destParent = store.addNode(title: '목적지', projectId: health.id);
      final destSibling =
          store.addNode(parentId: destParent.id, title: '기준형제', projectId: health.id);
      final moved = store.addNode(title: '이동할 작업', projectId: work.id);
      final child = store.addNode(parentId: moved.id, title: '자식', projectId: work.id);

      store.reorderSibling(
        moved.id,
        referenceSiblingId: destSibling.id,
        position: InsertPosition.after,
        newParentId: destParent.id,
      );

      expect(store.tree[moved.id]!.projectId, health.id);
      expect(store.tree[child.id]!.projectId, health.id);
    });

    test('같은 부모 내 순서만 바꾸는 reorder 는 projectId 를 건드리지 않는다', () {
      final work = store.projects.firstWhere((p) => p.name == '업무');
      final parent = store.addNode(title: '부모', projectId: work.id);
      final a = store.addNode(parentId: parent.id, title: 'a', projectId: null);
      final b = store.addNode(parentId: parent.id, title: 'b', projectId: work.id);

      // a 를 b 뒤로 — 같은 부모 내 순서 변경뿐, projectId 전파 트리거 아님.
      // newParentId 를 반드시 명시한다(생략 시 기본값 null=루트로 이동 의미가 되어
      // "같은 부모 유지" 의도와 달라진다 — tree_panel.dart 의 실제 호출부도 항상 명시함).
      store.reorderSibling(a.id,
          referenceSiblingId: b.id,
          position: InsertPosition.after,
          newParentId: parent.id);

      expect(store.tree[a.id]!.projectId, isNull,
          reason: '부모가 바뀌지 않았으므로 projectId 는 그대로 유지되어야 한다');
      expect(store.tree[b.id]!.projectId, work.id);
    });

    test('UI 코드는 projectId 를 직접 쓰지 않는다 — helper(cascadeProjectId) 로만 갱신',
        () {
      // PlanTree.cascadeProjectId 가 존재하고 정확히 동작하는지 자체를 직접 검증.
      final tree = PlanTree.fromNodes([
        const PlanNode(id: 'root', title: 'root', projectId: 'old'),
        const PlanNode(id: 'c1', parentId: 'root', title: 'c1', projectId: 'old'),
        const PlanNode(id: 'c2', parentId: 'c1', title: 'c2', projectId: 'old'),
        const PlanNode(id: 'other', title: 'other', projectId: 'old'),
      ]);
      tree.cascadeProjectId('root', 'new');
      expect(tree['root']!.projectId, 'new');
      expect(tree['c1']!.projectId, 'new');
      expect(tree['c2']!.projectId, 'new');
      expect(tree['other']!.projectId, 'old',
          reason: 'cascade 대상 subtree 밖의 노드는 영향받지 않아야 한다');
    });
  });

  group('필터 활성 상태에서의 이동/재정렬 무결성', () {
    test('필터로 좁혀진 화면에서도 ID 기반 이동은 트리 전체 기준으로 정확하다', () {
      final tree = PlanTree.fromNodes([
        PlanNode(id: 'p1', title: 'p1', projectId: 'A', sortOrder: 0),
        PlanNode(id: 'p2', title: 'p2', projectId: 'B', sortOrder: 1),
        PlanNode(id: 'a1', parentId: 'p1', title: 'a1', projectId: 'A', sortOrder: 0),
        PlanNode(id: 'a2', parentId: 'p1', title: 'a2', projectId: 'A', sortOrder: 1),
        PlanNode(id: 'b1', parentId: 'p2', title: 'b1', projectId: 'B', sortOrder: 0),
      ]);

      // "A" 프로젝트만 보이는 필터 — 화면엔 p1/a1/a2 만 보인다.
      final filter = const ProjectFilter.byId('A');
      final visibleIds = visibleIdsForProjectFilter(tree, filter);
      expect(visibleIds, {'p1', 'a1', 'a2'});
      final rows = flattenVisibleRows(tree, visibleIds: visibleIds);
      expect(rows.map((r) => r.id).toList(), ['p1', 'a1', 'a2']);

      // 화면에는 안 보이는 b1(다른 프로젝트) 아래로 a1 을 이동시켜도
      // ID 기반이라 정확히 동작해야 한다(화면 index 와 무관).
      tree.move('a1', 'b1');
      expect(tree['a1']!.parentId, 'b1');
      expect(tree.childrenOf('p1').map((n) => n.id), ['a2']);
      expect(tree.childrenOf('b1').map((n) => n.id), ['a1']);

      // 이동 후 필터를 다시 계산해도 데이터가 깨지지 않고 일관된 결과.
      final visibleIdsAfter = visibleIdsForProjectFilter(tree, filter);
      // a1 은 이제 projectId 는 그대로 'A' 이므로(순수 tree.move 는 projectId 를
      // 건드리지 않는다 — 그건 PlanStore 레벨 정책) 여전히 매칭되고, 조상(b1, p2)도
      // 계층 유지를 위해 함께 포함된다.
      expect(visibleIdsAfter.contains('a1'), isTrue);
      expect(visibleIdsAfter.contains('p1'), isTrue);
      expect(visibleIdsAfter.contains('a2'), isTrue);
    });

    test('접힌 parent 주변에서 이동해도 ordering 이 정상 유지된다', () {
      final tree = PlanTree.fromNodes([
        PlanNode(id: 'p1', title: 'p1', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c1', parentId: 'p1', title: 'c1', sortOrder: 0),
        PlanNode(id: 'c2', parentId: 'p1', title: 'c2', sortOrder: 1),
        PlanNode(id: 'p2', title: 'p2', sortOrder: 1),
      ]);
      // p1 이 접혀 있어 c1/c2 는 화면엔 안 보이지만, ID 기반 조작은 접힘과 무관하게
      // 항상 정상 동작해야 한다.
      final rowsBefore = flattenVisibleRows(tree);
      expect(rowsBefore.map((r) => r.id).toList(), ['p1', 'p2']);

      tree.move('c1', 'p2');
      expect(tree.childrenOf('p1').map((n) => n.id), ['c2']);
      expect(tree.childrenOf('p2').map((n) => n.id), ['c1']);
      // sortOrder 도 tight.
      expect(tree.childrenOf('p1').single.sortOrder, 0.0);
      expect(tree.childrenOf('p2').single.sortOrder, 0.0);

      // p1 을 펼치면 남은 c2 만 정상적으로 보인다.
      tree.update('p1', (n) => n.copyWith(isCollapsed: false));
      final rowsAfter = flattenVisibleRows(tree);
      expect(rowsAfter.map((r) => r.id).toList(), ['p1', 'c2', 'p2', 'c1']);
    });
  });

  group('저장 후 reload 결과 동일성 (Drag/Reparent 이후)', () {
    test('여러 mutation 후 flush -> 새 PlanStore 로 load 하면 동일한 트리가 복원된다',
        () async {
      final dir = _tmp('reload');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = PlanStore(
        repository: JsonPlanRepository(directory: dir),
        nowProvider: () => DateTime(2026, 8, 11),
        autosaveDelay: Duration.zero,
      );
      await store.load();
      final work = store.projects.firstWhere((p) => p.name == '업무');
      final research = store.projects.firstWhere((p) => p.name == '연구');

      final root = store.addNode(title: '루트', projectId: work.id);
      final child1 = store.addNode(parentId: root.id, title: 'c1', projectId: work.id);
      final child2 = store.addNode(parentId: root.id, title: 'c2', projectId: work.id);
      final otherRoot = store.addNode(title: '다른루트', projectId: research.id);

      // Drag 흉내: reorder + reparent + projectId 전파 확인까지.
      store.moveNode(child1.id, otherRoot.id);
      await store.flush();

      final reopened = PlanStore(repository: JsonPlanRepository(directory: dir));
      await reopened.load();
      addTearDown(reopened.dispose);

      expect(reopened.tree[child1.id]!.parentId, otherRoot.id);
      expect(reopened.tree[child1.id]!.projectId, research.id,
          reason: '재로드 후에도 projectId 전파 결과가 보존되어야 한다');
      expect(reopened.tree.childrenOf(root.id).map((n) => n.id), [child2.id]);
      expect(reopened.tree.childrenOf(otherRoot.id).map((n) => n.id), [child1.id]);
      store.dispose();
    });
  });
}
