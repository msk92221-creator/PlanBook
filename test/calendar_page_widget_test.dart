import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
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
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  // load() 가 기본 프로젝트 시드를 위해 예약한 autosave Timer 를 즉시 비운다
  // (안 그러면 아무 mutation 없이 pump 만 하는 테스트에서 pending timer 로 실패).
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

Future<void> _pumpNarrow(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: CalendarPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('오늘이 속한 달로 시작하고 오늘 날짜가 선택된다', (tester) async {
    final store = await _emptyStore();
    await _pumpWide(tester, store);
    expect(find.text('2026년 8월'), findsOneWidget);
  });

  testWidgets('다음/이전 달 이동이 동작한다', (tester) async {
    final store = await _emptyStore();
    await _pumpWide(tester, store);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('2026년 9월'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('2026년 7월'), findsOneWidget);
  });

  testWidgets('날짜에 걸치는 Task 가 셀과 선택 패널에 표시된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '기간 작업',
      startDate: PlanDate(2026, 8, 10),
      endDate: PlanDate(2026, 8, 12),
    );
    await store.flush();
    await _pumpWide(tester, store);

    // 오늘(8/11)이 기본 선택 상태이므로 패널에 바로 보여야 한다.
    expect(find.text('기간 작업'), findsWidgets);
  });

  testWidgets('Milestone 은 기준일에만 표시된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '중간 발표',
      isMilestone: true,
      endDate: PlanDate(2026, 8, 20),
    );
    await store.flush();
    await _pumpWide(tester, store);

    // 8/20 셀을 탭해서 선택.
    await tester.tap(find.text('20').first);
    await tester.pump();
    expect(find.text('중간 발표'), findsWidgets);
  });

  testWidgets('날짜 셀을 탭하면 선택 패널이 그 날짜로 갱신된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '15일 작업',
      startDate: PlanDate(2026, 8, 15),
      endDate: PlanDate(2026, 8, 15),
    );
    await store.flush();
    await _pumpWide(tester, store);

    // 달력 셀 자체에는 날짜와 무관하게 항상 라벨이 보인다(그리드 미리보기).
    // 선택 패널에는 아직 8/11(오늘) 이 선택된 상태라 안 보여야 한다.
    expect(find.text('15일 작업'), findsOneWidget); // 그리드 라벨 1개만.

    await tester.tap(find.text('15').first);
    await tester.pump();
    // 선택 후에는 그리드 라벨 + 선택 패널 행, 총 2곳에 보인다.
    expect(find.text('15일 작업'), findsNWidgets(2));
  });

  testWidgets('좁은 화면에서는 달력과 목록이 세로로 배치된다(크래시 없음)',
      (tester) async {
    final store = await _emptyStore();
    await _pumpNarrow(tester, store);
    expect(find.text('2026년 8월'), findsOneWidget);
  });

  testWidgets('필터를 적용하면 해당하지 않는 Task 는 선택 패널에서 사라진다',
      (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');
    final research = store.projects.firstWhere((p) => p.name == '연구');
    store.addNode(
      title: '업무 작업',
      projectId: work.id,
      startDate: PlanDate(2026, 8, 11),
      endDate: PlanDate(2026, 8, 11),
    );
    store.addNode(
      title: '연구 작업',
      projectId: research.id,
      startDate: PlanDate(2026, 8, 11),
      endDate: PlanDate(2026, 8, 11),
    );
    await store.flush();
    await _pumpWide(tester, store);

    expect(find.text('업무 작업'), findsWidgets);
    expect(find.text('연구 작업'), findsWidgets);

    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('업무').last);
    await tester.pumpAndSettle();
    // 팝업 닫기.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('업무 작업'), findsWidgets);
    expect(find.text('연구 작업'), findsNothing);
  });
}
