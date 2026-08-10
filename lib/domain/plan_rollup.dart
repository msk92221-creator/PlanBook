/// 부모 노드의 유효 기간/진행률/완료 여부를 자식들로부터 계산(rollup)하는 로직.
///
/// 핵심 원칙(DESIGN.md):
/// - 계산 결과는 **별도의 [RollupResult]** 로 반환되며, 노드의 원본 저장 값을
///   절대 덮어쓰지 않는다. (데이터 손실 방지)
/// - [PlanNode.autoRollup]==true 이고 자식이 있을 때만 자식 기반 계산을 한다.
///   자식이 없거나 autoRollup==false 면 노드 자신의 저장값을 그대로 반환.
/// - rollup 은 재귀적이다(자식도 autoRollup 이면 그 자식으로부터 계산).
library;

import '../core/date/plan_date.dart';
import 'plan_node.dart';
import 'plan_tree.dart';

/// rollup 계산 결과(유효값). 노드의 원본 값과 별개다.
class RollupResult {
  /// 유효 시작일(null = 미정).
  final PlanDate? startDate;

  /// 유효 종료일(null = 미정, inclusive).
  final PlanDate? endDate;

  /// 유효 진행률(0.0~1.0).
  final double progress;

  /// 유효 완료 여부(rollup 노드면 자식 전부 완료일 때 true).
  final bool isDone;

  /// 실제로 자식들로부터 계산되었는지(false 면 노드 자신의 저장값 사용).
  final bool computedFromChildren;

  const RollupResult({
    required this.startDate,
    required this.endDate,
    required this.progress,
    required this.isDone,
    required this.computedFromChildren,
  });

  @override
  String toString() =>
      'RollupResult(start=$startDate,end=$endDate,p=${(progress * 100).round()}%,'
      'done=$isDone,rolled=$computedFromChildren)';
}

/// [tree] 내 [nodeId] 의 유효값(rollup 결과)을 계산한다.
///
/// Rollup 규칙(autoRollup==true && 자식 존재):
/// - 유효기간 = 자식들 유효기간의 min(start) ~ max(end).
///   (날짜가 하나도 없으면 start/end 모두 null)
/// - 진행률 = 자식들의 유효 진행률.
///   모든 자식이 estimate(non-null) 를 가지고 estimate 합이 0보다 크면
///   **estimate 가중평균**, 그렇지 않으면 **단순 평균**.
/// - isDone = 모든 자식의 유효 isDone 이 true.
/// - 자식이 없거나 autoRollup==false → 노드 자신의 저장값.
RollupResult computeRollup(PlanTree tree, String nodeId) {
  final node = tree[nodeId];
  if (node == null) {
    throw PlanTreeException('Node not found: $nodeId');
  }
  final children = tree.childrenOf(nodeId);
  if (!node.autoRollup || children.isEmpty) {
    return RollupResult(
      startDate: node.startDate,
      endDate: node.endDate,
      progress: node.clampedProgress,
      isDone: node.isDone,
      computedFromChildren: false,
    );
  }

  // 자식들의 유효값 재귀 계산.
  final childResults = <({PlanNode node, RollupResult result})>[];
  for (final c in children) {
    childResults.add((node: c, result: computeRollup(tree, c.id)));
  }

  // 기간: 자식 유효 start 의 최소 / end 의 최대.
  // daysBetween(a,b) = b - a (JDN). s 가 minStart 보다 작으면(s 가 더 빠르면) 갱신.
  PlanDate? minStart;
  PlanDate? maxEnd;
  for (final cr in childResults) {
    final s = cr.result.startDate;
    final e = cr.result.endDate;
    if (s != null) {
      if (minStart == null || daysBetween(minStart, s) < 0) minStart = s;
    }
    if (e != null) {
      if (maxEnd == null || daysBetween(maxEnd, e) > 0) maxEnd = e;
    }
  }

  // 진행률: estimate 가중평균(모든 자식 estimate 있고 합>0) 또는 단순평균.
  final estimates = childResults.map((cr) => cr.node.estimate).toList();
  final allHaveEstimate =
      estimates.isNotEmpty && estimates.every((e) => e != null);
  final estimateSum = allHaveEstimate
      ? estimates.fold<num>(0, (a, e) => a + (e ?? 0))
      : 0;
  double progress;
  if (allHaveEstimate && estimateSum > 0) {
    var acc = 0.0;
    for (final cr in childResults) {
      final w = cr.node.estimate!.toDouble();
      acc += cr.result.progress * w;
    }
    progress = acc / estimateSum.toDouble();
  } else {
    progress = childResults.isEmpty
        ? 0.0
        : childResults.map((cr) => cr.result.progress).reduce((a, b) => a + b) /
            childResults.length;
  }
  if (progress.isNaN) progress = 0.0;
  if (progress < 0) progress = 0;
  if (progress > 1) progress = 1;

  // 완료: 모든 자식 유효 isDone.
  final isDone = childResults.every((cr) => cr.result.isDone);

  return RollupResult(
    startDate: minStart,
    endDate: maxEnd,
    progress: progress,
    isDone: isDone,
    computedFromChildren: true,
  );
}
