import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/today/today_page.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeOn(DateTime date) async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => date,
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

Future<void> _pump(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(MaterialApp(home: TodayPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('지연 섹션의 재조정 버튼으로 "오늘로 이동" 을 고르면 실제로 날짜가 바뀐다',
      (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    final node = store.addNode(
      title: '밀린 보고서',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 5),
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('지연'), findsOneWidget);
    expect(find.text('밀린 보고서'), findsOneWidget);

    await tester.tap(find.byTooltip('일정 재조정'));
    await tester.pumpAndSettle();

    expect(find.text('오늘로 이동'), findsOneWidget);
    await tester.tap(find.text('오늘로 이동'));
    await tester.pumpAndSettle();
    await store.flush();

    expect(store.tree[node.id]!.endDate, PlanDate(2026, 8, 11));
    // 오늘로 옮겨졌으니 더 이상 "지연" 이 아니라 "오늘 마감" 으로 옮겨간다.
    expect(find.text('오늘 마감'), findsOneWidget);
  });

  testWidgets('"그대로 두기" 를 고르면 날짜가 바뀌지 않는다', (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    final node = store.addNode(
      title: '밀린 작업',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 5),
    );
    await store.flush();
    await _pump(tester, store);

    await tester.tap(find.byTooltip('일정 재조정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('그대로 두기'));
    await tester.pumpAndSettle();
    await store.flush();

    expect(store.tree[node.id]!.endDate, PlanDate(2026, 8, 5));
  });

  testWidgets('진행중/다가오는 섹션에는 재조정 버튼이 없다(지연에만 제공)', (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    store.addNode(
      title: '진행중 작업',
      startDate: PlanDate(2026, 8, 10),
      endDate: PlanDate(2026, 8, 20),
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('진행중 작업'), findsOneWidget);
    expect(find.byTooltip('일정 재조정'), findsNothing);
  });
}
