/// Today 화면 — 이 앱에서 가장 중요한 화면.
///
/// **별도 데이터를 저장하지 않는다.** 항상 [PlanStore] 의 Task 데이터에서
/// [PlanStore.today] 기준으로 실시간 계산한다([computeTodaySections]).
///
/// 부모 Goal 이름이 아니라 **가장 하위 수준의 실행 가능한 Task(leaf)** 를
/// 우선 표시하고, 소속을 알 수 있도록 breadcrumb(프로젝트 > 조상들)을 함께 보여준다.
library;

import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/plan_node.dart';
import '../../domain/recurrence.dart';
import '../../domain/reschedule.dart';
import '../../domain/today_query.dart';
import '../../domain/workload_query.dart';
import '../common/navigation.dart';
import '../common/task_row.dart';
import '../common/ymd_date_picker.dart';
import '../plan/node_edit_dialog.dart';
import '../settings/settings_page.dart';

class TodayPage extends StatefulWidget {
  final PlanStore store;
  final OpenInGantt? onOpenInGantt;

  const TodayPage({super.key, required this.store, this.onOpenInGantt});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  PlanStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    if (!_store.isLoaded) _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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

  void _openInGantt(String nodeId) {
    widget.onOpenInGantt?.call(focusNodeId: nodeId);
  }

