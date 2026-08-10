import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/effective_dates.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(
  String id, {
  String? parent,
  PlanDate? start,
  PlanDate? end,
  bool autoRollup = false,
  double sortOrder = 0,
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: id,
      startDate: start,
      endDate: end,
      autoRollup: autoRollup,
      sortOrder: sortOrder,
    );

void main() {
  group('computeEffectiveDateRange', () {
    test('A) 노드 자신에게 날짜가 있으면 그 값을 그대로 쓴다(자손 무시)', () {
      final tree = PlanTree.fromNodes([
        _n('p', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 5)),
        _n('c',
            parent: 'p',
            start: PlanDate(2026, 1, 1),
            end: PlanDate(2026, 12, 31)),
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 8, 1));
      expect(r.end, PlanDate(2026, 8, 5));
      expect(r.isDerived, isFalse);
    });

    test('A-2) 자신에게 startDate 만 있어도 자손으로 대체하지 않는다', () {
      final tree = PlanTree.fromNodes([
        _n('p', start: PlanDate(2026, 8, 1)),
        _n('c', parent: 'p', end: PlanDate(2026, 9, 1)),
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 8, 1));
      expect(r.end, isNull);
      expect(r.isDerived, isFalse);
    });

    test('B) 자신에게 날짜가 전혀 없고 자식에게 있으면 min/max 로 계산', () {
      final tree = PlanTree.fromNodes([
        _n('p', autoRollup: false),
        _n('a', parent: 'p', start: PlanDate(2026, 8, 5), end: PlanDate(2026, 8, 10)),
        _n('b', parent: 'p', start: PlanDate(2026, 8, 1), end: PlanDate(2026, 8, 20)),
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 8, 1));
      expect(r.end, PlanDate(2026, 8, 20));
      expect(r.isDerived, isTrue);
    });

    test('B) autoRollup=false 여도 파생값 계산은 동작한다(rollup 과 독립)', () {
      // 이 helper 는 autoRollup 값을 전혀 보지 않는다 — computeRollup 과 다른 개념.
      final tree = PlanTree.fromNodes([
        _n('p', autoRollup: false),
        _n('c', parent: 'p', start: PlanDate(2026, 3, 1), end: PlanDate(2026, 3, 2)),
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 3, 1));
      expect(r.end, PlanDate(2026, 3, 2));
      expect(r.isDerived, isTrue);
    });

    test('C) 3단계 이상 재귀: 그랜드칠드런의 날짜까지 포함한다', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('mid', parent: 'root'),
        _n('leaf1',
            parent: 'mid', start: PlanDate(2026, 1, 10), end: PlanDate(2026, 1, 12)),
        _n('leaf2',
            parent: 'mid', start: PlanDate(2026, 1, 20), end: PlanDate(2026, 1, 25)),
        _n('mid2', parent: 'root'),
        _n('leaf3',
            parent: 'mid2', start: PlanDate(2026, 1, 1), end: PlanDate(2026, 1, 3)),
      ]);
      final r = computeEffectiveDateRange(tree, 'root');
      expect(r.start, PlanDate(2026, 1, 1));
      expect(r.end, PlanDate(2026, 1, 25));
      expect(r.isDerived, isTrue);
    });

    test('D) 자손까지 포함해도 날짜가 하나도 없으면 둘 다 null', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('mid', parent: 'root'),
        _n('leaf', parent: 'mid'),
      ]);
      final r = computeEffectiveDateRange(tree, 'root');
      expect(r.start, isNull);
      expect(r.end, isNull);
      expect(r.isDerived, isFalse);
    });

    test('일부 자식만 날짜가 있어도 있는 것만으로 min/max 계산', () {
      final tree = PlanTree.fromNodes([
        _n('p'),
        _n('a', parent: 'p'), // 날짜 없음
        _n('b', parent: 'p', start: PlanDate(2026, 5, 1), end: PlanDate(2026, 5, 2)),
        _n('c', parent: 'p'), // 날짜 없음
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 5, 1));
      expect(r.end, PlanDate(2026, 5, 2));
      expect(r.isDerived, isTrue);
    });

    test('start 만 있는 자손과 end 만 있는 자손을 함께 반영한다', () {
      final tree = PlanTree.fromNodes([
        _n('p'),
        _n('a', parent: 'p', start: PlanDate(2026, 6, 1)),
        _n('b', parent: 'p', end: PlanDate(2026, 6, 30)),
      ]);
      final r = computeEffectiveDateRange(tree, 'p');
      expect(r.start, PlanDate(2026, 6, 1));
      expect(r.end, PlanDate(2026, 6, 30));
      expect(r.isDerived, isTrue);
    });

    test('노드를 찾을 수 없으면 예외', () {
      final tree = PlanTree.fromNodes([_n('a')]);
      expect(() => computeEffectiveDateRange(tree, 'missing'),
          throwsA(isA<PlanTreeException>()));
    });
  });
}
