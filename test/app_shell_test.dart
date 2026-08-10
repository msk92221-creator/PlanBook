import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/app_settings.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_rollup.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/ui/app_shell.dart';

Directory _tmp(String n) => Directory.systemTemp.createTempSync('planbook_$n');

Future<void> _pumpShell(
  WidgetTester tester,
  PlanStore store, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late PlanStore store;

  setUp(() async {
    dir = _tmp('shell');
    store = PlanStore(
      repository: JsonPlanRepository(directory: dir),
      nowProvider: () => DateTime(2026, 8, 10),
    );
    await store.load();
  });

  tearDown(() {
    store.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('넓은 화면(>=720)은 NavigationRail 을 쓴다', (tester) async {
    await _pumpShell(tester, store, size: const Size(1400, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('좁은 화면(<720)은 NavigationBar 를 쓴다', (tester) async {
    await _pumpShell(tester, store, size: const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('기본 진입 화면은 Today', (tester) async {
    await _pumpShell(tester, store, size: const Size(1400, 900));
    expect(store.settings.lastScreen, AppScreen.today);
    // AppBar 제목으로 현재 화면을 확인.
    expect(find.widgetWithText(AppBar, '오늘'), findsOneWidget);
  });

  testWidgets(
      '"마지막 화면 복원" 이 꺼져 있으면(기본값) lastScreen 이 달력이어도 Today 로 진입한다',
      (tester) async {
    store.updateSettings((s) => s.copyWith(lastScreen: AppScreen.calendar));
    expect(store.settings.restoreLastScreen, isFalse, reason: '기본값은 false');
    await tester.runAsync(() => store.flush());
    await _pumpShell(tester, store, size: const Size(1400, 900));
    expect(find.widgetWithText(AppBar, '오늘'), findsOneWidget);
  });

  testWidgets('5개 탭 전환이 크래시 없이 동작하고 lastScreen 이 저장된다',
      (tester) async {
    await _pumpShell(tester, store, size: const Size(1400, 900));

    // 간트 탭으로.
    await tester.tap(find.text('간트').last);
    await tester.pumpAndSettle();
    expect(store.settings.lastScreen, AppScreen.gantt);

    // 달력 탭으로.
    await tester.tap(find.text('달력').last);
    await tester.pumpAndSettle();
    expect(store.settings.lastScreen, AppScreen.calendar);
    expect(find.widgetWithText(AppBar, '달력'), findsOneWidget);

    // 프로젝트 탭으로.
    await tester.tap(find.text('프로젝트').last);
    await tester.pumpAndSettle();
    expect(store.settings.lastScreen, AppScreen.projects);

    // 다시 오늘로.
    await tester.tap(find.text('오늘').last);
    await tester.pumpAndSettle();
    expect(store.settings.lastScreen, AppScreen.today);
  });

  testWidgets('"마지막 화면 복원" 이 켜져 있으면 저장된 lastScreen 이 재실행 시 복원된다',
      (tester) async {
    store.updateSettings((s) => s.copyWith(
        lastScreen: AppScreen.calendar, restoreLastScreen: true));

    // 실제 디스크 I/O 는 반드시 runAsync 안에서 해야 한다.
    // testWidgets 본문은 fake-async 존이라 real I/O future 가 완료되지 않는다.
    late PlanStore store2;
    await tester.runAsync(() async {
      await store.flush();
      store2 = PlanStore(repository: JsonPlanRepository(directory: dir));
      await store2.load();
    });
    addTearDown(store2.dispose);

    expect(store2.settings.lastScreen, AppScreen.calendar);

    await _pumpShell(tester, store2, size: const Size(1400, 900));
    expect(find.widgetWithText(AppBar, '달력'), findsOneWidget);
  });

  testWidgets('Projects 화면에 시드된 기본 프로젝트 5개가 보인다', (tester) async {
    await _pumpShell(tester, store, size: const Size(1400, 900));
    await tester.tap(find.text('프로젝트').last);
    await tester.pumpAndSettle();
    for (final name in ['업무', '연구', '건강', '개인', '기타']) {
      expect(find.text(name), findsWidgets, reason: '$name 프로젝트가 보여야 한다');
    }
  });

  group('onHold rollup', () {
    test('보류(onHold) 자식이 있으면 부모는 완료가 아니다', () {
      final tree = PlanTree.fromNodes([
        const PlanNode(id: 'p', title: 'p', autoRollup: true),
        const PlanNode(
            id: 'a', parentId: 'p', title: 'a', status: TaskStatus.done),
        const PlanNode(
            id: 'b', parentId: 'p', title: 'b', status: TaskStatus.onHold),
      ]);
      expect(computeRollup(tree, 'p').isDone, isFalse,
          reason: 'onHold 는 done 으로 취급하지 않는다');
    });

    test('모든 자식이 done 이면 부모는 완료', () {
      final tree = PlanTree.fromNodes([
        const PlanNode(id: 'p', title: 'p', autoRollup: true),
        const PlanNode(
            id: 'a', parentId: 'p', title: 'a', status: TaskStatus.done),
        const PlanNode(
            id: 'b', parentId: 'p', title: 'b', status: TaskStatus.done),
      ]);
      expect(computeRollup(tree, 'p').isDone, isTrue);
    });
  });
}
