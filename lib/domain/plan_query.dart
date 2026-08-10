/// 날짜 기반 조회(일간/주간/월간 뷰의 핵심 질의).
///
/// 일간 뷰가 이 앱의 핵심 목적: 오늘 날짜가 작업 기간 안(inclusive)에 들어가는
/// **leaf 작업**(실행 가능한 최하위 단위)을 자동으로 추출한다.
/// 상위 목표 이름이 아니라 leaf 작업이 표시되는 것이 목표다.
///
/// 모든 질의는 [PlanDate] 만 받아 동작 → 순수 함수, 테스트에서 고정 날짜 주입 가능.
library;

import '../core/date/plan_date.dart' as pd;
import '../core/date/plan_date.dart' show PlanDate, startOfWeek, endOfWeek, startOfMonth, endOfMonth, daysBetween;
import 'plan_node.dart';
import 'plan_tree.dart';

/// 날짜/범위 필터 결과(정렬된 노드 리스트).
typedef PlanQueryResult = List<PlanNode>;

/// [date] 가 [node] 의 기간 안(inclusive)에 들어가는지.
/// start/end 중 null 인 쪽은 무한으로 본다.
///
/// 주의: 유효(rollup) 기간이 아니라 **노드 자신의 저장 기간**을 본다.
/// leaf 작업은 자식이 없으므로 rollup 영향을 받지 않는다.
bool coversDate(PlanNode node, PlanDate date) =>
    date.isWithin(node.startDate, node.endDate);

/// [node] 의 기간이 `[from, to]` 구간과 겹치는지(inclusive).
bool overlapsRange(PlanNode node, PlanDate from, PlanDate to) {
  return pd.overlapsRange(node.startDate, node.endDate, from, to);
}

/// [tree] 의 노드 중 주어진 조건을 만족하는 것을 수집.
/// - [covers] / [overlaps] 둘 중 하나를 true 로 만드는 콜백을 전달.
/// - [leafOnly]==true 면 자식이 없는 노드만.
PlanQueryResult _select(
  PlanTree tree, {
  required bool Function(PlanNode) predicate,
  bool leafOnly = true,
}) {
  final result = <PlanNode>[];
  for (final n in tree.allNodes) {
    if (leafOnly && !tree.isLeaf(n.id)) continue;
    if (predicate(n)) result.add(n);
  }
  // 결정적 정렬: 루트→자식 순서가 아니라, startDate(오름차순, 가까운 날짜 먼저.
  // 없으면 가장 뒤) + sortOrder.
  // 주의: daysBetween(a,b) = b-a 이므로 오름차순 비교에는 daysBetween(sb,sa)
  // (= sa-sb) 를 써야 한다. daysBetween(sa,sb) 를 그대로 쓰면 부호가 뒤집혀
  // 내림차순(늦은 날짜 먼저)이 되는 버그가 생긴다.
  result.sort((a, b) {
    final sa = a.startDate;
    final sb = b.startDate;
    if (sa != null && sb != null) {
      final d = daysBetween(sb, sa);
      if (d != 0) return d;
    } else if (sa != null) {
      return -1;
    } else if (sb != null) {
      return 1;
    }
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return result;
}

/// [date] 당일에 걸치는 작업.
/// - [leafOnly]==true(기본) → 자식 없는 leaf 작업만(=일간 뷰용).
PlanQueryResult tasksCoveringDate(
  PlanTree tree,
  PlanDate date, {
  bool leafOnly = true,
}) =>
    _select(
      tree,
      predicate: (n) => coversDate(n, date),
      leafOnly: leafOnly,
    );

/// `[from, to]` 구간에 걸치는 작업(주간/월간 뷰용).
PlanQueryResult tasksOverlappingRange(
  PlanTree tree,
  PlanDate from,
  PlanDate to, {
  bool leafOnly = true,
}) =>
    _select(
      tree,
      predicate: (n) => overlapsRange(n, from, to),
      leafOnly: leafOnly,
    );

/// [date] 가 속한 주(월~일)에 걸치는 작업.
PlanQueryResult tasksForWeek(
  PlanTree tree,
  PlanDate date, {
  bool leafOnly = true,
}) {
  return tasksOverlappingRange(tree, startOfWeek(date), endOfWeek(date),
      leafOnly: leafOnly);
}

/// [date] 가 속한 월에 걸치는 작업.
PlanQueryResult tasksForMonth(
  PlanTree tree,
  PlanDate date, {
  bool leafOnly = true,
}) {
  return tasksOverlappingRange(tree, startOfMonth(date), endOfMonth(date),
      leafOnly: leafOnly);
}
