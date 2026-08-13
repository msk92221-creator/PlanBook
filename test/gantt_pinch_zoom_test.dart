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

/// 두 손가락(핀치) **연속** 확대/축소 + Ctrl+휠 줌 검증.
///
/// 줌은 고정 단계를 건너뛰지 않고 손가락 간격 배율만큼 하루 폭이 연속으로 바뀐다.
/// 눈금 단위(일/주/월/분기/년)는 그 폭에서 자동으로 파생된다.
///
/// **왜 [GanttTimeline] 을 직접 pump 하는가**: 줌 상태는 호출부가 소유하므로
/// [_ZoomHost] 만으로 축척 변화 + 가로 스크롤 보정을 정확히 검증할 수 있다.
/// (PlanPage 의 "오늘로 스크롤" postFrame 이 오프셋을 비결정적으로 만드는 걸 피한다.)

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

GanttMetrics _metricsFor(double dayWidth) => GanttMetrics(
      firstDay: _firstDay,
      lastDay: _lastDay,
      dayWidth: dayWidth,
    );

class _ZoomHost extends StatefulWidget {
  final PlanStore store;
  final ScrollController horizontalController;
  final Size viewSize;
  final double initialDayWidth;

  const _ZoomHost({
    required this.store,
    required this.horizontalController,
    required this.viewSize,
    required this.initialDayWidth,
  });

  @override
  State<_ZoomHost> createState() => _ZoomHostState();
}

class _ZoomHostState extends State<_ZoomHost> {
  late double _dayWidth;

  @override
  void initState() {
    super.initState();
    _dayWidth = widget.initialDayWidth;
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
            metrics: _metricsFor(_dayWidth),
            today: PlanDate(2026, 1, 1),
            horizontalController: widget.horizontalController,
            store: widget.store,
            onDayWidthChange: (w) => setState(() => _dayWidth = w),
          ),
        ),
      ),
    );
  }
}

