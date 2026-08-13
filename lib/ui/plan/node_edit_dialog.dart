/// 노드 편집 다이얼로그 (3단계, 4단계에서 Project/Tag 선택기 추가).
///
/// 편집 가능 필드(DESIGN.md §2.1 참고):
/// - 제목, 시작일, 종료일, 진행률, 상태(4단계), 우선순위, 소속 프로젝트, 태그,
///   마일스톤 여부, 메모, 예상 작업량(estimate), 실제 작업량(actual), autoRollup 여부
///
/// 정책:
/// - **시작일 > 종료일 입력은 자동 보정**: 종료일을 시작일로 당긴다
///   (end = start, 1일 기간). 사용자가 end 를 start 이전으로 고르면 즉시 보정.
/// - 날짜는 "지우기(null)" 도 가능. 둘 다 null 이면 기간 없음.
/// - autoRollup 이 켜진 노드는 자식이 있을 때 기간/진행률이 계산값으로 표시되므로,
///   다이얼로그에서 해당 필드가 "자식 요약으로 덮어씌워짐" 임을 안내한다.
/// - **Project 선택**: [PlanStore.projects] 기반. "미분류" 선택 가능(projectId=null).
///   보관(archived)된 프로젝트는 선택 목록에서 숨기되, 현재 노드가 이미 그 프로젝트에
///   속해 있으면 선택값이 사라지지 않도록 목록에 포함한다.
/// - **Tag 선택**: [PlanStore.tags] 기반 복수 선택(칩 토글). 태그 **이름**이 아니라
///   **id** 를 [PlanNode.tagIds] 에 저장한다(이름을 노드에 직접 저장하지 않는다).
///
/// 모든 커밋은 호출자가 [PlanStore.updateNode] 단일 경로로 보내도록 결과만 반환한다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/bar_color.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_node.dart';
import '../../domain/plan_rollup.dart';
import '../../domain/plan_tree.dart';
import '../../domain/project.dart';
import '../../domain/recurrence.dart';
import '../../domain/tag.dart';
import '../common/ymd_date_picker.dart';
import 'gantt_theme.dart';

/// 편집 다이얼로그가 반환할 변경 결과. null 은 "취소".
class NodeEditResult {
  final String title;

  /// 새 부모 id(null=최상위). **[applyTo] 는 이 값을 반영하지 않는다** — 부모
  /// 변경은 sortOrder 재색인/Project 전파가 필요해 [PlanTree.move] 를 거쳐야
  /// 하기 때문이다. 반드시 [commitNodeEdit] 로 커밋할 것(직접 copyWith 금지).
  final String? newParentId;

  final PlanDate? startDate;
  final PlanDate? endDate;
  final double progress;
  final TaskStatus status;
  final Priority priority;
  final bool isMilestone;
  final String? projectId;
  final List<String> tagIds;
  final String? memo;
  final num? estimate;
  final num? actual;
  final String? unit;
  final NodeKind nodeKind;
  final bool autoRollup;

  /// Gantt 막대 색(고정 팔레트). [BarColor.none] 이면 "색 지정 안 함".
  final BarColor barColor;

  /// [nodeKind]==recurring 일 때만 의미 있음. 그 외에는 항상 null/빈 값으로
  /// 저장되어(policy) 다른 유형으로 바꿨다가 되돌려도 예전 규칙이 유령처럼
  /// 남지 않는다.
  final RecurrenceRule? recurrenceRule;

  const NodeEditResult({
    required this.title,
    required this.newParentId,
    required this.startDate,
    required this.endDate,
    required this.progress,
    required this.status,
    required this.priority,
    required this.isMilestone,
    required this.projectId,
    required this.tagIds,
    required this.memo,
    required this.estimate,
    required this.actual,
    this.unit,
    this.nodeKind = NodeKind.project,
    required this.autoRollup,
    this.barColor = BarColor.none,
    this.recurrenceRule,
  });

  /// [PlanNode] 에 결과를 적용한 새 인스턴스. **parentId 는 반영하지 않는다**
  /// (원본 id/parentId/sortOrder 유지) — 부모 변경은 [commitNodeEdit] 참고.
  PlanNode applyTo(PlanNode src) {
    return src.copyWith(
      title: title,
      startDate: startDate,
      endDate: endDate,
      progress: progress,
      status: status,
      priority: priority,
      isMilestone: isMilestone,
      projectId: projectId,
      tagIds: List<String>.unmodifiable(tagIds),
      memo: memo,
      estimate: estimate,
      actual: actual,
      unit: unit,
      nodeKind: nodeKind,
      autoRollup: autoRollup,
      barColor: barColor,
      recurrenceFreq: nodeKind == NodeKind.recurring
          ? recurrenceRule?.freq.name
          : null,
      recurrenceWeekdays: nodeKind == NodeKind.recurring
          ? List<int>.unmodifiable(recurrenceRule?.weekdays ?? const <int>[])
          : const <int>[],
      recurrenceDayOfMonth: nodeKind == NodeKind.recurring
          ? recurrenceRule?.dayOfMonth
          : null,
    );
  }
}

