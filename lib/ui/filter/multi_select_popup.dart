/// 여러 화면(Gantt/Calendar)에서 공유하는 복수 선택 드롭다운.
///
/// 체크박스가 달린 [PopupMenuButton] 하나로 구현한다. 선택된 항목이 있으면
/// 버튼 라벨에 개수를 표시한다("상태 (2)").
library;

import 'package:flutter/material.dart';

class MultiSelectOption<T> {
  final T value;
  final String label;
  const MultiSelectOption(this.value, this.label);
}

class MultiSelectPopup<T> extends StatelessWidget {
  final String label;
  final List<MultiSelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  /// 옵션 목록 맨 위/아래에 추가로 넣을 특수 토글(예: "미분류", "태그 없음").
  /// value 는 [selected] 와 별개의 bool 로 관리되므로 [extraSelected]/[onExtraChanged]
  /// 로 전달한다. null 이면 표시하지 않는다.
  final String? extraLabel;
  final bool extraSelected;
  final ValueChanged<bool>? onExtraChanged;

  const MultiSelectPopup({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.extraLabel,
    this.extraSelected = false,
    this.onExtraChanged,
  });

  @override
  Widget build(BuildContext context) {
    final count = selected.length + (extraSelected ? 1 : 0);
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<void>(
      tooltip: label,
      itemBuilder: (context) => [
        for (final o in options)
          CheckedPopupMenuItem<T>(
            value: o.value,
            checked: selected.contains(o.value),
            onTap: () {
              final next = Set<T>.from(selected);
              if (next.contains(o.value)) {
                next.remove(o.value);
              } else {
                next.add(o.value);
              }
              onChanged(next);
            },
            child: Text(o.label),
          ),
        if (extraLabel != null)
          CheckedPopupMenuItem<T>(
            checked: extraSelected,
            onTap: () => onExtraChanged?.call(!extraSelected),
            child: Text(extraLabel!),
          ),
      ],
      // PopupMenuButton 은 항목을 고르면 기본적으로 팝업이 닫힌다. 복수 선택을
      // 계속하려면 다시 열어야 하는 건 다소 불편하지만, 신규 의존성 없이
      // 안정적으로 동작하는 최소 구현이다(과도한 커스텀 위젯 지양).
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: count > 0 ? scheme.primary : scheme.outlineVariant,
          ),
          color: count > 0 ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(count > 0 ? '$label ($count)' : label,
                style: TextStyle(
                  fontSize: 12,
                  color: count > 0 ? scheme.primary : scheme.onSurface,
                  fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w400,
                )),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16,
                color: count > 0 ? scheme.primary : scheme.onSurface),
          ],
        ),
      ),
    );
  }
}