Future<_ZoomHostState> _pumpHost(
  WidgetTester tester, {
  required PlanStore store,
  required ScrollController horizontalController,
  Size viewSize = const Size(600, 400),
  double initialDayWidth = 18.0,
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
      initialDayWidth: initialDayWidth,
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump();
  return tester.state(find.byType(_ZoomHost)) as _ZoomHostState;
}

/// 두 손가락을 [centerX] 중심 [gap] 간격으로 누르고 각각 [delta1]/[delta2] 만큼
/// 움직인 뒤 뗀다. y 는 헤더 영역(막대 드래그와 간섭 없는 곳).
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
  if (delta1 != Offset.zero) await g1.moveBy(delta1);
  if (delta2 != Offset.zero) await g2.moveBy(delta2);
  await tester.pump();
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

/// Ctrl 을 누른 채 휠을 굴린다. [dy] 가 음수면 위로(확대).
Future<void> _ctrlWheel(
  WidgetTester tester,
  Offset at, {
  required double dy,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(at);
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  group('핀치는 손가락 간격 배율만큼 연속으로 축척을 바꾼다', () {
    testWidgets('간격을 1.5배로 벌리면 하루 폭도 약 1.5배가 된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 10.0,
      );

      // gap=100 → 양쪽 25px 씩 벌리면 거리 150 = 1.5배.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-25, 0),
        delta2: const Offset(25, 0),
      );

      expect(state._dayWidth, closeTo(15.0, 0.6),
          reason: '고정 단계로 점프하지 않고 배율만큼 연속으로 커져야 한다');
    });

    testWidgets('간격을 절반으로 좁히면 하루 폭도 약 절반이 된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 20.0,
      );

      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(25, 0),
        delta2: const Offset(-25, 0),
      );

      expect(state._dayWidth, closeTo(10.0, 0.6));
    });

    testWidgets('아주 조금만 벌려도 그만큼 반응한다(예전의 임계값 대기가 없다)',
        (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 10.0,
      );

      // 양쪽 3px 씩 = 거리 106 → 1.06배. 예전 임계값(1.18)에는 못 미치던 양이라
      // 그때는 아무 반응이 없었다.
      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-3, 0),
        delta2: const Offset(3, 0),
      );

      expect(state._dayWidth, greaterThan(10.0),
          reason: '작은 움직임에도 즉시 반응해야 부드럽게 느껴진다');
      expect(state._dayWidth, lessThan(11.5),
          reason: '움직인 만큼만 바뀌어야 한다(과반응 금지)');
    });

    testWidgets('상한을 넘겨 벌려도 kMaxDayWidth 에서 멈춘다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: kMaxDayWidth,
      );

      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(-80, 0),
        delta2: const Offset(80, 0),
      );

      expect(state._dayWidth, kMaxDayWidth);
    });

    testWidgets('하한 밑으로 좁혀도 kMinDayWidth 에서 멈춘다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: kMinDayWidth,
      );

      await _pinch(
        tester,
        centerX: 300,
        gap: 100,
        delta1: const Offset(45, 0),
        delta2: const Offset(-45, 0),
      );

      expect(state._dayWidth, kMinDayWidth);
    });
  });

  group('눈금 단위는 축척에서 자동으로 파생된다', () {
    test('넓을수록 잘게, 좁을수록 굵게', () {
      expect(GanttZoomLevel.forDayWidth(40), GanttZoomLevel.day);
      expect(GanttZoomLevel.forDayWidth(20), GanttZoomLevel.day);
      expect(GanttZoomLevel.forDayWidth(12), GanttZoomLevel.week);
      expect(GanttZoomLevel.forDayWidth(7), GanttZoomLevel.week);
      expect(GanttZoomLevel.forDayWidth(4), GanttZoomLevel.month);
      expect(GanttZoomLevel.forDayWidth(2), GanttZoomLevel.month);
      expect(GanttZoomLevel.forDayWidth(1.2), GanttZoomLevel.quarter);
      expect(GanttZoomLevel.forDayWidth(0.8), GanttZoomLevel.quarter);
      expect(GanttZoomLevel.forDayWidth(0.5), GanttZoomLevel.year);
      expect(GanttZoomLevel.forDayWidth(kMinDayWidth), GanttZoomLevel.year);
    });

    testWidgets('핀치로 축척이 줄면 눈금 단위도 따라 굵어진다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 20.0, // 일 눈금
      );
      expect(_metricsFor(state._dayWidth).zoom, GanttZoomLevel.day);

      // 0.25배로 좁힌다 → 5px/일 → 월 눈금.
      await _pinch(
        tester,
        centerX: 300,
        gap: 160,
        delta1: const Offset(60, 0),
        delta2: const Offset(-60, 0),
      );

      expect(_metricsFor(state._dayWidth).zoom, GanttZoomLevel.month,
          reason: '축척이 줄면 헤더 눈금도 자동으로 굵어져야 한다');
    });
  });

  group('줌 후 보고 있던 날짜 유지 (스크롤 오프셋 보정)', () {
    testWidgets('핀치 중심의 날짜가 줌 후에도 같은 화면 x 근처에 남는다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        viewSize: const Size(600, 400),
        initialDayWidth: 40.0,
      );

      ctrl.jumpTo(800);
      await tester.pumpAndSettle();
      final offsetBefore = ctrl.offset;

      const focalX = 300.0;
      final focalDate = _metricsFor(40.0).dayColumnForX(offsetBefore + focalX);

      await _pinch(
        tester,
        centerX: focalX,
        gap: 100,
        delta1: const Offset(25, 0),
        delta2: const Offset(-25, 0),
      );

      final newMetrics = _metricsFor(state._dayWidth);
      final dateAtFocal = newMetrics.dayColumnForX(ctrl.offset + focalX);
      // 축척이 바뀌면 하루 칸이 좁아져 반올림 오차가 생기므로 며칠 이내면 통과.
      expect(daysBetween(focalDate, dateAtFocal).abs(), lessThanOrEqualTo(2),
          reason: '핀치 중심 날짜가 화면 같은 자리 근처에 남아야 한다');
    });
  });

  group('데스크톱: Ctrl + 마우스 휠', () {
    testWidgets('Ctrl+휠 위로 굴리면 kWheelZoomStep 배만큼 확대된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 10.0,
      );

      await _ctrlWheel(tester, const Offset(300, 26), dy: -1);
      expect(state._dayWidth, closeTo(10.0 * kWheelZoomStep, 0.01));
    });

    testWidgets('Ctrl+휠 아래로 굴리면 그만큼 축소된다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 10.0,
      );

      await _ctrlWheel(tester, const Offset(300, 26), dy: 1);
      expect(state._dayWidth, closeTo(10.0 / kWheelZoomStep, 0.01));
    });

    testWidgets('Ctrl 없는 휠은 축척을 바꾸지 않는다', (tester) async {
      final store = await _emptyStore();
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      final state = await _pumpHost(
        tester,
        store: store,
        horizontalController: ctrl,
        initialDayWidth: 10.0,
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(const Offset(300, 26));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -1)));
      await tester.pumpAndSettle();

      expect(state._dayWidth, 10.0);
    });
  });
}
