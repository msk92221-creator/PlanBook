import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_filter.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';

final today = PlanDate(2026, 8, 11); // 화요일

PlanNode _n(
  String id, {
  String? parent,
  String? project,
  TaskStatus status = TaskStatus.notStarted,
  List<String> tags = const [],
  Priority priority = Priority.none,
  PlanDate? start,
  PlanDate? end,
  double sortOrder = 0,
  String title = '',
}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: title.isEmpty ? id : title,
      projectId: project,
      status: status,
      tagIds: tags,
      priority: priority,
      startDate: start,
      endDate: end,
      sortOrder: sortOrder,
    );

void main() {
  group('PlanFilterState.isEmpty', () {
    test('기본 상태는 empty', () {
      expect(const PlanFilterState().isEmpty, isTrue);
    });
    test('아무 필드나 하나만 켜져도 empty 가 아니다', () {
      expect(const PlanFilterState(includeUnclassified: true).isEmpty, isFalse);
      expect(const PlanFilterState(searchText: 'x').isEmpty, isFalse);
      expect(const PlanFilterState(datePreset: DatePreset.today).isEmpty, isFalse);
    });
  });

  group('matchesFilter: Project', () {
    test('제한 없음 이면 projectId 무관하게 통과', () {
      final n = _n('a', project: 'p1');
      expect(matchesFilter(n, const PlanFilterState(), today: today), isTrue);
      expect(matchesFilter(_n('b'), const PlanFilterState(), today: today), isTrue);
    });

    test('projectIds 지정 시 그 프로젝트만 통과', () {
      const f = PlanFilterState(projectIds: {'p1'});
      expect(matchesFilter(_n('a', project: 'p1'), f, today: today), isTrue);
      expect(matchesFilter(_n('b', project: 'p2'), f, today: today), isFalse);
      expect(matchesFilter(_n('c'), f, today: today), isFalse,
          reason: '미분류는 includeUnclassified 없이는 통과 못 함');
    });

    test('includeUnclassified 만 켜면 미분류만 통과(복수 선택과 구분)', () {
      const f = PlanFilterState(includeUnclassified: true);
      expect(matchesFilter(_n('a'), f, today: today), isTrue);
      expect(matchesFilter(_n('b', project: 'p1'), f, today: today), isFalse);
    });

    test('projectIds + includeUnclassified 동시 지정 시 둘 다 통과', () {
      const f = PlanFilterState(projectIds: {'p1'}, includeUnclassified: true);
      expect(matchesFilter(_n('a', project: 'p1'), f, today: today), isTrue);
      expect(matchesFilter(_n('b'), f, today: today), isTrue);
      expect(matchesFilter(_n('c', project: 'p2'), f, today: today), isFalse);
    });
  });

  group('matchesFilter: Status (복수 선택)', () {
    test('빈 statuses 는 제한 없음', () {
      expect(matchesFilter(_n('a', status: TaskStatus.onHold),
          const PlanFilterState(), today: today), isTrue);
    });
    test('복수 선택 중 하나라도 맞으면 통과', () {
      const f = PlanFilterState(statuses: {TaskStatus.inProgress, TaskStatus.onHold});
      expect(matchesFilter(_n('a', status: TaskStatus.onHold), f, today: today), isTrue);
      expect(matchesFilter(_n('b', status: TaskStatus.done), f, today: today), isFalse);
    });
  });

  group('matchesFilter: Tag (OR)', () {
    test('빈 tagIds + includeUntagged=false 는 제한 없음', () {
      expect(matchesFilter(_n('a'), const PlanFilterState(), today: today), isTrue);
    });
    test('복수 태그는 OR(하나라도 겹치면 통과)', () {
      const f = PlanFilterState(tagIds: {'t1', 't2'});
      expect(matchesFilter(_n('a', tags: ['t2']), f, today: today), isTrue);
      expect(matchesFilter(_n('b', tags: ['t3']), f, today: today), isFalse);
    });
    test('includeUntagged 만 켜면 태그 없는 Task 만', () {
      const f = PlanFilterState(includeUntagged: true);
      expect(matchesFilter(_n('a'), f, today: today), isTrue);
      expect(matchesFilter(_n('b', tags: ['t1']), f, today: today), isFalse);
    });
    test('tagIds + includeUntagged 동시', () {
      const f = PlanFilterState(tagIds: {'t1'}, includeUntagged: true);
      expect(matchesFilter(_n('a', tags: ['t1']), f, today: today), isTrue);
      expect(matchesFilter(_n('b'), f, today: today), isTrue);
      expect(matchesFilter(_n('c', tags: ['t2']), f, today: today), isFalse);
    });
  });

  group('matchesFilter: Priority', () {
    test('복수 선택', () {
      const f = PlanFilterState(priorities: {Priority.high});
      expect(matchesFilter(_n('a', priority: Priority.high), f, today: today), isTrue);
      expect(matchesFilter(_n('b', priority: Priority.low), f, today: today), isFalse);
    });
  });

  group('matchesFilter: 기간(datePreset)', () {
    test('all 은 날짜 없는 Task 도 통과', () {
      expect(matchesFilter(_n('a'), const PlanFilterState(datePreset: DatePreset.all),
          today: today), isTrue);
    });

    test('today: 오늘을 포함하는 Task 만, 날짜 없는 Task 는 제외', () {
      const f = PlanFilterState(datePreset: DatePreset.today);
      expect(
          matchesFilter(
              _n('a', start: PlanDate(2026, 8, 10), end: PlanDate(2026, 8, 12)),
              f,
              today: today),
          isTrue);
      expect(
          matchesFilter(
              _n('b', start: PlanDate(2026, 8, 12), end: PlanDate(2026, 8, 15)),
              f,
              today: today),
          isFalse);
      expect(matchesFilter(_n('c'), f, today: today), isFalse,
          reason: '날짜 기반 필터는 날짜 없는 Task 를 제외해야 한다');
    });

    test('thisWeek: 주 시작요일(AppSettings.weekStart) 반영', () {
      const f = PlanFilterState(datePreset: DatePreset.thisWeek);
      // today = 2026-08-11(화). 월요일 시작 주 = 8/10~8/16.
      expect(
          matchesFilter(
              _n('a', start: PlanDate(2026, 8, 9), end: PlanDate(2026, 8, 10)),
              f,
              today: today,
              weekStartWeekday: DateTime.monday),
          isTrue,
          reason: '8/10 은 이번 주(월요일 시작) 안에 포함되어 겹친다');
      expect(
          matchesFilter(
              _n('b', start: PlanDate(2026, 8, 17), end: PlanDate(2026, 8, 18)),
              f,
              today: today,
              weekStartWeekday: DateTime.monday),
          isFalse,
          reason: '다음 주는 겹치지 않는다');
    });

    test('thisMonth: 이번 달과 겹치는 Task', () {
      const f = PlanFilterState(datePreset: DatePreset.thisMonth);
      expect(
          matchesFilter(
              _n('a', start: PlanDate(2026, 7, 25), end: PlanDate(2026, 8, 1)),
              f,
              today: today),
          isTrue);
      expect(
          matchesFilter(
              _n('b', start: PlanDate(2026, 9, 1), end: PlanDate(2026, 9, 5)),
              f,
              today: today),
          isFalse);
    });

    test('custom: 사용자 지정 기간과 overlap', () {
      final f = PlanFilterState(
        datePreset: DatePreset.custom,
        customStartDate: PlanDate(2026, 1, 1),
        customEndDate: PlanDate(2026, 1, 31),
      );
      expect(
          matchesFilter(
              _n('a', start: PlanDate(2026, 1, 15), end: PlanDate(2026, 2, 5)),
              f,
              today: today),
          isTrue);
      expect(
          matchesFilter(
              _n('b', start: PlanDate(2026, 2, 1), end: PlanDate(2026, 2, 5)),
              f,
              today: today),
          isFalse);
    });

    test('overdue: endDate < today && !done, 날짜 없으면 제외', () {
      const f = PlanFilterState(datePreset: DatePreset.overdue);
      expect(matchesFilter(_n('a', end: PlanDate(2026, 8, 10)), f, today: today),
          isTrue);
      expect(
          matchesFilter(
              _n('b', end: PlanDate(2026, 8, 10), status: TaskStatus.done),
              f,
              today: today),
          isFalse,
          reason: '완료된 건 지연이 아니다');
      expect(matchesFilter(_n('c', end: PlanDate(2026, 8, 11)), f, today: today),
          isFalse,
          reason: 'endDate==today 는 아직 지연 아님');
      expect(matchesFilter(_n('d'), f, today: today), isFalse,
          reason: '날짜 없는 Task 는 지연 판정 불가');
    });

    test('incomplete: status != done, 날짜 없는 Task 도 포함', () {
      const f = PlanFilterState(datePreset: DatePreset.incomplete);
      expect(matchesFilter(_n('a', status: TaskStatus.onHold), f, today: today),
          isTrue);
      expect(matchesFilter(_n('b'), f, today: today), isTrue,
          reason: 'incomplete 는 날짜 기반이 아니므로 날짜 없어도 포함');
      expect(matchesFilter(_n('c', status: TaskStatus.done), f, today: today),
          isFalse);
    });
  });

  group('matchesFilter: 검색어', () {
    test('제목 대소문자 무시 부분일치', () {
      const f = PlanFilterState(searchText: 'filter');
      expect(matchesFilter(_n('a', title: 'Complex Filter 완성'), f, today: today),
          isTrue);
      expect(matchesFilter(_n('b', title: '무관한 작업'), f, today: today), isFalse);
    });
  });

  group('복합 필터(AND across axes)', () {
    test('여러 축을 동시에 만족해야 한다', () {
      final f = PlanFilterState(
        projectIds: {'p1'},
        statuses: {TaskStatus.inProgress},
        priorities: {Priority.high},
      );
      final ok = _n('a',
          project: 'p1', status: TaskStatus.inProgress, priority: Priority.high);
      final wrongProject = _n('b',
          project: 'p2', status: TaskStatus.inProgress, priority: Priority.high);
      final wrongStatus =
          _n('c', project: 'p1', status: TaskStatus.done, priority: Priority.high);
      expect(matchesFilter(ok, f, today: today), isTrue);
      expect(matchesFilter(wrongProject, f, today: today), isFalse);
      expect(matchesFilter(wrongStatus, f, today: today), isFalse);
    });
  });

  group('computeFilterVisibility: 계층 보존', () {
    test('필터 없음(empty)이면 모든 노드가 matched', () {
      final tree = PlanTree.fromNodes([_n('a'), _n('b', parent: 'a')]);
      final v = computeFilterVisibility(tree, const PlanFilterState(), today: today);
      expect(v.matchedIds, {'a', 'b'});
      expect(v.contextAncestorIds, isEmpty);
    });

    test('매칭된 자손의 조상은 context ancestor 로 포함(매칭은 아님)', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('mid', parent: 'root'),
        _n('leaf', parent: 'mid', project: 'p1'),
      ]);
      const f = PlanFilterState(projectIds: {'p1'});
      final v = computeFilterVisibility(tree, f, today: today);
      expect(v.matchedIds, {'leaf'});
      expect(v.contextAncestorIds, {'root', 'mid'});
      expect(v.visibleIds, {'root', 'mid', 'leaf'});
      expect(v.matches('leaf'), isTrue);
      expect(v.isContextAncestor('root'), isTrue);
      expect(v.matches('root'), isFalse);
    });

    test('매칭도 조상도 아닌 가지는 완전히 제외', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('a', parent: 'root', project: 'p1'),
        _n('b', parent: 'root', project: 'p2'),
      ]);
      const f = PlanFilterState(projectIds: {'p1'});
      final v = computeFilterVisibility(tree, f, today: today);
      expect(v.visibleIds, {'root', 'a'});
      expect(v.visibleIds.contains('b'), isFalse);
    });
  });
}
