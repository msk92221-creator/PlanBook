import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/app_settings.dart';
import 'package:planbook/ui/plan/plan_page.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _store() async {
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

void main() {
  group('clampPeriodColumnWidth', () {
    test('범위 안 값은 그대로', () {
      expect(clampPeriodColumnWidth(150), 150);
    });

    test('범위를 벗어나면 자른다', () {
      expect(clampPeriodColumnWidth(1), kMinPeriodColumnWidth);
      expect(clampPeriodColumnWidth(9999), kMaxPeriodColumnWidth);
    });

    test('NaN/무한대는 기본값', () {
      expect(clampPeriodColumnWidth(double.nan), kDefaultPeriodColumnWidth);
      expect(clampPeriodColumnWidth(double.infinity), kDefaultPeriodColumnWidth);
    });
  });

  group('설정 저장/복원', () {
    test('기본값은 보임 + 기본 폭', () {
      const s = AppSettings();
      expect(s.showPeriodColumn, isTrue);
      expect(s.periodColumnWidth, kDefaultPeriodColumnWidth);
    });

    test('JSON 라운드트립으로 보존된다', () {
      const s = AppSettings(periodColumnWidth: 200, showPeriodColumn: false);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.periodColumnWidth, 200);
      expect(back.showPeriodColumn, isFalse);
    });

    test('저장값이 없던 예전 파일은 "보임"으로 읽힌다(하위 호환)', () {
      final json = const AppSettings().toJson()..remove('showPeriodColumn');
      expect(AppSettings.fromJson(json).showPeriodColumn, isTrue);
    });

    test('copyWith 도 폭 범위를 강제한다', () {
      expect(
        const AppSettings().copyWith(periodColumnWidth: -5).periodColumnWidth,
        kMinPeriodColumnWidth,
      );
    });
  });

  group('화면 동작', () {
    testWidgets('헤더에 "작업"/"기간" 열 제목이 보인다', (tester) async {
      final store = await _store();
      await _pumpWide(tester, store);

      expect(find.text('작업'), findsOneWidget);
      expect(find.text('기간'), findsOneWidget);
    });

    testWidgets('헤더 우클릭 메뉴로 기간 열을 숨길 수 있다', (tester) async {
      final store = await _store();
      await _pumpWide(tester, store);
      expect(store.settings.showPeriodColumn, isTrue);

      final header = tester.getCenter(find.text('작업'));
      final g = await tester.startGesture(header, buttons: kSecondaryButton);
      await g.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('기간 열 표시'));
      await tester.pumpAndSettle();
      await store.flush();

      expect(store.settings.showPeriodColumn, isFalse);
      expect(find.text('기간'), findsNothing, reason: '숨기면 열 제목도 사라져야 한다');
    });

    testWidgets('기간 열을 숨겨도 제목은 그대로 보인다', (tester) async {
      final store = await _store();
      store.updateSettings((s) => s.copyWith(showPeriodColumn: false));
      await store.flush();
      await _pumpWide(tester, store);

      expect(find.text('PA장비'), findsWidgets);
    });

    testWidgets('열 경계선을 끌면 기간 열 폭이 저장된다', (tester) async {
      final store = await _store();
      await _pumpWide(tester, store);
      final before = store.settings.periodColumnWidth;

      // 경계선은 "기간" 제목 바로 왼쪽에 있다.
      final periodLabel = tester.getTopLeft(find.text('기간'));
      await tester.dragFrom(
          periodLabel + const Offset(-5, 8), const Offset(-40, 0));
      await tester.pump();
      await store.flush();

      expect(store.settings.periodColumnWidth, greaterThan(before),
          reason: '왼쪽으로 끌면 기간 열이 넓어진다');
    });

    testWidgets('작업 칸을 아주 좁혀도 레이아웃이 넘치지 않는다', (tester) async {
      final store = await _store();
      // 기간 열을 최대로 넓혀 둔 상태에서 칸을 최소로 줄인다(가장 빡빡한 조건).
      store.updateSettings((s) => s.copyWith(
            periodColumnWidth: kMaxPeriodColumnWidth,
            treePaneWidth: kMinTreePaneWidth,
          ));
      await store.flush();
      await _pumpWide(tester, store);

      // 오버플로가 나면 렌더 예외로 테스트가 실패한다.
      expect(tester.takeException(), isNull);
    });
  });
}
