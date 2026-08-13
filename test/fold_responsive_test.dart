import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/app_shell.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/plan_page.dart';
import 'package:planbook/ui/plan/tree_panel.dart';

Directory _tmp(String n) => Directory.systemTemp.createTempSync('planbook_$n');

/// Fold 기기 대응: 접힌 상태(좁음, [NavigationBar])에서 펼친 상태(넓음,
/// [NavigationRail])로 화면 크기가 **런타임에** 바뀌어도(위젯을 새로 pump 하지
/// 않고), kTwoPaneBreakpoint 기준 [LayoutBuilder] 가 즉시 반응해 레이아웃이
/// 전환되어야 한다 — 앱 재시작 없이 자연스럽게 fold/unfold 되는 것이 목표.
void main() {
  late Directory dir;
  late PlanStore store;

  setUp(() async {
    dir = _tmp('fold');
    store = PlanStore(
      repository: JsonPlanRepository(directory: dir),
      nowProvider: () => DateTime(2026, 8, 11),
      autosaveDelay: Duration.zero,
    );
    await store.load();
    await store.flush();
  });

  tearDown(() {
    store.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('접힌 상태에서 펼친 상태로 실시간 전환되면 NavigationBar->NavigationRail 로 바뀐다',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1) 접힌(좁은) 상태로 시작.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    // 2) 펼친(넓은) 상태로 — 위젯을 다시 pump 하지 않고 뷰 크기만 변경한다
    //    (실제 Fold 기기의 화면 전환을 재현).
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // 3) 다시 접으면 원래대로 돌아온다(양방향 반응성 확인).
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('폭 전환 중에도 현재 화면(Today) 상태가 크래시 없이 유지된다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '오늘'), findsOneWidget);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '오늘'), findsOneWidget,
        reason: 'IndexedStack 이 화면 상태를 보존하므로 폭이 바뀌어도 같은 화면(오늘)이어야 한다');
  });

  // -------------------------------------------------------------------------
  // Fold 접힘 폭(380~430)에서도 트리와 타임라인이 동시에 보이는지 검증.
  // Gantt(PlanPage) 의 2분할 한계치(kGanttTwoPaneBreakpoint=380) 는 AppShell 의
  // Rail/Bar 한계치(720) 와 별개다.
  // -------------------------------------------------------------------------

  group('Gantt 폴드 접힘 화면(380~430) 2분할', () {
    late PlanStore ganttStore;

    setUp(() async {
      final repo = _MemoryRepo();
      ganttStore = PlanStore(
        repository: repo,
        nowProvider: () => DateTime(2026, 8, 11),
        autosaveDelay: Duration.zero,
      );
      await ganttStore.load();
      ganttStore.addNode(
        title: 'PA장비',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 20),
      );
      await ganttStore.flush();
      addTearDown(ganttStore.dispose);
    });

    Future<void> pumpAt(
      WidgetTester tester, {
      required double width,
      required double height,
    }) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: PlanPage(store: ganttStore)));
      await tester.pump();
    }

    testWidgets('폭 400 에서 TreePanel 과 GanttTimeline 이 동시에 보인다', (tester) async {
      await pumpAt(tester, width: 400, height: 900);

      expect(find.byType(TreePanel), findsOneWidget);
      expect(find.byType(GanttTimeline), findsOneWidget);
      // 전환 탭(좁은 모드 전용) 은 보이지 않아야 한다.
      expect(find.text('타임라인'), findsNothing);
    });

    testWidgets('폭 400 에서 트리 폭이 화면의 45% 이하다(실제 렌더 폭 측정)', (tester) async {
      await pumpAt(tester, width: 400, height: 900);

      final treeWidth = tester.getSize(find.byType(TreePanel)).width;
      // 폭 400 * 0.45 = 180. 설정 기본값(300) 대신 비율 상한이 적용돼야 한다.
      expect(treeWidth, lessThanOrEqualTo(400 * 0.45));
    });

    testWidgets('폭 1400 에서는 트리 폭이 설정 기본값(300) 과 동일하다', (tester) async {
      await pumpAt(tester, width: 1400, height: 900);

      // 1400 * 0.45 = 630 > 설정값 300 이므로 설정값이 그대로 쓰인다(기존 동작 유지).
      final treeWidth = tester.getSize(find.byType(TreePanel)).width;
      expect(treeWidth, 300);
    });

    testWidgets('폭 360(380 미만) 에서는 전환 탭이 보인다(기존 좁은 모드 유지)', (tester) async {
      await pumpAt(tester, width: 360, height: 900);

      // 380 미만이면 트리/타임라인 전환 탭 모드.
      expect(find.text('트리'), findsOneWidget);
      expect(find.text('타임라인'), findsOneWidget);
      // 기본(트리) 뷰: 타임라인은 전환 전까지 보이지 않는다.
      expect(find.byType(TreePanel), findsOneWidget);
      expect(find.byType(GanttTimeline), findsNothing);
    });
  });
}

/// 테스트용 인메모리 저장소(디스크 I/O 없음).
class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}
