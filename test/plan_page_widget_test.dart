import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/plan_page.dart';

/// 테스트용 인메모리 저장소(디스크 I/O 없음).
class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async {
    _snap = snapshot;
  }
}

Future<PlanStore> _seededStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2024, 8, 16),
    // 자동저장 Timer 가 테스트 종료 시 pending 상태로 남지 않도록
    // 즉시 flush 되도록 짧은 지연 사용.
    autosaveDelay: Duration.zero,
  );
  // load() 로 isLoaded=true 세팅(빈 상태) 후 샘플 채움.
  await store.load();
  store.createSampleData();
  // 샘플 생성 직후 예약된 autosave Timer 를 즉시 비움(pending Timer 방지).
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Future<PlanStore> _emptyStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2024, 8, 16),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

/// 이 파일은 **PlanPage 자체**를 검증한다.
/// (앱 진입 화면은 AppShell 의 Today 이므로 PlanBookApp 을 띄우면 Gantt 가 선택되지
///  않는다. 화면 전환은 app_shell_test.dart 가 따로 검증한다.)
Future<void> _pump(WidgetTester tester, PlanStore store) async {
  await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
  await tester.pump();
}

void main() {
  group('PlanPage 빈 상태', () {
    testWidgets('완전히 빈 상태에서도 "새 목표 추가" 버튼이 기본으로 보인다(샘플 버튼만 있으면 안 됨)',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _emptyStore();
      await _pump(tester, store);

      expect(find.text('새 목표 추가'), findsOneWidget);
      expect(find.text('샘플 계획으로 둘러보기'), findsOneWidget);
    });

    testWidgets('빈 상태에서 "새 목표 추가"를 누르면 편집 다이얼로그가 뜬다', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _emptyStore();
      await _pump(tester, store);

      await tester.tap(find.text('새 목표 추가'));
      await tester.pumpAndSettle();

      expect(find.text('항목 편집'), findsOneWidget);
    });
  });

  group('PlanPage 렌더', () {
    testWidgets('6) 샘플 트리 크래시 없이 렌더된다', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);
      // 루트 제목이 보인다.
      expect(find.text('PlanBook 앱 개발'), findsWidgets);
      expect(find.text('건강 관리'), findsWidgets);
      // 타임라인이 렌더된다.
      expect(find.byType(GanttTimeline), findsOneWidget);
      // 오늘 세로선 라벨이 렌더된다(오늘 = 2024-08-16).
      expect(find.text('오늘'), findsWidgets);
    });

    testWidgets('9-wide) 넓은 폭(1400)에서 크래시 없이 렌더', (tester) async {
      tester.view.physicalSize = const Size(1400, 900) * tester.view.devicePixelRatio;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);
      expect(find.text('PlanBook 앱 개발'), findsWidgets);
    });

    testWidgets('9-narrow) 좁은 폭(360)에서 전환 UI 와 함께 렌더', (tester) async {
      // 폴드 접힘 폭(380) 미만의 소형 화면에서는 트리/타임라인 전환 탭 모드.
      // (380 이상은 이제 2분할로 트리와 타임라인이 동시에 보인다.)
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);
      // 좁은 모드: 트리/타임라인 전환 SegmentedButton 의 라벨이 보인다.
      expect(find.text('트리'), findsOneWidget);
      expect(find.text('타임라인'), findsOneWidget);
      // 기본(트리) 뷰: 트리 헤더 '작업' 이 보인다.
      expect(find.text('작업'), findsOneWidget);
      // 타임라인으로 전환해도 크래시 없음. 트리 헤더는 사라진다.
      await tester.tap(find.text('타임라인'));
      await tester.pump();
      expect(find.text('작업'), findsNothing);
    });

    testWidgets('7) 부모를 접으면 자손 행이 사라지고 펼치면 다시 나타난다',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);

      const childTitle = '1단계: 코어/저장소';
      // 처음엔 보임(트리 + 타임라인 바 라벨).
      expect(find.text(childTitle), findsWidgets);

      // 첫 번째 '접기' 토글 = 루트 "PlanBook 앱 개발".
      await tester.tap(find.byTooltip('접기').first);
      await tester.pump();

      // 루트가 접혀 자손이 양쪽 패널에서 모두 사라진다.
      expect(find.text(childTitle), findsNothing);

      // 다시 펼치기(루트는 이제 '펼치기' 토글).
      await tester.tap(find.byTooltip('펼치기').first);
      await tester.pump();
      expect(find.text(childTitle), findsWidgets);
      // 접기/펼치기 mutation 이 예약한 autosave Timer 즉시 비움.
      await store.flush();
    });

    testWidgets('7b) "전체 접기"/"전체 펼치기" 버튼이 모든 부모에 한 번에 적용된다',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);

      const child1 = '1단계: 코어/저장소';
      const child2 = '2단계: Gantt 렌더링';
      expect(find.text(child1), findsWidgets);
      expect(find.text(child2), findsWidgets);

      await tester.tap(find.byTooltip('전체 접기'));
      await tester.pump();

      expect(find.text(child1), findsNothing);
      expect(find.text(child2), findsNothing);

      await tester.tap(find.byTooltip('전체 펼치기'));
      await tester.pump();

      expect(find.text(child1), findsWidgets);
      expect(find.text(child2), findsWidgets);
      await store.flush();
    });

    testWidgets('8) 완료 노드가 시각적으로 구분된다(Key 로 검증)', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);

      // 샘플의 완료 leaf: "날짜 처리 모듈 작성"(isDone=true, progress=1.0).
      // tree_panel 에서 done 노드는 'done-mark-<id>' 키의 check_circle 아이콘을
      // 가진다. 완료 전용 시각 요소가 존재함을 검증.
      expect(
        find.byWidgetPredicate((w) =>
            w is Icon &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('done-mark-')),
        findsWidgets,
      );
    });

    testWidgets('10) 날짜가 null 인 노드가 섞여 있어도 크래시하지 않는다',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await _seededStore();
      await _pump(tester, store);
      // 샘플의 null-date 노드가 "날짜 미정" 표시로 렌더된다.
      expect(find.text('날짜 미정'), findsWidgets);
    });
  });
}
