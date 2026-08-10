/// 검색 — 제목/메모/Project 이름/Tag 이름을 대상으로 한다.
///
/// **필터 시스템의 검색어 판정을 재사용한다.** [plan_filter.matchesFilter] 는
/// 이미 title 검색(대소문자 무시, contains)을 구현하고 있으므로, 여기서는 그
/// 로직을 다시 쓰지 않고 [PlanFilterState] 에 [PlanFilterState.searchText] 를
/// 담아 [matchesFilter] 를 호출한 뒤, title 매칭이 아니었던 항목에 한해서만
/// memo/프로젝트 이름/태그 이름을 추가로 검사한다(Project/Tag 이름 조회는
/// [PlanStore] 접근이 필요해 store-비의존적인 도메인 필터 계층에는 없다).
library;

import '../core/date/plan_date.dart';
import 'plan_filter.dart';
import 'plan_node.dart';
import 'plan_tree.dart';

/// [node] 가 [query] 와 title/memo/projectName/tagNames 중 하나라도 매칭되는지.
///
/// [projectName]: [PlanNode.projectId] → 프로젝트 이름(없으면 null).
/// [tagName]: 태그 id → 태그 이름.
bool matchesSearchExtended(
  PlanNode node,
  String query, {
  required String? Function(String? projectId) projectName,
  required String Function(String tagId) tagName,
  required PlanDate today,
}) {
  final q = query.trim();
  if (q.isEmpty) return true;

  // title 검색은 matchesFilter 의 기존 판정을 재사용(다른 축은 전부 제한 없음
  // 상태로 호출해 순수하게 검색어 매칭 결과만 받는다).
  final titleMatches = matchesFilter(
    node,
    PlanFilterState.empty.copyWith(searchText: q),
    today: today,
  );
  if (titleMatches) return true;

  final lower = q.toLowerCase();
  if ((node.memo ?? '').toLowerCase().contains(lower)) return true;

  final pname = projectName(node.projectId);
  if (pname != null && pname.toLowerCase().contains(lower)) return true;

  for (final tid in node.tagIds) {
    if (tagName(tid).toLowerCase().contains(lower)) return true;
  }
  return false;
}

/// 트리 전체에서 [query] 에 매칭되는 노드 목록(제목 오름차순). 빈 검색어는
/// 빈 결과(전체 덤프를 보여주지 않는다 — 검색 화면은 입력 전엔 비어 있어야 한다).
List<PlanNode> searchNodes(
  PlanTree tree,
  String query, {
  required String? Function(String? projectId) projectName,
  required String Function(String tagId) tagName,
  required PlanDate today,
}) {
  final q = query.trim();
  if (q.isEmpty) return const <PlanNode>[];
  final out = <PlanNode>[
    for (final n in tree.allNodes)
      if (matchesSearchExtended(n, q,
          projectName: projectName, tagName: tagName, today: today))
        n,
  ];
  out.sort((a, b) => a.title.compareTo(b.title));
  return out;
}