/// [showNodeEditDialog] 결과를 [store] 에 커밋하는 **단일 경로**.
///
/// 모든 호출부가 이 함수 하나로 커밋해서, "필드 변경은 updateNode, 부모 변경은
/// moveNode" 를 매번 따로 챙기지 않게 한다. 부모가 바뀐 경우 [PlanStore.moveNode]
/// 를 거치므로 sortOrder 재색인과 Project 전파(자손 projectId cascade, cycle
/// 검사)가 자동으로 함께 적용된다.
void commitNodeEdit(PlanStore store, PlanNode node, NodeEditResult result) {
  store.updateNode(node.id, (cur) => result.applyTo(cur));
  if (result.newParentId != node.parentId) {
    store.moveNode(node.id, result.newParentId);
  }
}

/// 노드 편집 다이얼로그를 띄우고 결과를 받는다. 취소 시 null 반환.
///
/// [store] 는 Project/Tag 선택기 목록을 읽는 데만 쓴다(저장은 호출자가
/// [PlanStore.updateNode] 로 한다 — 이 다이얼로그는 store 를 직접 변경하지 않는다).
Future<NodeEditResult?> showNodeEditDialog(
  BuildContext context, {
  required PlanTree tree,
  required PlanNode node,
  required PlanStore store,
}) {
  return showDialog<NodeEditResult>(
    context: context,
    builder: (ctx) => NodeEditDialog(tree: tree, node: node, store: store),
  );
}

class NodeEditDialog extends StatefulWidget {
  final PlanTree tree;
  final PlanNode node;
  final PlanStore store;

  const NodeEditDialog({
    super.key,
    required this.tree,
    required this.node,
    required this.store,
  });

  @override
  State<NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<NodeEditDialog> {
  late final TextEditingController _titleCtrl;
    late final TextEditingController _memoCtrl;
  late final TextEditingController _estimateCtrl;
  late final TextEditingController _actualCtrl;
  late final TextEditingController _unitCtrl;

  late PlanDate? _start;
  late PlanDate? _end;
  late double _progress;
  late TaskStatus _status;
  late bool _isMilestone;
  late Priority _priority;
  late bool _autoRollup;
  late NodeKind _nodeKind;
  late String? _projectId;
  late Set<String> _tagIds;
  late String? _parentId;
  late BarColor _barColor;
  late RecurrenceFreq _recurrenceFreq;
  late Set<int> _recurrenceWeekdays;
  late TextEditingController _recurrenceDayOfMonthCtrl;

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _titleCtrl = TextEditingController(text: n.title);
        _memoCtrl = TextEditingController(text: n.memo ?? '');
    _estimateCtrl = TextEditingController(text: _numToText(n.estimate));
    _actualCtrl = TextEditingController(text: _numToText(n.actual));
    _unitCtrl = TextEditingController(text: n.unit ?? '');
    _nodeKind = n.nodeKind;
    final rule = n.recurrenceRule;
    _recurrenceFreq = rule?.freq ?? RecurrenceFreq.daily;
    _recurrenceWeekdays = rule?.weekdays.toSet() ?? <int>{};
    _recurrenceDayOfMonthCtrl =
        TextEditingController(text: '${rule?.dayOfMonth ?? 1}');
    _start = n.startDate;
    _end = n.endDate;
    _progress = n.clampedProgress;
    _status = n.status;
    _isMilestone = n.isMilestone;
    _priority = n.priority;
    _autoRollup = n.autoRollup;
    _projectId = n.projectId;
    _tagIds = n.tagIds.toSet();
    _parentId = n.parentId;
    _barColor = n.barColor;
  }

  /// 선택 가능한 프로젝트 목록. 보관(archived)된 프로젝트는 숨기되, 현재 선택값이
  /// 보관 프로젝트를 가리키면 목록에서 사라지지 않도록 포함한다.
  List<Project> _selectableProjects() {
    final all = widget.store.projects;
    final visible = all.where((p) => !p.isArchived).toList();
    final current = _projectId;
    if (current != null && !visible.any((p) => p.id == current)) {
      final archived = widget.store.projectById(current);
      if (archived != null) visible.add(archived);
    }
    return visible;
  }

