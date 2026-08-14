/// 좌측 트리 패널 (3단계: CRUD + DnD + 컨텍스트 메뉴 포함).
///
/// [GanttTimeline] 과 **같은 행 순서/높이** 로 렌더된다([flattenVisibleRows] 결과 공유).
///
/// 기능:
/// - 들여쓰기로 depth 표현, 부모 접기/펼치기 → [onToggleCollapse]
/// - 행 우클릭/길게 누름 → 컨텍스트 메뉴(하위 추가/형제 추가/편집/완료 토글/삭제)
/// - 행 더블클릭 → 편집 다이얼로그
/// - 완료 체크박스 → 즉시 토글(store 경유)
/// - LongPressDraggable + DragTarget 으로 **ID 기반** 순서 변경/계층 이동
///   (insertAt/move 사용, 화면 index 사용 금지)
///
/// 모든 변경은 [PlanStore] 단일 mutation 경로를 지난다.
library;

import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/app_settings.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_node.dart';
import '../../domain/plan_rollup.dart';
import '../../domain/plan_tree.dart';
import 'gantt_theme.dart';
import 'node_delete_dialog.dart';
import 'node_edit_dialog.dart';
import 'tree_flatten.dart';

/// 드롭 영역(히트 테스트 결과). null = 드롭 불가.
enum DropZone { before, after, child }

/// [node] 가 자기 부모의 형제들 중 마지막인지("└" vs "├" 판정에 쓴다).
/// 부모가 없으면(루트) 항상 true 로 본다.
bool _isLastChild(PlanTree tree, PlanNode node) {
  final siblings = tree.childrenOf(node.parentId);
  if (siblings.isEmpty) return true;
  return siblings.last.id == node.id;
}

/// [node] 의 조상들(직속 부모 제외, 루트→직속부모 앞 순서) 각각이 "형제가 더
/// 남아 있는지"(= 마지막 자식이 아닌지) 를 담은 리스트. 트리 안내선을 그릴 때
/// 각 들여쓰기 칸이 세로선으로 이어져야 하는지 판단하는 데 쓴다 — 조상이
/// 마지막 자식이면 그 조상 아래로는 더 그릴 형제가 없으니 안내선을 끊는다.
List<bool> _ancestorContinuations(PlanTree tree, PlanNode node) {
  final ancestors = tree.ancestorsOf(node.id).reversed.toList(); // 루트→직속부모.
  if (ancestors.isEmpty) return const [];
  final withoutImmediateParent = ancestors.sublist(0, ancestors.length - 1);
  return [for (final a in withoutImmediateParent) !_isLastChild(tree, a)];
}

enum _GuideKind { straight, corner, tee }

/// 트리 계층 안내선("이 항목은 위 항목에 속해 있다"는 걸 시각적으로 보여줌).
/// [_GuideKind.corner]("└") 는 이 행이 부모의 마지막 자식일 때,
/// [_GuideKind.tee]("├") 는 더 뒤에 형제가 남아 있을 때 쓴다.
class _TreeGuidePainter extends CustomPainter {
  final _GuideKind kind;
  final Color color;
  const _TreeGuidePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final midX = size.width / 2;
    final midY = size.height / 2;
    switch (kind) {
      case _GuideKind.straight:
        canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
      case _GuideKind.corner:
        canvas.drawLine(Offset(midX, 0), Offset(midX, midY), paint);
        canvas.drawLine(Offset(midX, midY), Offset(size.width, midY), paint);
      case _GuideKind.tee:
        canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), paint);
        canvas.drawLine(Offset(midX, midY), Offset(size.width, midY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGuidePainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

/// [row] 의 들여쓰기 칸들을 안내선으로 채운 위젯. depth==0 이면 빈 위젯.
class _TreeGuides extends StatelessWidget {
  final PlanTree tree;
  final PlanNode node;
  final int depth;

  const _TreeGuides({required this.tree, required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.outline.withValues(alpha: 0.35);
    final continuations = _ancestorContinuations(tree, node);
    final isLast = _isLastChild(tree, node);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < depth; i++)
          SizedBox(
            width: 16,
            height: kRowHeight,
            child: i < depth - 1
                ? (continuations[i]
                    ? CustomPaint(painter: _TreeGuidePainter(kind: _GuideKind.straight, color: color))
                    : const SizedBox.shrink())
                : CustomPaint(
                    painter: _TreeGuidePainter(
                      kind: isLast ? _GuideKind.corner : _GuideKind.tee,
                      color: color,
                    ),
                  ),
          ),
      ],
    );
  }
}

