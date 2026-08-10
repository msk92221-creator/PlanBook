/// [PlanNode] 들의 계층 트리를 보관/조작하는 불변 인덱스 기반 컨테이너.
///
/// 설계 요점:
/// - 노드는 flat 한 [Map] 으로 보관하고 [PlanNode.parentId] 로 계층을 만든다.
/// - 모든 "이동/재정렬" 연산은 **대상 노드 ID + (기준 형제 ID + before/after)** 로 표현한다.
///   (절대 화면상의 index 로 표현하지 않는다. 필터가 켜져 있을 때 화면 index 와
///   실제 형제 index 가 달라서 index 기반 이동은 반드시 버그를 만든다. → DESIGN.md)
/// - 순환 참조(self/descendant 아래로 이동)는 이동 전에 검사해서 거부한다.
/// - 부모 삭제 정책: cascade(자손 전부 삭제) 기본. promote(자식을 조부모로 승격) 제공.
///   삭제 전 [descendantCount] 로 삭제될 자손 수를 셀 수 있다(확인창용).
library;

import 'dart:collection';

import 'plan_node.dart';

/// 트리 조작 중 무결성 위반(순환 참조, 미존재 노드 등)을 나타내는 예외.
class PlanTreeException implements Exception {
  final String message;
  const PlanTreeException(this.message);
  @override
  String toString() => 'PlanTreeException: $message';
}

/// 형제 사이 삽입 위치.
enum InsertPosition { before, after }

/// [PlanTree] 의 트리 구조/조작 로직.
///
/// 상태 보유는 여기서 하지만, **앱의 단일 mutation 경로**는 [PlanStore] 이다.
/// [PlanTree] 의 변경 메서드는 단순히 구조만 바꾸고, 저장/알림/Undo 훅은
/// [PlanStore] 가 담당한다. 따라서 이 클래스는 ChangeNotifier 가 아니다.
class PlanTree {
  final Map<String, PlanNode> _byId = HashMap<String, PlanNode>();

  PlanTree();

  /// [nodes] 로 트리를 구성한다. 동일 id 가 중복되면 마지막 값이 이긴다.
  PlanTree.fromNodes(Iterable<PlanNode> nodes) {
    for (final n in nodes) {
      _byId[n.id] = n;
    }
  }

  /// 모든 노드를 flat 리스트로. 순서는 정의되지 않음(필요시 [roots]/[childrenOf] 사용).
  List<PlanNode> get allNodes => _byId.values.toList(growable: false);

  /// 노드 수.
  int get length => _byId.length;

  /// 비었는지.
  bool get isEmpty => _byId.isEmpty;

  /// id 로 노드 조회. 없으면 null.
  PlanNode? operator [](String id) => _byId[id];

  /// id 존재 여부.
  bool contains(String id) => _byId.containsKey(id);

  /// 최상위(parentId==null) 노드들을 [sortOrder] 오름차순으로.
  List<PlanNode> get roots =>
      _childrenOfParent(null);

