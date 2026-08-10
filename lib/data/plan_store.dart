/// 앱의 단일 mutation 경로이자 자동 저장을 담당하는 상태 저장소.
///
/// **설계 핵심**:
/// - 모든 변경(추가/수정/이동/재정렬/삭제/날짜변경)은 이 클래스의 메서드를 통과하고,
///   내부적으로 [_mutate] 라는 단일 private 경로를 지난다.
/// - [_mutate] 안에서: 트리 조작 → dirty 표시 → 자동 저장(debounce) 예약 →
///   ChangeNotifier 알림. **이 지점이 향후 Undo 스택(command 기록)을 붙일 확장점**이다.
/// - 자동 저장은 변경 후 ~400ms debounce. 앱 종료/백그라운드 진입 시 [flush] 로 즉시 기록.
/// - "오늘"은 주입 가능한 [DateTimeProvider] 로 받는다(테스트에서 고정 가능).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/date/plan_date.dart';
import '../core/ids.dart';
import '../domain/app_settings.dart';
import '../domain/plan_enums.dart';
import '../domain/plan_node.dart';
import '../domain/plan_tree.dart';
import '../domain/project.dart';
import '../domain/reschedule.dart' as domain_reschedule show rescheduleNode;
import '../domain/reschedule.dart' show RescheduleOption;
import '../domain/tag.dart';
import 'plan_repository.dart';

/// mutation 종류. (향후 Undo 커맨드 분류용)
enum MutationKind { add, update, remove, move, reorder, clear, sample }

class PlanStore extends ChangeNotifier {
  PlanStore({
    required this.repository,
    DateTimeProvider? nowProvider,
    this.autosaveDelay = const Duration(milliseconds: 400),
  }) : _now = nowProvider ?? DateTime.now;

  final PlanRepository repository;
  final Duration autosaveDelay;
  final DateTimeProvider _now;

  final PlanTree _tree = PlanTree();
  final List<Project> _projects = <Project>[];
  final List<Tag> _tags = <Tag>[];
  AppSettings _settings = const AppSettings();

  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  // ---------------- Undo/Redo ----------------
  //
  // 정책: "한 번의 사용자 동작 = 한 번의 undo 스텝". 드래그/리사이즈처럼 여러
  // 프레임에 걸친 제스처는 이미 gesture-end(drop) 시점에만 store 메서드를
  // 한 번 호출하도록 UI 쪽이 구현되어 있어([_mutate] 호출 1회), 여기서 별도로
  // "마우스 이동마다 스냅샷"을 막을 필요가 없다. addNode 안에서 다시 addNode 를
  // 호출하는 등 [_mutate] 가 중첩 호출되는 경우([createSampleData] 등)에는
  // **가장 바깥쪽 호출만** 하나의 undo 엔트리를 남긴다([_mutateDepth]).
  //
  // 트리 전체를 Map 스냅샷으로 비교하는 단순한 방식이다(개인용 데이터 규모
  // 가정 — 이 앱의 다른 조회 로직들과 동일한 설계 원칙). Project/Tag/Settings
  // 변경은 트리를 건드리지 않으므로 자동으로 undo 대상에서 제외된다.
  static const int _kMaxUndoEntries = 50;
  final List<_TreeUndoEntry> _undoStack = <_TreeUndoEntry>[];
  final List<_TreeUndoEntry> _redoStack = <_TreeUndoEntry>[];
  int _mutateDepth = 0;
  Map<String, PlanNode>? _pendingBeforeSnapshot;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Map<String, PlanNode> _snapshotTree() =>
      {for (final n in _tree.allNodes) n.id: n};

  bool _sameSnapshot(Map<String, PlanNode> a, Map<String, PlanNode> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _restoreSnapshot(Map<String, PlanNode> snap) {
    _tree.clear();
    for (final n in snap.values) {
      _tree.upsert(n);
    }
  }

  /// 마지막 트리 변경을 되돌린다. 되돌릴 게 없으면 아무 일도 하지 않는다.
  void undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    _restoreSnapshot(entry.before);
    _dirty = true;
    _scheduleAutosave();
    notifyListeners();
  }

