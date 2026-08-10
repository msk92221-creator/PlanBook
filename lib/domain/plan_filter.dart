/// 고급 필터: 하나의 불변 상태([PlanFilterState])와 그 판정 로직.
///
/// **설계 원칙**: 판정 로직은 여기 순수 함수로만 존재한다. UI(Gantt 상단
/// 필터바, 향후 Calendar/검색)는 이 파일의 함수를 호출만 하고, 조건식을
/// 스스로 다시 작성하지 않는다.
///
/// 필터는 원본 데이터를 바꾸지 않는다 — 화면에 무엇을 보여줄지 결정하는
/// view 단계 값이다.
library;

import 'package:flutter/foundation.dart';

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_node.dart';
import 'plan_tree.dart';

/// 기간(빠른 필터) 종류.
enum DatePreset {
  /// 기간 제한 없음(날짜 없는 Task 포함).
  all,
  today,
  thisWeek,
  thisMonth,

  /// [PlanFilterState.customStartDate]/[customEndDate] 사용.
  custom,

  /// endDate < today && status != done. 날짜 없는 Task 는 제외.
  overdue,

  /// status != done (날짜 무관 — 날짜 없는 Task 도 포함).
  incomplete,
}

/// 하나의 불변 필터 상태. 모든 필드가 "비어 있으면 그 축은 제한 없음" 규칙을 따른다.
///
/// **Project 필터의 특수 규칙**: [projectIds] 와 [includeUnclassified] 가 **둘 다**
/// 비어있음/false 면 "제한 없음"(전체 프로젝트 통과)이다. 둘 중 하나라도 켜지면
/// 그 순간부터는 명시적 화이트리스트가 된다 — 예를 들어 [includeUnclassified]
/// 만 true 이고 [projectIds] 가 비어있으면 **미분류만** 통과한다(이게 "미분류만
/// 보기"를 표현하는 방법이다. "제한 없음"과 구분하기 위해 반드시 이 두 필드를
/// 함께 봐야 한다 — 하나만 봐서는 판단할 수 없다).
///
/// [tagIds]/[includeUntagged] 도 동일한 규칙.
@immutable
class PlanFilterState {
  final Set<String> projectIds;
  final bool includeUnclassified;

  final Set<TaskStatus> statuses;

  final Set<String> tagIds;
  final bool includeUntagged;

  final Set<Priority> priorities;

  final DatePreset datePreset;
  final PlanDate? customStartDate;
  final PlanDate? customEndDate;

  final String searchText;

  const PlanFilterState({
    this.projectIds = const {},
    this.includeUnclassified = false,
    this.statuses = const {},
    this.tagIds = const {},
    this.includeUntagged = false,
    this.priorities = const {},
    this.datePreset = DatePreset.all,
    this.customStartDate,
    this.customEndDate,
    this.searchText = '',
  });

  /// 아무 조건도 없는 기본 상태("전체 보기").
  static const PlanFilterState empty = PlanFilterState();

  /// 필터가 하나도 적용되지 않은 상태인지("초기화" 버튼 활성/빠른 필터 강조에 사용).
  bool get isEmpty =>
      projectIds.isEmpty &&
      !includeUnclassified &&
      statuses.isEmpty &&
      tagIds.isEmpty &&
      !includeUntagged &&
      priorities.isEmpty &&
      datePreset == DatePreset.all &&
      searchText.trim().isEmpty;

  bool get hasProjectRestriction => projectIds.isNotEmpty || includeUnclassified;
  bool get hasTagRestriction => tagIds.isNotEmpty || includeUntagged;

