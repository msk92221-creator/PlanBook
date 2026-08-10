import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/reschedule.dart';

void main() {
  final overdueNode = PlanNode(
    id: 'a',
    title: 'a',
    startDate: PlanDate(2026, 8, 1),
    endDate: PlanDate(2026, 8, 5), // 오늘(8/11) 기준 6일 지연.
  );
  final today = PlanDate(2026, 8, 11);

  group('rescheduleNode', () {
    test('today: endDate 가 오늘로, 기간 길이(5일)는 유지된다', () {
      final r = rescheduleNode(overdueNode, RescheduleOption.today, today);
      expect(r, isNotNull);
      expect(r!.endDate, today);
      expect(r.startDate, PlanDate(2026, 8, 7)); // 6일 뒤로 밀림 → 8/1+6=8/7.
      expect(inclusiveDayCount(r.startDate, r.endDate), 5);
    });

    test('tomorrow: endDate = 오늘+1', () {
      final r = rescheduleNode(overdueNode, RescheduleOption.tomorrow, today);
      expect(r!.endDate, PlanDate(2026, 8, 12));
    });

    test('specificDate: 지정한 날짜로 이동, 기간 길이 유지', () {
      final r = rescheduleNode(
        overdueNode,
        RescheduleOption.specificDate,
        today,
        specificDate: PlanDate(2026, 9, 1),
      );
      expect(r!.endDate, PlanDate(2026, 9, 1));
      expect(inclusiveDayCount(r.startDate, r.endDate), 5);
    });

    test('specificDate 인데 날짜를 안 주면 null(적용 안 함)', () {
      final r =
          rescheduleNode(overdueNode, RescheduleOption.specificDate, today);
      expect(r, isNull);
    });

    test('autoRedistribute: 지연된 일수(6일)만큼 뒤로 밀린다', () {
      final r = rescheduleNode(
          overdueNode, RescheduleOption.autoRedistribute, today);
      expect(r!.endDate, today); // 6일 지연 → +6일 → 8/5+6=8/11=오늘.
      expect(r.startDate, PlanDate(2026, 8, 7));
    });

    test('autoRedistribute: 아직 지연 안 됐으면 변경 없음(null)', () {
      final notOverdue = overdueNode.copyWith(
        startDate: PlanDate(2026, 8, 10),
        endDate: PlanDate(2026, 8, 20),
      );
      final r = rescheduleNode(
          notOverdue, RescheduleOption.autoRedistribute, today);
      expect(r, isNull);
    });

    test('keepAsIs: 항상 null(아무 것도 안 함)', () {
      final r = rescheduleNode(overdueNode, RescheduleOption.keepAsIs, today);
      expect(r, isNull);
    });

    test('endDate 가 없으면 어떤 옵션이든 null', () {
      final noEnd = PlanNode(id: 'b', title: 'b');
      expect(rescheduleNode(noEnd, RescheduleOption.today, today), isNull);
      expect(
          rescheduleNode(noEnd, RescheduleOption.autoRedistribute, today),
          isNull);
    });

    test('startDate 가 없으면 endDate 만 이동한다', () {
      final endOnly =
          PlanNode(id: 'c', title: 'c', endDate: PlanDate(2026, 8, 5));
      final r = rescheduleNode(endOnly, RescheduleOption.today, today);
      expect(r!.endDate, today);
      expect(r.startDate, isNull);
    });

    test('변경이 없으면(delta==0) null 을 반환해 불필요한 저장을 막는다', () {
      final atToday = overdueNode.copyWith(endDate: today);
      final r = rescheduleNode(atToday, RescheduleOption.today, today);
      expect(r, isNull);
    });
  });
}