  List<PlanNode> _childrenOfParent(String? parentId) {
    final list = _byId.values.where((n) => n.parentId == parentId).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  /// [parentId] 의 자식들을 [sortOrder] 순으로.
  /// [parentId]==null 이면 루트(최상위) 들을 반환.
  List<PlanNode> childrenOf(String? parentId) => _childrenOfParent(parentId);

  /// [id]의 자식 수.
  int childCount(String id) => _byId.values.where((n) => n.parentId == id).length;

  /// [id] 가 리프(자식 없음) 인지.
  bool isLeaf(String id) => childCount(id) == 0;

  /// [id] 의 부모 노드(없으면 null).
  PlanNode? parentOf(String id) {
    final n = _byId[id];
    if (n == null || n.parentId == null) return null;
    return _byId[n.parentId];
  }

  /// [id] 의 조상 체인(자기 자신 제외, 가까운 조상부터 루트까지).
  List<PlanNode> ancestorsOf(String id) {
    final result = <PlanNode>[];
    var cur = _byId[id];
    // self 제외, 부모부터.
    while (cur != null && cur.parentId != null) {
      final p = _byId[cur.parentId!];
      if (p == null) break;
      result.add(p);
      cur = p;
    }
    return result;
  }

  /// [candidateAncestorId] 가 [id] 의 자기 자신 또는 조상인지.
  /// (즉, [id] 를 [candidateAncestorId] 아래로 옮기면 순환이 생기는지 판별용)
  bool isSelfOrAncestor(String id, String candidateAncestorId) {
    if (id == candidateAncestorId) return true;
    return ancestorsOf(id).any((a) => a.id == candidateAncestorId);
  }

  /// [id] 를 [newParentId] 의 자식으로 옮기면 순환/무결성 위반이 생기는지.
  /// - [newParentId]==[id]: 자기 자신 아래 (순환)
  /// - [newParentId]가 [id] 의 자손: 순환
  /// - [newParentId] 가 트리에 없거나 null(루트) 이면 OK.
  bool wouldCreateCycle(String id, String? newParentId) {
    if (newParentId == null) return false; // 루트로 옮기는 건 항상 OK
    if (!_byId.containsKey(newParentId)) return true; // 존재하지 않는 부모
    if (id == newParentId) return true;
    // newParentId 가 id 의 자손인지 검사: id 의 subtree 에 newParentId 가 있으면 cycle.
    return isDescendant(ancestorId: id, candidateDescendantId: newParentId);
  }

  /// [candidateDescendantId] 가 [ancestorId] 의 자손(또는 자기 자신)인지.
  bool isDescendant({
    required String ancestorId,
    required String candidateDescendantId,
  }) {
    var cur = candidateDescendantId;
    // candidate 의 조상 체인을 따라가며 ancestorId 가 나오면 true.
    // 자기 자신도 자손으로 본다(cycle 판정 목적).
    if (cur == ancestorId) return true;
    for (final a in ancestorsOf(candidateDescendantId)) {
      if (a.id == ancestorId) return true;
    }
    return false;
  }

  /// [id] 의 자손 수(자기 자신 제외).
  int descendantCount(String id) {
    return _byId.values.where((n) {
      if (n.id == id) return false;
      return isDescendant(ancestorId: id, candidateDescendantId: n.id);
    }).length;
  }

  /// [id] 와 모든 자손(자기 자신 포함)을 깊이 우선, [sortOrder] 순으로.
  List<PlanNode> subtree(String id) {
    final out = <PlanNode>[];
    void visit(String pid) {
      final n = _byId[pid];
      if (n == null) return;
      out.add(n);
      for (final c in _childrenOfParent(pid)) {
        visit(c.id);
      }
    }

    visit(id);
    return out;
  }

  // ---------------- 변경 연산 ----------------

  /// [node] 를 추가/덮어쓴다. (parentId 는 node 의 값 그대로 반영)
  void upsert(PlanNode node) {
    _byId[node.id] = node;
  }

  /// 단순 속성 업데이트(parentId/sortOrder 는 트리 연산으로만 바꿀 것).
  PlanNode update(String id, PlanNode Function(PlanNode current) updater) {
    final cur = _byId[id];
    if (cur == null) {
      throw PlanTreeException('Node not found: $id');
    }
    final updated = updater(cur);
    _byId[id] = updated;
    return updated;
  }

  /// [id] 를 [newParentId] 의 자식으로 이동.
  /// - [newParentId]==null → 최상위(루트)로 승격.
  /// - 순환/미존재 부모면 [PlanTreeException] throw (트리는 변경되지 않음).
  /// - 기본적으로 새 부모 자식 리스트의 끝에 붙인다.
  /// - 정밀 위치 지정이 필요하면 [insertAt] 사용.
  void move(String id, String? newParentId) {
    final n = _byId[id];
    if (n == null) throw PlanTreeException('Node not found: $id');
    if (n.parentId == newParentId) {
      return; // 동일 부모, 위치만 바꾸려면 insertAt/reorder 사용
    }
    if (wouldCreateCycle(id, newParentId)) {
      throw PlanTreeException(
        'Cycle detected: cannot move "$id" under "$newParentId"',
      );
    }
    _setParent(id, newParentId, appendToEnd: true);
  }

  /// [id] 를 [newParentId] 자식들 중 [referenceSiblingId] 의 [position]
  /// (before/after) 위치로 옮긴다.
  ///
  /// - [newParentId]==null → 최상위(루트).
  /// - [referenceSiblingId] 는 [newParentId] 의 기존 자식이어야 한다(예외에서 검증).
  ///   단, [referenceSiblingId]==[id] 자신인 경우는 허용하지 않는다.
  /// - 동일 부모 내 순서 변경(reorder) 도 이 함수로 처리한다.
  /// - index 가 아닌 **ID 기반**이므로 필터가 켜져 있어도 안전하다.
  void insertAt(
    String id, {
    String? newParentId,
    required String referenceSiblingId,
    required InsertPosition position,
  }) {
    final n = _byId[id];
    if (n == null) throw PlanTreeException('Node not found: $id');
    if (referenceSiblingId == id) {
      throw PlanTreeException(
        'referenceSiblingId must differ from the moved node id',
      );
    }
    final ref = _byId[referenceSiblingId];
    if (ref == null) {
      throw PlanTreeException('Reference sibling not found: $referenceSiblingId');
    }
    if (ref.parentId != newParentId) {
      throw PlanTreeException(
        'Reference sibling "$referenceSiblingId" is not a child of newParentId',
      );
    }
    if (wouldCreateCycle(id, newParentId)) {
      throw PlanTreeException(
        'Cycle detected: cannot move "$id" under "$newParentId"',
      );
    }

    // 1) 부모 변경(필요시). 옛 부모 ID 를 먼저 기억해둔다.
    final oldParentId = n.parentId;
    if (oldParentId != newParentId) {
      _byId[id] = n.copyWith(parentId: newParentId);
    }

    // 2) 해당 부모 자식들을 sortOrder 순으로 재정렬하되, id 를 ref 의 before/after
    //    위치에 강제 배치. 정수 인덱스로 0,1,2,... 재부여하여 결정적(deterministic)으로.
    final siblings = _childrenOfParent(newParentId).where((s) => s.id != id).toList();
    int targetIndex;
    final refIndex = siblings.indexWhere((s) => s.id == referenceSiblingId);
    if (refIndex < 0) {
      // 방어: 앞서 검증했으므로 여기 올 수 없다.
      targetIndex = siblings.length;
    } else {
      targetIndex = position == InsertPosition.before ? refIndex : refIndex + 1;
    }
    siblings.insert(targetIndex, _byId[id]!);

    // 3) sortOrder 재부여(0,1,2,...) — 결정적 정렬 보장.
    _reindexSiblings(newParentId, siblings);

    // 4) 부모가 바뀐 경우, 옛 부모에 남은 자식들의 sortOrder 도 빈틈없이
    //    0,1,2,... 로 재색인한다(_setParent 와 동일한 불변식).
    //    그렇지 않으면 move() 와 insertAt() 이 같은 의미의 연산임에도 경로에 따라
    //    서로 다른 결과(구멍 난 sortOrder) 를 낳는다.
    if (oldParentId != newParentId) {
      if (_byId.values.any((s) => s.parentId == oldParentId)) {
        _reindexSiblings(oldParentId, _childrenOfParent(oldParentId));
      }
    }
  }

  /// [id] 를 새 부모의 자식 끝에 추가. (정렬은 자동)
  void _setParent(String id, String? newParentId, {required bool appendToEnd}) {
    final n = _byId[id]!;
    final oldParentId = n.parentId;
    if (oldParentId == newParentId) {
      // 동일 부모: append 모드면 id 를 끝으로 옮긴 순서로, 아니면 현재 순서 그대로 재색인.
      final siblings = _childrenOfParent(newParentId);
      if (appendToEnd) {
        final others = siblings.where((s) => s.id != id).toList();
        _reindexSiblings(newParentId, [...others, n]);
      } else {
        _reindexSiblings(newParentId, siblings);
      }
      return;
    }
    final updated = n.copyWith(parentId: newParentId);
    _byId[id] = updated;
    if (appendToEnd) {
      // 기존 자식들(정렬) 뒤에 이동 노드를 **끝에 append** 한 리스트로 재색인한다.
      // _childrenOfParent() 결과를 그대로 넘기면 이동 노드의 낡은 sortOrder 가
      // 새 부모 형제들과 겹쳐 중간에 끼어드는 버그가 생긴다(버그 #1).
      // 반드시 의도한 최종 순서 리스트를 넘길 것.
      final others = _childrenOfParent(newParentId)
          .where((s) => s.id != id)
          .toList();
      _reindexSiblings(newParentId, [...others, updated]);
    } else {
      _reindexSiblings(newParentId, _childrenOfParent(newParentId));
    }
    // 옛 부모에 남은 자식들의 sortOrder 도 빈틈없이 0,1,2,... 로 재색인.
    if (_byId.values.any((s) => s.parentId == oldParentId)) {
      _reindexSiblings(oldParentId, _childrenOfParent(oldParentId));
    }
  }

  /// 주어진 순서의 형제 리스트에 0,1,2,... 의 sortOrder 를 부여한다.
  ///
  /// **주의**: [siblings] 는 호출자가 **의도한 최종 순서 그대로**의 리스트여야 한다.
  /// `_childrenOfParent(parentId)` 결과를 그대로 넘기면 낡은 sortOrder 기준으로
  /// 재정렬된 리스트가 들어가, 애써 만든 배치가 정렬에 의해 덮어써지는 버그가
  /// 생긴다(순서를 바꾸지 않는 순수 재색인 목적일 때만 예외).
  void _reindexSiblings(String? parentId, List<PlanNode> siblings) {
    for (var i = 0; i < siblings.length; i++) {
      final n = siblings[i];
      if (n.sortOrder != i.toDouble()) {
        _byId[n.id] = n.copyWith(sortOrder: i.toDouble());
      }
    }
  }

  /// [id] 와 모든 자손을 삭제(cascade). 삭제된 노드 수(자기 자신 포함) 반환.
  int deleteCascade(String id) {
    if (!_byId.containsKey(id)) {
      throw PlanTreeException('Node not found: $id');
    }
    final toRemove = subtree(id).map((n) => n.id).toSet();
    for (final rid in toRemove) {
      _byId.remove(rid);
    }
    return toRemove.length;
  }

  /// [id] 만 삭제하고, 그 자식들을 조부모([id]의 기존 부모) 아래로 승격.
  /// 자식들의 상대 순서는 유지되며, 원래 [id]가 있던 위치에 끼워넣는다.
  /// 삭제된 노드 수는 항상 1.
  int deletePromote(String id) {
    final n = _byId[id];
    if (n == null) throw PlanTreeException('Node not found: $id');
    final grandParentId = n.parentId;
    final siblings = _childrenOfParent(grandParentId);
    final myIndex = siblings.indexWhere((s) => s.id == id);
    final children = _childrenOfParent(id);

    // 자식들의 부모를 조부모로 변경. sortOrder 는 임시로 큰 값 배정 후 전체 재색인.
    final newOrder = <PlanNode>[];
    for (var i = 0; i < siblings.length; i++) {
      final s = siblings[i];
      if (s.id == id) {
        // id 자리에 자식들을 그대로 끼워넣는다.
        for (final c in children) {
          newOrder.add(c.copyWith(parentId: grandParentId));
        }
      } else {
        newOrder.add(s);
      }
    }

    // 적용.
    _byId.remove(id);
    for (final node in newOrder) {
      _byId[node.id] = node;
    }
    // 주의: 위에서 만든 newOrder 를 그대로 넘겨야 의도한 배치가 유지된다.
    // _childrenOfParent(grandParentId) 를 넘기면 승격된 자식들의 낡은 sortOrder 가
    // 기존 형제들과 겹쳐 순서가 깨진다(버그 #2).
    _reindexSiblings(grandParentId, newOrder);
    // myIndex 가 -1일 리는 없지만 방어.
    assert(myIndex >= 0);
    return 1;
  }

  /// [nodeId] 와 그 자손 전체(자기 자신 포함)의 projectId 를 [projectId] 로
  /// 통일한다.
  ///
  /// **reparent(다른 부모 아래로 이동) 직후에만 호출한다** — 정책: "이동한 Task는
  /// 새 부모의 projectId 를 물려받고, 그 자손 전체도 같은 projectId 로 갱신된다.
  /// 새 부모가 projectId==null(미분류/루트) 이면 자손도 전부 null 이 된다."
  /// (호출부: [PlanStore.moveNode]/[PlanStore.reorderSibling] — parentId 가 실제로
  /// 바뀐 경우에만 호출해서, 같은 부모 내 순서 변경(reorder)에는 영향이 없게 한다)
  void cascadeProjectId(String nodeId, String? projectId) {
    for (final n in subtree(nodeId)) {
      if (n.projectId != projectId) {
        _byId[n.id] = n.copyWith(projectId: projectId);
      }
    }
  }

  /// 트리를 flat 리스트로 반환(직렬화용). sortOrder/parentId 기반 복원 가능.
  List<PlanNode> toFlatList() => _byId.values.toList(growable: false);

  /// 모든 노드 제거.
  void clear() {
    _byId.clear();
  }
}
