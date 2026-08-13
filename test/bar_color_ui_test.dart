import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/bar_color.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';
import 'package:planbook/ui/plan/gantt_theme.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/node_edit_dialog.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

/// 막대 색(고정 팔레트) UI 매핑·렌더링·편집을 검증하는 위젯 테스트.
/// [GanttTimeline] 을 직접 pump 한다(PlanPage 를 거치지 않음) —
/// gantt_openended_test.dart 와 같은 이유(가로 스크롤 오프셋 비결정성 회피).
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
    nowProvider: () => DateTime(2026, 1, 1),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

final _metrics = GanttMetrics(
  firstDay: PlanDate(2025, 12, 1),
  lastDay: PlanDate(2026, 2, 28),
  dayWidth: 40.0,
);

Future<void> _pumpTimeline(
  WidgetTester tester,
  PlanStore store, {
  Brightness brightness = Brightness.light,
}) async {
  // 뷰를 content 폭에 맞춰 가로 스크롤 오프셋을 0 으로 고정한다
  // (막대 좌표/히트가 비결정적으로 흔들리지 않도록).
  final viewWidth = _metrics.totalWidth;
  tester.view.physicalSize = Size(viewWidth, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = flattenVisibleRows(store.tree);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: SizedBox(
          width: viewWidth,
          height: 600,
          child: GanttTimeline(
            tree: store.tree,
            rows: rows,
            metrics: _metrics,
            today: PlanDate(2026, 1, 1),
            store: store,
          ),
        ),
      ),
    ),
  );
  // pump() 한 번으로는 부족하다: MaterialApp 은 테마 변경을 AnimatedTheme 으로
  // 200ms 에 걸쳐 보간하므로, 라이트→다크로 바꾼 직후 한 프레임만 진행하면
  // Theme.of() 가 아직 예전(라이트) 값을 돌려준다. 애니메이션을 끝까지 돌려야
  // 다크 모드 색을 정확히 읽을 수 있다.
  await tester.pumpAndSettle();
}

/// 막대 진행(채움) 영역의 실제 색을 꺼낸다. `gantt-bar-<id>` 키 아래의
/// 채움 Container(BoxDecoration.color) 를 찾아 색을 비교한다(픽셀 비교는 안 한다).
Color? _barFillColor(WidgetTester tester, String nodeId) {
  final bar = find.byKey(ValueKey('gantt-bar-$nodeId'));
  // 막대 아래에는 트랙(미충족)과 진행 채움 두 종류의 Container 가 있다.
  // 진행 채움만 FractionallySizedBox 자식이므로 그걸로 좁혀서 집는다.
  final progressed = find.descendant(
    of: find.descendant(of: bar, matching: find.byType(FractionallySizedBox)),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color != null,
    ),
  );
  final c = tester.widget<Container>(progressed);
  return (c.decoration as BoxDecoration).color;
}

void main() {
  group('막대 색 렌더링', () {
    testWidgets('barColor 를 지정한 노드는 해당 색으로 그려진다', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '빨간 막대',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
        barColor: BarColor.red,
      );
      await store.flush();
      await _pumpTimeline(tester, store);

      final expected = barColorOf(
        tester.element(find.byType(GanttTimeline)),
        BarColor.red,
      );
      expect(expected, isNotNull);
      expect(_barFillColor(tester, task.id), expected);
    });

    testWidgets('barColor==none 인 노드는 기존 status 색을 그대로 쓴다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '진행중(색 없음)',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
        status: TaskStatus.inProgress,
        barColor: BarColor.none,
      );
      await store.flush();
      await _pumpTimeline(tester, store);

      final ctx = tester.element(find.byType(GanttTimeline));
      final expected = statusBarFillColor(ctx, TaskStatus.inProgress);
      expect(_barFillColor(tester, task.id), expected);
    });

    testWidgets('done==true 인 노드는 barColor 를 지정해도 완료 색으로 그려진다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '완료인데 빨강 지정',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
        status: TaskStatus.done,
        barColor: BarColor.red,
      );
      await store.flush();
      await _pumpTimeline(tester, store);

      final ctx = tester.element(find.byType(GanttTimeline));
      final expected = barFillColor(ctx, done: true);
      expect(_barFillColor(tester, task.id), expected);
      // 명확히: 빨강 색이 아니어야 한다(완료 색이 이긴다).
      expect(_barFillColor(tester, task.id), isNot(barColorOf(ctx, BarColor.red)));
    });

    testWidgets('다크 모드에서도 사용자 색이 라이트와 다른 값으로 매핑된다',
        (tester) async {
      final store = await _emptyStore();
      store.addNode(
        title: '빨강',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
        barColor: BarColor.red,
      );
      await store.flush();

      await _pumpTimeline(tester, store, brightness: Brightness.light);
      final lightColor = barColorOf(
        tester.element(find.byType(GanttTimeline)),
        BarColor.red,
      );

      await _pumpTimeline(tester, store, brightness: Brightness.dark);
      final darkColor = barColorOf(
        tester.element(find.byType(GanttTimeline)),
        BarColor.red,
      );

      expect(lightColor, isNotNull);
      expect(darkColor, isNotNull);
      // 다크에서 더 밝게 조정되므로 두 값이 달라야 한다(매핑이 휘도를 반영함).
      expect(darkColor, isNot(lightColor));
    });
  });

  group('편집 다이얼로그에서 색 선택', () {
    testWidgets('색 견본을 골라 저장하면 결과의 barColor 가 바뀐다', (tester) async {
      final store = await _emptyStore();
      final node = store.addNode(
        title: '작업',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
      );

      NodeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 파란색 견본을 semantics 라벨로 찾아 탭(swatch 는 색만으로는 식별이 어려워
      // 각 견본에 BarColor.label 이 Semantics 로 붙어 있다).
      final blueSemantics = find.bySemanticsLabel(BarColor.blue.label);
      await tester.ensureVisible(blueSemantics);
      await tester.pumpAndSettle();
      await tester.tap(blueSemantics);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.barColor, BarColor.blue);

      // commitNodeEdit 로 커밋하면 노드에 반영된다(기존 단일 경로).
      commitNodeEdit(store, node, result!);
      expect(store.tree[node.id]!.barColor, BarColor.blue);
      await store.flush();
    });
  });
}