  PlanFilterState copyWith({
    Set<String>? projectIds,
    bool? includeUnclassified,
    Set<TaskStatus>? statuses,
    Set<String>? tagIds,
    bool? includeUntagged,
    Set<Priority>? priorities,
    DatePreset? datePreset,
    Object? customStartDate = _sentinel,
    Object? customEndDate = _sentinel,
    String? searchText,
  }) {
    return PlanFilterState(
      projectIds: projectIds ?? this.projectIds,
      includeUnclassified: includeUnclassified ?? this.includeUnclassified,
      statuses: statuses ?? this.statuses,
      tagIds: tagIds ?? this.tagIds,
      includeUntagged: includeUntagged ?? this.includeUntagged,
      priorities: priorities ?? this.priorities,
      datePreset: datePreset ?? this.datePreset,
      customStartDate: identical(customStartDate, _sentinel)
          ? this.customStartDate
          : customStartDate as PlanDate?,
      customEndDate: identical(customEndDate, _sentinel)
          ? this.customEndDate
          : customEndDate as PlanDate?,
      searchText: searchText ?? this.searchText,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlanFilterState &&
      _setEq(other.projectIds, projectIds) &&
      other.includeUnclassified == includeUnclassified &&
      _setEq(other.statuses, statuses) &&
      _setEq(other.tagIds, tagIds) &&
      other.includeUntagged == includeUntagged &&
      _setEq(other.priorities, priorities) &&
      other.datePreset == datePreset &&
      other.customStartDate == customStartDate &&
      other.customEndDate == customEndDate &&
      other.searchText == searchText;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(projectIds),
        includeUnclassified,
        Object.hashAllUnordered(statuses),
        Object.hashAllUnordered(tagIds),
        includeUntagged,
        Object.hashAllUnordered(priorities),
        datePreset,
        customStartDate,
        customEndDate,
        searchText,
      );
}

const Object _sentinel = Object();

bool _setEq<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.every(b.contains);

/// [preset] 이 날짜 기반 조건일 때의 `[from, to]` 구간(inclusive). 날짜 기반이
/// 아니면(all/overdue/incomplete) null.
({PlanDate from, PlanDate to})? _dateRangeFor(
  DatePreset preset,
  PlanDate today,
  int weekStartWeekday,
  PlanDate? customStart,
  PlanDate? customEnd,
) {
  switch (preset) {
    case DatePreset.today:
      return (from: today, to: today);
    case DatePreset.thisWeek:
      return (
        from: startOfWeekWith(today, weekStartWeekday),
        to: endOfWeekWith(today, weekStartWeekday),
      );
    case DatePreset.thisMonth:
      return (from: startOfMonth(today), to: endOfMonth(today));
    case DatePreset.custom:
      if (customStart == null && customEnd == null) return null;
      return (
        from: customStart ?? customEnd!,
        to: customEnd ?? customStart!,
      );
    case DatePreset.all:
    case DatePreset.overdue:
    case DatePreset.incomplete:
      return null;
  }
}

/// [node] 가 [filter] 를 만족하는지(자기 자신의 속성만 본다 — 조상 포함 여부는
/// [computeFilterVisibility] 가 별도로 처리한다).
bool matchesFilter(
  PlanNode node,
  PlanFilterState filter, {
  required PlanDate today,
  int weekStartWeekday = kWeekStartWeekday,
}) {
  // Project.
  if (filter.hasProjectRestriction) {
    final pid = node.projectId;
    final byId = pid != null && filter.projectIds.contains(pid);
    final byUnclassified = pid == null && filter.includeUnclassified;
    if (!byId && !byUnclassified) return false;
  }

  // Status.
  if (filter.statuses.isNotEmpty && !filter.statuses.contains(node.status)) {
    return false;
  }

  // Tag (OR).
  if (filter.hasTagRestriction) {
    final byTag = node.tagIds.any(filter.tagIds.contains);
    final byUntagged = node.tagIds.isEmpty && filter.includeUntagged;
    if (!byTag && !byUntagged) return false;
  }

  // Priority.
  if (filter.priorities.isNotEmpty && !filter.priorities.contains(node.priority)) {
    return false;
  }

  // 기간(날짜 기반이 아닌 것부터).
  switch (filter.datePreset) {
    case DatePreset.incomplete:
      if (node.isDone) return false;
      break;
    case DatePreset.overdue:
      if (node.endDate == null) return false; // 날짜 없는 Task 는 지연 판정 불가 → 제외.
      if (node.isDone) return false;
      if (daysBetween(node.endDate!, today) <= 0) return false; // endDate < today 만.
      break;
    case DatePreset.all:
      break;
    case DatePreset.today:
    case DatePreset.thisWeek:
    case DatePreset.thisMonth:
    case DatePreset.custom:
      // 날짜 기반 필터는 날짜가 전혀 없는 Task 를 제외한다.
      if (node.startDate == null && node.endDate == null) return false;
      final range = _dateRangeFor(
        filter.datePreset,
        today,
        weekStartWeekday,
        filter.customStartDate,
        filter.customEndDate,
      );
      if (range == null) break; // custom 인데 양쪽 다 비어있으면 제한 없음.
      // overlap: taskStart <= filterEnd AND taskEnd >= filterStart (한쪽 없으면 무한대로).
      final taskStart = node.startDate;
      final taskEnd = node.endDate;
      if (taskStart != null && daysBetween(taskStart, range.to) < 0) return false;
      if (taskEnd != null && daysBetween(range.from, taskEnd) < 0) return false;
      break;
  }

  // 검색어(제목만 — 프로젝트/태그명 검색은 PlanStore 접근이 필요해 상위(Phase 9)에서
  // matchesSearchExtended 로 확장한다. 여기서는 title 만 봐서 store 의존을 피한다).
  final q = filter.searchText.trim();
  if (q.isNotEmpty && !node.title.toLowerCase().contains(q.toLowerCase())) {
    return false;
  }

  return true;
}

/// [computeFilterVisibility] 의 결과.
class FilterVisibility {
  /// Task 자신이 필터에 매칭됨.
  final Set<String> matchedIds;