class TreePanel extends StatefulWidget {
  final PlanTree tree;
  final List<FlatRow> rows;

  /// 좌측/우측 세로 스크롤 동기화용 컨트롤러(외부 주입).
  final ScrollController? verticalController;

  /// 접기/펼치기 토글 콜백. store 를 통해 영속화한다.
  final void Function(PlanNode node) onToggleCollapse;

  /// 변경용 store. null 이면 CRUD/DnD 비활성(읽기 전용 표시).
  final PlanStore? store;

  /// 현재 강조(선택) 표시할 노드 id(Today/Calendar/검색에서 넘어올 때 등).
  final String? selectedNodeId;

  /// 행 탭 시 선택 상태를 갱신하는 콜백(선택 강조는 순수 UI 상태 — store 에는 안 남음).
  final ValueChanged<String>? onSelect;

  const TreePanel({
    super.key,
    required this.tree,
    required this.rows,
    this.verticalController,
    required this.onToggleCollapse,
    this.store,
    this.selectedNodeId,
    this.onSelect,
  });

  @override
  State<TreePanel> createState() => _TreePanelState();
}

class _TreePanelState extends State<TreePanel> {
  // DnD 표시용: 현재 드롭 대상 행 id 와 zone.
  String? _hoverId;
  DropZone? _hoverZone;
  // 드롭이 거부되는(순환) 대상이면 이 id 에 대해 거부 표시.
  String? _rejectId;

  PlanStore? get _store => widget.store;
  bool get _interactive => _store != null;

  /// 열 설정. store 가 없으면(읽기 전용 미리보기) 기본값을 쓴다.
  double get _periodWidth =>
      clampPeriodColumnWidth(_store?.settings.periodColumnWidth ??
          kDefaultPeriodColumnWidth);
  bool get _showPeriod => _store?.settings.showPeriodColumn ?? true;

  void _setHover(String? id, DropZone? zone, {bool rejected = false}) {
    if (_hoverId == id && _hoverZone == zone && _rejectId == (rejected ? id : null)) {
      return;
    }
    setState(() {
      _hoverId = id;
      _hoverZone = zone;
      _rejectId = rejected ? id : null;
    });
  }

  // ---------------- 액션 핸들러 (모두 store 경유) ----------------

  void _addChild(PlanNode parent) {
    final store = _store;
    if (store == null) return;
    final node = store.addNode(parentId: parent.id, title: '');
    // 자동 펼치기(자식이 보이도록).
    if (parent.isCollapsed) {
      store.updateNode(parent.id, (n) => n.copyWith(isCollapsed: false));
    }
    _editAndDeleteIfEmpty(node);
  }

  void _addSibling(PlanNode sibling) {
    final store = _store;
    if (store == null) return;
    final node =
        store.addNode(parentId: sibling.parentId, title: '');
    _editAndDeleteIfEmpty(node);
  }

  void _addRoot() {
    final store = _store;
    if (store == null) return;
    final node = store.addNode(parentId: null, title: '');
    _editAndDeleteIfEmpty(node);
  }

