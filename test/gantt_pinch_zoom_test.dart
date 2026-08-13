import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

/// 두 손가락(핀치) 확대/축소 + Ctrl+휠 줌 을 검증하는 위젯 테스트.
///
/// **왜 [GanttTimeline] 을 직접 pump 하는가**: 핀치로 줌이 바뀌면 [GanttTimeline] 이
/// `onZoomChange` 로 새 줌을 알리고, 호출부([_ZoomHost]) 가 metrics 를 새로 계산해
/// rebuild 한다. 줌 상태 소유자가 분리되어 있으므로 [PlanPage] 까지 띄울 필요 없이
/// [_ZoomHost] 만으로 줌 전환 + 가로 스크롤 오프셋 보정을 정확히 검증할 수 있다.
/// (gantt_drag_widget_test.dart 와 같은 취지 — PlanPage 의 "오늘로 스크롤" postFrame
/// 이 오프셋을 비결정적으로 만드는 걸 피한다.)

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

/// 타임라인의 날짜 범위. 2026-01-01 ~ 2026-03-31 (inclusive = 90일).
final _firstDay = PlanDate(2026, 1, 1);
final _lastDay = PlanDate(2026, 3, 31);

GanttMetrics _metricsFor(GanttZoomLevel zoom) => GanttMetrics(
      firstDay: _firstDay,
      lastDay: _lastDay,
      dayWidth: zoom.dayWidth,
      zoom: zoom,
    );

/// [GanttTimeline] 을 감싸며 줌 상태를 소유하는 호스트. `onZoomChange` 가 오면
/// 줌을 바꿔 metrics 를 새로 계산하고 rebuild 한다(PlanPage 의 역할을 최소로 흉내).
class _ZoomHost extends StatefulWidget {
  final PlanStore store;
  final ScrollController horizontalController;
  final Size viewSize;
  final GanttZoomLevel initialZoom;

  const _ZoomHost({
    required this.store,
    required this.horizontalController,
    required this.viewSize,
    required this.initialZoom,
  });

  @override
  State<_ZoomHost> createState() => _ZoomHostState();
}

class _ZoomHostState extends State<_ZoomHost> {
  late GanttZoomLevel _zoom;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
  }

  @override
  Widget build(BuildContext context) {
    final rows = flattenVisibleRows(widget.store.tree);
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: widget.viewSize.width,
          height: widget.viewSize.height,
          child: GanttTimeline(
            tree: widget.store.tree,
            rows: rows,
            metrics: _metricsFor(_zoom),
            today: PlanDate(2026, 1, 1),
            horizontalController: widget.horizontalController,
            store: widget.store,
            onZoomChange: (z) => setState(() => _zoom = z),
          ),
        ),
      ),
    );
  }
}

/// [_ZoomHost] 를 고정 뷰 크기로 pump 한다.
Future<_ZoomHostState> _pumpHost(
  WidgetTester tester, {
  required PlanStore store,
  required ScrollController horizontalController,
  Size viewSize = const Size(600, 400),
  GanttZoomLevel initialZoom = GanttZoomLevel.week,
}) async {
  tester.view.physicalSize = viewSize * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _ZoomHost(
      store: store,
      horizontalController: horizontalController,
      viewSize: viewSize,
      initialZoom: initialZoom,
    ),
  );
  await tester.pumpAndSettle();
  // 주입한 컨트롤러가 attach 될 때까지 한 프레임 더.
  await tester.pump();
  return tester.state(find.byType(_ZoomHost)) as _ZoomHostState;
}

