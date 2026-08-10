/// 수량형([NodeKind.quantity])/시간형([NodeKind.effort]) Task 의 일일 권장량 계산.
///
/// **매일 새로 계산한다 — 과거 계획을 저장/수정하지 않는다.** 사용자가 계획보다
/// 덜(또는 더) 했으면, [PlanNode.actual](누적 완료량)만 갱신되고 다음 계산은
/// 그 시점의 남은 양/남은 기간을 기준으로 자동으로 다시 나온다.
library;

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_node.dart';

class WorkloadPlan {
  /// 목표량(estimate).
  final num target;

  /// 지금까지 완료한 양(actual, 없으면 0).
  final num done;

  /// 남은 양(target - done, 음수면 0).
  final num remaining;

  /// 남은 작업 가능일(오늘 포함, endDate 까지). 기한이 지났으면 0.
  final int remainingDays;

  /// 오늘 권장 작업량. remaining==0 이면 0.
  final num dailyTarget;

  const WorkloadPlan({
    required this.target,
    required this.done,
    required this.remaining,
    required this.remainingDays,
    required this.dailyTarget,
  });

  bool get isComplete => remaining <= 0;

  /// 기한이 이미 지났는데 남은 양이 있는지("밀린" 수량형 작업).
  bool get isBehindSchedule => remainingDays <= 0 && remaining > 0;
}

/// [node] 가 [NodeKind.quantity]/[NodeKind.effort] 이고 [PlanNode.estimate] 와
/// [PlanNode.endDate] 가 있을 때 오늘([today]) 기준 작업 계획을 계산한다.
/// 해당 없으면(일반 Task 이거나 목표량/종료일이 없으면) null.
WorkloadPlan? computeWorkloadPlan(PlanNode node, PlanDate today) {
  if (node.nodeKind != NodeKind.quantity && node.nodeKind != NodeKind.effort) {
    return null;
  }
  final target = node.estimate;
  final end = node.endDate;
  if (target == null || end == null) return null;

  final done = node.actual ?? 0;
  final remaining = target - done;
  if (remaining <= 0) {
    return WorkloadPlan(
      target: target,
      done: done,
      remaining: 0,
      remainingDays: 0,
      dailyTarget: 0,
    );
  }

  final remainingDays = daysBetween(today, end) + 1; // 오늘 포함, inclusive.
  if (remainingDays <= 0) {
    // 기한이 이미 지났다 — 남은 양 전부가 "오늘(또는 그전) 몫".
    return WorkloadPlan(
      target: target,
      done: done,
      remaining: remaining,
      remainingDays: 0,
      dailyTarget: remaining,
    );
  }

  final rawDaily = remaining / remainingDays;
  // 수량형(정수 단위 가정)은 올림, 시간형은 소수 그대로(예: "하루 2.3시간").
  final dailyTarget =
      node.nodeKind == NodeKind.quantity ? rawDaily.ceil() : rawDaily;

  return WorkloadPlan(
    target: target,
    done: done,
    remaining: remaining,
    remainingDays: remainingDays,
    dailyTarget: dailyTarget,
  );
}

/// Today 화면 등에서 쓸 한 줄 표시 문구. 예) "20 page", "2.3시간".
/// [plan] 이 완료 상태면 "완료" 문구를 낸다.
String workloadSummaryLabel(WorkloadPlan plan, String? unit) {
  if (plan.isComplete) return '완료';
  final amount = plan.dailyTarget is int || plan.dailyTarget == plan.dailyTarget.roundToDouble()
      ? plan.dailyTarget.toInt().toString()
      : plan.dailyTarget.toStringAsFixed(1);
  final u = unit?.trim();
  return (u == null || u.isEmpty) ? '오늘 $amount' : '오늘 $amount$u';
}