  /// 새 노드를 편집 다이얼로그로 띄운다. 취소하면 빈 노드를 제거(autosave 정리).
  Future<void> _editAndDeleteIfEmpty(PlanNode node) async {
    final store = _store;
    if (store == null || !mounted) return;
    final result = await showNodeEditDialog(
      context,
      tree: store.tree,
      node: node,
      store: store,
    );
    if (result == null) {
      // 취소: 빈 노드 제거.
      if (store.tree.contains(node.id)) {
        store.deleteCascade(node.id);
      }
      return;
    }
    commitNodeEdit(store, node, result);
  }

  Future<void> _editNode(PlanNode node) async {
    final store = _store;
    if (store == null) return;
    final result = await showNodeEditDialog(
      context,
      tree: store.tree,
      node: node,
      store: store,
    );
    if (result == null) return;
    commitNodeEdit(store, node, result);
  }

  void _toggleDone(PlanNode node) {
    final store = _store;
    if (store == null) return;
    final rollup = computeRollup(store.tree, node.id);
    if (rollup.computedFromChildren) return; // 요약 노드는 직접 토글 불가
    // 체크/해제 공통 정책은 PlanStore.setNodeDone 에 모여있다(Today 화면과 공유).
    store.setNodeDone(node.id, !node.isDone);
  }

  Future<void> _deleteNode(PlanNode node) async {
    final store = _store;
    if (store == null) return;
    final choice = await showDeleteConfirmDialog(
      context,
      tree: store.tree,
      id: node.id,
    );
    if (choice == DeleteChoice.cancel) return;
    if (choice == DeleteChoice.cascade) {
      store.deleteCascade(node.id);
    } else if (choice == DeleteChoice.promote) {
      store.deletePromote(node.id);
    }
  }

  // ---------------- 컨텍스트 메뉴 ----------------