/// 두 손가락을 [centerX] 를 중심으로 간격 [gap] 으로 동시에 누르고, 각각
/// [delta1]/[delta2] 만큼 이동시킨 뒤 손을 뗀다. 핀치 제스처를 흉내낸다.
/// 두 손가락의 y 는 헤더 영역(제스처 디텍터가 없는 곳) 으로 둬 막대 드래그와
/// 간섭하지 않게 한다.
Future<void> _pinch(
  WidgetTester tester, {
  required double centerX,
  double gap = 100,
  Offset delta1 = Offset.zero,
  Offset delta2 = Offset.zero,
  double y = 26,
}) async {
  final g1 = await tester.startGesture(Offset(centerX - gap / 2, y));
  final g2 = await tester.startGesture(Offset(centerX + gap / 2, y));
  // 두 손가락이 모두 눌린 뒤(핀치 기준 거리 확정) 이동시킨다.
  if (delta1 != Offset.zero) {
    await g1.moveBy(delta1);
  }
  if (delta2 != Offset.zero) {
    await g2.moveBy(delta2);
  }
  await tester.pump();
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  group('핀치 확대/축소 — 3단계 줌 사이를 오간다', () {
    testWidgets('두 손가락을 벌리면 한 단계 확대된다 (week → day)', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      // gap=100 → 기준 거리 100. 양쪽으로 30px 씩 더 벌리면 거리 160, 비율 1.6 ≥ 1.4.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-30, 0),
        delta2: const Offset(30, 0),
      );

      expect(state._zoom, GanttZoomLevel.day,
          reason: '핀치 아웃(벌리기) 은 확대 방향으로 한 단계 이동해야 한다');
    });

    testWidgets('두 손가락을 좁히면 한 단계 축소된다 (week → month)', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      // gap=100 → 기준 거리 100. 양쪽으로 20px 씩 좁히면 거리 60, 비율 0.6 ≤ 1/1.4.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(20, 0),
        delta2: const Offset(-20, 0),
      );

      expect(state._zoom, GanttZoomLevel.month,
          reason: '핀치 인(좁히기) 은 축소 방향으로 한 단계 이동해야 한다');
    });

    testWidgets('year(최대 축소) 에서 더 좁혀도 그대로 year 다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.year,
      );

      // 아무리 세게 좁혀도(거리 100 → 10) year 아래 단계는 없다.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(45, 0),
        delta2: const Offset(-45, 0),
      );

      expect(state._zoom, GanttZoomLevel.year, reason: '최대 축소 단계에서 더 축소 불가');
    });

    testWidgets('day(최대 확대) 에서 더 벌려도 그대로 day 다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.day,
      );

      // 아무리 세게 벌려도 day 위 단계는 없다.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-80, 0),
        delta2: const Offset(80, 0),
      );

      expect(state._zoom, GanttZoomLevel.day, reason: '최대 확대 단계에서 더 확대 불가');
    });

    testWidgets('임계값 이하로 살짝 움직이면 줌이 바뀌지 않는다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      // gap=100 → 거리 100. 5px 씩만 벌리면 거리 110, 비율 1.10 < 1.18. → 변화 없음.
      // (임계값을 1.4 → 1.18 로 낮췄으므로 이 테스트의 이동량도 함께 줄인다.
      //  1.4 기준이던 예전 값 10px 씩(=1.2배) 은 이제 임계값을 넘어버린다.)
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-5, 0),
        delta2: const Offset(5, 0),
      );

      expect(state._zoom, GanttZoomLevel.week,
          reason: '임계값($kPinchZoomInRatio 배) 미만이면 줌 유지');
    });
  });

  group('줌 후 보고 있던 날짜 유지 (스크롤 오프셋 보정)', () {
    testWidgets('핀치 중심의 날짜가 줌 후에도 같은 화면 x 에 남는다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      // day 줌(dayWidth=40) 으로 시작. content 폭 = 90*40 = 3600, 뷰 폭 600 → 스크롤 가능.
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        viewSize: const Size(600, 400),
        initialZoom: GanttZoomLevel.day,
      );

      // 스크롤을 오른쪽으로 어느 정도 옮겨둔다(오프셋 800).
      ctrl.jumpTo(800);
      await tester.pumpAndSettle();
      final offsetBefore = ctrl.offset;

      // 핀치 중심을 화면 x=300 에 둔다. 그 위치의 날짜(오프셋+300 = 1100px = 27.5일째 칸
      // → floor → 27일 → firstDay+27 = 2026-01-28).
      const focalX = 300.0;
      // 축소(day → week) 시킨다(두 손가락을 좁힌다). gap=100 기준, 25px 씩 좁히면
      // 거리 50, 비율 0.5 ≤ 1/1.4.
      await _pinch(
        tester,
        centerX: focalX,
        gap: 100,
        delta1: const Offset(25, 0),
        delta2: const Offset(-25, 0),
      );

      expect(state._zoom, GanttZoomLevel.week);

      // 보정 후: newMetrics.xForDate(focalDate) - focalX == newOffset (clamp 내).
      final focalDate = _metricsFor(GanttZoomLevel.day).dayColumnForX(
        offsetBefore + focalX,
      );
      final newMetrics = _metricsFor(GanttZoomLevel.week);
      final expectedOffset =
          (newMetrics.xForDate(focalDate) - focalX).clamp(0.0, ctrl.position.maxScrollExtent);
      expect(ctrl.offset, closeTo(expectedOffset, 0.5),
          reason: '핀치 중심 날짜가 같은 화면 x(=$focalX) 에 오도록 오프셋이 보정돼야 한다');
      // 그 날짜가 실제로 화면 x=focalX 에 있는지도 확인.
      final dateAtFocal = newMetrics.dayColumnForX(ctrl.offset + focalX);
      expect(dateAtFocal, focalDate);
    });
  });

  group('데스크톱: Ctrl + 마우스 휠', () {
    testWidgets('Ctrl 을 누르고 휠을 위로 굴리면 한 단계 확대된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      // Ctrl 키를 누른 상태로 마우스 휠 "위"(scrollDelta.dy 가 음수) 를 굴린다.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _wheel(tester, const Offset(300, 26), scrollDeltaY: -100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(state._zoom, GanttZoomLevel.day,
          reason: 'Ctrl+휠 위 = 확대 한 단계');
    });

    testWidgets('Ctrl 을 누르고 휠을 아래로 굴리면 한 단계 축소된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _wheel(tester, const Offset(300, 26), scrollDeltaY: 100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(state._zoom, GanttZoomLevel.month, reason: 'Ctrl+휠 아래 = 축소 한 단계');
    });

    testWidgets('Ctrl 없이 휠을 굴리면 줌이 바뀌지 않는다 (기본 스크롤 동작)', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialZoom: GanttZoomLevel.week,
      );

      // Ctrl 키 없이 휠만.
      await _wheel(tester, const Offset(300, 26), scrollDeltaY: -100);
      await tester.pumpAndSettle();

      expect(state._zoom, GanttZoomLevel.week, reason: 'Ctrl 없는 휠은 줌을 바꾸지 않는다');
    });
  });
}

/// [offset](위젯 전역 좌표) 위치에서 마우스 휠 [PointerScrollEvent] 를 발생시킨다.
/// [scrollDeltaY] 가 양수면 휠 아래, 음수면 휠 위. [GanttTimeline] 의 Listener 가
/// onPointerSignal 로 받는다.
Future<void> _wheel(
  WidgetTester tester,
  Offset offset, {
  required double scrollDeltaY,
}) async {
  // 마우스 포인터를 해당 위치에 올려 hit-test 경로에 넣은 뒤 휠 시그널을 발생시킨다.
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: offset);
  await tester.pump();
  tester.binding.handlePointerEvent(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: offset,
      scrollDelta: Offset(0, scrollDeltaY),
    ),
  );
  await tester.pump();
  await gesture.removePointer();
}
