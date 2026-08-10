import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/domain/today_query.dart';

final today = PlanDate(2026, 8, 11);

PlanNode _n(
  String id, {
  String? parent,
  PlanDate? start,
  PlanDate? end,
  TaskStatus status = TaskStatus.notStarted,
  double sortOrder = 0,
  String title = '',
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: title.isEmpty ? id : title,
      startDate: start,
      endDate: end,
      status: status,
      sortOrder: sortOrder,
    );

void main() {
  group('computeTodaySections', () {
    test('A) 오늘 진행 중: startDate<=today<=endDate && !done', () {
      final tree = PlanTree.fromNodes([
        _n('a', start: PlanDate(2026, 8, 9), end: PlanDate(2026, 8, 15)),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.inProgress.map((n) => n.id), ['a']);
    });

    test('B) 오늘 마감: endDate==today. inProgress 와 중복되지 않고 dueToday 로만',
        () {
      final tree = PlanTree.fromNodes([
        _n('a', start: PlanDate(2026, 8, 9), end: PlanDate(2026, 8, 11)),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.dueToday.map((n) => n.id), ['a']);
      expect(s.inProgress, isEmpty, reason: '중복 표시 금지 — dueToday 에만 있어야 한다');
    });

    test('C) 지연: endDate < today && !done', () {
      final tree = PlanTree.fromNodes([
        _n('a', end: PlanDate(2026, 8, 5)),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.overdue.map((n) => n.id), ['a']);
    });

    test('완료된 Task 는 지연이어도 표시되지 않는다', () {
      final tree = PlanTree.fromNodes([
        _n('a', end: PlanDate(2026, 8, 5), status: TaskStatus.done),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.overdue, isEmpty);
      expect(s.isEmpty, isTrue);
    });

    test('D) 다가오는 작업: startDate > today, 가까운 순서로 정렬', () {
      final tree = PlanTree.fromNodes([
        _n('far', start: PlanDate(2026, 9, 1)),
        _n('near', start: PlanDate(2026, 8, 12)),
        _n('mid', start: PlanDate(2026, 8, 20)),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.upcoming.map((n) => n.id), ['near', 'mid', 'far']);
    });

    test('leafOnly=true(기본): 부모 Goal 은 제외하고 leaf 만 표시', () {
      final tree = PlanTree.fromNodes([
        _n('goal',
            start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 31), title: '목표'),
        _n('leaf',
            parent: 'goal',
            start: PlanDate(2026, 8, 9),
            end: PlanDate(2026, 8, 15),
            title: 'leaf 작업'),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.inProgress.map((n) => n.id), ['leaf']);
      expect(s.inProgress.any((n) => n.id == 'goal'), isFalse,
          reason: '부모 Goal 이름이 아니라 leaf 작업이 표시되어야 한다');
    });

    test('leafOnly=false: 부모도 포함', () {
      final tree = PlanTree.fromNodes([
        _n('goal', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 31)),
        _n('leaf',
            parent: 'goal', start: PlanDate(2026, 8, 9), end: PlanDate(2026, 8, 15)),
      ]);
      final s = computeTodaySections(tree, today, leafOnly: false);
      expect(s.inProgress.map((n) => n.id).toSet(), {'goal', 'leaf'});
    });

    test('날짜 없는 Task 는 어느 섹션에도 뜨지 않는다', () {
      final tree = PlanTree.fromNodes([_n('a')]);
      final s = computeTodaySections(tree, today);
      expect(s.isEmpty, isTrue);
    });

    test('upcomingLimit 로 다가오는 작업 개수를 제한한다', () {
      final nodes = [
        for (var i = 1; i <= 5; i++)
          _n('u$i', start: today.addDays(i)),
      ];
      final tree = PlanTree.fromNodes(nodes);
      final s = computeTodaySections(tree, today, upcomingLimit: 3);
      expect(s.upcoming.length, 3);
    });

    test('복합: 진행중/마감/지연/예정이 각자 정확한 섹션에만 들어간다', () {
      final tree = PlanTree.fromNodes([
        _n('inprog', start: PlanDate(2026, 8, 9), end: PlanDate(2026, 8, 20)),
        _n('due', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 11)),
        _n('overdue', end: PlanDate(2026, 8, 5)),
        _n('upcoming', start: PlanDate(2026, 8, 15)),
      ]);
      final s = computeTodaySections(tree, today);
      expect(s.inProgress.map((n) => n.id), ['inprog']);
      expect(s.dueToday.map((n) => n.id), ['due']);
      expect(s.overdue.map((n) => n.id), ['overdue']);
      expect(s.upcoming.map((n) => n.id), ['upcoming']);
    });
  });

  group('isOverdue / overdueDays', () {
    test('endDate < today && !done', () {
      final n = _n('a', end: PlanDate(2026, 8, 5));
      expect(isOverdue(n, today), isTrue);
      expect(overdueDays(n, today), 6);
    });
    test('endDate == today 는 지연 아님', () {
      final n = _n('a', end: today);
      expect(isOverdue(n, today), isFalse);
      expect(overdueDays(n, today), 0);
    });
    test('done 이면 지연 아님', () {
      final n = _n('a', end: PlanDate(2026, 8, 5), status: TaskStatus.done);
      expect(isOverdue(n, today), isFalse);
    });
    test('날짜 없으면 지연 아님', () {
      expect(isOverdue(_n('a'), today), isFalse);
    });
  });
}
