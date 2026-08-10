import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_rollup.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(
  String id, {
  String? parent,
  PlanDate? start,
  PlanDate? end,
  double progress = 0.0,
  bool isDone = false,
  TaskStatus? status,
  num? estimate,
  bool autoRollup = false,
  double sortOrder = 0,
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: id,
      startDate: start,
      endDate: end,
      progress: progress,
      // 완료는 이제 status 에서 파생된다. isDone 편의 인자는 done 으로 매핑하고,
      // status 를 직접 준 경우 그 값을 우선한다(onHold 검증용).
      status: status ?? (isDone ? TaskStatus.done : TaskStatus.notStarted),
      estimate: estimate,
      autoRollup: autoRollup,
      sortOrder: sortOrder,
    );

void main() {
  group('rollup period = children min..max', () {
    test('effective start = min(child starts), end = max(child ends)', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('c1', parent: 'parent',
            start: PlanDate(2024, 8, 10), end: PlanDate(2024, 8, 12)),
        _n('c2', parent: 'parent',
            start: PlanDate(2024, 8, 5), end: PlanDate(2024, 8, 20)),
        _n('c3', parent: 'parent',
            start: PlanDate(2024, 8, 15), end: PlanDate(2024, 8, 18)),
      ]);
      final r = computeRollup(tree, 'parent');
      expect(r.startDate, PlanDate(2024, 8, 5));
      expect(r.endDate, PlanDate(2024, 8, 20));
    });

    test('children with no dates ignored for min/max', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('c1', parent: 'parent',
            start: PlanDate(2024, 8, 10), end: PlanDate(2024, 8, 12)),
        _n('c2', parent: 'parent'), // no dates
      ]);
      final r = computeRollup(tree, 'parent');
      expect(r.startDate, PlanDate(2024, 8, 10));
      expect(r.endDate, PlanDate(2024, 8, 12));
    });

    test('no dated children -> null period', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('c1', parent: 'parent'),
      ]);
      final r = computeRollup(tree, 'parent');
      expect(r.startDate, isNull);
      expect(r.endDate, isNull);
    });
  });

  group('progress rollup', () {
    test('simple average when estimates absent', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('a', parent: 'parent', progress: 0.0),
        _n('b', parent: 'parent', progress: 1.0),
        _n('c', parent: 'parent', progress: 0.5),
      ]);
      final r = computeRollup(tree, 'parent');
      // (0 + 1 + 0.5)/3 = 0.5
      expect(r.progress, closeTo(0.5, 1e-9));
    });

    test('weighted average when all children have estimates', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('a', parent: 'parent', progress: 1.0, estimate: 4),
        _n('b', parent: 'parent', progress: 0.0, estimate: 6),
      ]);
      final r = computeRollup(tree, 'parent');
      // (1*4 + 0*6)/(4+6) = 0.4
      expect(r.progress, closeTo(0.4, 1e-9));
    });

    test('falls back to simple average when only some have estimates', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('a', parent: 'parent', progress: 1.0, estimate: 4),
        _n('b', parent: 'parent', progress: 0.0), // no estimate
      ]);
      final r = computeRollup(tree, 'parent');
      // simple avg (1 + 0)/2 = 0.5
      expect(r.progress, closeTo(0.5, 1e-9));
    });

    test('recursive rollup mixes parent and grandparent correctly', () {
      // parent (autoRollup) -> sub(autoRollup) -> [leaf1, leaf2]
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('sub', parent: 'parent', autoRollup: true,
            start: PlanDate(2024, 8, 1), end: PlanDate(2024, 8, 10)),
        _n('leaf1', parent: 'sub',
            progress: 0.5, estimate: 2,
            start: PlanDate(2024, 8, 1), end: PlanDate(2024, 8, 5)),
        _n('leaf2', parent: 'sub',
            progress: 1.0, estimate: 2,
            start: PlanDate(2024, 8, 6), end: PlanDate(2024, 8, 10)),
      ]);
      final subR = computeRollup(tree, 'sub');
      expect(subR.progress, closeTo(0.75, 1e-9)); // (0.5*2 + 1.0*2)/4
      final parentR = computeRollup(tree, 'parent');
      expect(parentR.startDate, PlanDate(2024, 8, 1));
      expect(parentR.endDate, PlanDate(2024, 8, 10));
      expect(parentR.progress, closeTo(0.75, 1e-9));
    });
  });

  group('isDone rollup', () {
    test('all children done -> parent done', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('a', parent: 'parent', isDone: true),
        _n('b', parent: 'parent', isDone: true),
      ]);
      expect(computeRollup(tree, 'parent').isDone, isTrue);
    });

    test('any child not done -> parent not done', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: true),
        _n('a', parent: 'parent', isDone: true),
        _n('b', parent: 'parent', isDone: false),
      ]);
      expect(computeRollup(tree, 'parent').isDone, isFalse);
    });
  });

  group('stored original values not corrupted', () {
    test('parent stored dates/progress remain untouched after rollup', () {
      final parent = _n('parent',
          autoRollup: true,
          start: PlanDate(2020, 1, 1),
          end: PlanDate(2020, 1, 2),
          progress: 0.99);
      final tree = PlanTree.fromNodes([
        parent,
        _n('c1', parent: 'parent',
            start: PlanDate(2024, 8, 10), end: PlanDate(2024, 8, 12),
            progress: 0.0, estimate: 1),
      ]);
      final r = computeRollup(tree, 'parent');
      // effective uses children
      expect(r.startDate, PlanDate(2024, 8, 10));
      expect(r.progress, 0.0);
      // but stored original preserved
      final stored = tree['parent']!;
      expect(stored.startDate, PlanDate(2020, 1, 1));
      expect(stored.endDate, PlanDate(2020, 1, 2));
      expect(stored.progress, 0.99);
    });

    test('non-rollup node uses own stored values', () {
      final tree = PlanTree.fromNodes([
        _n('parent', autoRollup: false,
            start: PlanDate(2024, 1, 1), end: PlanDate(2024, 1, 10),
            progress: 0.3, isDone: false),
        _n('c1', parent: 'parent', progress: 1.0),
      ]);
      final r = computeRollup(tree, 'parent');
      expect(r.startDate, PlanDate(2024, 1, 1));
      expect(r.endDate, PlanDate(2024, 1, 10));
      expect(r.progress, 0.3);
      expect(r.isDone, isFalse);
      expect(r.computedFromChildren, isFalse);
    });
  });
}
