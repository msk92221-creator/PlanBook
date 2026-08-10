import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_query.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(
  String id, {
  String? parent,
  PlanDate? start,
  PlanDate? end,
  double sortOrder = 0,
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: id,
      startDate: start,
      endDate: end,
      sortOrder: sortOrder,
    );

void main() {
  // Shared tree:
  //   goal (8/1~8/31)
  //   ├─ sub (8/10~8/20)
  //   │   ├─ taskA (8/10~8/12)   leaf
  //   │   └─ taskB (8/14~8/18)   leaf
  //   └─ taskC (8/22~8/24)       leaf (direct child of goal)
  late PlanTree tree;
  setUp(() {
    tree = PlanTree.fromNodes([
      _n('goal', start: PlanDate(2024, 8, 1), end: PlanDate(2024, 8, 31)),
      _n('sub', parent: 'goal',
          start: PlanDate(2024, 8, 10), end: PlanDate(2024, 8, 20), sortOrder: 0),
      _n('taskC', parent: 'goal',
          start: PlanDate(2024, 8, 22), end: PlanDate(2024, 8, 24), sortOrder: 1),
      _n('taskA', parent: 'sub',
          start: PlanDate(2024, 8, 10), end: PlanDate(2024, 8, 12), sortOrder: 0),
      _n('taskB', parent: 'sub',
          start: PlanDate(2024, 8, 14), end: PlanDate(2024, 8, 18), sortOrder: 1),
    ]);
  });

  group('coversDate on node', () {
    test('inclusive start/end', () {
      final taskA = tree['taskA']!;
      expect(coversDate(taskA, PlanDate(2024, 8, 10)), isTrue);
      expect(coversDate(taskA, PlanDate(2024, 8, 12)), isTrue);
      expect(coversDate(taskA, PlanDate(2024, 8, 11)), isTrue);
      expect(coversDate(taskA, PlanDate(2024, 8, 9)), isFalse);
      expect(coversDate(taskA, PlanDate(2024, 8, 13)), isFalse);
    });
  });

  group('tasksCoveringDate (leaf-only by default)', () {
    test('leaf tasks only for a given day', () {
      final r = tasksCoveringDate(tree, PlanDate(2024, 8, 11));
      // 8/11 is within taskA only (8/10~8/12).
      expect(r.map((n) => n.id), ['taskA']);
    });

    test('multiple leaves overlap on same day', () {
      // 8/16 -> taskB (8/14~8/18)
      final r = tasksCoveringDate(tree, PlanDate(2024, 8, 16));
      expect(r.map((n) => n.id), ['taskB']);
    });

    test('include non-leaf when leafOnly=false', () {
      final r =
          tasksCoveringDate(tree, PlanDate(2024, 8, 11), leafOnly: false);
      // 8/11 within goal(8/1~8/31), sub(8/10~8/20), taskA(8/10~8/12)
      expect(r.map((n) => n.id).toSet(), {'goal', 'sub', 'taskA'});
    });

    test('upper goals excluded in leaf-only daily view', () {
      // 8/23 -> taskC (direct child of goal, leaf)
      final r = tasksCoveringDate(tree, PlanDate(2024, 8, 23));
      expect(r.map((n) => n.id), ['taskC']);
      // 'goal' and 'sub' must NOT appear
      expect(r.any((n) => n.id == 'goal' || n.id == 'sub'), isFalse);
    });

    test('no tasks on empty day', () {
      final r = tasksCoveringDate(tree, PlanDate(2024, 8, 13));
      expect(r, isEmpty);
    });
  });

  group('overlapsRange / tasksOverlappingRange', () {
    test('tasks overlapping a week range', () {
      // Week of 2024-08-12 (Monday) .. 2024-08-18 (Sunday)
      final r = tasksOverlappingRange(
          tree, PlanDate(2024, 8, 12), PlanDate(2024, 8, 18));
      // taskA (8/10~8/12) overlaps 8/12, taskB (8/14~8/18) overlaps fully.
      expect(r.map((n) => n.id).toSet(), {'taskA', 'taskB'});
    });

    test('month range includes all leaves', () {
      final r = tasksOverlappingRange(
          tree, PlanDate(2024, 8, 1), PlanDate(2024, 8, 31));
      expect(r.map((n) => n.id).toSet(), {'taskA', 'taskB', 'taskC'});
    });

    test('range outside all tasks -> empty', () {
      final r = tasksOverlappingRange(
          tree, PlanDate(2024, 9, 1), PlanDate(2024, 9, 5));
      expect(r, isEmpty);
    });
  });

  group('tasksForWeek / tasksForMonth helpers', () {
    test('week of Monday 2024-08-12', () {
      final r = tasksForWeek(tree, PlanDate(2024, 8, 12));
      expect(r.map((n) => n.id).toSet(), {'taskA', 'taskB'});
    });

    test('week of Sunday 2024-08-25 includes taskC', () {
      // Week containing 2024-08-25 (Sunday) = 2024-08-19..08-25 -> taskC(8/22~24)
      final r = tasksForWeek(tree, PlanDate(2024, 8, 25));
      expect(r.map((n) => n.id), ['taskC']);
    });

    test('month of August includes all leaves', () {
      final r = tasksForMonth(tree, PlanDate(2024, 8, 15));
      expect(r.map((n) => n.id).toSet(), {'taskA', 'taskB', 'taskC'});
    });

    test('month with no tasks', () {
      final r = tasksForMonth(tree, PlanDate(2024, 10, 15));
      expect(r, isEmpty);
    });
  });

  group('결과 정렬 순서(regression: daysBetween 부호 버그)', () {
    test('tasksForMonth 결과는 startDate 오름차순(이른 날짜 먼저)이어야 한다', () {
      final r = tasksForMonth(tree, PlanDate(2024, 8, 15));
      // taskA(8/10) < taskB(8/14) < taskC(8/22).
      expect(r.map((n) => n.id).toList(), ['taskA', 'taskB', 'taskC'],
          reason:
              'daysBetween(a,b)=b-a 를 그대로 comparator 에 쓰면 부호가 뒤집혀 '
              '내림차순이 되는 버그가 있었다 — 오름차순(이른 날짜 먼저)이어야 한다');
    });

    test('startDate 가 늦은 순으로 입력해도 결과는 항상 오름차순', () {
      final t = PlanTree.fromNodes([
        _n('late', start: PlanDate(2024, 1, 20), end: PlanDate(2024, 1, 25)),
        _n('early', start: PlanDate(2024, 1, 1), end: PlanDate(2024, 1, 5)),
        _n('mid', start: PlanDate(2024, 1, 10), end: PlanDate(2024, 1, 15)),
      ]);
      final r = tasksOverlappingRange(
          t, PlanDate(2024, 1, 1), PlanDate(2024, 1, 31));
      expect(r.map((n) => n.id).toList(), ['early', 'mid', 'late']);
    });
  });
}
