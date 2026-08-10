import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/workload_query.dart';

void main() {
  group('computeWorkloadPlan: 수량형', () {
    test('300page, 80 완료, 8/1~8/30, 오늘 8/20 → 남은 220, 남은 11일, 올림', () {
      final node = PlanNode(
        id: 'a',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 300,
        actual: 80,
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 30),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 20));
      expect(plan, isNotNull);
      expect(plan!.remaining, 220);
      expect(plan.remainingDays, 11); // 8/20~8/30 inclusive = 11일.
      expect(plan.dailyTarget, (220 / 11).ceil());
      expect(plan.dailyTarget, 20);
    });

    test('나눠떨어지지 않으면 올림(ceil)', () {
      final node = PlanNode(
        id: 'a',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 100,
        actual: 0,
        endDate: PlanDate(2026, 8, 10),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 9));
      // 남은 2일(8/9,8/10), 100/2=50 정확히 나눠떨어짐.
      expect(plan!.remainingDays, 2);
      expect(plan.dailyTarget, 50);
    });

    test('완료(remaining<=0)면 dailyTarget=0, isComplete=true', () {
      final node = PlanNode(
        id: 'a',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 300,
        actual: 300,
        endDate: PlanDate(2026, 8, 30),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 20));
      expect(plan!.isComplete, isTrue);
      expect(plan.dailyTarget, 0);
    });

    test('기한이 지났는데 남은 양이 있으면 남은 양 전체가 오늘 몫, isBehindSchedule',
        () {
      final node = PlanNode(
        id: 'a',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 300,
        actual: 100,
        endDate: PlanDate(2026, 8, 10),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 15));
      expect(plan!.remainingDays, 0);
      expect(plan.dailyTarget, 200);
      expect(plan.isBehindSchedule, isTrue);
    });

    test('actual 이 null 이면 0으로 취급', () {
      final node = PlanNode(
        id: 'a',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 100,
        endDate: PlanDate(2026, 8, 10),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 10));
      expect(plan!.done, 0);
      expect(plan.remaining, 100);
    });
  });

  group('computeWorkloadPlan: 시간형', () {
    test('20시간, 6시간 완료, 남은 7일 → 소수 그대로(올림 안 함)', () {
      final node = PlanNode(
        id: 'a',
        title: '공부',
        nodeKind: NodeKind.effort,
        estimate: 20,
        actual: 6,
        endDate: PlanDate(2026, 8, 17),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 11));
      // 8/11~8/17 inclusive = 7일. remaining=14. 14/7=2.0.
      expect(plan!.remainingDays, 7);
      expect(plan.dailyTarget, 2.0);
    });

    test('나눠떨어지지 않으면 소수 유지(올림하지 않음)', () {
      final node = PlanNode(
        id: 'a',
        title: '공부',
        nodeKind: NodeKind.effort,
        estimate: 10,
        actual: 0,
        endDate: PlanDate(2026, 8, 4),
      );
      final plan = computeWorkloadPlan(node, PlanDate(2026, 8, 1));
      // 8/1~8/4 inclusive = 4일. 10/4=2.5.
      expect(plan!.remainingDays, 4);
      expect(plan.dailyTarget, 2.5);
    });
  });

  group('computeWorkloadPlan: 해당 없음', () {
    test('nodeKind==project 면 null', () {
      final node = PlanNode(
        id: 'a',
        title: 'x',
        estimate: 100,
        endDate: PlanDate(2026, 8, 10),
      );
      expect(computeWorkloadPlan(node, PlanDate(2026, 8, 1)), isNull);
    });

    test('estimate 없으면 null', () {
      final node = PlanNode(
        id: 'a',
        title: 'x',
        nodeKind: NodeKind.quantity,
        endDate: PlanDate(2026, 8, 10),
      );
      expect(computeWorkloadPlan(node, PlanDate(2026, 8, 1)), isNull);
    });

    test('endDate 없으면 null(일일 권장량 계산 불가)', () {
      final node = PlanNode(
        id: 'a',
        title: 'x',
        nodeKind: NodeKind.quantity,
        estimate: 100,
      );
      expect(computeWorkloadPlan(node, PlanDate(2026, 8, 1)), isNull);
    });
  });

  group('workloadSummaryLabel', () {
    test('정수 dailyTarget + unit', () {
      const plan = WorkloadPlan(
          target: 300, done: 80, remaining: 220, remainingDays: 11, dailyTarget: 20);
      expect(workloadSummaryLabel(plan, 'page'), '오늘 20page');
    });
    test('소수 dailyTarget + unit', () {
      const plan = WorkloadPlan(
          target: 20, done: 6, remaining: 14, remainingDays: 7, dailyTarget: 2.0);
      expect(workloadSummaryLabel(plan, '시간'), '오늘 2시간');
    });
    test('완료면 "완료"', () {
      const plan = WorkloadPlan(
          target: 300, done: 300, remaining: 0, remainingDays: 0, dailyTarget: 0);
      expect(workloadSummaryLabel(plan, 'page'), '완료');
    });
    test('unit 없으면 그냥 숫자만', () {
      const plan = WorkloadPlan(
          target: 100, done: 0, remaining: 100, remainingDays: 10, dailyTarget: 10);
      expect(workloadSummaryLabel(plan, null), '오늘 10');
    });
  });
}
