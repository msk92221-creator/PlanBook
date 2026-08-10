/// "오늘" 화면의 핵심 질의 — 이 앱의 가장 중요한 화면.
///
/// **Today 는 별도 데이터를 저장하지 않는다.** 항상 Task 데이터에서 오늘 날짜
/// 기준으로 실시간 계산한다(요구사항 §11).
///
/// 조건(중복 없이 한 카테고리에만 들어가도록 배타적으로 나눔):
/// - [TodaySections.inProgress]: startDate<=today<=endDate && !done, **단
///   endDate==today(오늘 마감) 인 것은 제외**하고 [dueToday] 로만 보낸다
///   (같은 Task 가 두 섹션에 중복으로 뜨는 것을 막기 위함 — 요구사항의
///   "중복 Task 는 한 번만 표시" 를 이렇게 만족시킨다).
/// - [TodaySections.dueToday]: endDate==today && !done.
/// - [TodaySections.overdue]: endDate<today && !done.
/// - [TodaySections.upcoming]: startDate>today, 가까운 순서.
///
/// [leafOnly]==true(기본) 면 **가장 하위 수준의 실행 가능한 작업**만 뽑는다
/// (부모 Goal 이름이 아니라 leaf Task 를 보여주는 게 이 화면의 핵심 목적).
library;

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_node.dart';
import 'plan_tree.dart';
import 'recurrence.dart';

class TodaySections {
  final List<PlanNode> inProgress;
  final List<PlanNode> dueToday;
  final List<PlanNode> overdue;
  final List<PlanNode> upcoming;

  const TodaySections({
    required this.inProgress,
    required this.dueToday,
    required this.overdue,
    required this.upcoming,
  });

  bool get isEmpty =>
      inProgress.isEmpty &&
      dueToday.isEmpty &&
      overdue.isEmpty &&
      upcoming.isEmpty;
}

/// [today] 기준 Today 섹션을 계산한다.
///
/// [upcomingLimit] 은 "다가오는 작업" 목록에 보여줄 최대 개수(가까운 날짜 순).
TodaySections computeTodaySections(
  PlanTree tree,
  PlanDate today, {
  bool leafOnly = true,
  int upcomingLimit = 10,
}) {
  final inProgress = <PlanNode>[];
  final dueToday = <PlanNode>[];
  final overdue = <PlanNode>[];
  final upcoming = <PlanNode>[];

  for (final n in tree.allNodes) {
    // 반복형은 startDate/endDate 가 있어도(반복 기간의 경계일 뿐) 여기서는
    // 다루지 않는다 — 전용 섹션([recurringOccurrencesOn])에서만 표시한다.
    // 안 그러면 기간 안에 있다는 이유만으로 A~D 섹션에도 중복으로 뜬다.
    if (n.nodeKind == NodeKind.recurring) continue;
    if (leafOnly && !tree.isLeaf(n.id)) continue;
    if (n.isDone) continue; // 완료된 건 어느 섹션에도 안 뜬다.

    final s = n.startDate;
    final e = n.endDate;
    // 날짜가 전혀 없는 Task 는 Today 의 어느 섹션에도 뜨지 않는다(A~D 모두
    // 날짜 기반 조건이다). `PlanDate.isWithin(null,null)` 는 "무한 범위" 라
    // true 를 반환하므로, 여기서 명시적으로 걸러야 아래 로직에 안 걸린다.
    if (s == null && e == null) continue;

    if (e != null && daysBetween(e, today) == 0) {
      dueToday.add(n);
      continue;
    }
    if (e != null && daysBetween(e, today) > 0) {
      overdue.add(n);
      continue;
    }
    if (today.isWithin(s, e)) {
      inProgress.add(n);
      continue;
    }
    if (s != null && daysBetween(today, s) > 0) {
      upcoming.add(n);
      continue;
    }
    // 그 외(예: endDate 만 있고 미래인 경우 등)는 Today 에 표시하지 않는다.
  }

  // 주의: daysBetween(a,b)=b-a 이므로 오름차순(가까운 날짜 먼저) 비교에는
  // daysBetween(sb,sa)(=sa-sb) 를 써야 한다. 순서를 바꿔 쓰면 부호가 뒤집혀
  // 내림차순이 되는 버그가 생긴다(plan_query.dart 의 동일 함정 참고).
  int byStart(PlanNode a, PlanNode b) {
    final sa = a.startDate;
    final sb = b.startDate;
    if (sa != null && sb != null) return daysBetween(sb, sa);
    if (sa != null) return -1;
    if (sb != null) return 1;
    return a.sortOrder.compareTo(b.sortOrder);
  }

  /// endDate 오름차순(가장 오래 지연된 것부터 — endDate 가 이를수록 더 오래 지연).
  int byEnd(PlanNode a, PlanNode b) {
    final ea = a.endDate;
    final eb = b.endDate;
    if (ea != null && eb != null) return daysBetween(eb, ea);
    return a.sortOrder.compareTo(b.sortOrder);
  }

  inProgress.sort(byStart);
  dueToday.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  overdue.sort(byEnd); // 가장 오래 지연된 것부터.
  upcoming.sort(byStart);
  final limitedUpcoming =
      upcoming.length > upcomingLimit ? upcoming.sublist(0, upcomingLimit) : upcoming;

  return TodaySections(
    inProgress: inProgress,
    dueToday: dueToday,
    overdue: overdue,
    upcoming: limitedUpcoming,
  );
}

/// [node] 가 지연되었는지: endDate < today && !done. 날짜 없으면 false.
bool isOverdue(PlanNode node, PlanDate today) {
  if (node.isDone) return false;
  final e = node.endDate;
  if (e == null) return false;
  return daysBetween(e, today) > 0;
}

/// [node] 가 며칠 지연되었는지(지연 아니면 0).
int overdueDays(PlanNode node, PlanDate today) {
  if (!isOverdue(node, today)) return 0;
  return daysBetween(node.endDate!, today);
}

/// [today] 에 occurrence 가 있는 반복형([NodeKind.recurring]) Task 목록.
/// (제목 기준 정렬 — 반복 Task 는 날짜 기반 정렬 기준이 없다)
List<PlanNode> recurringOccurrencesOn(PlanTree tree, PlanDate today) {
  final out = <PlanNode>[
    for (final n in tree.allNodes)
      if (recurrenceOccursOn(n, today)) n,
  ];
  out.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return out;
}
