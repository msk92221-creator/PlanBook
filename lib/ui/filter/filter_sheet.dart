/// 고급 필터 편집 바텀시트. 좁은 화면([FilterBar.compact]) 에서는 이게
/// 필터를 조작하는 유일한 진입점이고, 넓은 화면에서는 커스텀 기간 지정 등
/// 상단 바에 없는 항목을 위한 보조 진입점이다.
library;

import 'package:flutter/material.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_filter.dart';

/// 편집 결과를 반환한다. 취소하면 null.
Future<PlanFilterState?> showFilterSheet(
  BuildContext context, {
  required PlanStore store,
  required PlanFilterState value,
}) {
  return showModalBottomSheet<PlanFilterState>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _FilterSheet(store: store, initial: value),
  );
}

class _FilterSheet extends StatefulWidget {
  final PlanStore store;
  final PlanFilterState initial;
  const _FilterSheet({required this.store, required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late PlanFilterState _f;
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
    _searchCtrl = TextEditingController(text: _f.searchText);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSet<T>(Set<T> set, T value, void Function(Set<T>) apply) {
    final next = Set<T>.from(set);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    apply(next);
  }

  Future<void> _pickCustomDate(bool isStart) async {
    final now = DateTime.now();
    final initial = (isStart ? _f.customStartDate : _f.customEndDate)
            ?.toDateTime() ??
        DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final d = PlanDate.fromDateTime(picked);
      _f = _f.copyWith(
        datePreset: DatePreset.custom,
        customStartDate: isStart ? d : _f.customStartDate,
        customEndDate: isStart ? _f.customEndDate : d,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('필터', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _f = PlanFilterState.empty),
                    child: const Text('초기화'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('프로젝트', style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in widget.store.projects)
                    FilterChip(
                      label: Text(p.name),
                      selected: _f.projectIds.contains(p.id),
                      onSelected: (_) => setState(() => _toggleSet(
                          _f.projectIds, p.id, (s) => _f = _f.copyWith(projectIds: s))),
                    ),
                  FilterChip(
                    label: const Text('미분류'),
                    selected: _f.includeUnclassified,
                    onSelected: (v) =>
                        setState(() => _f = _f.copyWith(includeUnclassified: v)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('상태', style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in TaskStatus.values)
                    FilterChip(
                      label: Text(s.label),
                      selected: _f.statuses.contains(s),
                      onSelected: (_) => setState(() => _toggleSet(
                          _f.statuses, s, (s2) => _f = _f.copyWith(statuses: s2))),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('태그', style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in widget.store.tags)
                    FilterChip(
                      label: Text(t.name),
                      selected: _f.tagIds.contains(t.id),
                      onSelected: (_) => setState(() => _toggleSet(
                          _f.tagIds, t.id, (s) => _f = _f.copyWith(tagIds: s))),
                    ),
                  FilterChip(
                    label: const Text('태그 없음'),
                    selected: _f.includeUntagged,
                    onSelected: (v) =>
                        setState(() => _f = _f.copyWith(includeUntagged: v)),
                  ),
                  if (widget.store.tags.isEmpty)
                    Text('등록된 태그가 없습니다.',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                ],
              ),
              const SizedBox(height: 12),
              Text('우선순위', style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in Priority.values)
                    FilterChip(
                      label: Text(p.label),
                      selected: _f.priorities.contains(p),
                      onSelected: (_) => setState(() => _toggleSet(
                          _f.priorities, p, (s) => _f = _f.copyWith(priorities: s))),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('기간', style: Theme.of(context).textTheme.labelMedium),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in const [
                    (DatePreset.all, '전체'),
                    (DatePreset.today, '오늘'),
                    (DatePreset.thisWeek, '이번 주'),
                    (DatePreset.thisMonth, '이번 달'),
                    (DatePreset.overdue, '지연'),
                    (DatePreset.incomplete, '미완료'),
                    (DatePreset.custom, '사용자 지정'),
                  ])
                    ChoiceChip(
                      label: Text(entry.$2),
                      selected: _f.datePreset == entry.$1,
                      onSelected: (_) =>
                          setState(() => _f = _f.copyWith(datePreset: entry.$1)),
                    ),
                ],
              ),
              if (_f.datePreset == DatePreset.custom)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickCustomDate(true),
                          child: Text(_f.customStartDate?.toIso() ?? '시작일'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('~'),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickCustomDate(false),
                          child: Text(_f.customEndDate?.toIso() ?? '종료일'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: '검색',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _f = _f.copyWith(searchText: v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop(_f.copyWith(searchText: _searchCtrl.text)),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
