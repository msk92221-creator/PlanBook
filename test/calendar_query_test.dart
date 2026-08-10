import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/calendar_query.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(
  String id, {
  String? parent,
  PlanDate? start,
  PlanDate? end,
  bool milestone = false,
  double sortOrder = 0,
  String title = '',
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: title.isEmpty ? id : title,
      startDate: start,
      endDate: end,
      isMilestone: milestone,
      sortOrder: sortOrder,
    );

void main() {
  group('nodeTouchesDate / tasksForDate', () {
    test('기간형 Task: startDate<=date<=endDate 이면 걸침', () {
      final n = _n('a', start: PlanDate(2026, 8, 10), end: PlanDate(2026, 8, 15));
      expect(nodeTouchesDate(n, PlanDate(2026, 8, 12)), isTrue);
      expect(nodeTouchesDate(n, PlanDate(2026, 8, 9)), isFalse);
      expect(nodeTouchesDate(n, PlanDate(2026, 8, 16)), isFalse);
    });

    test('Milestone: 기준일(endDate 우선)과 정확히 같은 날짜만 걸침', () {
      final m = _n('m', end: PlanDate(2026, 8, 20), milestone: true);
      expect(nodeTouchesDate(m, PlanDate(2026, 8, 20)), isTrue);
      expect(nodeTouchesDate(m, PlanDate(2026, 8, 19)), isFalse,
          reason: 'coversDate 를 그대로 쓰면 null=무한 규칙 때문에 이전 날짜에도 '
              '걸린다고 오판할 수 있다 — milestone 은 정확히 그 날만 걸쳐야 한다');
      expect(nodeTouchesDate(m, PlanDate(2026, 8, 21)), isFalse);
    });

    test('startDate 만 있는 Milestone 은 startDate 기준', () {
      final m = _n('m', start: PlanDate(2026, 8, 5), milestone: true);
      expect(nodeTouchesDate(m, PlanDate(2026, 8, 5)), isTrue);
      expect(nodeTouchesDate(m, PlanDate(2026, 8, 6)), isFalse);
    });

    test('tasksForDate: milestone 이 먼저, 그다음 startDate 오름차순', () {
      final tree = PlanTree.fromNodes([
        _n('range1', start: PlanDate(2026, 8, 10), end: PlanDate(2026, 8, 20), title: 'range1'),
        _n('mile', end: PlanDate(2026, 8, 15), milestone: true, title: 'mile'),
        _n('range2', start: PlanDate(2026, 8, 12), end: PlanDate(2026, 8, 18), title: 'range2'),
      ]);
      final r = tasksForDate(tree, PlanDate(2026, 8, 15));
      expect(r.map((n) => n.id), ['mile', 'range1', 'range2']);
    });

    test('leafOnly=true 면 부모는 제외', () {
      final tree = PlanTree.fromNodes([
        _n('parent', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 31)),
        _n('leaf', parent: 'parent', start: PlanDate(2026, 8, 10), end: PlanDate(2026, 8, 15)),
      ]);
      final r = tasksForDate(tree, PlanDate(2026, 8, 12), leafOnly: true);
      expect(r.map((n) => n.id), ['leaf']);
    });
  });

  group('monthGridDays', () {
    test('월요일 시작 기준 2026년 8월 그리드는 7의 배수 일수', () {
      final days = monthGridDays(PlanDate(2026, 8, 15), DateTime.monday);
      expect(days.length % 7, 0);
      // 8/1(토) 이 속한 주의 월요일부터 시작해야 한다.
      expect(days.first.toDateTime().weekday, DateTime.monday);
      expect(days.first.compareTo(PlanDate(2026, 8, 1)) <= 0, isTrue);
      expect(days.last.compareTo(PlanDate(2026, 8, 31)) >= 0, isTrue);
    });

    test('일요일 시작 기준이면 그리드 첫날이 일요일', () {
      final days = monthGridDays(PlanDate(2026, 8, 15), DateTime.sunday);
      expect(days.first.toDateTime().weekday, DateTime.sunday);
    });
  });

  group('calendarBuckets', () {
    test('각 날짜별로 걸치는 Task 를 모은다', () {
      final tree = PlanTree.fromNodes([
        _n('a', start: PlanDate(2026, 8, 10), end: PlanDate(2026, 8, 12)),
      ]);
      final days = [
        PlanDate(2026, 8, 9),
        PlanDate(2026, 8, 10),
        PlanDate(2026, 8, 11),
        PlanDate(2026, 8, 12),
        PlanDate(2026, 8, 13),
      ];
      final buckets = calendarBuckets(tree, days);
      expect(buckets[PlanDate(2026, 8, 9).toIso()], isNull);
      expect(buckets[PlanDate(2026, 8, 10).toIso()]?.map((n) => n.id), ['a']);
      expect(buckets[PlanDate(2026, 8, 11).toIso()]?.map((n) => n.id), ['a']);
      expect(buckets[PlanDate(2026, 8, 13).toIso()], isNull);
    });

    test('반복형(daily) Task 는 그리드의 모든 날짜에 걸친다', () {
      final tree = PlanTree.fromNodes([
        PlanNode(
          id: 'r',
          title: '매일',
          nodeKind: NodeKind.recurring,
          recurrenceFreq: 'daily',
        ),
      ]);
      final days = [PlanDate(2026, 8, 10), PlanDate(2026, 8, 11)];
      final buckets = calendarBuckets(tree, days);
      expect(buckets[PlanDate(2026, 8, 10).toIso()]?.map((n) => n.id), ['r']);
      expect(buckets[PlanDate(2026, 8, 11).toIso()]?.map((n) => n.id), ['r']);
    });
  });

  group('nodeTouchesDate — 반복형', () {
    test('weekly 는 지정 요일에만 걸치고, 기간형 coversDate 규칙을 타지 않는다', () {
      final n = PlanNode(
        id: 'w',
        title: 'w',
        nodeKind: NodeKind.recurring,
        recurrenceFreq: 'weekly',
        recurrenceWeekdays: [DateTime.monday],
        // startDate/endDate 가 있어도 "기간 내 매일 걸침" 규칙(coversDate)이
        // 적용되면 안 된다 — 반복 규칙에 맞는 날만 걸쳐야 한다.
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 31),
      );
      // 2026-08-10 은 월요일, 2026-08-11 은 화요일.
      expect(nodeTouchesDate(n, PlanDate(2026, 8, 10)), isTrue);
      expect(nodeTouchesDate(n, PlanDate(2026, 8, 11)), isFalse);
    });
  });
}