  /// [undo] 로 되돌린 변경을 다시 적용한다.
  void redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    _restoreSnapshot(entry.after);
    _dirty = true;
    _scheduleAutosave();
    notifyListeners();
  }

  /// 로드 완료 여부.
  bool get isLoaded => _loaded;

  /// 트리(읽기 전용 접근). UI 는 이 getter 로만 트리를 읽는다.
  PlanTree get tree => _tree;

  /// 프로젝트 목록(sortOrder 순, 읽기 전용).
  List<Project> get projects {
    final list = List<Project>.from(_projects);
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List<Project>.unmodifiable(list);
  }

  /// 태그 목록(읽기 전용).
  List<Tag> get tags => List<Tag>.unmodifiable(_tags);

  /// 앱 설정(읽기 전용).
  AppSettings get settings => _settings;

  /// id 로 프로젝트 조회. 없으면 null.
  Project? projectById(String? id) {
    if (id == null) return null;
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// id 로 태그 조회. 없으면 null.
  Tag? tagById(String id) {
    for (final t in _tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 오늘(주입된 clock 기준).
  PlanDate get today {
    final dt = _now();
    return PlanDate(dt.year, dt.month, dt.day);
  }

  /// 비었는지.
  bool get isEmpty => _tree.isEmpty;

  /// 현재 상태의 스냅샷(내보내기용). [flush] 가 저장하는 것과 동일한 구조.
  PlanSnapshot exportableSnapshot() => PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: _tree.toFlatList(),
        projects: List<Project>.from(_projects),
        tags: List<Tag>.from(_tags),
        settings: _settings,
      );

  // ---------------- 수명 주기 ----------------

  /// 저장소에서 로드. 파일이 없거나 손상이면 빈 상태로 시작(예외 없음).
  Future<void> load() async {
    final snap = await repository.load();
    _tree.clear();
    _projects.clear();
    _tags.clear();
    _settings = const AppSettings();
    if (snap != null) {
      for (final n in snap.nodes) {
        _tree.upsert(n);
      }
      _projects.addAll(snap.projects);
      _tags.addAll(snap.tags);
      _settings = snap.settings;
    }
    _loaded = true;
    _dirty = false;
    // 기본 프로젝트는 최초 1회만 시드한다. 사용자가 지운 뒤 재실행해도 되살아나지
    // 않도록 settings.seededDefaultProjects 플래그로 제어한다.
    if (!_settings.seededDefaultProjects) {
      _seedDefaultProjects();
    }
    notifyListeners();
  }

  /// 기본 프로젝트 5개 시드. [load] 에서 플래그가 꺼져 있을 때만 호출된다.
  ///
  /// 여기서는 [_mutate] 를 쓰지 않고 직접 dirty 를 세운다 — load 직후이며
  /// notifyListeners 는 [load] 가 마지막에 한 번만 부르기 때문이다.
  void _seedDefaultProjects() {
    for (var i = 0; i < kDefaultProjectNames.length; i++) {
      _projects.add(Project(
        id: newId(),
        name: kDefaultProjectNames[i],
        color: kDefaultProjectColors[i],
        sortOrder: i.toDouble(),
      ));
    }
    _settings = _settings.copyWith(seededDefaultProjects: true);
    _dirty = true;
    _scheduleAutosave();
  }

  /// 보류 중인 저장이 있으면 즉시 실행. (앱 종료/백그라운드 진입 시 호출)
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      await repository.save(
        PlanSnapshot(
          schemaVersion: PlanSnapshot.currentSchemaVersion,
          nodes: _tree.toFlatList(),
          projects: List<Project>.from(_projects),
          tags: List<Tag>.from(_tags),
          settings: _settings,
        ),
      );
    } catch (e) {
      // 저장 실패 시 dirty 복구하여 다음 기회에 재시도.
      _dirty = true;
      if (kDebugMode) {
        debugPrint('PlanStore.flush: save failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }

  // ---------------- 단일 mutation 경로 ----------------

  /// 모든 변경의 단일 진입점.
  /// - [kind] : 변경 종류(Undo 분류용).
  /// - [action] : 트리를 실제로 조작하는 콜백. 반환값을 그대로 돌려준다.
  ///
  /// 향후 Undo 를 넣을 때: 이 함수 안에서 (before/after 스냅샷 또는 역연산 커맨드)를
  /// 기록하는 로직만 추가하면 된다. (확장 지점 — 현재는 미구현)
  T _mutate<T>(MutationKind kind, T Function() action) {
    final isOutermost = _mutateDepth == 0;
    if (isOutermost) _pendingBeforeSnapshot = _snapshotTree();
    _mutateDepth++;
    final T result;
    try {
      result = action();
    } finally {
      _mutateDepth--;
    }
    if (isOutermost) {
      final before = _pendingBeforeSnapshot!;
      _pendingBeforeSnapshot = null;
      final after = _snapshotTree();
      if (!_sameSnapshot(before, after)) {
        _undoStack.add(_TreeUndoEntry(before: before, after: after));
        if (_undoStack.length > _kMaxUndoEntries) _undoStack.removeAt(0);
        _redoStack.clear();
      }
    }
    _dirty = true;
    _scheduleAutosave();
    notifyListeners();
    return result;
  }

  void _scheduleAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, () {
      // Timer 콜백은 동기; flush 비동기 실행(에러 무시).
      flush();
    });
  }

  // ---------------- 변경 API ----------------

  /// 새 노드 추가. [parentId]==null 이면 루트. 생성된 노드를 반환.
  PlanNode addNode({
    String? parentId,
    required String title,
    PlanDate? startDate,
    PlanDate? endDate,
    double progress = 0.0,
    TaskStatus status = TaskStatus.notStarted,
    Priority priority = Priority.none,
    String? projectId,
    List<String> tagIds = const [],
    bool isMilestone = false,
    String? memo,
    num? estimate,
    num? actual,
    String? unit,
    NodeKind nodeKind = NodeKind.project,
    bool autoRollup = true,
    String? id,
    String? recurrenceFreq,
    List<int> recurrenceWeekdays = const [],
    int? recurrenceDayOfMonth,
  }) {
    return _mutate(MutationKind.add, () {
      final siblings = _tree.childrenOf(parentId);
      final sortOrder = siblings.isEmpty
          ? 0.0
          : siblings.last.sortOrder + 1.0;
      final node = PlanNode(
        id: id ?? newId(),
        parentId: parentId,
        title: title,
        startDate: startDate,
        endDate: endDate,
        progress: progress,
        status: status,
        priority: priority,
        projectId: projectId,
        tagIds: List<String>.unmodifiable(tagIds),
        isMilestone: isMilestone,
        memo: memo,
        estimate: estimate,
        actual: actual,
        unit: unit,
        sortOrder: sortOrder,
        nodeKind: nodeKind,
        autoRollup: autoRollup,
        recurrenceFreq: recurrenceFreq,
        recurrenceWeekdays: List<int>.unmodifiable(recurrenceWeekdays),
        recurrenceDayOfMonth: recurrenceDayOfMonth,
      );
      _tree.upsert(node);
      return node;
    });
  }

  // ---------------- Project / Tag / Settings ----------------
  //
  // 아래 CRUD 도 전부 기존 단일 mutation 경로(_mutate)를 통과한다.
  // 저장을 우회하는 별도 save 경로를 만들지 않는다.

  /// 프로젝트 추가. 생성된 [Project] 반환.
  Project createProject(String name, {int? color, String? id}) {
    return _mutate(MutationKind.add, () {
      final order = _projects.isEmpty
          ? 0.0
          : _projects
                  .map((p) => p.sortOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1.0;
      final p = Project(
        id: id ?? newId(),
        name: name,
        color: color ?? 0xFF6750A4,
        sortOrder: order,
      );
      _projects.add(p);
      return p;
    });
  }

  /// 프로젝트 수정.
  void updateProject(String id, Project Function(Project current) updater) {
    _mutate(MutationKind.update, () {
      final i = _projects.indexWhere((p) => p.id == id);
      if (i < 0) return;
      _projects[i] = updater(_projects[i]);
    });
  }

  /// 프로젝트 삭제.
  ///
  /// **Task 는 삭제하지 않는다.** 해당 프로젝트에 속한 Task 들의 [PlanNode.projectId]
  /// 만 null 로 만들어 "미분류" 로 남긴다. (분류 하나를 지웠다고 작업이 사라지면 안 된다)
  /// 반환값은 미분류로 바뀐 Task 수.
  int deleteProject(String id) {
    return _mutate(MutationKind.remove, () {
      _projects.removeWhere((p) => p.id == id);
      var detached = 0;
      for (final n in _tree.allNodes) {
        if (n.projectId == id) {
          _tree.upsert(n.copyWith(projectId: null));
          detached++;
        }
      }
      return detached;
    });
  }

  /// [orderedIds] 순서대로 프로젝트 sortOrder 를 0,1,2,... 로 재부여한다.
  /// (프로젝트 목록은 flat 이라 Task 트리처럼 "영향받는 형제만" 재색인할 필요
  /// 없이 전체를 다시 매기는 것이 가장 단순하고 정확하다)
  void reorderProjects(List<String> orderedIds) {
    _mutate(MutationKind.reorder, () {
      for (var i = 0; i < orderedIds.length; i++) {
        final idx = _projects.indexWhere((p) => p.id == orderedIds[i]);
        if (idx < 0) continue;
        if (_projects[idx].sortOrder != i.toDouble()) {
          _projects[idx] = _projects[idx].copyWith(sortOrder: i.toDouble());
        }
      }
    });
  }

  /// 태그 추가. 생성된 [Tag] 반환.
  Tag createTag(String name, {int? color, String? id}) {
    return _mutate(MutationKind.add, () {
      final t = Tag(id: id ?? newId(), name: name, color: color ?? 0xFF6B7280);
      _tags.add(t);
      return t;
    });
  }

  /// 태그 수정.
  void updateTag(String id, Tag Function(Tag current) updater) {
    _mutate(MutationKind.update, () {
      final i = _tags.indexWhere((t) => t.id == id);
      if (i < 0) return;
      _tags[i] = updater(_tags[i]);
    });
  }

  /// 태그 삭제. 모든 Task 의 [PlanNode.tagIds] 에서도 제거한다.
  /// 반환값은 태그가 제거된 Task 수.
  int deleteTag(String id) {
    return _mutate(MutationKind.remove, () {
      _tags.removeWhere((t) => t.id == id);
      var affected = 0;
      for (final n in _tree.allNodes) {
        if (n.tagIds.contains(id)) {
          final next = n.tagIds.where((t) => t != id).toList(growable: false);
          _tree.upsert(n.copyWith(tagIds: List<String>.unmodifiable(next)));
          affected++;
        }
      }
      return affected;
    });
  }

  /// 이름으로 프로젝트 id 를 찾고, 없으면 만들어서 id 를 돌려준다.
  /// (샘플/마이그레이션용 내부 헬퍼 — [_mutate] 안에서 호출된다)
  String _projectIdByNameOrCreate(String name) {
    for (final p in _projects) {
      if (p.name == name) return p.id;
    }
    final i = kDefaultProjectNames.indexOf(name);
    final created = Project(
      id: newId(),
      name: name,
      color: i >= 0 ? kDefaultProjectColors[i] : 0xFF6750A4,
      sortOrder: _projects.length.toDouble(),
    );
    _projects.add(created);
    return created.id;
  }

  /// 앱 설정 변경.
  void updateSettings(AppSettings Function(AppSettings current) updater) {
    _mutate(MutationKind.update, () {
      _settings = updater(_settings);
    });
  }

  // ---------------- 노드 변경 API (계속) ----------------

  /// 단순 속성 업데이트(parentId/sortOrder 는 move/insertAt 사용).
  void updateNode(String id, PlanNode Function(PlanNode current) updater) {
    _mutate(MutationKind.update, () {
      _tree.update(id, updater);
    });
  }

  /// 완료 체크/해제. Tree/Today 양쪽에서 공유하는 단일 정책:
  /// - 체크(done=true)  → status = done.
  /// - 해제(done=false) → 기존 진행률 기준. progress>0 이면 inProgress,
  ///   아니면 notStarted(완전히 처음 상태로 되돌리지 않고 맥락을 보존).
  void setNodeDone(String id, bool done) {
    _mutate(MutationKind.update, () {
      _tree.update(id, (n) {
        if (done) return n.copyWith(status: TaskStatus.done);
        final next =
            n.progress > 0 ? TaskStatus.inProgress : TaskStatus.notStarted;
        return n.copyWith(status: next);
      });
    });
  }

  /// 반복 Task([PlanNode.nodeKind]==recurring)의 특정 날짜 occurrence 완료
  /// 상태를 기록/해제한다. **원본 노드의 [PlanNode.status] 는 건드리지 않는다**
  /// — occurrence 완료는 [PlanNode.recurrenceCompletedDates] 에만 반영되므로
  /// 미래 occurrence 표시에는 영향이 없다.
  void setRecurrenceOccurrenceDone(String id, PlanDate date, bool done) {
    _mutate(MutationKind.update, () {
      _tree.update(id, (n) {
        final iso = date.toIso();
        final set = n.recurrenceCompletedDates.toSet();
        if (done) {
          set.add(iso);
        } else {
          set.remove(iso);
        }
        return n.copyWith(
            recurrenceCompletedDates: List<String>.unmodifiable(set));
      });
    });
  }

  /// 일정 재분배. **호출 자체가 이미 사용자의 명시적 선택**이라고 가정한다
  /// (UI 는 항상 사용자가 옵션을 고른 뒤에만 이 메서드를 호출해야 하며, 어떤
  /// 경우에도 자동으로 호출해서는 안 된다). 변경할 게 없으면(keepAsIs 등)
  /// 아무 것도 하지 않는다(반환값 false).
  bool rescheduleNode(
    String id,
    RescheduleOption option, {
    PlanDate? specificDate,
  }) {
    final current = _tree[id];
    if (current == null) return false;
    final updated =
        domain_reschedule.rescheduleNode(current, option, today, specificDate: specificDate);
    if (updated == null) return false;
    _mutate(MutationKind.update, () => _tree.upsert(updated));
    return true;
  }

  /// 자식이 있는 모든 노드의 접기 상태를 한 번에 [collapsed] 로 맞춘다
  /// ("전체 펼치기"/"전체 접기"). 한 번의 사용자 동작이므로 undo 도 한 스텝이다
  /// (중첩된 [_mutate] 는 가장 바깥쪽만 엔트리를 남긴다).
  void setAllCollapsed(bool collapsed) {
    _mutate(MutationKind.update, () {
      for (final n in _tree.allNodes) {
        if (n.isCollapsed != collapsed && !_tree.isLeaf(n.id)) {
          _tree.upsert(n.copyWith(isCollapsed: collapsed));
        }
      }
    });
  }

  /// [id] 를 [newParentId] 자식 끝으로 이동.
  ///
  /// 부모가 실제로 바뀌면(같은 부모로 이동은 no-op) **Project 소속을 새 부모에
  /// 맞춰 전파**한다 — 정책: 이동한 Task 와 그 자손 전체의 projectId 를 새 부모의
  /// projectId 로 통일(새 부모가 루트/미분류면 전부 null). 이 전파는 여기 한
  /// 곳([PlanTree.cascadeProjectId])에서만 처리하고, UI 코드가 직접 projectId 를
  /// 건드리지 않는다.
  void moveNode(String id, String? newParentId) {
    _mutate(MutationKind.move, () {
      final oldParentId = _tree[id]?.parentId;
      _tree.move(id, newParentId);
      if (oldParentId != newParentId) {
        final newProjectId =
            newParentId == null ? null : _tree[newParentId]?.projectId;
        _tree.cascadeProjectId(id, newProjectId);
      }
    });
  }

  /// [id] 를 [referenceSiblingId] 의 [position](before/after) 위치로 이동/정렬.
  /// (필터가 켜져 있어도 ID 기반이라 안전)
  ///
  /// [moveNode] 와 동일하게, 부모가 실제로 바뀐 경우에만 Project 소속을 새
  /// 부모에 맞춰 전파한다(같은 부모 내 순서 변경은 영향 없음).
  void reorderSibling(
    String id, {
    required String referenceSiblingId,
    required InsertPosition position,
    String? newParentId,
  }) {
    _mutate(MutationKind.reorder, () {
      final oldParentId = _tree[id]?.parentId;
      _tree.insertAt(
        id,
        newParentId: newParentId,
        referenceSiblingId: referenceSiblingId,
        position: position,
      );
      if (oldParentId != newParentId) {
        final newProjectId =
            newParentId == null ? null : _tree[newParentId]?.projectId;
        _tree.cascadeProjectId(id, newProjectId);
      }
    });
  }

  /// [id] 와 자손 전부 삭제(cascade). 삭제된 노드 수 반환.
  int deleteCascade(String id) {
    return _mutate(MutationKind.remove, () => _tree.deleteCascade(id));
  }

  /// [id] 만 삭제하고 자식을 조부모로 승격. 삭제된 노드 수(항상 1) 반환.
  int deletePromote(String id) {
    return _mutate(MutationKind.remove, () => _tree.deletePromote(id));
  }

  /// 데모용 샘플 트리 생성(기존 데이터는 덮어쓰지 않고, 비어있을 때만 채웅을 권장).
  /// 반환값: 생성된 루트 노드 id 들.
  List<String> createSampleData() {
    return _mutate(MutationKind.sample, () {
      final today = this.today;
      PlanDate d(int delta) => today.addDays(delta);
      // 샘플은 기존 프로젝트에 붙인다. 이름이 없으면 그때 만든다.
      // (시드가 이미 돌았으면 여기서 새로 만들 일은 없다)
      final workId = _projectIdByNameOrCreate('업무');
      final personalId = _projectIdByNameOrCreate('개인');
      // 루트 프로젝트 1: "PlanBook 앱 개발" (autoRollup)
      final root = addNode(
        title: 'PlanBook 앱 개발',
        projectId: workId,
        priority: Priority.high,
        autoRollup: true,
      );
      final sub1 = addNode(
        parentId: root.id,
        title: '1단계: 코어/저장소',
        projectId: workId,
        startDate: d(-2),
        endDate: d(10),
        autoRollup: true,
      );
      addNode(
        parentId: sub1.id,
        title: '날짜 처리 모듈 작성',
        projectId: workId,
        startDate: d(-2),
        endDate: d(0),
        progress: 1.0,
        status: TaskStatus.done,
        estimate: 3,
        autoRollup: false,
      );
      addNode(
        parentId: sub1.id,
        title: '저장소(JSON) 구현',
        projectId: workId,
        startDate: d(1),
        endDate: d(3),
        progress: 0.0,
        estimate: 3,
        autoRollup: false,
      );
      addNode(
        parentId: sub1.id,
        title: '트리 조작/rollup 단위 테스트',
        projectId: workId,
        startDate: d(2),
        endDate: d(5),
        progress: 0.3,
        estimate: 4,
        autoRollup: false,
      );
      final sub2 = addNode(
        parentId: root.id,
        title: '2단계: Gantt 렌더링',
        projectId: workId,
        startDate: d(11),
        endDate: d(25),
        autoRollup: true,
      );
      addNode(
        parentId: sub2.id,
        title: '타임라인 캔버스 구현',
        projectId: workId,
        startDate: d(11),
        endDate: d(16),
        estimate: 5,
        autoRollup: false,
      );
      final dragTask = addNode(
        parentId: sub2.id,
        title: 'Gantt bar 드래그 이동/리사이즈',
        projectId: workId,
        startDate: d(17),
        endDate: d(22),
        estimate: 5,
        autoRollup: false,
      );
      // 4단계 깊이 예시(3+ depth): 드래그 작업을 세분.
      addNode(
        parentId: dragTask.id,
        title: '좌우 드래그로 일정 이동',
        projectId: workId,
        startDate: d(17),
        endDate: d(19),
        estimate: 2,
        autoRollup: false,
      );
      addNode(
        parentId: dragTask.id,
        title: '양 끝 핸들로 시작/종료일 변경',
        projectId: workId,
        startDate: d(20),
        endDate: d(22),
        estimate: 3,
        autoRollup: false,
      );
      // 날짜 미정 노드 예시(렌더 안정성 확인용).
      addNode(
        parentId: sub2.id,
        title: '필터/일간뷰(3단계, 미정)',
        projectId: workId,
        autoRollup: false,
      );

      // 루트 프로젝트 2: "건강 관리"
      final root2 = addNode(
        title: '건강 관리',
        projectId: personalId,
        priority: Priority.medium,
        autoRollup: true,
      );
      addNode(
        parentId: root2.id,
        title: '주 3회 러닝',
        projectId: personalId,
        startDate: d(0),
        endDate: d(30),
        autoRollup: false,
      );
      addNode(
        parentId: root2.id,
        title: '정기 건강검진 예약',
        projectId: personalId,
        startDate: d(7),
        endDate: d(7),
        autoRollup: false,
      );

      return [root.id, root2.id];
    });
  }

  /// 전체 삭제.
  void clear() {
    _mutate(MutationKind.clear, () {
      _tree.clear();
    });
  }

  /// [snapshot] 으로 현재 상태를 **완전히 교체**한다(가져오기/Import).
  ///
  /// 호출 전에 UI 가 반드시 "덮어쓰기 확인"을 사용자에게 받아야 한다 — 이
  /// 메서드 자체는 확인 없이 즉시 교체한다. 저장은 기존 [repository] 를 그대로
  /// 통해서만 한다(별도 저장 경로를 만들지 않는다).
  Future<void> importSnapshot(PlanSnapshot snapshot) async {
    _mutate(MutationKind.clear, () {
      _tree.clear();
      for (final n in snapshot.nodes) {
        _tree.upsert(n);
      }
      _projects
        ..clear()
        ..addAll(snapshot.projects);
      _tags
        ..clear()
        ..addAll(snapshot.tags);
      _settings = snapshot.settings;
    });
    await flush();
  }
}

/// 하나의 undo 스텝. 트리 전체의 id→node 스냅샷 두 장(변경 전/후)만 들고 있는
/// 단순한 구조 — 연산 종류별로 역연산을 따로 구현하지 않는다(정확성 우선).
class _TreeUndoEntry {
  final Map<String, PlanNode> before;
  final Map<String, PlanNode> after;
  const _TreeUndoEntry({required this.before, required this.after});
}