  /// 매칭되지 않았지만 매칭된 자손의 조상이라 "맥락(context)" 으로 표시되는 노드.
  final Set<String> contextAncestorIds;

  const FilterVisibility({
    required this.matchedIds,
    required this.contextAncestorIds,
  });

  /// 화면에 보여야 하는 전체 id(매칭 + 맥락 조상).
  Set<String> get visibleIds => matchedIds.union(contextAncestorIds);

  bool matches(String id) => matchedIds.contains(id);
  bool isContextAncestor(String id) => contextAncestorIds.contains(id);
}

/// [filter] 를 트리 전체에 적용해 보여야 할 노드 id 집합을 계산한다.
///
/// **계층 관계를 깨지 않기 위해**, 매칭된 노드의 조상 전체를 항상 포함한다
/// (프로젝트 필터와 동일한 원칙 — [visibleIdsForProjectFilter] 참고).
///
/// [filter.isEmpty] 면 모든 노드가 matched 로 취급된다(필터 없음과 동일한 결과).
FilterVisibility computeFilterVisibility(
  PlanTree tree,
  PlanFilterState filter, {
  required PlanDate today,
  int weekStartWeekday = kWeekStartWeekday,
}) {
  if (filter.isEmpty) {
    final all = {for (final n in tree.allNodes) n.id};
    return FilterVisibility(matchedIds: all, contextAncestorIds: const {});
  }
  final matched = <String>{};
  final ancestors = <String>{};
  for (final n in tree.allNodes) {
    if (matchesFilter(n, filter, today: today, weekStartWeekday: weekStartWeekday)) {
      matched.add(n.id);
    }
  }
  for (final id in matched) {
    for (final a in tree.ancestorsOf(id)) {
      if (!matched.contains(a.id)) {
        ancestors.add(a.id);
      }
    }
  }
  return FilterVisibility(matchedIds: matched, contextAncestorIds: ancestors);
}
