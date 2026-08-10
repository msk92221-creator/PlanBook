import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/app_shell.dart';

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
}
