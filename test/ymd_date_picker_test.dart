import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/ui/common/ymd_date_picker.dart';

/// "년도-일" 순으로만 고를 수 있어 불편하다는 피드백에 따라 만든 년/월/일
/// 드롭다운 선택기. 세 드롭다운을 순서대로 골라서 정확한 날짜가 나오는지,
/// 월을 바꿔 그 달에 없는 날짜(31일→2월)를 자동으로 보정하는지 확인한다.
///
/// Flutter 의 드롭다운 팝업 메뉴는 항목이 많으면 가상화(virtualization)돼
/// 현재 선택값 근처만 실제로 렌더링한다(열릴 때 현재 선택값이 보이도록 자동
/// 스크롤). 그래서 테스트에서는 **현재 값 바로 옆(인접)** 값을 골라 항상
/// 화면에 렌더돼 있는 항목만 탭한다.
void main() {
  Finder yearField() => find.byType(DropdownButtonFormField<int>).at(0);
  Finder monthField() => find.byType(DropdownButtonFormField<int>).at(1);
  Finder dayField() => find.byType(DropdownButtonFormField<int>).at(2);

  testWidgets('년 → 월 → 일 순서로 골라 정확한 날짜를 반환한다', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showYmdDatePicker(
                context,
                initialDate: DateTime(2026, 8, 11),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 년: 2026 -> 2027(인접값 — 팝업이 열리면 현재값 근처만 실제로 렌더된다).
    await tester.tap(yearField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('2027').last);
    await tester.pumpAndSettle();

    // 월: 8 -> 9.
    await tester.tap(monthField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.pumpAndSettle();

    // 일: 11 -> 12.
    await tester.tap(dayField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('12').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(result, DateTime(2027, 9, 12));
  });

  testWidgets('취소를 누르면 null 을 반환한다', (tester) async {
    DateTime? result = DateTime(1999);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showYmdDatePicker(
                context,
                initialDate: DateTime(2026, 8, 11),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('31일 선택 후 2월로 바꾸면 그 달의 마지막 날로 자동 보정된다',
      (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showYmdDatePicker(
                context,
                initialDate: DateTime(2026, 1, 31),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 월: 1 -> 2(2월, 2026년은 평년이라 28일까지). 1과 2는 인접값.
    await tester.tap(monthField());
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(result, DateTime(2026, 2, 28));
  });
}
