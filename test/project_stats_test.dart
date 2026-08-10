import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/domain/project_stats.dart';

final today = PlanDate(2026, 8, 11);

PlanNode _n(
  String id, {
  String? parent,
  String? project,
  PlanDate? start,
  PlanDate? end,
  TaskStatus status = TaskStatus.notStarted,
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: id,
      projectId: project,
      startDate: start,
      endDate: end,
      status: status,
    );

void main() {
  group('computeProjectStats', () {
    test('total/done/incomplete/overdue 카운트', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1', status: TaskStatus.done),
        _n('b', project: 'p1', end: PlanDate(2026, 8, 5)), // 지연
        _n('c', project: 'p1'), // 미완료, 날짜 없음
        _n('d', project: 'p2'), // 다른 프로젝트 — 제외
      ]);
      final s = computeProjectStats(tree, 'p1', today);
      expect(s.total, 3);
      expect(s.done, 1);
      expect(s.incomplete, 2);
      expect(s.overdue, 1);
      expect(s.progress, closeTo(1 / 3, 0.001));
    });

    test('가장 가까운 마감(지나지 않은 것 중 최솟값)', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1', end: PlanDate(2026, 8, 20)),
        _n('b', project: 'p1', end: PlanDate(2026, 8, 15)),
        _n('c', project: 'p1', end: PlanDate(2026, 8, 5)), // 이미 지남 — 제외
        _n('d', project: 'p1', end: today, status: TaskStatus.done), // 완료 — 제외
      ]);
      final s = computeProjectStats(tree, 'p1', today);
      expect(s.nearestDeadline, PlanDate(2026, 8, 15));
    });

    test('전체 기간(최소 시작 ~ 최대 종료)', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 10)),
        _n('b', project: 'p1', start: PlanDate(2026, 7, 20), end: PlanDate(2026, 8, 25)),
      ]);
      final s = computeProjectStats(tree, 'p1', today);
      expect(s.periodStart, PlanDate(2026, 7, 20));
      expect(s.periodEnd, PlanDate(2026, 8, 25));
    });

    test('leafOnly=true(기본): 부모 노드는 카운트하지 않는다', () {
      final tree = PlanTree.fromNodes([
        _n('goal', project: 'p1'),
        _n('leaf', parent: 'goal', project: 'p1', status: TaskStatus.done),
      ]);
      final s = computeProjectStats(tree, 'p1', today);
      expect(s.total, 1);
    });

    test('해당 프로젝트에 Task 가 없으면 전부 0/null', () {
      final tree = PlanTree.fromNodes([_n('a', project: 'other')]);
      final s = computeProjectStats(tree, 'p1', today);
      expect(s.total, 0);
      expect(s.progress, 0.0);
      expect(s.nearestDeadline, isNull);
      expect(s.periodStart, isNull);
      expect(s.periodEnd, isNull);
    });
  });
}
