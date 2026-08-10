import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/ui/calendar/calendar_page.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _emptyStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    // 2026-08-11 은 화요일.
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Future<void> _pumpWide(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: CalendarPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('매월 11일 반복 Task 는 오늘(8/11) 날짜 셀 + 선택 패널에 표시된다(오늘이 기본 선택)',
      (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '매월 정산',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'monthly',
      recurrenceDayOfMonth: 11,
    );
    await store.flush();
    await _pumpWide(tester, store);

    // 이 달엔 11일이 한 번뿐이라 그리드 라벨 1개 + 패널 항목 1개 = 2개.
    expect(find.text('매월 정산'), findsNWidgets(2));
  });

  testWidgets('요일이 안 맞는 weekly 반복 Task 는 오늘(화) 선택 패널에는 뜨지 않는다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '월/수/금 운동',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'weekly',
      recurrenceWeekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday],
    );
    await store.flush();
    await _pumpWide(tester, store);

    // 선택 패널(오른쪽 320px 고정폭 영역)에는 표시되지 않아야 한다.
    // 그리드 쪽(이번 달의 다른 월/수/금)에는 나타날 수 있으므로 전체 findsNothing 은 쓰지 않는다.
    expect(find.text('이 날짜에 해당하는 작업이 없습니다.'), findsOneWidget);
  });

  testWidgets('선택 패널에서 완료 체크하면 해당 날짜 occurrence 만 기록된다', (tester) async {
    final store = await _emptyStore();
    final node = store.addNode(
      title: '매월 확인',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'monthly',
      recurrenceDayOfMonth: 11,
    );
    await store.flush();
    await _pumpWide(tester, store);

    final toggle = find.descendant(
      of: find.ancestor(of: find.text('매월 확인'), matching: find.byType(Card)),
      matching: find.byType(IconButton),
    );
    await tester.tap(toggle.first);
    await tester.pump();
    await store.flush();

    final updated = store.tree[node.id]!;
    expect(updated.recurrenceCompletedDates, ['2026-08-11']);
    expect(updated.status, TaskStatus.notStarted);
  });
}
