import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/milestone_query.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(
  String id, {
  String? parent,
  String? title,
  bool milestone = false,
  PlanDate? start,
  PlanDate? end,
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: title ?? id,
      isMilestone: milestone,
      startDate: start,
      endDate: end,
    );

void main() {
  test('직계 자식 마일스톤을 모은다', () {
    final tree = PlanTree.fromNodes([
      _n('pa', title: 'PA장비'),
      _n('m1', parent: 'pa', title: '착수', milestone: true, end: PlanDate(2026, 1, 5)),
    ]);
    final r = collectDescendantMilestones(tree, 'pa');
    expect(r.map((m) => m.id), ['m1']);
    expect(r.single.title, '착수');
    expect(r.single.date, PlanDate(2026, 1, 5));
  });

  test('손자 이하 마일스톤도 모은다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('sub', parent: 'pa'),
      _n('m1', parent: 'sub', milestone: true, end: PlanDate(2027, 3, 1)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa').map((m) => m.id), ['m1']);
  });

  test('자기 자신은 포함하지 않는다', () {
    final tree = PlanTree.fromNodes([
      _n('m0', milestone: true, end: PlanDate(2026, 1, 1)),
    ]);
    expect(collectDescendantMilestones(tree, 'm0'), isEmpty);
  });

  test('마일스톤이 아닌 자식은 제외한다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('c1', parent: 'pa', start: PlanDate(2026, 1, 1), end: PlanDate(2026, 2, 1)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa'), isEmpty);
  });

  test('날짜가 전혀 없는 마일스톤은 찍을 위치가 없으므로 제외한다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('m1', parent: 'pa', milestone: true),
    ]);
    expect(collectDescendantMilestones(tree, 'pa'), isEmpty);
  });

  test('endDate 가 없으면 startDate 를 기준일로 쓴다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('m1', parent: 'pa', milestone: true, start: PlanDate(2026, 6, 9)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa').single.date,
        PlanDate(2026, 6, 9));
  });

  test('endDate 가 startDate 보다 우선한다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('m1',
          parent: 'pa',
          milestone: true,
          start: PlanDate(2026, 1, 1),
          end: PlanDate(2026, 2, 2)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa').single.date,
        PlanDate(2026, 2, 2));
  });

  test('날짜 오름차순으로 정렬된다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('late', parent: 'pa', milestone: true, end: PlanDate(2028, 1, 1)),
      _n('early', parent: 'pa', milestone: true, end: PlanDate(2026, 1, 1)),
      _n('mid', parent: 'pa', milestone: true, end: PlanDate(2027, 1, 1)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa').map((m) => m.id),
        ['early', 'mid', 'late']);
  });

  test('같은 날짜면 id 순으로 안정 정렬된다', () {
    final tree = PlanTree.fromNodes([
      _n('pa'),
      _n('b', parent: 'pa', milestone: true, end: PlanDate(2026, 1, 1)),
      _n('a', parent: 'pa', milestone: true, end: PlanDate(2026, 1, 1)),
    ]);
    expect(collectDescendantMilestones(tree, 'pa').map((m) => m.id), ['a', 'b']);
  });
}
