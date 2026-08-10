/// 보이는(펼쳐진) 트리 행을 평탄화(flatten) 하는 순수 로직.
///
/// 좌측 트리 패널과 우측 Gantt 패널은 **같은 순서·같은 행 수** 로 렌더되어야
/// 행 높이가 정확히 정렬된다. 두 패널 모두 이 함수의 결과를 그대로 순회한다.
///
/// - [PlanNode.isCollapsed]==true 인 노드의 **자손 전체** 를 숨긴다.
///   (자기 자신은 보이고, 그 아래만 숨김) — 단, **필터가 활성 상태**([visibleIds]
///   가 non-null)일 때는 예외: 접힌 노드 아래에 필터 매칭 자손이 있으면 그
///   자손까지는 강제로 펼쳐서 보여준다. 이때 [PlanNode.isCollapsed] **값 자체는
///   절대 수정하지 않는다** — 화면 표시만 임시로 무시하는 것이고, 필터를
///   해제하면 원래 접힌 상태로 돌아온다.
/// - [depth] 는 들여쓰기 단위. 루트=0.
/// - [hasChildren] 은 자식 존재 여부(접기/펼치기 토글 표시용).
/// - [effectiveStartDate]/[effectiveEndDate]/[isDateDerived] 는
///   [computeEffectiveDateRange] 결과를 그대로 담은 것 — Tree/Gantt 양쪽이
///   같은 값을 쓰도록 flatten 시점에 한 번만 계산한다(날짜 계산 로직 중복 금지).
/// - [matchesFilter]/[isContextAncestor] 는 고급 필터([matchedIds] 인자) 결과를
///   그대로 담는다. 필터가 없으면(matchedIds==null) 모든 행이 matchesFilter=true.
///
/// 위젯에 의존하지 않는 순수 함수이므로 단위 테스트가 가능하다.
library;

import '../../core/date/plan_date.dart';
import '../../domain/effective_dates.dart';
import '../../domain/plan_node.dart';
import '../../domain/plan_tree.dart';

/// 평탄화된 한 행의 부가 정보. (= "VisibleTaskRow")
class FlatRow {
  final PlanNode node;

  /// 들여쓰기 깊이(루트=0).
  final int depth;

  /// 자식이 있는지(토글 버튼 표시용).
  /// [flattenVisibleRows] 에 `visibleIds` 필터가 주어졌으면, 필터를 통과한
  /// 자식이 하나라도 있는지를 뜻한다(필터로 자식이 전부 가려지면 false).
  final bool hasChildren;

  /// 지금 이 행 **바로 아래에 자손 행이 실제로 렌더되고 있는지**.
  /// 보통 `hasChildren && !node.isCollapsed` 와 같지만, 필터가 매칭 자손을
  /// 강제로 펼쳐서 보여주는 경우는 `node.isCollapsed==true` 여도 true 가 된다.
  /// 트리 UI 의 접기/펼치기 화살표 **방향**은 이 값을 따르고, 탭 동작은
  /// 여전히 `node.isCollapsed` 의 실제 값을 토글한다(표시와 조작을 분리).
  final bool isChildrenShown;

  /// 유효 시작일. [computeEffectiveDateRange] 결과.
  final PlanDate? effectiveStartDate;

  /// 유효 종료일. [computeEffectiveDateRange] 결과.
  final PlanDate? effectiveEndDate;

  /// true 면 [effectiveStartDate]/[effectiveEndDate] 가 노드 자신의 값이 아니라
  /// 자손으로부터 추론된 값이다(향후 Drag 단계에서 이 bar 는 드래그 대상에서 제외).
  final bool isDateDerived;

  /// 이 노드 자체가 현재 활성 필터에 매칭되는지. 필터가 없으면 항상 true.
  final bool matchesFilter;

  /// 이 노드는 필터에 직접 매칭되지 않았지만, 매칭된 자손의 조상이라 맥락
  /// 표시용으로 보이는 것인지. 필터가 없으면 항상 false.
  final bool isContextAncestor;

  const FlatRow({
    required this.node,
    required this.depth,
    required this.hasChildren,
    required this.isChildrenShown,
    required this.effectiveStartDate,
    required this.effectiveEndDate,
    required this.isDateDerived,
    this.matchesFilter = true,
    this.isContextAncestor = false,
  });

  String get id => node.id;

  /// 펼쳐진 상태인지(접힘의 반대). `node.isCollapsed` 의 편의 getter.
  /// **주의**: 이것은 저장된 상태일 뿐, 실제로 자손이 보이는지는 [isChildrenShown]
  /// 을 봐야 한다(필터가 강제로 펼쳐 보여줄 수 있음).
  bool get isExpanded => !node.isCollapsed;
}

/// [tree] 의 보이는 행을 깊이 우선, [sortOrder] 순으로 평탄화한다.
///
/// 접힌([PlanNode.isCollapsed]==true) 노드의 자손은 결과에서 제외된다.
///
/// [visibleIds] 를 주면(예: Project/고급 필터 적용 시) 그 집합에 없는 노드는
/// 자기 자신과 자손 모두 결과에서 제외된다. `null`(기본값)이면 필터 없이
/// 전체를 대상으로 한다(기존 호출부와 동일하게 동작 — 하위 호환).
///
/// [visibleIds] 가 주어졌을 때는 접힌 노드라도 그 자손이 [visibleIds] 안에
/// 있으면 강제로 펼쳐서 보여준다(필터 매칭 자손이 숨지 않게). `isCollapsed`
/// 자체는 수정하지 않는다.
///
/// [matchedIds]/[contextAncestorIds] 를 주면([FilterVisibility] 의 필드를 그대로
/// 넘기면 됨) 각 행의 [FlatRow.matchesFilter]/[FlatRow.isContextAncestor] 에 반영된다.
List<FlatRow> flattenVisibleRows(
  PlanTree tree, {
  Set<String>? visibleIds,
  Set<String>? matchedIds,
  Set<String>? contextAncestorIds,
}) {
  final out = <FlatRow>[];
  final filtering = visibleIds != null;
  void visit(String? parentId, int depth) {
    for (final n in tree.childrenOf(parentId)) {
      if (visibleIds != null && !visibleIds.contains(n.id)) continue;
      final children = tree.childrenOf(n.id);
      final hasKids = visibleIds == null
          ? children.isNotEmpty
          : children.any((c) => visibleIds.contains(c.id));
      // 필터 중이면 접힘을 무시하고 강제로 펼친다(visibleIds 자체가 이미
      // "매칭 또는 매칭의 조상"으로 좁혀져 있으므로 안전하다 — 무관한 형제는
      // 어차피 위의 continue 에서 걸린다).
      final showChildren = hasKids && (filtering || !n.isCollapsed);
      final range = computeEffectiveDateRange(tree, n.id);
      out.add(FlatRow(
        node: n,
        depth: depth,
        hasChildren: hasKids,
        isChildrenShown: showChildren,
        effectiveStartDate: range.start,
        effectiveEndDate: range.end,
        isDateDerived: range.isDerived,
        matchesFilter: matchedIds == null || matchedIds.contains(n.id),
        isContextAncestor:
            contextAncestorIds != null && contextAncestorIds.contains(n.id),
      ));
      if (showChildren) {
        visit(n.id, depth + 1);
      }
    }
  }

  visit(null, 0);
  return out;
}