  void _showContextMenu(PlanNode node, Offset globalPos) {
    if (!_interactive) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPos);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        box.size.width - local.dx,
        box.size.height - local.dy,
      ),
      items: [
        const PopupMenuItem(value: 'addChild', child: Text('하위 항목 추가')),
        const PopupMenuItem(value: 'addSibling', child: Text('형제 항목 추가')),
        const PopupMenuItem(value: 'edit', child: Text('편집...')),
        const PopupMenuItem(value: 'toggleDone', child: Text('완료 토글')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('삭제...')),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      switch (value) {
        case 'addChild':
          _addChild(node);
          break;
        case 'addSibling':
          _addSibling(node);
          break;
        case 'edit':
          _editNode(node);
          break;
        case 'toggleDone':
          _toggleDone(node);
          break;
        case 'delete':
          _deleteNode(node);
          break;
      }
    });
  }

  // ---------------- DnD ----------------

  /// 드롭 가능 여부(순환/자기자신 판정). 불가면 null.
  DropZone? _resolveDropZone(FlatRow dragged, FlatRow target, double localY) {
    if (dragged.id == target.id) return null;
    // 순환: target 이 dragged 의 자기 자신/자손이면 어떤 zone 이든 불가.
    if (widget.tree.isDescendant(
      ancestorId: dragged.id,
      candidateDescendantId: target.id,
    )) {
      return null;
    }
    // 세 영역 판정: 행 위쪽 20% → before, 아래쪽 20% → after, 가운데 → child.
    const edge = 0.20;
    final frac = (localY / kRowHeight).clamp(0.0, 1.0);
    if (frac < edge) return DropZone.before;
    if (frac > (1 - edge)) return DropZone.after;
    return DropZone.child;
  }

  void _performDrop(FlatRow dragged, FlatRow target, DropZone zone) {
    final store = _store;
    if (store == null) return;
    try {
      if (zone == DropZone.child) {
        // 자식으로 이동(append). 접혀 있으면 자동 펼치기(정책).
        store.moveNode(dragged.id, target.id);
        final target2 = store.tree[target.id];
        if (target2 != null && target2.isCollapsed) {
          store.updateNode(target.id, (n) => n.copyWith(isCollapsed: false));
        }
      } else {
        // before/after: 같은 부모(= target 의 부모) 내에서 reorderSibling.
        final targetNode = store.tree[target.id];
        if (targetNode == null) return;
        store.reorderSibling(
          dragged.id,
          referenceSiblingId: target.id,
          position: zone == DropZone.before
              ? InsertPosition.before
              : InsertPosition.after,
          newParentId: targetNode.parentId,
        );
      }
    } on PlanTreeException {
      // 안전망: 이미 _resolveDropZone 에서 걸렀어야 함. 조용히 무시.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: kHeaderHeight,
          child: _TreeHeader(
            periodWidth: _periodWidth,
            showPeriod: _showPeriod,
            onPeriodWidthDelta: _interactive
                ? (dx) => _store!.updateSettings(
                      // 경계선을 왼쪽으로 끌면 기간 열이 넓어진다(오른쪽 열이므로).
                      (st) => st.copyWith(
                          periodColumnWidth: st.periodColumnWidth - dx),
                    )
                : null,
            onTogglePeriod: _interactive
                ? () => _store!.updateSettings(
                      (st) => st.copyWith(showPeriodColumn: !st.showPeriodColumn),
                    )
                : null,
            onAddRoot: _interactive ? _addRoot : null,
            onExpandAll: _interactive
                ? () => _store!.setAllCollapsed(false)
                : null,
            onCollapseAll: _interactive
                ? () => _store!.setAllCollapsed(true)
                : null,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.verticalController,
            itemExtent: kRowHeight,
            itemCount: widget.rows.length,
            padding: EdgeInsets.zero,
            itemBuilder: (context, i) {
              final row = widget.rows[i];
              final isHover = _hoverId == row.id;
              final isReject = _rejectId == row.id;
              return _TreeRow(
                row: row,
                tree: widget.tree,
                periodWidth: _periodWidth,
                showPeriod: _showPeriod,
                onToggleCollapse: widget.onToggleCollapse,
                interactive: _interactive,
                selected: widget.selectedNodeId == row.id,
                onTap: widget.onSelect == null
                    ? null
                    : () => widget.onSelect!(row.id),
                onContextMenu: (pos) => _showContextMenu(row.node, pos),
                onDoubleTap: () => _editNode(row.node),
                onToggleDone: () => _toggleDone(row.node),
                // DnD 표시
                hoverZone: isHover ? _hoverZone : null,
                rejected: isReject,
                // DnD 입력
                onWillAccept: (dragged) {
                  // zone 은 위치 기반이라 여기서 확정 불가. 일단 수락 후보인지만.
                  if (dragged.id == row.id) return false;
                  if (widget.tree.isDescendant(
                    ancestorId: dragged.id,
                    candidateDescendantId: row.id,
                  )) {
                    setState(() => _rejectId = row.id);
                    return false;
                  }
                  return true;
                },
                onHoverZone: (dragged, localY) {
                  final zone = _resolveDropZone(dragged, row, localY);
                  if (zone == null) {
                    _setHover(row.id, null, rejected: true);
                  } else {
                    _setHover(row.id, zone, rejected: false);
                  }
                },
                onAccept: (dragged) {
                  final zone = _resolveDropZoneFromHover(row);
                  if (zone != null) {
                    _performDrop(dragged, row, zone);
                  }
                  _setHover(null, null);
                },
                onLeave: () {
                  if (_hoverId == row.id || _rejectId == row.id) {
                    _setHover(null, null);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  DropZone? _resolveDropZoneFromHover(FlatRow row) {
    if (_hoverId == row.id) return _hoverZone;
    return null;
  }
}

// ---------------------------------------------------------------------------
// 헤더
// ---------------------------------------------------------------------------

class _TreeHeader extends StatelessWidget {
  final VoidCallback? onAddRoot;
  final VoidCallback? onExpandAll;
  final VoidCallback? onCollapseAll;

  /// "기간" 열 폭과 표시 여부. 행들과 같은 값을 써야 열이 어긋나지 않는다.
  final double periodWidth;
  final bool showPeriod;

  /// 열 경계선을 끈 가로 이동량(px).
  final ValueChanged<double>? onPeriodWidthDelta;

  /// 헤더 우클릭 메뉴에서 "기간" 열 표시를 토글한다.
  final VoidCallback? onTogglePeriod;

  const _TreeHeader({
    this.onAddRoot,
    this.onExpandAll,
    this.onCollapseAll,
    required this.periodWidth,
    required this.showPeriod,
    this.onPeriodWidthDelta,
    this.onTogglePeriod,
  });

  /// 헤더 어디서든 우클릭하면 열 표시 여부를 고를 수 있게 한다
  /// (엑셀에서 열 머리글을 우클릭하는 것과 같은 감각).
  void _showColumnMenu(BuildContext context, Offset globalPos) {
    if (onTogglePeriod == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(globalPos);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        box.size.width - local.dx,
        box.size.height - local.dy,
      ),
      items: [
        CheckedPopupMenuItem(
          value: 'period',
          checked: showPeriod,
          child: const Text('기간 열 표시'),
        ),
      ],
    ).then((v) {
      if (v == 'period') onTogglePeriod!.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (d) => _showColumnMenu(context, d.globalPosition),
      onLongPressStart: (d) => _showColumnMenu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: LayoutBuilder(builder: (context, cons) {
        // 아이콘 버튼들이 고정폭이라, 칸이 좁아지면 기간 열을 잘라야 넘치지 않는다.
        // (행 쪽과 같은 규칙 — 헤더와 행의 기간 열이 어긋나지 않게 한다)
        final effPeriod =
            periodWidth.clamp(0.0, (cons.maxWidth - 140).clamp(0.0, double.infinity));
        return Row(
          children: [
            const Expanded(
              child: Text('작업', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (showPeriod) ...[
              _ColumnDivider(onDelta: onPeriodWidthDelta),
              SizedBox(
                width: effPeriod,
                child: Text(
                  '기간',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
            if (onExpandAll != null)
              IconButton(
                tooltip: '전체 펼치기',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: onExpandAll,
                icon: const Icon(Icons.unfold_more),
              ),
            if (onCollapseAll != null)
              IconButton(
                tooltip: '전체 접기',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: onCollapseAll,
                icon: const Icon(Icons.unfold_less),
              ),
            if (onAddRoot != null)
              IconButton(
                tooltip: '최상위 목표 추가',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: onAddRoot,
                icon: const Icon(Icons.add_circle_outline),
              ),
          ],
        );
        }),
      ),
    );
  }
}

/// 열 사이의 드래그 가능한 경계선.
///
/// 보이는 선은 가늘게 두고 잡히는 영역만 넓혀서, 마우스로도 손가락으로도
/// 집을 수 있게 한다(작업 칸 경계선과 같은 방식).
class _ColumnDivider extends StatefulWidget {
  final ValueChanged<double>? onDelta;
  const _ColumnDivider({required this.onDelta});

  @override
  State<_ColumnDivider> createState() => _ColumnDividerState();
}

class _ColumnDividerState extends State<_ColumnDivider> {
  static const double _hitWidth = 10;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.onDelta == null) {
      return const SizedBox(width: _hitWidth);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDelta!(d.delta.dx),
        child: SizedBox(
          width: _hitWidth,
          child: Center(
            child: Container(
              width: _active ? 2 : 1,
              height: 18,
              color: _active ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 행
// ---------------------------------------------------------------------------

class _TreeRow extends StatelessWidget {
  final FlatRow row;
  final PlanTree tree;

  /// 헤더와 같은 값을 받아야 열이 어긋나지 않는다.
  final double periodWidth;
  final bool showPeriod;
  final void Function(PlanNode node) onToggleCollapse;
  final bool interactive;

  // 3단계 인터랙션 콜백
  final void Function(Offset globalPos) onContextMenu;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleDone;

  /// 선택(강조) 상태 및 탭 콜백(Today/Calendar/검색 연동용). onTap==null 이면
  /// 선택 기능 비활성.
  final bool selected;
  final VoidCallback? onTap;

  // DnD 표시
  final DropZone? hoverZone;
  final bool rejected;

  // DnD 입력 콜백
  final bool Function(FlatRow dragged) onWillAccept;
  final void Function(FlatRow dragged, double localY) onHoverZone;
  final void Function(FlatRow dragged) onAccept;
  final VoidCallback onLeave;

  const _TreeRow({
    required this.periodWidth,
    required this.showPeriod,
    required this.row,
    required this.tree,
    required this.onToggleCollapse,
    required this.interactive,
    required this.onContextMenu,
    required this.onDoubleTap,
    required this.onToggleDone,
    this.selected = false,
    this.onTap,
    required this.hoverZone,
    required this.rejected,
    required this.onWillAccept,
    required this.onHoverZone,
    required this.onAccept,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    final rollup = computeRollup(tree, node.id);
    final done = rollup.isDone;
    final effStart = rollup.startDate;
    final effEnd = rollup.endDate;
    // 요약(rollup) 행은 기존 2상태(완료/미완료) 유지, leaf(또는 autoRollup=false)
    // 행만 4상태(status) 로 표시한다(Gantt bar 와 동일한 정책).
    final status = rollup.computedFromChildren ? null : node.status;
    final scheme = Theme.of(context).colorScheme;

    // DnD 표시 색/선.
    final Color? borderColor;
    final Color? lineColor;
    if (rejected) {
      borderColor = scheme.error.withValues(alpha: 0.4);
      lineColor = scheme.error;
    } else if (hoverZone == DropZone.child) {
      borderColor = scheme.primary.withValues(alpha: 0.7);
      lineColor = null;
    } else {
      borderColor = null;
      lineColor = (hoverZone == DropZone.before || hoverZone == DropZone.after)
          ? scheme.primary
          : null;
    }

    // 선택(강조) 배경이 DnD 강조보다는 우선순위가 낮다(borderColor 가 있으면 그게 우선).
    final rowBg = borderColor?.withValues(alpha: 0.15) ??
        (selected ? scheme.primary.withValues(alpha: 0.12) : null);

    Widget content = Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          // 선택된 행은 왼쪽에 강조선을 추가로 준다(스캔하기 쉽게).
          left: selected
              ? BorderSide(color: scheme.primary, width: 3)
              : BorderSide.none,
          // child 강조 박스
          top: hoverZone == DropZone.before
              ? BorderSide(color: lineColor!, width: 2)
              : BorderSide.none,
        ),
        color: rowBg,
      ),
      // 필터 중 매칭되지 않고 조상(맥락)으로만 보이는 행은 은은하게 dim 처리한다
      // (계층 위치는 알아볼 수 있게 하되 실제 매칭과는 시각적으로 구분).
      child: Opacity(
        opacity: row.isContextAncestor ? 0.55 : 1.0,
        child: LayoutBuilder(builder: (context, cons) {
        // 기간 열이 고정폭이라, 칸을 좁히면 남는 폭보다 커져 Row 가 넘칠 수 있다.
        // 가용 폭에 맞춰 잘라서 항상 제목 자리를 남긴다.
        // 예약폭: 들여쓰기 + 접기 화살표(28) + 상태/마일스톤 아이콘(~40) +
        // 제목이 최소한 읽힐 폭(~40). 이보다 좁아지면 기간 열을 먼저 줄인다.
        final reserved = 120.0 + row.depth * 16.0;
        final effPeriod = showPeriod
            ? periodWidth.clamp(
                0.0, (cons.maxWidth - reserved).clamp(0.0, double.infinity))
            : 0.0;
        return Row(
        children: [
          // 선행 아이콘 + 제목을 한 덩어리로 묶어 남는 폭을 모두 흡수시킨다
          // (고정폭 기간 열이 있어도 Row 가 넘치지 않게).
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 4),
                _TreeGuides(tree: tree, node: node, depth: row.depth),
          // 접기/펼치기 토글.
          SizedBox(
            width: 28,
            child: row.hasChildren
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: kRowHeight,
                      maxWidth: 28,
                      maxHeight: kRowHeight,
                    ),
                    iconSize: 18,
                    tooltip: node.isCollapsed ? '펼치기' : '접기',
                    onPressed: () => onToggleCollapse(node),
                    // 화살표 방향은 "지금 실제로 자손이 보이는가"(row.isChildrenShown)
                    // 를 따른다 — 필터가 강제로 펼쳐 보여주는 중이면 isCollapsed==true
                    // 여도 펼침 화살표를 보여준다(탭 동작은 여전히 실제 isCollapsed 를
                    // 토글하므로 표시와 조작이 분리된다).
                    icon: Icon(
                      row.isChildrenShown
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 완료/상태 체크박스(요약 노드는 비활성, leaf 는 4상태 표시).
          if (interactive)
            _DoneCheckbox(
              done: done,
              status: status,
              disabled: rollup.computedFromChildren,
              onTap: onToggleDone,
              semanticsLabel: done
                  ? '${node.title} ($kDoneSemantics)'
                  : status == TaskStatus.onHold
                      ? '${node.title} ($kOnHoldSemantics)'
                      : '${node.title} 완료 표시',
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                status != null ? statusIconData(status) : (done ? Icons.check_circle : Icons.circle_outlined),
                key: done ? ValueKey('done-mark-${node.id}') : null,
                size: 16,
                color: status != null
                    ? statusAccentColor(context, status)
                    : (done ? scheme.primary : scheme.outline),
              ),
            ),
          // 마일스톤 표식(Tree 전용 — 날짜 유무와 무관하게 항상 보인다).
          if (node.isMilestone)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: '마일스톤',
                child: Icon(
                  Icons.diamond_outlined,
                  size: 13,
                  color: scheme.tertiary,
                ),
              ),
            ),
          const SizedBox(width: 6),
          // 제목 (한 줄). 더블탭 → 편집, 우클릭/롱프레스 → 컨텍스트 메뉴.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: interactive
                  ? (d) => onContextMenu(d.globalPosition)
                  : null,
              onTap: onTap,
              onDoubleTap: interactive ? onDoubleTap : null,
              onLongPressStart: interactive
                  ? (d) => onContextMenu(d.globalPosition)
                  : null,
              child: Semantics(
                label: done ? '${node.title} ($kDoneSemantics)' : node.title,
                child: Text(
                  node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        row.depth == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: done
                        ? scheme.onSurface.withValues(alpha: 0.45)
                        : scheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
          ),
              ],
            ),
          ),
          // 헤더의 열 경계선과 폭을 맞추기 위한 간격(_ColumnDivider 와 같은 10px).
          if (showPeriod) ...[
            const SizedBox(width: 10),
            // 기간 열(고정폭 — 헤더에서 끌어 조절한 값).
            SizedBox(
              width: effPeriod,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapDown: interactive
                    ? (d) => onContextMenu(d.globalPosition)
                    : null,
                onLongPressStart: interactive
                    ? (d) => onContextMenu(d.globalPosition)
                    : null,
                child: Text(
                  _periodLabel(effStart, effEnd, rollup.computedFromChildren),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
          // 더보기(⋮) 버튼 — 우클릭/롱프레스로 여는 컨텍스트 메뉴와 **완전히
          // 같은 메뉴**를 단순 탭으로도 열 수 있게 한다. 터치에서는 롱프레스가
          // 바깥의 [LongPressDraggable](재정렬 드래그) 과 같은 제스처 계열이라
          // 경합에서 밀려 컨텍스트 메뉴가 아예 안 뜨는 경우가 있어(우클릭이
          // 없는 모바일에서 실제로 보고된 문제), 일반 탭 하나만으로 확실하게
          // 열리는 진입점을 별도로 둔다.
          if (interactive)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () {},
              onTapDown: (d) => onContextMenu(d.globalPosition),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_vert, size: 18),
              ),
            ),
          const SizedBox(width: 4),
        ],
        );
        }),
      ),
    );

    if (!interactive) {
      return content;
    }

    // 하단 after 삽입선은 별도 Stack 오버레이로.
    content = Stack(
      children: [
        content,
        if (hoverZone == DropZone.after)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: lineColor!,
              child: const SizedBox(height: 2),
            ),
          ),
      ],
    );

    // DragTarget + LongPressDraggable 로 감싼다.
    return DragTarget<FlatRow>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onMove: (details) {
        // DragTarget 은 로컬 좌표를 직접 안 주므로, RenderBox 로 변환.
        final RenderBox box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.offset);
        onHoverZone(details.data, local.dy.clamp(0.0, kRowHeight));
      },
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<FlatRow>(
          data: row,
          delay: const Duration(milliseconds: 250),
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Card(
                elevation: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    node.title.isEmpty ? '(새 항목)' : node.title,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: content),
          // 행 자체는 추가 제스처 없이 content(내부 제목/날짜 영역에
          // secondary/longPress/doubleTap 이 있음). 행 전체를 감싸는 제스처를
          // 두면 자식 IconButton(접기/완료) 의 single tap 과 double-tap 이
          // gesture arena 에서 충돌하므로 주의.
          child: content,
        );
      },
    );
  }

  String _periodLabel(PlanDate? s, PlanDate? e, bool computed) {
    final range = (s == null && e == null)
        ? '날짜 미정'
        : '${s?.toIso() ?? '?'} ~ ${e?.toIso() ?? '?'}';
    return computed ? '$range (요약)' : range;
  }
}

// ---------------------------------------------------------------------------
// 완료 체크박스
// ---------------------------------------------------------------------------

class _DoneCheckbox extends StatelessWidget {
  final bool done;

  /// leaf(또는 autoRollup=false) 노드에서만 non-null — 4상태 아이콘 표시용.
  /// 요약(rollup) 노드는 null 로 넘겨 기존 2상태(완료/미완료) 아이콘을 유지한다.
  final TaskStatus? status;
  final bool disabled;
  final VoidCallback onTap;
  final String semanticsLabel;

  const _DoneCheckbox({
    required this.done,
    this.status,
    required this.disabled,
    required this.onTap,
    required this.semanticsLabel,
  });

  IconData get _icon =>
      status != null ? statusIconData(status!) : (done ? Icons.check_circle : Icons.circle_outlined);

  Color _color(BuildContext context, {required double dimAlpha}) {
    if (status != null) {
      final c = statusAccentColor(context, status!);
      return dimAlpha < 1.0 ? c.withValues(alpha: dimAlpha) : c;
    }
    final scheme = Theme.of(context).colorScheme;
    if (!done) return scheme.outline;
    return dimAlpha < 1.0
        ? scheme.primary.withValues(alpha: dimAlpha)
        : scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    // 요약 노드면 체크를 비활성(파생값). leaf/비-rollup 만 토글 가능.
    if (disabled) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Icon(
          _icon,
          key: done ? const ValueKey('done-mark-disabled') : null,
          size: 16,
          color: _color(context, dimAlpha: 0.5),
        ),
      );
    }
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: Tooltip(
        message: '완료 토글',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              _icon,
              key: done ? const ValueKey('done-mark-active') : null,
              size: 16,
              color: _color(context, dimAlpha: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}