  /// 선택 가능한 부모 후보. **자기 자신/자손은 제외**한다(순환 방지 —
  /// [PlanTree.wouldCreateCycle] 을 그대로 재사용). 각 후보는 breadcrumb 형태로
  /// 표시해 이름이 같은 노드끼리 구분한다.
  List<({String id, String label})> _selectableParents() {
    final out = <({String id, String label})>[];
    for (final n in widget.tree.allNodes) {
      if (n.id == widget.node.id) continue;
      if (widget.tree.wouldCreateCycle(widget.node.id, n.id)) continue;
      final chain = [
        ...widget.tree.ancestorsOf(n.id).reversed.map((a) => a.title),
        n.title.isEmpty ? '(제목 없음)' : n.title,
      ];
      out.add((id: n.id, label: chain.join(' > ')));
    }
    out.sort((a, b) => a.label.compareTo(b.label));
    return out;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _memoCtrl.dispose();
    _estimateCtrl.dispose();
    _actualCtrl.dispose();
    _unitCtrl.dispose();
    _recurrenceDayOfMonthCtrl.dispose();
    super.dispose();
  }

  String _numToText(num? v) => v == null ? '' : v.toString();

  /// 시작일 > 종료일 이면 종료일을 시작일로 보정(정책: 종료일을 당김).
  void _enforceOrder() {
    if (_start != null && _end != null && daysBetween(_start!, _end!) < 0) {
      _end = _start;
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = (isStart ? _start : _end)?.toDateTime() ??
        DateTime(now.year, now.month, now.day);
    final picked = await showYmdDatePicker(
      context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = PlanDate.fromDateTime(picked);
      } else {
        _end = PlanDate.fromDateTime(picked);
      }
      _enforceOrder();
    });
  }

  void _clearDate(bool isStart) {
    setState(() {
      if (isStart) {
        _start = null;
      } else {
        _end = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final rollup = computeRollup(widget.tree, n.id);
    final isRollupSummary = rollup.computedFromChildren;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('항목 편집'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 제목
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '제목',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // 날짜 행
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '시작일',
                      date: _start,
                      onPick: () => _pickDate(true),
                      onClear: () => _clearDate(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('~'),
                  ),
                  Expanded(
                    child: _DateField(
                      label: '종료일',
                      date: _end,
                      onPick: () => _pickDate(false),
                      onClear: () => _clearDate(false),
                    ),
                  ),
                ],
              ),
              if (isRollupSummary)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '※ 자식 항목이 있어 autoRollup 켜짐 — 진행률/완료는 자식들로부터 '
                    '자동 계산됩니다. 위 날짜는 그대로 입력할 수 있고, 화면에는 '
                    '자식 전체 기간과 합쳐진(더 넓은) 기간이 표시됩니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // 진행률 + 완료
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('진행률: ${(_progress * 100).round()}%',
                            style: Theme.of(context).textTheme.labelMedium),
                        Slider(
                          value: _progress,
                          min: 0,
                          max: 1,
                          divisions: 100,
                          onChanged: isRollupSummary
                              ? null
                              : (v) => setState(() => _progress = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<TaskStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: '상태',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in TaskStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: isRollupSummary
                          ? null
                          : (v) => setState(
                              () => _status = v ?? TaskStatus.notStarted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 우선순위 + autoRollup
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Priority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: '우선순위',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in Priority.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? Priority.none),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('자동 요약', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('autoRollup',
                          style: TextStyle(fontSize: 10)),
                      value: _autoRollup,
                      onChanged: (v) => setState(() => _autoRollup = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 마일스톤
              SwitchListTile(
                title: const Text('마일스톤', style: TextStyle(fontSize: 13)),
                subtitle: const Text('간트에서 마름모로 표시',
                    style: TextStyle(fontSize: 10)),
                value: _isMilestone,
                onChanged: (v) => setState(() => _isMilestone = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              // 상위 목표(부모). 자기 자신/자손은 후보에서 제외되어 순환이
              // 구조적으로 불가능하다([_selectableParents] 참고).
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: const InputDecoration(
                  labelText: '상위 목표',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('없음(최상위)'),
                  ),
                  for (final p in _selectableParents())
                    DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _parentId = v),
              ),
              const SizedBox(height: 8),
              // 소속 프로젝트.
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                decoration: const InputDecoration(
                  labelText: '프로젝트',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('미분류'),
                  ),
                  for (final p in _selectableProjects())
                    DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.isArchived ? '${p.name} (보관됨)' : p.name),
                    ),
                ],
                onChanged: (v) => setState(() => _projectId = v),
              ),
              const SizedBox(height: 8),
              // 태그(복수 선택). 이름이 아니라 id 를 저장한다.
              _TagPicker(
                allTags: widget.store.tags,
                selected: _tagIds,
                onToggle: (id) => setState(() {
                  if (_tagIds.contains(id)) {
                    _tagIds.remove(id);
                  } else {
                    _tagIds.add(id);
                  }
                }),
              ),
              const SizedBox(height: 8),
              // 작업 유형(일반/수량형/시간형). 수량형·시간형을 고르면
              // estimate/actual 이 "목표량/완료량" 으로 재해석되어 Today 화면에
              // 일일 권장량이 자동 계산돼 표시된다(workload_query.dart).
              DropdownButtonFormField<NodeKind>(
                initialValue: _nodeKind,
                decoration: const InputDecoration(
                  labelText: '작업 유형',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in NodeKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _nodeKind = v ?? NodeKind.project),
              ),
              const SizedBox(height: 8),
              if (_nodeKind == NodeKind.quantity || _nodeKind == NodeKind.effort) ...[
                // estimate / actual — 작업 유형에 따라 라벨이 바뀐다.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _estimateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '목표량',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _actualCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '완료량',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _unitCtrl,
                        decoration: const InputDecoration(
                          labelText: '단위',
                          hintText: 'page, 시간...',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '종료일까지 남은 기간을 기준으로 Today 에 오늘 권장량이 자동 표시됩니다.',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ),
              ] else if (_nodeKind == NodeKind.project) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _estimateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '예상 작업량',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _actualCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '실제 작업량',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_nodeKind == NodeKind.recurring)
                _RecurrenceRuleEditor(
                  freq: _recurrenceFreq,
                  weekdays: _recurrenceWeekdays,
                  dayOfMonthCtrl: _recurrenceDayOfMonthCtrl,
                  onFreqChanged: (f) => setState(() => _recurrenceFreq = f),
                  onWeekdayToggle: (wd) => setState(() {
                    if (_recurrenceWeekdays.contains(wd)) {
                      _recurrenceWeekdays.remove(wd);
                    } else {
                      _recurrenceWeekdays.add(wd);
                    }
                  }),
                ),
              const SizedBox(height: 8),
              // 메모
              TextField(
                controller: _memoCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '메모',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              // 막대 색 선택. 드롭다운보다 색 견본을 직접 보고 고르는 편이 낫다.
              //
              // **폼 맨 끝에 두는 이유**: 중간에 끼워 넣으면 아래쪽 필드(상위 목표
              // 드롭다운 등)가 그만큼 밀려 내려가, 800x600 테스트 화면에서 화면 밖으로
              // 나가 hit test 가 실패한다(실제로 기존 테스트가 그렇게 깨졌다).
              // 맨 끝에 붙이면 기존 필드의 위치가 전혀 바뀌지 않는다.
              _BarColorPicker(
                selected: _barColor,
                onSelect: (c) => setState(() => _barColor = c),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _onCommit,
          child: const Text('저장'),
        ),
      ],
    );
  }

  void _onCommit() {
    num? parseNum(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return num.tryParse(t);
    }

    Navigator.of(context).pop(NodeEditResult(
      title: _titleCtrl.text.trim().isEmpty
          ? '(제목 없음)'
          : _titleCtrl.text.trim(),
      newParentId: _parentId,
      startDate: _start,
      endDate: _end,
      progress: _progress,
      status: _status,
      priority: _priority,
      isMilestone: _isMilestone,
      projectId: _projectId,
      tagIds: _tagIds.toList(growable: false),
      memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim(),
      estimate: parseNum(_estimateCtrl.text),
      actual: parseNum(_actualCtrl.text),
      unit: _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim(),
      nodeKind: _nodeKind,
      autoRollup: _autoRollup,
      barColor: _barColor,
      recurrenceRule: _nodeKind == NodeKind.recurring
          ? RecurrenceRule(
              freq: _recurrenceFreq,
              weekdays: _recurrenceWeekdays,
              dayOfMonth: int.tryParse(_recurrenceDayOfMonthCtrl.text.trim()) ?? 1,
            )
          : null,
    ));
  }
}

