/// 년-월-일 순서로 고르는 날짜 선택기.
///
/// 기본 Material [showDatePicker] 는 달력 그리드 + "연도 그리드로 전환"만
/// 지원한다 — 월을 바꾸려면 좌우 화살표를 여러 번 눌러야 해서, 사용자
/// 체감상 "연도 선택 + 하루하루 이동"처럼 느껴진다는 피드백이 있었다. 이
/// 위젯은 연/월/일 드롭다운 3개를 순서대로 보여줘 세 번의 선택만으로 끝난다.
library;

import 'package:flutter/material.dart';

import 'dialog_insets.dart';

/// [showDatePicker] 와 동일한 반환 타입(`Future<DateTime?>`)을 갖는 대체 함수.
/// 기존 호출부는 함수 이름만 바꾸면 그대로 쓸 수 있다.
Future<DateTime?> showYmdDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _YmdPickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

int _daysInMonth(int year, int month) {
  final firstOfNextMonth =
      month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return firstOfNextMonth.subtract(const Duration(days: 1)).day;
}

class _YmdPickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _YmdPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_YmdPickerDialog> createState() => _YmdPickerDialogState();
}

class _YmdPickerDialogState extends State<_YmdPickerDialog> {
  late int _year;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;
  }

  @override
  Widget build(BuildContext context) {
    // 월이 바뀌어 그 달의 마지막 날보다 커지면(예: 31일 선택 후 2월로 변경)
    // 자동으로 그 달의 마지막 날로 당긴다.
    final maxDay = _daysInMonth(_year, _month);
    if (_day > maxDay) _day = maxDay;

    return AlertDialog(
      insetPadding: safeDialogInsetPadding(context),
      title: const Text('날짜 선택'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: '년', isDense: true),
              items: [
                for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) => setState(() => _year = v ?? _year),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: '월', isDense: true),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text('$m')),
              ],
              onChanged: (v) => setState(() => _month = v ?? _month),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: const InputDecoration(labelText: '일', isDense: true),
              items: [
                for (var d = 1; d <= maxDay; d++)
                  DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (v) => setState(() => _day = v ?? _day),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            var picked = DateTime(_year, _month, _day);
            if (picked.isBefore(widget.firstDate)) picked = widget.firstDate;
            if (picked.isAfter(widget.lastDate)) picked = widget.lastDate;
            Navigator.of(context).pop(picked);
          },
          child: const Text('확인'),
        ),
      ],
    );
  }
}
