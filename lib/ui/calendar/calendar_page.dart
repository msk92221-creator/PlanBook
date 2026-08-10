/// Calendar 화면 — 월간 달력.
///
/// Gantt 와 **동일한 Task 데이터**를 쓴다(화면별 복제 저장 없음). 날짜별 Task
/// 조회는 `domain/calendar_query.dart`(overlap 기준 — [nodeTouchesDate])를 그대로
/// 쓰고, 필터는 Phase 1 의 [PlanFilterState]/[matchesFilter] 를 재사용한다
/// ("Calendar 용으로 새로 작성하지 말 것" 요구사항).
library;

import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/calendar_query.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_filter.dart';
import '../../domain/plan_node.dart';
import '../../domain/recurrence.dart';
import '../common/navigation.dart';
import '../common/task_row.dart';
import '../filter/filter_bar.dart';
import '../plan/gantt_theme.dart';
import '../plan/node_edit_dialog.dart';

class CalendarPage extends StatefulWidget {
  final PlanStore store;
  final OpenInGantt? onOpenInGantt;

  const CalendarPage({super.key, required this.store, this.onOpenInGantt});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  PlanStore get _store => widget.store;

  late PlanDate _visibleMonth; // 그 달의 임의의 날짜(보통 1일)로 표현.
  PlanDate? _selected;
  PlanFilterState _filter = PlanFilterState.empty;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.isLoaded) _store.load();
    final today = _store.today;
    _visibleMonth = startOfMonth(today);
    _selected = today;
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _goToMonth(int deltaMonths) {
    setState(() {
      final y = _visibleMonth.year;
      final m = _visibleMonth.month + deltaMonths;
      final ny = y + ((m - 1) ~/ 12) + (((m - 1) % 12 < 0) ? -1 : 0);
      final nm = ((m - 1) % 12 + 12) % 12 + 1;
      _visibleMonth = PlanDate(ny, nm, 1);
    });
  }

  void _goToToday() {
    final today = _store.today;
    setState(() {
      _visibleMonth = startOfMonth(today);
      _selected = today;
    });
  }

  Future<void> _editNode(PlanNode node) async {
    final result = await showNodeEditDialog(
      context,
      tree: _store.tree,
      node: node,
      store: _store,
    );
    if (result == null) return;
    commitNodeEdit(_store, node, result);
  }

  List<String> _breadcrumb(PlanNode node) {
    final out = <String>[];
    final project = _store.projectById(node.projectId);
    if (project != null) out.add(project.name);
    out.addAll(_store.tree.ancestorsOf(node.id).reversed.map((a) => a.title));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (!_store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final weekStart = _store.settings.weekStart;
    final gridDays = monthGridDays(_visibleMonth, weekStart);
    final today = _store.today;

    // 필터를 적용한 뒤 날짜별로 버킷을 만든다 — Calendar 전용 로직을 새로
    // 작성하지 않고 Phase1 의 matchesFilter 를 그대로 재사용한다.
    final visibleTree = _store.tree;
    bool passesFilter(PlanNode n) => _filter.isEmpty ||
        matchesFilter(n, _filter, today: today, weekStartWeekday: weekStart);
    final buckets = <String, List<PlanNode>>{};
    for (final entry
        in calendarBuckets(visibleTree, gridDays, leafOnly: false).entries) {
      final filtered = entry.value.where(passesFilter).toList();
      if (filtered.isNotEmpty) buckets[entry.key] = filtered;
    }

    final selectedItems = _selected == null
        ? const <PlanNode>[]
        : (buckets[_selected!.toIso()] ?? const <PlanNode>[]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('달력'),
        actions: [
          IconButton(
            tooltip: '이전 달',
            onPressed: () => _goToMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: _goToToday,
            child: Text('${_visibleMonth.year}년 ${_visibleMonth.month}월'),
          ),
          IconButton(
            tooltip: '다음 달',
            onPressed: () => _goToMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kTwoPaneBreakpoint;
          final grid = _MonthGrid(
            gridDays: gridDays,
            visibleMonth: _visibleMonth,
            today: today,
            selected: _selected,
            buckets: buckets,
            weekStartWeekday: weekStart,
            onSelect: (d) => setState(() => _selected = d),
          );
          final panel = _SelectedDayPanel(
            date: _selected,
            items: selectedItems,
            breadcrumbFor: _breadcrumb,
            onToggleDone: (n) {
              final d = _selected ?? today;
              if (n.nodeKind == NodeKind.recurring) {
                _store.setRecurrenceOccurrenceDone(
                    n.id, d, !isOccurrenceDone(n, d));
              } else {
                _store.setNodeDone(n.id, !n.isDone);
              }
            },
            onTap: _editNode,
            onOpenInGantt: widget.onOpenInGantt == null
                ? null
                : (n) => widget.onOpenInGantt!(focusNodeId: n.id),
          );

          final filterBar = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: FilterBar(
              store: _store,
              value: _filter,
              compact: !wide,
              onChanged: (f) => setState(() => _filter = f),
            ),
          );

          if (wide) {
            return Column(
              children: [
                filterBar,
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: grid),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 320, child: panel),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              filterBar,
              Expanded(flex: 5, child: grid),
              const Divider(height: 1),
              Expanded(flex: 4, child: panel),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 월 그리드
// ---------------------------------------------------------------------------

class _MonthGrid extends StatelessWidget {
  final List<PlanDate> gridDays;
  final PlanDate visibleMonth;
  final PlanDate today;
  final PlanDate? selected;
  final Map<String, List<PlanNode>> buckets;
  final int weekStartWeekday;
  final ValueChanged<PlanDate> onSelect;

  const _MonthGrid({
    required this.gridDays,
    required this.visibleMonth,
    required this.today,
    required this.selected,
    required this.buckets,
    required this.weekStartWeekday,
    required this.onSelect,
  });

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // weekStartWeekday(1=월..7=일) 를 기준으로 라벨을 회전.
    final offset = weekStartWeekday - DateTime.monday;
    final labels = [
      for (var i = 0; i < 7; i++) _weekdayLabels[(i + offset) % 7],
    ];
    return Column(
      children: [
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(l,
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                ),
              ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: gridDays.length,
            itemBuilder: (context, i) {
              final d = gridDays[i];
              final inMonth = d.month == visibleMonth.month;
              final isToday = d == today;
              final isSelected = d == selected;
              final items = buckets[d.toIso()] ?? const <PlanNode>[];
              return _DayCell(
                date: d,
                inMonth: inMonth,
                isToday: isToday,
                isSelected: isSelected,
                items: items,
                onTap: () => onSelect(d),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final PlanDate date;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<PlanNode> items;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.onTap,
  });

  static const int _maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = items.length > _maxShown ? items.sublist(0, _maxShown) : items;
    final overflow = items.length - shown.length;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 0.5,
          ),
          borderRadius: BorderRadius.circular(4),
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday
                        ? scheme.onPrimary
                        : inMonth
                            ? scheme.onSurface
                            : scheme.outline,
                  ),
                ),
              ),
            ),
            for (final n in shown)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: (n.isMilestone
                          ? scheme.tertiary
                          : ((n.nodeKind == NodeKind.recurring
                                  ? isOccurrenceDone(n, date)
                                  : n.isDone)
                              ? scheme.outline
                              : scheme.primary))
                      .withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
                width: double.infinity,
                child: Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            if (overflow > 0)
              Text('+$overflow', style: TextStyle(fontSize: 9, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 선택일 패널
// ---------------------------------------------------------------------------

class _SelectedDayPanel extends StatelessWidget {
  final PlanDate? date;
  final List<PlanNode> items;
  final List<String> Function(PlanNode) breadcrumbFor;
  final void Function(PlanNode) onToggleDone;
  final void Function(PlanNode) onTap;
  final void Function(PlanNode)? onOpenInGantt;

  const _SelectedDayPanel({
    required this.date,
    required this.items,
    required this.breadcrumbFor,
    required this.onToggleDone,
    required this.onTap,
    this.onOpenInGantt,
  });

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return const Center(child: Text('날짜를 선택하세요'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('${date!.year}년 ${date!.month}월 ${date!.day}일',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('이 날짜에 해당하는 작업이 없습니다.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          )
        else
          for (final n in items)
            TaskRow(
              node: n,
              breadcrumb: breadcrumbFor(n),
              subtitle: n.nodeKind == NodeKind.recurring && n.recurrenceRule != null
                  ? recurrenceRuleLabel(n.recurrenceRule!)
                  : null,
              doneOverride: n.nodeKind == NodeKind.recurring && date != null
                  ? isOccurrenceDone(n, date!)
                  : null,
              onToggleDone: () => onToggleDone(n),
              onTap: () => onTap(n),
              onOpenInGantt: onOpenInGantt == null ? null : () => onOpenInGantt!(n),
            ),
      ],
    );
  }
}
