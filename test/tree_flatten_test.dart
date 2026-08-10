import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

PlanTree _tree(List<PlanNode> nodes) => PlanTree.fromNodes(nodes);

void main() {
  group('flattenVisibleRows', () {
    test('빈 트리 → 빈 목록', () {
      expect(flattenVisibleRows(_tree(const [])), isEmpty);
    });

    test('깊이 우선, sortOrder 순으로 평탄화', () {
      final tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0),
        PlanNode(id: 'r2', title: '루트2', sortOrder: 1),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
        PlanNode(id: 'c2', parentId: 'r1', title: '자식2', sortOrder: 1),
        PlanNode(id: 'g1', parentId: 'c1', title: '손자1', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree);
      expect(rows.map((r) => r.id).toList(), ['r1', 'c1', 'g1', 'c2', 'r2']);
    });

    test('depth 가 올바르다', () {
      final tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
        PlanNode(id: 'g1', parentId: 'c1', title: '손자1', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree);
      expect(rows[0].depth, 0); // r1
      expect(rows[1].depth, 1); // c1
      expect(rows[2].depth, 2); // g1
    });

    test('hasChildren 이 자식 유무를 반영', () {
      final tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree);
      expect(rows.firstWhere((r) => r.id == 'r1').hasChildren, isTrue);
      expect(rows.firstWhere((r) => r.id == 'c1').hasChildren, isFalse);
    });

    test('접힌 부모(isCollapsed) 의 자손은 제외된다', () {
      final tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
        PlanNode(id: 'g1', parentId: 'c1', title: '손자1', sortOrder: 0),
        PlanNode(id: 'r2', title: '루트2', sortOrder: 1),
      ]);
      final rows = flattenVisibleRows(tree);
      // r1 은 보이되 그 아래(c1, g1)는 숨겨진다.
      expect(rows.map((r) => r.id).toList(), ['r1', 'r2']);
    });

    test('접힌 조부모 아래 전체가 숨겨진다(깊이 무관)', () {
      final tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0,
            isCollapsed: true),
        PlanNode(id: 'g1', parentId: 'c1', title: '손자1', sortOrder: 0),
        PlanNode(id: 'gg1', parentId: 'g1', title: '증손1', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree);
      // r1, c1 까지만 보임.
      expect(rows.map((r) => r.id).toList(), ['r1', 'c1']);
    });

    test('접기 토글 시 자손이 다시 나타난다(동적 반영)', () {
      var tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
      ]);
      expect(flattenVisibleRows(tree).length, 1); // r1 만
      // 펼치기.
      tree = _tree([
        PlanNode(id: 'r1', title: '루트1', sortOrder: 0, isCollapsed: false),
        PlanNode(id: 'c1', parentId: 'r1', title: '자식1', sortOrder: 0),
      ]);
      expect(flattenVisibleRows(tree).length, 2);
    });
  });

  group('FlatRow.isExpanded', () {
    test('isCollapsed 의 반대값', () {
      final tree = _tree([
        PlanNode(id: 'a', title: 'a', isCollapsed: true),
        PlanNode(id: 'b', title: 'b', isCollapsed: false),
      ]);
      final rows = flattenVisibleRows(tree);
      expect(rows.firstWhere((r) => r.id == 'a').isExpanded, isFalse);
      expect(rows.firstWhere((r) => r.id == 'b').isExpanded, isTrue);
    });
  });

  group('FlatRow effective 기간 (VisibleTaskRow 확장)', () {
    test('flatten 결과에 effectiveStartDate/effectiveEndDate/isDateDerived 가 채워진다', () {
      final tree = _tree([
        PlanNode(
          id: 'p',
          title: 'p',
          sortOrder: 0,
        ),
        PlanNode(
          id: 'c',
          parentId: 'p',
          title: 'c',
          sortOrder: 0,
          startDate: PlanDate(2026, 1, 1),
          endDate: PlanDate(2026, 1, 10),
        ),
      ]);
      final rows = flattenVisibleRows(tree);
      final p = rows.firstWhere((r) => r.id == 'p');
      final c = rows.firstWhere((r) => r.id == 'c');

      // p 는 자신에게 날짜가 없으므로 자식(c)으로부터 파생.
      expect(p.effectiveStartDate, PlanDate(2026, 1, 1));
      expect(p.effectiveEndDate, PlanDate(2026, 1, 10));
      expect(p.isDateDerived, isTrue);

      // c 는 자기 자신의 날짜를 그대로 쓴다(파생 아님).
      expect(c.effectiveStartDate, PlanDate(2026, 1, 1));
      expect(c.effectiveEndDate, PlanDate(2026, 1, 10));
      expect(c.isDateDerived, isFalse);
    });

    test('날짜가 전혀 없는 노드는 effective 값도 null 이고 크래시하지 않는다', () {
      final tree = _tree([PlanNode(id: 'a', title: 'a')]);
      final rows = flattenVisibleRows(tree);
      expect(rows.single.effectiveStartDate, isNull);
      expect(rows.single.effectiveEndDate, isNull);
      expect(rows.single.isDateDerived, isFalse);
    });
  });

  group('flattenVisibleRows(visibleIds: ...) — Project 필터 적용', () {
    test('visibleIds 를 생략하면 기존과 동일하게 전체가 나온다(하위 호환)', () {
      final tree = _tree([
        PlanNode(id: 'a', title: 'a', sortOrder: 0),
        PlanNode(id: 'b', title: 'b', sortOrder: 1),
      ]);
      expect(flattenVisibleRows(tree).map((r) => r.id).toList(), ['a', 'b']);
      expect(flattenVisibleRows(tree, visibleIds: null).map((r) => r.id).toList(),
          ['a', 'b']);
    });

    test('visibleIds 에 없는 노드와 그 자손은 제외된다', () {
      final tree = _tree([
        PlanNode(id: 'a', title: 'a', sortOrder: 0),
        PlanNode(id: 'b', title: 'b', sortOrder: 1),
        PlanNode(id: 'b1', parentId: 'b', title: 'b1', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree, visibleIds: {'a'});
      expect(rows.map((r) => r.id).toList(), ['a']);
    });

    test('필터로 자식이 전부 가려지면 hasChildren 이 false 가 된다', () {
      final tree = _tree([
        PlanNode(id: 'p', title: 'p', sortOrder: 0),
        PlanNode(id: 'c', parentId: 'p', title: 'c', sortOrder: 0),
      ]);
      // p 만 보이는 필터: c 가 가려지므로 p 의 hasChildren 은 false 여야 한다
      // (접기/펼치기 토글이 뜨지 않아야 함 — 숨겨진 자식만 있는데 토글이 보이면 혼란).
      final rows = flattenVisibleRows(tree, visibleIds: {'p'});
      expect(rows.single.hasChildren, isFalse);
    });

    test('필터를 통과한 자식만 있으면 hasChildren 은 true', () {
      final tree = _tree([
        PlanNode(id: 'p', title: 'p', sortOrder: 0),
        PlanNode(id: 'c1', parentId: 'p', title: 'c1', sortOrder: 0),
        PlanNode(id: 'c2', parentId: 'p', title: 'c2', sortOrder: 1),
      ]);
      final rows = flattenVisibleRows(tree, visibleIds: {'p', 'c1'});
      expect(rows.map((r) => r.id).toList(), ['p', 'c1']);
      expect(rows.first.hasChildren, isTrue);
    });

    test(
        '필터가 활성 상태(visibleIds 지정)면 접힌 부모 아래 매칭 자손도 강제로 '
        '펼쳐서 보여준다(persisted isCollapsed 는 수정하지 않음)', () {
      final tree = _tree([
        PlanNode(id: 'p', title: 'p', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c', parentId: 'p', title: 'c', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree, visibleIds: {'p', 'c'});
      // 필터가 켜져 있으면(visibleIds != null) 매칭 자손이 숨으면 안 된다.
      expect(rows.map((r) => r.id).toList(), ['p', 'c']);
      // 강제로 펼쳐 보였을 뿐, 저장된 isCollapsed 값 자체는 그대로다.
      expect(tree['p']!.isCollapsed, isTrue,
          reason: '표시만 임시로 무시했을 뿐 persisted 상태는 수정되면 안 된다');
      // 화살표 방향은 "실제로 보이는가" 를 따른다 — 강제로 펼쳐졌으니 펼침 표시.
      expect(rows.first.isChildrenShown, isTrue);
    });

    test('필터가 없으면(visibleIds: null) 접힌 부모는 자손을 그대로 숨긴다(기존 동작)',
        () {
      final tree = _tree([
        PlanNode(id: 'p', title: 'p', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c', parentId: 'p', title: 'c', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(tree);
      expect(rows.map((r) => r.id).toList(), ['p']);
      expect(rows.single.isChildrenShown, isFalse);
    });

    test('필터를 해제하면(visibleIds 없이 다시 호출) 기존 접기 상태로 돌아온다', () {
      final tree = _tree([
        PlanNode(id: 'p', title: 'p', sortOrder: 0, isCollapsed: true),
        PlanNode(id: 'c', parentId: 'p', title: 'c', sortOrder: 0),
      ]);
      // 필터 적용 중 — c 가 보인다.
      expect(flattenVisibleRows(tree, visibleIds: {'p', 'c'}).map((r) => r.id),
          ['p', 'c']);
      // 필터 해제 — isCollapsed 를 건드리지 않았으므로 원래 접힌 상태로 복귀.
      expect(flattenVisibleRows(tree).map((r) => r.id), ['p']);
    });
  });

  group('FlatRow.matchesFilter / isContextAncestor', () {
    test('matchedIds/contextAncestorIds 를 주면 각 행에 반영된다', () {
      final tree = _tree([
        PlanNode(id: 'root', title: 'root', sortOrder: 0),
        PlanNode(id: 'leaf', parentId: 'root', title: 'leaf', sortOrder: 0),
      ]);
      final rows = flattenVisibleRows(
        tree,
        visibleIds: {'root', 'leaf'},
        matchedIds: {'leaf'},
        contextAncestorIds: {'root'},
      );
      final root = rows.firstWhere((r) => r.id == 'root');
      final leaf = rows.firstWhere((r) => r.id == 'leaf');
      expect(root.matchesFilter, isFalse);
      expect(root.isContextAncestor, isTrue);
      expect(leaf.matchesFilter, isTrue);
      expect(leaf.isContextAncestor, isFalse);
    });

    test('matchedIds 를 안 주면(필터 없음) 모든 행이 matchesFilter=true', () {
      final tree = _tree([PlanNode(id: 'a', title: 'a')]);
      final rows = flattenVisibleRows(tree);
      expect(rows.single.matchesFilter, isTrue);
      expect(rows.single.isContextAncestor, isFalse);
    });
  });
}
