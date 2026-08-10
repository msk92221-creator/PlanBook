/// 반복 목표(예: "월/수/금 운동", "매일 영어 30분", "매월 1일 정산").
///
/// **미래 Task 객체를 대량으로 미리 생성하지 않는다.** 반복 규칙([RecurrenceRule])
/// 하나만 [PlanNode] 에 저장하고, 특정 날짜가 occurrence 인지는 그때그때
/// [recurrenceOccursOn] 으로 계산한다(Today/Calendar 가 이 함수를 그대로 쓴다).
///
/// **완료 상태는 occurrence(날짜)별로 따로 기록**된다
/// ([PlanNode.recurrenceCompletedDates] — ISO 날짜 문자열 집합). 원본 반복
/// Task 자체의 [PlanNode.status] 를 done 으로 바꾸는 방식은 쓰지 않는다 —
/// 그러면 그 시점 이후 모든 미래 occurrence 가 통째로 "완료된 반복 작업"처럼
/// 보여 미래 일정이 사라지는 것과 같은 효과가 나기 때문이다.
library;

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_node.dart';

enum RecurrenceFreq {
  daily,
  weekly,
  monthly;

  static RecurrenceFreq fromName(String? name) {
    if (name == null) return RecurrenceFreq.daily;
    for (final v in RecurrenceFreq.values) {
      if (v.name == name) return v;
    }
    return RecurrenceFreq.daily;
  }

  String get label => switch (this) {
        RecurrenceFreq.daily => '매일',
        RecurrenceFreq.weekly => '매주(요일 선택)',
        RecurrenceFreq.monthly => '매월',
      };
}

/// 반복 규칙. [PlanNode] 에는 이 값이 필드 3개(freq/weekdays/dayOfMonth)로
/// 평탄화되어 저장된다(다른 모델과 동일하게 중첩 객체를 피하는 스타일 유지).
class RecurrenceRule {
  final RecurrenceFreq freq;

  /// [freq]==weekly 일 때만 의미 있음. `DateTime.monday`(1)~`DateTime.sunday`(7).
  final Set<int> weekdays;

  /// [freq]==monthly 일 때만 의미 있음. 1~31 — 그 달의 마지막 날보다 크면
  /// 그 달의 마지막 날로 clamp 한다(예: 31일 지정 + 2월 → 28/29일).
  final int dayOfMonth;

  const RecurrenceRule({
    required this.freq,
    this.weekdays = const {},
    this.dayOfMonth = 1,
  });

  RecurrenceRule copyWith({
    RecurrenceFreq? freq,
    Set<int>? weekdays,
    int? dayOfMonth,
  }) =>
      RecurrenceRule(
        freq: freq ?? this.freq,
        weekdays: weekdays ?? this.weekdays,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      );

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule &&
      other.freq == freq &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays) &&
      other.dayOfMonth == dayOfMonth;

  @override
  int get hashCode =>
      Object.hash(freq, Object.hashAllUnordered(weekdays), dayOfMonth);
}

/// [PlanNode] 에 평탄화 저장된 recurrenceFreq/recurrenceWeekdays/
/// recurrenceDayOfMonth 필드로부터 구조화된 [RecurrenceRule] 을 조립한다.
/// (순환 참조를 피하려고 `plan_node.dart` 자체에는 이 getter 를 두지 않았다.)
extension PlanNodeRecurrenceX on PlanNode {
  RecurrenceRule? get recurrenceRule {
    if (nodeKind != NodeKind.recurring || recurrenceFreq == null) return null;
    return RecurrenceRule(
      freq: RecurrenceFreq.fromName(recurrenceFreq),
      weekdays: recurrenceWeekdays.toSet(),
      dayOfMonth: recurrenceDayOfMonth ?? 1,
    );
  }
}

/// [node] 가 [date] 에 "발생"하는지(occurrence 인지).
///
/// - [PlanNode.nodeKind] 가 [NodeKind.recurring] 이 아니거나 규칙이 없으면 false.
/// - [PlanNode.startDate]/[endDate] 가 있으면 그 범위 밖은 발생하지 않는다
///   (예: "8/1~8/31 매일" 처럼 기간이 있는 반복 목표).둘 다 없으면 무기한.
bool recurrenceOccursOn(PlanNode node, PlanDate date) {
  if (node.nodeKind != NodeKind.recurring) return false;
  final rule = node.recurrenceRule;
  if (rule == null) return false;
  final s = node.startDate;
  final e = node.endDate;
  if (s != null && daysBetween(s, date) < 0) return false; // date < start
  if (e != null && daysBetween(date, e) < 0) return false; // date > end

  switch (rule.freq) {
    case RecurrenceFreq.daily:
      return true;
    case RecurrenceFreq.weekly:
      return rule.weekdays.contains(date.toDateTime().weekday);
    case RecurrenceFreq.monthly:
      final lastDay = endOfMonth(date).day;
      final target = rule.dayOfMonth.clamp(1, lastDay);
      return date.day == target;
  }
}

/// [node] 의 [date] occurrence 가 완료 처리되어 있는지.
bool isOccurrenceDone(PlanNode node, PlanDate date) =>
    node.recurrenceCompletedDates.contains(date.toIso());

const List<String> _kWeekdayShortLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 반복 규칙의 한 줄 표시 문구. 예) "매일", "월,수,금", "매월 3일".
String recurrenceRuleLabel(RecurrenceRule rule) {
  switch (rule.freq) {
    case RecurrenceFreq.daily:
      return '매일';
    case RecurrenceFreq.weekly:
      if (rule.weekdays.isEmpty) return '매주';
      final sorted = rule.weekdays.toList()..sort();
      return sorted.map((w) => _kWeekdayShortLabels[w - 1]).join(',');
    case RecurrenceFreq.monthly:
      return '매월 ${rule.dayOfMonth}일';
  }
}

/// `[from, to]`(inclusive) 구간에서 [node] 가 발생하는 날짜 목록.
/// Calendar 월 그리드처럼 좁은 범위에서만 호출할 것을 가정한 단순 구현이다.
List<PlanDate> recurrenceOccurrencesInRange(
  PlanNode node,
  PlanDate from,
  PlanDate to,
) {
  final out = <PlanDate>[];
  var cursor = from;
  while (daysBetween(cursor, to) >= 0) {
    if (recurrenceOccursOn(node, cursor)) out.add(cursor);
    cursor = cursor.addDays(1);
  }
  return out;
}