  /// [node] 의 소속(프로젝트 이름) + 조상 제목들을 root→parent 순서로.
  List<String> _breadcrumb(PlanNode node) {
    final out = <String>[];
    final project = _store.projectById(node.projectId);
    if (project != null) out.add(project.name);
    // ancestorsOf 는 가까운 조상부터 반환하므로 뒤집어서 root→parent 순서로.
    out.addAll(_store.tree.ancestorsOf(node.id).reversed.map((a) => a.title));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (!_store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final today = _store.today;
    final sections = computeTodaySections(_store.tree, today);
    final recurring = recurringOccurrencesOn(_store.tree, today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsPage(store: _store)),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_formatKoreanDate(today),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (sections.isEmpty && recurring.isEmpty) _allDoneCard(context),
            _recurringSection(context, recurring, today),
            _section(
              context,
              title: '오늘 진행할 작업',
              icon: Icons.play_circle_outline,
              items: sections.inProgress,
              emptyHint: null,
            ),
            _section(
              context,
              title: '오늘 마감',
              icon: Icons.flag_outlined,
              items: sections.dueToday,
              emptyHint: null,
              accentColor: Theme.of(context).colorScheme.tertiary,
            ),
            _section(
              context,
              title: '지연',
              icon: Icons.warning_amber_outlined,
              items: sections.overdue,
              emptyHint: null,
              accentColor: Theme.of(context).colorScheme.error,
              subtitleBuilder: (n) =>
                  '${overdueDays(n, today)}일 지연',
              allowReschedule: true,
            ),
            _upcomingSection(context, sections.upcoming, today),
          ],
        ),
      ),
    );
  }

  Widget _allDoneCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.celebration_outlined),
            SizedBox(width: 12),
            Expanded(child: Text('오늘 할 일이 모두 정리되었습니다.')),
          ],
        ),
      ),
    );
  }

  /// [n] 이 수량형/시간형이면 "오늘 20page" 같은 권장량 문구, 아니면 null
  /// (null 이면 호출부가 기존 subtitle/날짜범위로 대체한다).
  String? _workloadSubtitle(PlanNode n) {
    final plan = computeWorkloadPlan(n, _store.today);
    if (plan == null) return null;
    return workloadSummaryLabel(plan, n.unit);
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<PlanNode> items,
    required String? emptyHint,
    Color? accentColor,
    String Function(PlanNode)? subtitleBuilder,
    bool allowReschedule = false,
  }) {
    if (items.isEmpty && emptyHint == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accentColor ?? scheme.primary),
              const SizedBox(width: 6),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: accentColor)),
              const SizedBox(width: 6),
              Text('${items.length}', style: TextStyle(color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 4),
          for (final n in items)
            TaskRow(
              node: n,
              breadcrumb: _breadcrumb(n),
              // 수량형/시간형 Task 는 날짜 범위 대신 오늘 권장량을 보여준다
              // (예: "오늘 20page") — 그 외에는 기존 subtitleBuilder(지연일수 등).
              subtitle: _workloadSubtitle(n) ?? subtitleBuilder?.call(n),
              onToggleDone: () => _store.setNodeDone(n.id, !n.isDone),
              onTap: () => _editNode(n),
              onOpenInGantt:
                  widget.onOpenInGantt == null ? null : () => _openInGantt(n.id),
              onReschedule: allowReschedule ? () => _showRescheduleMenu(n) : null,
            ),
        ],
      ),
    );
  }

  /// 일정 재분배 옵션 메뉴. **사용자가 여기서 직접 옵션을 고를 때만** 실제
  /// 날짜가 바뀐다 — 앱이 알아서 자동으로 재조정하는 경우는 없다.
  Future<void> _showRescheduleMenu(PlanNode node) async {
    final option = await showModalBottomSheet<RescheduleOption>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('"${node.title}" 일정 재조정',
                  style: Theme.of(ctx).textTheme.titleSmall),
            ),
            for (final opt in RescheduleOption.values)
              ListTile(
                title: Text(opt.label),
                onTap: () => Navigator.of(ctx).pop(opt),
              ),
          ],
        ),
      ),
    );
    if (option == null || option == RescheduleOption.keepAsIs) return;

    if (option == RescheduleOption.specificDate) {
      if (!mounted) return;
      final picked = await showYmdDatePicker(
        context,
        initialDate: _store.today.toDateTime(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      _store.rescheduleNode(node.id, option,
          specificDate: PlanDate.fromDateTime(picked));
      return;
    }
    _store.rescheduleNode(node.id, option);
  }

  /// 반복형(daily/weekly/monthly) Task 중 오늘 occurrence 가 있는 것들.
  /// 완료 체크는 [PlanStore.setRecurrenceOccurrenceDone] 으로 **오늘 날짜에만**
  /// 기록된다 — 원본 노드의 status 는 바뀌지 않으므로 다른 날짜의 occurrence
  /// 에는 영향이 없다.
  Widget _recurringSection(
      BuildContext context, List<PlanNode> items, PlanDate today) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('오늘의 반복 작업', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 6),
              Text('${items.length}', style: TextStyle(color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 4),
          for (final n in items)
            TaskRow(
              node: n,
              breadcrumb: _breadcrumb(n),
              subtitle: n.recurrenceRule == null
                  ? null
                  : recurrenceRuleLabel(n.recurrenceRule!),
              doneOverride: isOccurrenceDone(n, today),
              onToggleDone: () => _store.setRecurrenceOccurrenceDone(
                  n.id, today, !isOccurrenceDone(n, today)),
              onTap: () => _editNode(n),
              onOpenInGantt:
                  widget.onOpenInGantt == null ? null : () => _openInGantt(n.id),
            ),
        ],
      ),
    );
  }

  Widget _upcomingSection(
      BuildContext context, List<PlanNode> items, PlanDate today) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upcoming_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('다가오는 작업', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          for (final n in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 44,
                child: Text(
                  n.startDate != null ? '${n.startDate!.month}/${n.startDate!.day}' : '',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
              title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _editNode(n),
              trailing: widget.onOpenInGantt == null
                  ? null
                  : IconButton(
                      iconSize: 18,
                      tooltip: 'Gantt 에서 보기',
                      icon: const Icon(Icons.view_timeline_outlined),
                      onPressed: () => _openInGantt(n.id),
                    ),
            ),
        ],
      ),
    );
  }
}

String _formatKoreanDate(PlanDate d) => '${d.year}년 ${d.month}월 ${d.day}일';
