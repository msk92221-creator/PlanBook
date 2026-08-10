import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/ui/today/today_page.dart';

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
    nowProvider: () => DateTime(2026, 8, 20),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

void main() {
  testWidgets('수량형 Task 는 Today 에 날짜 대신 오늘 권장량이 표시된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '책 읽기',
      nodeKind: NodeKind.quantity,
      estimate: 300,
      actual: 80,
      unit: 'page',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 30),
    );
    await store.flush();

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: TodayPage(store: store)));
    await tester.pump();

    expect(find.text('책 읽기'), findsOneWidget);
    // 8/20 기준 남은 220page, 남은 11일(8/20~8/30) → 20page/일.
    expect(find.text('오늘 20page'), findsOneWidget);
    expect(find.textContaining('2026-08-01'), findsNothing,
        reason: '수량형은 날짜 범위 대신 권장량이 표시되어야 한다');
  });

  testWidgets('시간형 Task 는 소수 권장량이 표시된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '논문 공부',
      nodeKind: NodeKind.effort,
      estimate: 20,
      actual: 6,
      unit: '시간',
      startDate: PlanDate(2026, 8, 14),
      endDate: PlanDate(2026, 8, 26),
    );
    await store.flush();

    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: TodayPage(store: store)));
    await tester.pump();

    // 8/20~8/26 inclusive = 7일. remaining=14. 14/7=2.0 → "2시간".
    expect(find.text('오늘 2시간'), findsOneWidget);
  });
}
