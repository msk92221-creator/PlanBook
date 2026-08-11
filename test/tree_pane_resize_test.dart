import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/app_settings.dart';
import 'package:planbook/ui/plan/plan_page.dart';
import 'package:planbook/ui/plan/tree_panel.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeWithOneTask() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 10),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  store.addNode(
    title: 'PA장비',
    startDate: PlanDate(2026, 8, 1),
    endDate: PlanDate(2026, 8, 20),
  );
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Future<void> _pumpWide(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
  await tester.pump();
}

double _treeWidth(WidgetTester tester) =>
    tester.getSize(find.byType(TreePanel)).width;

void main() {
  group('clampTreePaneWidth', () {
    test('허용 범위 안의 값은 그대로 둔다', () {
      expect(clampTreePaneWidth(420), 420);
    });

    test('너무 좁으면 최소값으로 올린다', () {
      expect(clampTreePaneWidth(10), kMinTreePaneWidth);
    });

    test('너무 넓으면 최대값으로 내린다', () {
      expect(clampTreePaneWidth(99999), kMaxTreePaneWidth);
    });

    test('NaN/무한대는 기본값으로 되돌린다(저장 파일 손상 대비)', () {
      expect(clampTreePaneWidth(double.nan), kDefaultTreePaneWidth);
      expect(clampTreePaneWidth(double.infinity), kDefaultTreePaneWidth);
    });
  });

  group('AppSettings.treePaneWidth 저장/복원', () {
    test('기본값은 kDefaultTreePaneWidth', () {
      expect(const AppSettings().treePaneWidth, kDefaultTreePaneWidth);
    });

    test('JSON 라운드트립으로 값이 보존된다', () {
      const s = AppSettings(treePaneWidth: 380);
      expect(AppSettings.fromJson(s.toJson()).treePaneWidth, 380);
    });

    test('저장 파일에 범위 밖 값이 있어도 잘라서 읽는다', () {
      final json = const AppSettings().toJson()..['treePaneWidth'] = 5.0;
      expect(AppSettings.fromJson(json).treePaneWidth, kMinTreePaneWidth);
    });

    test('copyWith 도 범위를 강제한다', () {
      expect(
        const AppSettings().copyWith(treePaneWidth: -100).treePaneWidth,
        kMinTreePaneWidth,
      );
    });
  });

  group('경계선 드래그', () {
    testWidgets('오른쪽으로 끌면 작업 트리 칸이 넓어진다', (tester) async {
      final store = await _storeWithOneTask();
      await _pumpWide(tester, store);

      final before = _treeWidth(tester);
      expect(before, kDefaultTreePaneWidth);

      // 경계선은 트리 패널 바로 오른쪽에 있다.
      final divider = tester.getTopRight(find.byType(TreePanel));
      await tester.dragFrom(divider + const Offset(4, 200), const Offset(120, 0));
      await tester.pump();
      await store.flush();

      expect(_treeWidth(tester), greaterThan(before));
      expect(store.settings.treePaneWidth, greaterThan(before));
    });

    testWidgets('왼쪽으로 끌면 좁아진다', (tester) async {
      final store = await _storeWithOneTask();
      await _pumpWide(tester, store);

      final before = _treeWidth(tester);
      final divider = tester.getTopRight(find.byType(TreePanel));
      await tester.dragFrom(divider + const Offset(4, 200), const Offset(-80, 0));
      await tester.pump();
      await store.flush();

      expect(_treeWidth(tester), lessThan(before));
    });

    testWidgets('아무리 끌어도 최소 폭 아래로는 줄지 않는다', (tester) async {
      final store = await _storeWithOneTask();
      await _pumpWide(tester, store);

      final divider = tester.getTopRight(find.byType(TreePanel));
      await tester.dragFrom(divider + const Offset(4, 200), const Offset(-2000, 0));
      await tester.pump();
      await store.flush();

      expect(_treeWidth(tester), kMinTreePaneWidth);
      expect(store.settings.treePaneWidth, kMinTreePaneWidth);
    });

    testWidgets('조절한 폭은 설정에 저장돼 다시 그려도 유지된다', (tester) async {
      final store = await _storeWithOneTask();
      await _pumpWide(tester, store);

      final divider = tester.getTopRight(find.byType(TreePanel));
      await tester.dragFrom(divider + const Offset(4, 200), const Offset(100, 0));
      await tester.pump();
      final resized = store.settings.treePaneWidth;
      await store.flush();

      // 같은 store 로 화면을 새로 만들어도(=재시작 상황) 폭이 유지된다.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
      await tester.pump();

      expect(_treeWidth(tester), resized);
    });
  });
}
