/// Calendar 화면의 핵심 질의 — 날짜별로 어떤 Task 가 걸쳐 있는지.
///
/// **날짜 계산은 `plan_query.dart`/`plan_date.dart` 를 재사용**한다(기간형 Task 는
/// [coversDate] 를 그대로 쓰고, Milestone 만 별도 규칙을 추가한다 — Milestone 은
/// "시점" 이라 [coversDate] 의 "무한 범위" 처리(null=무한)를 그대로 적용하면 안
/// 되기 때문이다: endDate 만 있는 Milestone 에 `coversDate` 를 쓰면 "그 날짜
/// 이전 모든 날"에 다 걸리는 것처럼 오판된다).
library;

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_node.dart';
import 'plan_query.dart' show coversDate;
import 'plan_tree.dart';
import 'recurrence.dart';

/// Milestone 의 기준일. endDate 우선, 없으면 startDate. 둘 다 없으면 null.
/// (Gantt 의 마일스톤 마커 앵커 규칙과 동일 — `gantt_timeline.dart` 참고)
PlanDate? milestoneAnchor(PlanNode node) => node.endDate ?? node.startDate;

/// [node] 가 [date] 에 "걸쳐 있는지"(Calendar 셀에 표시할지 판정).
///
/// 반복형([NodeKind.recurring])은 기간형 [coversDate] 규칙(시작~종료 사이 매일
/// 걸침)을 쓰지 않는다 — 반복 규칙에 맞는 날짜에만 걸친다([recurrenceOccursOn]).
bool nodeTouchesDate(PlanNode node, PlanDate date) {
  if (node.nodeKind == NodeKind.recurring) {
    return recurrenceOccursOn(node, date);
  }
  if (node.isMilestone) {
    final anchor = milestoneAnchor(node);
    return anchor != null && anchor == date;
  }
  return coversDate(node, date);
}

/// [date] 에 걸치는 Task 목록(정렬: milestone 먼저, 그다음 startDate, sortOrder).
List<PlanNode> tasksForDate(
  PlanTree tree,
  PlanDate date, {
  bool leafOnly = false,
}) {
  final result = <PlanNode>[];
  for (final n in tree.allNodes) {
    if (leafOnly && !tree.isLeaf(n.id)) continue;
    if (nodeTouchesDate(n, date)) result.add(n);
  }
  result.sort((a, b) {
    if (a.isMilestone != b.isMilestone) return a.isMilestone ? -1 : 1;
    final sa = a.startDate;
    final sb = b.startDate;
    if (sa != null && sb != null) {
      final d = daysBetween(sb, sa); // 오름차순(이른 날짜 먼저).
      if (d != 0) return d;
    }
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return result;
}

/// [gridDays] (달력에 실제로 그려질 날짜들 — 이전/다음 달 padding 포함) 각각에
/// 대해 걸치는 Task 목록을 계산한다. key 는 [PlanDate.toIso].
///
/// 개인용 데이터 규모(수백 Task, ~42 일 그리드)를 가정한 단순 구현이다 —
/// 필요 이상으로 최적화하지 않는다.
Map<String, List<PlanNode>> calendarBuckets(
  PlanTree tree,
  List<PlanDate> gridDays, {
  bool leafOnly = false,
}) {
  final map = <String, List<PlanNode>>{};
  for (final day in gridDays) {
    final items = tasksForDate(tree, day, leafOnly: leafOnly);
    if (items.isNotEmpty) map[day.toIso()] = items;
  }
  return map;
}

/// [anyDateInMonth] 가 속한 달의 달력 그리드 날짜 목록(이전/다음 달 padding
/// 포함, [weekStartWeekday] 기준 항상 7 의 배수 개수 — 보통 5~6 주).
List<PlanDate> monthGridDays(PlanDate anyDateInMonth, int weekStartWeekday) {
  final first = startOfMonth(anyDateInMonth);
  final last = endOfMonth(anyDateInMonth);
  final gridStart = startOfWeekWith(first, weekStartWeekday);
  final gridEnd = endOfWeekWith(last, weekStartWeekday);
  final days = <PlanDate>[];
  var cursor = gridStart;
  while (daysBetween(cursor, gridEnd) >= 0) {
    days.add(cursor);
    cursor = cursor.addDays(1);
  }
  return days;
}
