/// 화면 표시용 "유효 기간(effective date range)" 계산.
///
/// [plan_rollup.dart] 의 rollup 과는 **다른, 독립된 개념**이다:
/// - rollup 은 `autoRollup==true` 일 때만 자식 기반으로 계산하고, 진행률/완료 여부도
///   함께 계산한다(트리 계산이 `autoRollup==false` 인 노드에서 멈춘다).
/// - 이 파일의 [computeEffectiveDateRange] 는 **`autoRollup` 값과 무관하게**, 노드
///   자신에게 날짜가 전혀 없을 때 자손 전체(그랜드칠드런 포함)를 재귀적으로 훑어
///   "화면에 뭐라도 보여줄 기간"만 추론한다. 오직 표시용이며 [PlanNode] 에는
///   저장하지 않는다.
///
/// 규칙:
/// A. 노드 자신에게 startDate 또는 endDate 가 있으면(둘 중 하나라도) 그 값을 그대로 쓴다.
/// B. 둘 다 없으면 모든 자손(자식의 자식까지 포함)에서 최소 startDate / 최대 endDate 를 찾는다.
/// C. 그래도 없으면(자손도 날짜가 없음) null.
library;

import '../core/date/plan_date.dart';
import 'plan_tree.dart';

/// [computeEffectiveDateRange] 의 결과.
class EffectiveDateRange {
  /// 유효 시작일(없으면 null).
  final PlanDate? start;

  /// 유효 종료일(없으면 null, inclusive).
  final PlanDate? end;

  /// true 면 노드 자신에게는 날짜가 전혀 없고, 자손으로부터 추론된 값이다.
  /// (향후 Drag 단계에서 "추론된 부모 bar 는 직접 드래그하지 않는다" 판정에 사용)
  final bool isDerived;

  const EffectiveDateRange({
    required this.start,
    required this.end,
    required this.isDerived,
  });

  @override
  String toString() =>
      'EffectiveDateRange(start=$start,end=$end,derived=$isDerived)';
}

/// [tree] 안의 [nodeId] 에 대한 유효 기간을 계산한다.
///
/// - 노드 자신에게 startDate 또는 endDate 가 있으면 그 값을 그대로 반환한다
///   (반대쪽이 없어도 자손으로 대체하지 않는다 — "자체 값 우선" 원칙).
/// - 둘 다 없으면 모든 자손(재귀, 그랜드칠드런 포함)의 startDate 최소값 /
///   endDate 최대값을 찾는다. `autoRollup` 여부는 보지 않는다.
/// - 자손에도 날짜가 없으면 둘 다 null.
EffectiveDateRange computeEffectiveDateRange(PlanTree tree, String nodeId) {
  final node = tree[nodeId];
  if (node == null) {
    throw PlanTreeException('Node not found: $nodeId');
  }

  if (node.startDate != null || node.endDate != null) {
    return EffectiveDateRange(
      start: node.startDate,
      end: node.endDate,
      isDerived: false,
    );
  }

  PlanDate? minStart;
  PlanDate? maxEnd;

  void visit(String parentId) {
    for (final child in tree.childrenOf(parentId)) {
      final s = child.startDate;
      final e = child.endDate;
      if (s != null) {
        if (minStart == null || daysBetween(minStart!, s) < 0) minStart = s;
      }
      if (e != null) {
        if (maxEnd == null || daysBetween(maxEnd!, e) > 0) maxEnd = e;
      }
      // 그랜드칠드런까지 포함 — autoRollup 여부와 무관하게 항상 재귀한다.
      visit(child.id);
    }
  }

  visit(nodeId);

  if (minStart == null && maxEnd == null) {
    return const EffectiveDateRange(start: null, end: null, isDerived: false);
  }
  return EffectiveDateRange(start: minStart, end: maxEnd, isDerived: true);
}
