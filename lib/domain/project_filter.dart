/// Gantt 화면 상단의 Project 필터 상태와 적용 로직.
///
/// **필터는 원본 데이터를 바꾸지 않는다.** 화면에 어떤 노드를 보여줄지 결정하는
/// view 단계 값일 뿐이다. 선택 옵션은 하드코딩된 이름이 아니라 항상 실제
/// [PlanStore.projects] 데이터를 기반으로 구성한다.
library;

import 'package:flutter/foundation.dart';

import 'plan_tree.dart';

/// 필터 종류.
enum ProjectFilterKind {
  /// 전체 — 모든 Task 표시.
  all,

  /// 미분류 — projectId == null 인 Task 만.
  unclassified,

  /// 특정 프로젝트 — projectId == 지정된 id 인 Task 만.
  byId,
}

/// 현재 선택된 Project 필터. 불변 값 객체.
@immutable
class ProjectFilter {
  final ProjectFilterKind kind;

  /// [kind]==[ProjectFilterKind.byId] 일 때만 의미 있음.
  final String? projectId;

  const ProjectFilter._(this.kind, this.projectId);

  const ProjectFilter.all() : this._(ProjectFilterKind.all, null);
  const ProjectFilter.unclassified()
      : this._(ProjectFilterKind.unclassified, null);
  const ProjectFilter.byId(String id) : this._(ProjectFilterKind.byId, id);

  /// 이 필터에 따라 [taskProjectId] 를 가진 Task 가 보여야 하는지.
  bool matches(String? taskProjectId) => switch (kind) {
        ProjectFilterKind.all => true,
        ProjectFilterKind.unclassified => taskProjectId == null,
        ProjectFilterKind.byId => taskProjectId == projectId,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectFilter && other.kind == kind && other.projectId == projectId;

  @override
  int get hashCode => Object.hash(kind, projectId);

  @override
  String toString() => 'ProjectFilter($kind${projectId != null ? ":$projectId" : ""})';
}

/// [filter] 를 적용했을 때 보여야 하는 노드 id 집합을 계산한다.
///
/// **계층 관계를 깨지 않기 위해**, 필터에 매칭된 노드뿐 아니라 그 **조상 전체**도
/// 포함한다. 예) 자식이 선택 Project 에 속하는데 부모가 다른(또는 없는) projectId
/// 를 가진 비정상 데이터가 있어도, 자식이 매칭되면 부모는 "맥락 표시용"으로 계속
/// 보인다 — 화면에 부모 없는 자식이 뜨는 깨진 트리가 되지 않는다.
///
/// [ProjectFilterKind.all] 이면 모든 노드 id 를 반환한다(사실상 필터 없음과 동일).
Set<String> visibleIdsForProjectFilter(PlanTree tree, ProjectFilter filter) {
  if (filter.kind == ProjectFilterKind.all) {
    return {for (final n in tree.allNodes) n.id};
  }
  final visible = <String>{};
  for (final n in tree.allNodes) {
    if (!filter.matches(n.projectId)) continue;
    visible.add(n.id);
    for (final ancestor in tree.ancestorsOf(n.id)) {
      visible.add(ancestor.id);
    }
  }
  return visible;
}
