/// Gantt(및 향후 Calendar) 상단 필터 바.
///
/// **화면(Gantt/Calendar)에서 조건식을 다시 만들지 않는다** — 이 위젯은
/// [PlanFilterState] 값만 들고 있고, 실제 판정은 `domain/plan_filter.dart` 의
/// 순수 함수가 한다.
///
/// [compact]==true(좁은 화면) 이면 촘촘한 개별 드롭다운 대신, 빠른 필터 칩
/// 한 줄 + "필터" 아이콘 버튼(전체 조건 편집용 바텀시트)만 보여준다.
library;

import 'package:flutter/material.dart';

import '../../data/plan_store.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_filter.dart';
import 'filter_sheet.dart';
import 'multi_select_popup.dart';

class FilterBar extends StatelessWidget {
  final PlanStore store;
  final PlanFilterState value;
  final ValueChanged<PlanFilterState> onChanged;
  final bool compact;

  const FilterBar({
    super.key,
    required this.store,
    required this.value,
    required this.onChanged,
    required this.compact,
  });

  void _setDatePreset(DatePreset preset) {
    if (preset == DatePreset.all && value.datePreset == DatePreset.all) {
      // "전체" 를 다시 누르면 전체 초기화(모든 축) — 그 외 quick preset 은
      // 기간 축만 바꾸고 나머지(Project/Tag/...)는 유지한다.
      onChanged(PlanFilterState.empty);
      return;
    }
    onChanged(value.copyWith(
      datePreset: preset,
      customStartDate: null,
      customEndDate: null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final quickChips = _QuickFilterChips(
      current: value.datePreset,
      onSelect: _setDatePreset,
    );

    if (compact) {
      return Row(
        children: [
          Expanded(child: quickChips),
          IconButton(
            tooltip: '필터',
            onPressed: () => _openSheet(context),
            icon: Badge(
              isLabelVisible: !value.isEmpty,
              child: const Icon(Icons.filter_list),
            ),
          ),
          if (!value.isEmpty)
            IconButton(
              tooltip: '필터 초기화',
              onPressed: () => onChanged(PlanFilterState.empty),
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          MultiSelectPopup<String>(
            label: 'Project',
            options: [
              for (final p in store.projects)
                MultiSelectOption(p.id, p.name),
            ],
            selected: value.projectIds,
            onChanged: (s) => onChanged(value.copyWith(projectIds: s)),
            extraLabel: '미분류',
            extraSelected: value.includeUnclassified,
            onExtraChanged: (v) =>
                onChanged(value.copyWith(includeUnclassified: v)),
          ),
          const SizedBox(width: 6),
          MultiSelectPopup<TaskStatus>(
            label: '상태',
            options: [
              for (final s in TaskStatus.values) MultiSelectOption(s, s.label),
            ],
            selected: value.statuses,
            onChanged: (s) => onChanged(value.copyWith(statuses: s)),
          ),
          const SizedBox(width: 6),
          MultiSelectPopup<String>(
            label: '태그',
            options: [
              for (final t in store.tags) MultiSelectOption(t.id, t.name),
            ],
            selected: value.tagIds,
            onChanged: (s) => onChanged(value.copyWith(tagIds: s)),
            extraLabel: '태그 없음',
            extraSelected: value.includeUntagged,
            onExtraChanged: (v) =>
                onChanged(value.copyWith(includeUntagged: v)),
          ),
          const SizedBox(width: 6),
          MultiSelectPopup<Priority>(
            label: '우선순위',
            options: [
              for (final p in Priority.values) MultiSelectOption(p, p.label),
            ],
            selected: value.priorities,
            onChanged: (s) => onChanged(value.copyWith(priorities: s)),
          ),
          const SizedBox(width: 10),
          quickChips,
          const SizedBox(width: 10),
          SizedBox(
            width: 160,
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '검색',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: value.searchText)
                ..selection = TextSelection.collapsed(offset: value.searchText.length),
              onSubmitted: (v) => onChanged(value.copyWith(searchText: v)),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '고급 필터(기간 직접 지정 등)',
            onPressed: () => _openSheet(context),
            icon: const Icon(Icons.tune),
          ),
          if (!value.isEmpty)
            IconButton(
              tooltip: '필터 초기화',
              onPressed: () => onChanged(PlanFilterState.empty),
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showFilterSheet(context, store: store, value: value);
    if (result != null) onChanged(result);
  }
}

class _QuickFilterChips extends StatelessWidget {
  final DatePreset current;
  final ValueChanged<DatePreset> onSelect;

  const _QuickFilterChips({required this.current, required this.onSelect});

  static const _quick = [
    (DatePreset.all, '전체'),
    (DatePreset.today, '오늘'),
    (DatePreset.thisWeek, '이번 주'),
    (DatePreset.thisMonth, '이번 달'),
    (DatePreset.overdue, '지연'),
    (DatePreset.incomplete, '미완료'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (preset, label) in _quick)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selected: current == preset,
                onSelected: (_) => onSelect(preset),
              ),
            ),
        ],
      ),
    );
  }
}