// ---------------------------------------------------------------------------
// 반복 규칙 편집기(daily/weekly-요일선택/monthly-일자)
// ---------------------------------------------------------------------------

const List<({int weekday, String label})> _kWeekdayLabels = [
  (weekday: DateTime.monday, label: '월'),
  (weekday: DateTime.tuesday, label: '화'),
  (weekday: DateTime.wednesday, label: '수'),
  (weekday: DateTime.thursday, label: '목'),
  (weekday: DateTime.friday, label: '금'),
  (weekday: DateTime.saturday, label: '토'),
  (weekday: DateTime.sunday, label: '일'),
];

class _RecurrenceRuleEditor extends StatelessWidget {
  final RecurrenceFreq freq;
  final Set<int> weekdays;
  final TextEditingController dayOfMonthCtrl;
  final ValueChanged<RecurrenceFreq> onFreqChanged;
  final ValueChanged<int> onWeekdayToggle;

  const _RecurrenceRuleEditor({
    required this.freq,
    required this.weekdays,
    required this.dayOfMonthCtrl,
    required this.onFreqChanged,
    required this.onWeekdayToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('반복 규칙', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        DropdownButtonFormField<RecurrenceFreq>(
          initialValue: freq,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final f in RecurrenceFreq.values)
              DropdownMenuItem(value: f, child: Text(f.label)),
          ],
          onChanged: (v) => onFreqChanged(v ?? RecurrenceFreq.daily),
        ),
        const SizedBox(height: 8),
        if (freq == RecurrenceFreq.weekly)
          Wrap(
            spacing: 4,
            children: [
              for (final w in _kWeekdayLabels)
                FilterChip(
                  label: Text(w.label),
                  selected: weekdays.contains(w.weekday),
                  onSelected: (_) => onWeekdayToggle(w.weekday),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        if (freq == RecurrenceFreq.monthly)
          SizedBox(
            width: 120,
            child: TextField(
              controller: dayOfMonthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '매월 며칠',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Today/Calendar 에서 해당 요일/일자에 자동으로 표시되며, '
            '완료 체크는 각 날짜별로 따로 기록됩니다(하루를 완료해도 다른 날짜는 그대로).',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 태그 복수 선택(칩 토글)
// ---------------------------------------------------------------------------

/// [PlanStore.tags] 기반 복수 선택 위젯. 이름이 아니라 id 를 넘긴다.
class _TagPicker extends StatelessWidget {
  final List<Tag> allTags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _TagPicker({
    required this.allTags,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('태그', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          if (allTags.isEmpty)
            Text(
              '등록된 태그가 없습니다.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in allTags)
                  FilterChip(
                    label: Text(t.name),
                    selected: selected.contains(t.id),
                    onSelected: (_) => onToggle(t.id),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 막대 색 견본 선택(동그란 swatch 가로 배열)
// ---------------------------------------------------------------------------

/// 막대 색을 8개(없음 + 7색) 동그란 견본으로 보여주고 탭해 고른다.
/// 색상 상수는 gantt_theme.dart 의 [barColorOf] 에 모아뒀으므로 여기서는 매핑을
/// 새로 두지 않고 그 헬퍼를 재사용한다.
class _BarColorPicker extends StatelessWidget {
  final BarColor selected;
  final ValueChanged<BarColor> onSelect;

  const _BarColorPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('막대 색', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final c in BarColor.values)
                _swatch(context, c, scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatch(BuildContext context, BarColor c, ColorScheme scheme) {
    final isSelected = c == selected;
    // '없음' 은 색이 아니므로 빈 원 + 회색 테두리 + 사선으로 "지정 안 함"을 드러낸다.
    // 나머지는 [barColorOf] 로 매핑한 실제 색으로 채운다.
    final fill = barColorOf(context, c);
    final none = c == BarColor.none;
    return Semantics(
      label: c.label,
      button: true,
      selected: isSelected,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelect(c),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(
              // 선택된 견본은 외곽선을 두껍게/강조 색으로 둘러 선택 상태를 명확히 한다.
              color: isSelected
                  ? scheme.primary
                  : (none ? scheme.outline : scheme.outlineVariant),
              width: isSelected ? 3 : 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // '없음' 견본: 사선(/) 표시.
              if (none)
                Transform.rotate(
                  angle: -math.pi / 4,
                  child: Container(
                    width: 22,
                    height: 1.6,
                    color: scheme.outline,
                  ),
                ),
              // 선택된 견본: 체크 표시(없음은 사선 위에 겹치지 않도록 생략).
              if (isSelected && !none)
                Icon(
                  Icons.check,
                  size: 16,
                  color: onCustomBarTextColor(context, c) ?? scheme.onPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 날짜 필드 (선택/지우기)
// ---------------------------------------------------------------------------

class _DateField extends StatelessWidget {
  final String label;
  final PlanDate? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateField({
    required this.label,
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: date == null
              ? null
              : IconButton(
                  tooltip: '날짜 지우기',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          date?.toIso() ?? '미정',
          style: TextStyle(
            fontSize: 13,
            color: date == null
                ? Theme.of(context).hintColor
                : Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}
