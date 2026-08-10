/// 일정 재분배(밀린 작업의 날짜를 다시 잡는 것) — **항상 사용자가 명시적으로
/// 선택해야 실행된다.** 앱이 알아서 일정을 바꾸는 자동 실행은 절대 없다.
///
/// 정책: 기간(startDate~endDate)의 **길이를 보존**하면서 통째로 이동시키는
/// 단순한 날짜-shift 방식을 기본으로 쓴다([shiftRange] 재사용). 수량형/시간형
/// Task 의 "남은 양/일일 권장량"은 이 파일이 직접 계산하지 않는다 — endDate 가
/// 바뀌면 [workload_query.computeWorkloadPlan] 이 다음 조회 시점에 자동으로
/// 새 값을 실시간 계산한다(과거 계획을 여기서 강제로 다시 쓰지 않는다).
library;

import '../core/date/plan_date.dart';
import 'plan_node.dart';

enum RescheduleOption {
  /// 오늘로 이동: endDate = 오늘 (기간 길이 유지).
  today,

  /// 내일로 이동: endDate = 오늘+1.
  tomorrow,

  /// 사용자가 고른 특정 날짜로 이동.
  specificDate,

  /// 자동 재분배: 지연된 일수만큼 뒤로 밀어(기간 길이 유지) 오늘부터 다시
  /// 시작 가능하게 만든다. 아직 지연되지 않았으면 변경 없음.
  autoRedistribute,

  /// 그대로 둔다(명시적 "아무것도 안 함" — 취소와 구분하기 위해 옵션으로 존재).
  keepAsIs,
}

/// [node] 를 [option] 에 따라 재조정한 새 [PlanNode] 를 반환. 변경이 없거나
/// 적용할 수 없으면(keepAsIs, endDate 없음, specificDate 미지정 등) null.
///
/// **주의**: 이 함수 자체는 아무것도 저장하지 않는다 — 호출자(주로
/// [PlanStore.rescheduleNode])가 사용자의 명시적 선택 이후에만 호출해야 한다.
PlanNode? rescheduleNode(
  PlanNode node,
  RescheduleOption option,
  PlanDate today, {
  PlanDate? specificDate,
}) {
  if (option == RescheduleOption.keepAsIs) return null;
  final s = node.startDate;
  final e = node.endDate;
  if (e == null) return null; // 마감이 없으면 "재조정" 할 대상이 없다.

  PlanDate newEnd;
  switch (option) {
    case RescheduleOption.today:
      newEnd = today;
      break;
    case RescheduleOption.tomorrow:
      newEnd = today.addDays(1);
      break;
    case RescheduleOption.specificDate:
      if (specificDate == null) return null;
      newEnd = specificDate;
      break;
    case RescheduleOption.autoRedistribute:
      final overdue = daysBetween(e, today);
      newEnd = overdue > 0 ? e.addDays(overdue) : e;
      break;
    case RescheduleOption.keepAsIs:
      return null; // 위에서 이미 처리했지만 switch 완전성을 위해 남겨둠.
  }

  final delta = daysBetween(e, newEnd);
  if (delta == 0) return null;
  final shifted = shiftRange(s, e, delta);
  return node.copyWith(startDate: shifted.start, endDate: shifted.end);
}

/// [RescheduleOption] UI 표시 라벨.
extension RescheduleOptionLabel on RescheduleOption {
  String get label => switch (this) {
        RescheduleOption.today => '오늘로 이동',
        RescheduleOption.tomorrow => '내일로 이동',
        RescheduleOption.specificDate => '특정 날짜로 이동...',
        RescheduleOption.autoRedistribute => '자동 재분배(밀린 만큼 뒤로)',
        RescheduleOption.keepAsIs => '그대로 두기',
      };
}
