import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/recurrence.dart';

PlanNode _daily({PlanDate? start, PlanDate? end}) => PlanNode(
      id: 'd1',
      title: '매일 영어 30분',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: RecurrenceFreq.daily.name,
      startDate: start,
      endDate: end,
    );

PlanNode _weekly(Set<int> weekdays, {PlanDate? start, PlanDate? end}) =>
    PlanNode(
      id: 'w1',
      title: '월/수/금 운동',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: RecurrenceFreq.weekly.name,
      recurrenceWeekdays: weekdays.toList(),
      startDate: start,
      endDate: end,
    );

PlanNode _monthly(int dayOfMonth, {PlanDate? start, PlanDate? end}) =>
    PlanNode(
      id: 'm1',
      title: '매월 정산',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: RecurrenceFreq.monthly.name,
      recurrenceDayOfMonth: dayOfMonth,
      startDate: start,
      endDate: end,
    );

void main() {
  group('recurrenceRule 조립(extension)', () {
    test('nodeKind != recurring 이면 null', () {
      final n = PlanNode(id: 'x', title: 'x', nodeKind: NodeKind.project);
      expect(n.recurrenceRule, isNull);
    });

    test('recurring 인데 recurrenceFreq 없으면 null', () {
      final n = PlanNode(id: 'x', title: 'x', nodeKind: NodeKind.recurring);
      expect(n.recurrenceRule, isNull);
    });

    test('weekly 규칙이 올바르게 조립된다', () {
      final n = _weekly({DateTime.monday, DateTime.friday});
      final rule = n.recurrenceRule;
      expect(rule, isNotNull);
      expect(rule!.freq, RecurrenceFreq.weekly);
      expect(rule.weekdays, {DateTime.monday, DateTime.friday});
    });
  });

  group('recurrenceOccursOn — daily', () {
    test('무기한 daily 는 항상 발생', () {
      final n = _daily();
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 11)), isTrue);
      expect(recurrenceOccursOn(n, PlanDate(2030, 1, 1)), isTrue);
    });

    test('start/end 범위 밖은 발생하지 않는다', () {
      final n = _daily(start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 31));
      expect(recurrenceOccursOn(n, PlanDate(2026, 7, 31)), isFalse);
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 1)), isTrue);
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 31)), isTrue);
      expect(recurrenceOccursOn(n, PlanDate(2026, 9, 1)), isFalse);
    });

    test('non-recurring nodeKind 는 항상 false', () {
      final n = PlanNode(
        id: 'p1',
        title: 'p',
        nodeKind: NodeKind.project,
        recurrenceFreq: RecurrenceFreq.daily.name,
      );
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 11)), isFalse);
    });
  });

  group('recurrenceOccursOn — weekly(요일 선택)', () {
    test('월/수/금만 발생', () {
      final n = _weekly({DateTime.monday, DateTime.wednesday, DateTime.friday});
      // 2026-08-10 은 월요일.
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 10)), isTrue); // 월
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 11)), isFalse); // 화
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 12)), isTrue); // 수
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 13)), isFalse); // 목
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 14)), isTrue); // 금
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 15)), isFalse); // 토
    });
  });

  group('recurrenceOccursOn — monthly', () {
    test('지정한 날짜에만 발생', () {
      final n = _monthly(1);
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 1)), isTrue);
      expect(recurrenceOccursOn(n, PlanDate(2026, 8, 2)), isFalse);
      expect(recurrenceOccursOn(n, PlanDate(2026, 9, 1)), isTrue);
    });

    test('짧은 달은 마지막 날로 clamp 된다(31일 지정 + 2월)', () {
      final n = _monthly(31);
      // 2026년은 평년 → 2월 28일이 마지막 날.
      expect(recurrenceOccursOn(n, PlanDate(2026, 2, 28)), isTrue);
      expect(recurrenceOccursOn(n, PlanDate(2026, 2, 27)), isFalse);
      expect(recurrenceOccursOn(n, PlanDate(2026, 1, 31)), isTrue);
    });
  });

  group('isOccurrenceDone', () {
    test('completedDates 에 있는 날짜만 true', () {
      final n = _daily().copyWith(
        recurrenceCompletedDates: ['2026-08-10', '2026-08-12'],
      );
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 10)), isTrue);
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 11)), isFalse);
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 12)), isTrue);
    });

    test('한 occurrence 완료가 다른 occurrence 에 영향을 주지 않는다', () {
      // "원본을 done 처리하면 미래 전부 사라짐" 버그 재현 방지 회귀 테스트.
      var n = _daily();
      n = n.copyWith(recurrenceCompletedDates: ['2026-08-10']);
      expect(n.status, TaskStatus.notStarted, reason: '원본 status 는 불변');
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 10)), isTrue);
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 11)), isFalse);
      expect(isOccurrenceDone(n, PlanDate(2026, 8, 12)), isFalse);
    });
  });

  group('recurrenceOccurrencesInRange', () {
    test('weekly 범위 안 occurrence 목록', () {
      final n = _weekly({DateTime.monday, DateTime.friday});
      final list = recurrenceOccurrencesInRange(
          n, PlanDate(2026, 8, 10), PlanDate(2026, 8, 16));
      expect(list, [PlanDate(2026, 8, 10), PlanDate(2026, 8, 14)]);
    });

    test('대량 사전 생성 없이 좁은 범위만 계산(성능/구조 확인용)', () {
      final n = _daily();
      final list = recurrenceOccurrencesInRange(
          n, PlanDate(2026, 1, 1), PlanDate(2026, 1, 5));
      expect(list.length, 5);
    });
  });

  group('fromName', () {
    test('알 수 없는 문자열은 daily 로 폴백', () {
      expect(RecurrenceFreq.fromName('bogus'), RecurrenceFreq.daily);
      expect(RecurrenceFreq.fromName(null), RecurrenceFreq.daily);
    });
    test('정상 이름은 매칭된다', () {
      expect(RecurrenceFreq.fromName('weekly'), RecurrenceFreq.weekly);
      expect(RecurrenceFreq.fromName('monthly'), RecurrenceFreq.monthly);
    });
  });
}
