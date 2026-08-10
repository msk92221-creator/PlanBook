/// Projects 화면 카드에 표시할 통계 — 실시간 계산(별도 저장 없음).
library;

import '../core/date/plan_date.dart';
import 'plan_tree.dart';
import 'today_query.dart' show isOverdue;

class ProjectStats {
  final int total;
  final int done;
  final int incomplete;
  final int overdue;

  /// 미완료 Task 중 가장 가까운(아직 안 지난) 마감일. 없으면 null.
  final PlanDate? nearestDeadline;

  /// 프로젝트에 속한 Task 들의 전체 기간(최소 시작일 ~ 최대 종료일). 날짜 있는
  /// Task 가 하나도 없으면 둘 다 null.
  final PlanDate? periodStart;
  final PlanDate? periodEnd;

  const ProjectStats({
    required this.total,
    required this.done,
    required this.incomplete,
    required this.overdue,
    required this.nearestDeadline,
    required this.periodStart,
    required this.periodEnd,
  });

  /// 0.0~1.0. total==0 이면 0.
  double get progress => total == 0 ? 0.0 : done / total;
}

/// [projectId] 에 속한 Task 기준 통계를 계산한다([leafOnly] 기본 true —
/// 실행 가능한 최하위 작업 기준으로 세는 게 더 실질적인 진행률을 준다).
ProjectStats computeProjectStats(
  PlanTree tree,
  String projectId,
  PlanDate today, {
  bool leafOnly = true,
}) {
  var total = 0;
  var done = 0;
  var overdue = 0;
  PlanDate? nearestDeadline;
  PlanDate? periodStart;
  PlanDate? periodEnd;

  for (final n in tree.allNodes) {
    if (n.projectId != projectId) continue;
    if (leafOnly && !tree.isLeaf(n.id)) continue;

    total++;
    if (n.isDone) done++;
    if (isOverdue(n, today)) overdue++;

    final s = n.startDate;
    final e = n.endDate;
    if (s != null) {
      if (periodStart == null || daysBetween(periodStart, s) < 0) periodStart = s;
    }
    if (e != null) {
      if (periodEnd == null || daysBetween(periodEnd, e) > 0) periodEnd = e;
      if (!n.isDone && daysBetween(today, e) >= 0) {
        // "가장 가까운"(=가장 이른) 마감을 찾는다. daysBetween(a,b)=b-a 이므로
        // 최솟값을 찾을 때는 daysBetween(candidate, best) > 0 일 때 갱신해야
        // 한다(best 가 candidate 보다 늦으면 = candidate 가 더 이르면 교체).
        if (nearestDeadline == null || daysBetween(e, nearestDeadline) > 0) {
          nearestDeadline = e;
        }
      }
    }
  }

  return ProjectStats(
    total: total,
    done: done,
    incomplete: total - done,
    overdue: overdue,
    nearestDeadline: nearestDeadline,
    periodStart: periodStart,
    periodEnd: periodEnd,
  );
}
