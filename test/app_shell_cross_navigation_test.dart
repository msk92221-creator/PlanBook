import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/app_shell.dart';

/// Phase 15(통합 네비게이션) 감사용: Projects/Calendar/Search 에서 "Gantt 에서
/// 보기"를 눌렀을 때 실제로 Gantt 탭으로 전환되고 필터/포커스가 적용되는지,
/// 그리고 원래 탭으로 돌아가면(같은 탭 재선택) 그 화면 상태가 그대로인지를
/// **AppShell 전체를 통해서** 확인한다(각 화면 단위 테스트는 콜백 호출 여부만
/// 확인했을 뿐, 실제 탭 전환/상태 보존까지는 검증하지 않았었다).
class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeWithData() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  final work = store.projects.firstWhere((p) => p.name == '업무');
  store.addNode(
    title: '보고서 작성',
    projectId: work.id,
    startDate: PlanDate(2026, 8, 11),
    endDate: PlanDate(2026, 8, 15),
  );
  await store.flush();
  return store;
}

/// 탭 라벨 텍스트("검색" 등)가 화면 내용(예: Gantt FilterBar 의 "검색" 힌트
/// 텍스트)과 겹칠 수 있으므로, 반드시 [NavigationRail] 안에서만 찾는다.
Future<void> _tapTab(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpWide(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Projects 카드 탭 → Gantt 탭으로 전환 + 프로젝트 필터 적용, '
      '다시 프로젝트 탭으로 돌아가면 그대로 보인다', (tester) async {
    final store = await _storeWithData();
    await _pumpWide(tester, store);

    await _tapTab(tester, '프로젝트');
    expect(find.widgetWithText(AppBar, 'PlanBook'), findsNothing);

    await tester.tap(find.text('업무').first);
    await tester.pumpAndSettle();

    // Gantt 탭으로 전환되었고, 업무 프로젝트 필터가 적용되어 해당 Task 가 보인다.
    expect(find.widgetWithText(AppBar, 'PlanBook'), findsOneWidget);
    expect(find.text('보고서 작성'), findsWidgets);

    // 다시 프로젝트 탭으로 — 원래 화면으로 정상 복귀(크래시 없음, 카드 그대로).
    await _tapTab(tester, '프로젝트');
    expect(find.text('업무'), findsWidgets);
  });

  testWidgets('Search 결과의 Gantt 아이콘 → Gantt 탭으로 전환되고 해당 Task 가 보인다',
      (tester) async {
    final store = await _storeWithData();
    await _pumpWide(tester, store);

    await _tapTab(tester, '검색');

    await tester.enterText(find.byType(TextField), '보고서');
    await tester.pump();
    expect(find.text('보고서 작성'), findsOneWidget);

    await tester.tap(find.byTooltip('Gantt 에서 보기'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'PlanBook'), findsOneWidget);
    expect(find.text('보고서 작성'), findsWidgets);

    // 검색 탭으로 되돌아가면 입력했던 검색어/결과가 그대로 보존돼 있다
    // (IndexedStack 이 화면 상태를 유지하므로).
    await _tapTab(tester, '검색');
    expect(find.text('보고서 작성'), findsOneWidget);
  });

  testWidgets('Calendar 의 Gantt 아이콘 → Gantt 탭으로 전환되고 해당 Task 가 보인다',
      (tester) async {
    final store = await _storeWithData();
    await _pumpWide(tester, store);

    await _tapTab(tester, '달력');

    // 오늘(8/11)이 기본 선택 상태라 선택일 패널에 바로 표시된다.
    expect(find.text('보고서 작성'), findsWidgets);
    await tester.tap(find.byTooltip('Gantt 에서 보기').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'PlanBook'), findsOneWidget);
    expect(find.text('보고서 작성'), findsWidgets);
  });
}
