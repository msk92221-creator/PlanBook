/// Task 컨텍스트 메뉴(우클릭/롱프레스) — **트리와 Gantt 가 공유한다**.
///
/// 원래 이 로직은 [TreePanel] 안에만 있었다. 그래서 왼쪽 목록에서는 우클릭이
/// 되는데 오른쪽 Gantt 막대에서는 아무 일도 일어나지 않았다. 같은 Task 를
/// 두 곳에서 보는 화면인데 조작 방법이 다르면 안 되므로, 메뉴와 동작을 여기로
/// 옮겨 양쪽이 같은 코드를 부르게 했다.
///
/// 메뉴 항목의 동작은 전부 [PlanStore] 의 기존 단일 변경 경로를 통과한다
/// (여기서 별도 저장/변경 경로를 만들지 않는다).
library;

import 'package:flutter/material.dart';

import '../../data/plan_store.dart';
import '../../domain/plan_node.dart';
import '../../domain/plan_rollup.dart';
import 'node_delete_dialog.dart';
import 'node_edit_dialog.dart';

/// [globalPos] 위치에 Task 컨텍스트 메뉴를 띄우고 선택된 동작을 실행한다.
///
/// [anchor] 는 좌표 변환 기준이 되는 위젯의 컨텍스트다(메뉴를 띄우는 화면).
Future<void> showNodeContextMenu(
  BuildContext anchor, {
  required PlanStore store,
  required PlanNode node,
  required Offset globalPos,
}) async {
  final box = anchor.findRenderObject();
  if (box is! RenderBox) return;
  final local = box.globalToLocal(globalPos);

  final value = await showMenu<String>(
    context: anchor,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      box.size.width - local.dx,
      box.size.height - local.dy,
    ),
    items: const [
      PopupMenuItem(value: 'addChild', child: Text('하위 항목 추가')),
      PopupMenuItem(value: 'addSibling', child: Text('형제 항목 추가')),
      PopupMenuItem(value: 'edit', child: Text('편집...')),
      PopupMenuItem(value: 'toggleDone', child: Text('완료 토글')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'delete', child: Text('삭제...')),
    ],
  );
  if (value == null || !anchor.mounted) return;

  switch (value) {
    case 'addChild':
      await _addChild(anchor, store, node);
    case 'addSibling':
      await _addSibling(anchor, store, node);
    case 'edit':
      await _editNode(anchor, store, node);
    case 'toggleDone':
      _toggleDone(store, node);
    case 'delete':
      await _deleteNode(anchor, store, node);
  }
}

Future<void> _addChild(
    BuildContext context, PlanStore store, PlanNode parent) async {
  final node = store.addNode(parentId: parent.id, title: '');
  // 접혀 있으면 새 자식이 보이지 않으므로 펼쳐준다.
  if (parent.isCollapsed) {
    store.updateNode(parent.id, (n) => n.copyWith(isCollapsed: false));
  }
  await _editAndDeleteIfEmpty(context, store, node);
}

Future<void> _addSibling(
    BuildContext context, PlanStore store, PlanNode sibling) async {
  final node = store.addNode(parentId: sibling.parentId, title: '');
  await _editAndDeleteIfEmpty(context, store, node);
}

/// 새 노드를 편집 다이얼로그로 띄운다. 취소하면 빈 노드를 제거한다.
Future<void> _editAndDeleteIfEmpty(
    BuildContext context, PlanStore store, PlanNode node) async {
  if (!context.mounted) return;
  final result = await showNodeEditDialog(
    context,
    tree: store.tree,
    node: node,
    store: store,
  );
  if (result == null) {
    if (store.tree.contains(node.id)) {
      store.deleteCascade(node.id);
    }
    return;
  }
  commitNodeEdit(store, node, result);
}

Future<void> _editNode(
    BuildContext context, PlanStore store, PlanNode node) async {
  final result = await showNodeEditDialog(
    context,
    tree: store.tree,
    node: node,
    store: store,
  );
  if (result == null) return;
  commitNodeEdit(store, node, result);
}

void _toggleDone(PlanStore store, PlanNode node) {
  // 요약(rollup) 노드는 자식으로부터 계산되므로 직접 토글하지 않는다.
  if (computeRollup(store.tree, node.id).computedFromChildren) return;
  store.setNodeDone(node.id, !node.isDone);
}

Future<void> _deleteNode(
    BuildContext context, PlanStore store, PlanNode node) async {
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
