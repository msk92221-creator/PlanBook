/// Gantt 타임라인(우측 패널).
///
/// 구성:
/// - 상단 헤더: [buildHeaderCells] 로 만든 날짜 눈금. 가로 스크롤 가능.
/// - 본체: 보이는 행([FlatRow]) 목록을 같은 높이/순서로 렌더. 각 행에 기간 막대(bar).
/// - 배경: 일 단위에서 주말 칼럼 음영. 월/주 단위는 범용 배경.
/// - "오늘" 세로선: [GanttMetrics.xForToday] 위치에 전체 높이의 빨간 선.
///
/// 3단계: bar 드래그(이동)/양끝 핸들 드래그(시작/종료일 변경). 모든 변경은
/// [store] 단일 경로로 커밋.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/bar_color.dart';
import '../../domain/milestone_query.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_rollup.dart';
import '../../domain/plan_tree.dart';
import 'gantt_metrics.dart';
import 'gantt_theme.dart';
import 'tree_flatten.dart';

/// "열린 기간"(종료일 미정) 막대의 semantics 라벨(위젯 테스트 검증용).
/// [kDoneSemantics]/[kOnHoldSemantics] 와 같은 목적이지만, 상수 파일(gantt_theme.dart)
/// 은 이번 변경 범위가 아니므로 같은 스타일의 로컬 상수로 여기에 둔다.
const String kOpenEndedSemantics = '종료일 미정';

/// 우측 Gantt 타임라인 패널.
///
/// [verticalController] 는 좌측 트리 패널과 동기화되는 세로 스크롤 컨트롤러(외부 주입).
/// [horizontalController] 는 가로 스크롤 컨트롤러(초기 "오늘" 위치 보정에도 사용).
///
/// **두 손가락(핀치) 확대/축소** 가 추가됐다. [StatefulWidget] 인 이유는 핀치 판정을
/// 위해 현재 눌려 있는 포인터들을 직접 추적해야 하기 때문이다.
class GanttTimeline extends StatefulWidget {
  final PlanTree tree;
  final List<FlatRow> rows;
  final GanttMetrics metrics;
  final PlanDate today;

  /// 좌측 패널과 공유하는 세로 스크롤러.
  final ScrollController? verticalController;

  /// 가로 스크롤러(외부 Scrollbar 연결용).
  final ScrollController? horizontalController;

  /// 변경용 store. null 이면 드래그/리사이즈 비활성(읽기 전용).
  final PlanStore? store;

  /// 현재 강조(선택) 표시할 노드 id(Today/Calendar/검색에서 넘어올 때 등).
  final String? selectedNodeId;

  /// **핀치 / Ctrl+휠 로 줌 단계가 바뀌었을 때** 호출. [PlanPage] 가 줌 상태를
  /// 소유하고 있으므로, 여기서는 새 줌을 알려주기만 한다(상태를 직접 바꾸지 않는다).
  /// null 이면(단독 테스트 등) 핀치/휠 줌이 비활성이다.
  final ValueChanged<GanttZoomLevel>? onZoomChange;

  const GanttTimeline({
    super.key,
    required this.tree,
    required this.rows,
    required this.metrics,
    required this.today,
    this.verticalController,
    this.horizontalController,
    this.store,
    this.selectedNodeId,
    this.onZoomChange,
  });

  @override
  State<GanttTimeline> createState() => _GanttTimelineState();
}

class _GanttTimelineState extends State<GanttTimeline> {
  // ----- 핀치 줌 상태 -----
  // **왜 GestureDetector(onScaleUpdate) 가 아니라 Listener 로 포인터를 직접 세는가**:
  // ScaleGestureRecognizer 는 손가락 1개일 때도 제스처 아레나에 참여해서, 가로/세로
  // 스크롤과 bar 드래그(날짜를 실제로 바꾸는 기능) 를 이겨버린다. 그러면 스크롤이
  // 안 되거나 막대를 못 옮기게 된다. Listener 는 아레나에 참여하지 않으므로 기존
  // 포인터 동작(스크롤/드래그) 이 100% 그대로 살아 있다. 핀치는 "포인터가 2개 이상"
  // 일 때만 판정하므로 1개 손가락 동작은 전혀 간섭하지 않는다.
  // → 절대 무심코 GestureDetector(onScale*) 로 바꾸지 말 것. 스크롤이 죽는다.

  /// 현재 눌려 있는 포인터(id → 최근 뷰 로컬 위치). 1개 = 일반 드래그/스크롤,
  /// 2개 이상 = 핀치 후보.
  final Map<int, Offset> _pointers = {};

  /// 핀치 "기준 거리". 두 번째 손가락이 닿은 순간(또는 한 단계 줌이 바뀐 직후) 의
  /// 두 포인터 사이 거리. 여기서부터 배율을 재서 임계값을 넘으면 한 단계씩 바꾼다.
  double? _pinchBaseDistance;

  /// 줌이 바뀐 뒤 적용할 가로 스크롤 오프셋 보정 정보.
  /// (핀치/휠 중심의 날짜, 그 중심의 뷰 로컬 x).
  /// 줌 변경 → [PlanPage] 가 metrics 를 새로 계산해 rebuild → [didUpdateWidget] 에서
  /// 새 metrics 기준으로 보정을 적용한다(동기적으론 새 metrics 가 아직 없다).
  ({PlanDate focalDate, double focalLocalX})? _pendingScroll;
  GanttZoomLevel? _pendingFromZoom;

  ScrollController? get _hCtrl => widget.horizontalController;

  @override
  void didUpdateWidget(covariant GanttTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 줌이 실제로 바뀌어 새 metrics 가 들어왔으면, 보류 중이던 스크롤 보정을 적용한다.
    final pending = _pendingScroll;
    if (pending != null &&
        _pendingFromZoom != null &&
        widget.metrics.zoom != _pendingFromZoom) {
      _pendingScroll = null;
      _pendingFromZoom = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyScrollCorrection(pending.focalDate, pending.focalLocalX);
      });
    }
  }

  /// 뷰 로컬 좌표를 구하기 위한 렌더 박스(없으면 null).
  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  Offset _localOf(Offset global) {
    final box = _box;
    return box != null ? box.globalToLocal(global) : Offset.zero;
  }

  /// 두 점 사이 거리.
  double _distance(Offset a, Offset b) => (a - b).distance;

  /// 현재 두 개 포인터 사이 거리(2개 이상이면 처음 2개 기준).
  double? _currentPairDistance() {
    if (_pointers.length < 2) return null;
    final iter = _pointers.values.take(2).toList();
    return _distance(iter[0], iter[1]);
  }

  /// 핀치 중심(두 손가락의 가운데) 의 뷰 로컬 좌표.
  Offset _pinchFocalLocal() {
    final iter = _pointers.values.take(2).toList();
    return (iter[0] + iter[1]) / 2;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = _localOf(event.position);
    // 두 번째 손가락이 닿으면 핀치 기준 거리를 잡는다.
    if (_pointers.length == 2) {
      _pinchBaseDistance = _currentPairDistance();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = _localOf(event.position);
    if (_pointers.length >= 2) _evaluatePinch();
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinchBaseDistance = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinchBaseDistance = null;
  }

  /// 현재 두 손가락 거리의 배율을 기준 거리와 비교해 한 단계 줌을 바꾼다.
  void _evaluatePinch() {
    final base = _pinchBaseDistance;
    final cur = _currentPairDistance();
    if (base == null || cur == null || base <= 0) return;

    final ratio = cur / base;
    GanttZoomLevel? next;
    if (ratio >= kPinchZoomInRatio) {
      next = _zoomIn(widget.metrics.zoom);
    } else if (ratio <= kPinchZoomOutRatio) {
      next = _zoomOut(widget.metrics.zoom);
    }
    if (next == null) return; // 경계 밖이거나 임계값 미달 → 아무것도 안 함.

    // 한 단계 바뀌었으니 기준 거리를 현재 거리로 리셋. 이래야 한 번의 핀치 동작이
    // 여러 단계를 순식간에 건너뛰지 않는다(손가락을 더 벌려야 다음 단계로 간다).
    _pinchBaseDistance = cur;
    final focal = _pinchFocalLocal();
    _requestZoom(next, focal.dx);
  }

  /// [newZoom] 으로 줌을 바꾸도록 [PlanPage] 에 알리고, 줌 후 스크롤 보정을 예약.
  void _requestZoom(GanttZoomLevel newZoom, double focalLocalX) {
    if (widget.onZoomChange == null) return; // 단독 테스트 등: 줌 변경 불가.
    final offset = (_hCtrl?.hasClients ?? false) ? _hCtrl!.offset : 0.0;
    // 핀치/휠 중심이 가리키는 날짜(현재 metrics + 현재 스크롤 오프셋 기준).
    final focalDate = widget.metrics.dayColumnForX(offset + focalLocalX);
    _pendingScroll = (focalDate: focalDate, focalLocalX: focalLocalX);
    _pendingFromZoom = widget.metrics.zoom;
    widget.onZoomChange!(newZoom);
  }

  /// 줌 변경 후 새 metrics 로, 보고 있던 날짜가 같은 화면 위치에 오도록 보정.
  void _applyScrollCorrection(PlanDate focalDate, double focalLocalX) {
    final ctrl = _hCtrl;
    if (ctrl == null || !ctrl.hasClients) return;
    final newX = widget.metrics.xForDate(focalDate) - focalLocalX;
    ctrl.jumpTo(newX.clamp(0.0, ctrl.position.maxScrollExtent));
  }

  /// 데스크톱(Windows 등) 에서 **Ctrl + 마우스 휠** 로 줌. 핀치가 없는 환경에서
  /// 같은 3단계 줌을 오가게 한다. Ctrl 을 누르지 않은 일반 휠은 여기서 아무것도
  /// 하지 않는다 — 세로/shift+가로 스크롤은 각 스크롤러의 기존 동작에 맡긴다.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) return;
    // Ctrl+휠 위 = 확대, 아래 = 축소.
    final down = event.scrollDelta.dy > 0;
    final next = down
        ? _zoomOut(widget.metrics.zoom)
        : _zoomIn(widget.metrics.zoom);
    if (next == null) return; // 이미 경계면이면 아무것도 안 함.
    final focal = _localOf(event.position);
    _requestZoom(next, focal.dx);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight;
        final contentWidth = metrics.totalWidth;
        // Listener(포인터 직접 추적) 로 타임라인 전체를 감싼다. 아레나에 참여하지
        // 않으므로 아래 SingleChildScrollView / ListView / bar 의 기존 스크롤·
        // 드래그 제스처에 전혀 영향을 주지 않는다.
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: _onPointerSignal,
          child: Scrollbar(
            controller: widget.horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: widget.horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth <= 0 ? 1.0 : contentWidth,
                height: viewHeight,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        SizedBox(
                          height: kHeaderHeight,
                          width: contentWidth,
                          child: _TimelineHeader(metrics: metrics),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: widget.verticalController,
                            itemExtent: kRowHeight,
                            itemCount: widget.rows.length,
                            padding: EdgeInsets.zero,
                            itemBuilder: (context, i) => _TimelineRow(
                              row: widget.rows[i],
                              tree: widget.tree,
                              metrics: metrics,
                              store: widget.store,
                              selected: widget.rows[i].id == widget.selectedNodeId,
                              today: widget.today,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 주말 음영 + 오늘 선은 헤더 아래 본체 영역만 덮도록 위에서부터.
                    if (metrics.zoom == GanttZoomLevel.day)
                      Positioned(
                        left: 0,
                        top: kHeaderHeight,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: _WeekendBackground(metrics: metrics),
                        ),
                      ),
                    // 오늘 세로선(전체 높이). 헤더 위까지 연장.
                    _TodayOverlay(metrics: metrics, today: widget.today),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 핀치 줌 임계값. 기준 거리 대비 배율이 이 값을 넘으면 한 단계 확대한다.
/// 1.4 배로 잡는다(요구사항 예시). 축소는 이 값의 역수(1/1.4) 밑으로 내려가야 한다.
const double kPinchZoomInRatio = 1.4;
const double kPinchZoomOutRatio = 1.0 / 1.4;

/// [z] 에서 한 단계 더 확대(month → week → day). 이미 day 면 null(변화 없음).
GanttZoomLevel? _zoomIn(GanttZoomLevel z) {
  switch (z) {
    case GanttZoomLevel.month:
      return GanttZoomLevel.week;
    case GanttZoomLevel.week:
      return GanttZoomLevel.day;
    case GanttZoomLevel.day:
      return null; // 최대 확대. 더 벌려도 그대로.
  }
}

/// [z] 에서 한 단계 더 축소(day → week → month). 이미 month 면 null(변화 없음).
GanttZoomLevel? _zoomOut(GanttZoomLevel z) {
  switch (z) {
    case GanttZoomLevel.day:
      return GanttZoomLevel.week;
    case GanttZoomLevel.week:
      return GanttZoomLevel.month;
    case GanttZoomLevel.month:
      return null; // 최대 축소. 더 좁혀도 그대로.
  }
}

// ---------------------------------------------------------------------------
// 헤더
// ---------------------------------------------------------------------------

class _TimelineHeader extends StatelessWidget {
  final GanttMetrics metrics;
  const _TimelineHeader({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cells = buildHeaderCells(metrics);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRect(
      child: CustomPaint(
        painter: _HeaderPainter(
          cells: cells,
          zoom: metrics.zoom,
          baseline: theme.colorScheme,
          dividerColor: scheme.outlineVariant,
          labelColor: scheme.onSurface,
          weekendColor: scheme.errorContainer,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HeaderPainter extends CustomPainter {
  final List<GanttHeaderCell> cells;
  final GanttZoomLevel zoom;
  final ColorScheme baseline;
  final Color dividerColor;
  final Color labelColor;
  final Color weekendColor;

  const _HeaderPainter({
    required this.cells,
    required this.zoom,
    required this.baseline,
    required this.dividerColor,
    required this.labelColor,
    required this.weekendColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 배경.
    final bgPaint = Paint()..color = baseline.surface;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final div = Paint()
      ..color = dividerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 일 단위에서 주말 칸 배경.
    if (zoom == GanttZoomLevel.day) {
      final wkPaint = Paint()..color = weekendColor.withValues(alpha: 0.5);
      for (final c in cells) {
        if (c.isWeekend && c.x >= -c.width && c.x < size.width) {
          canvas.drawRect(Rect.fromLTWH(c.x, 0, c.width, size.height), wkPaint);
        }
      }
    }

    // 텍스트는 line별로.
    final baseStyle = TextStyle(
      color: labelColor,
      fontSize: zoom == GanttZoomLevel.day ? 10 : 11,
      fontWeight: FontWeight.w500,
    );
    final emphasizeStyle = TextStyle(
      color: labelColor,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );

    for (final c in cells) {
      // 셀 오른쪽 경계선.
      final right = c.x + c.width;
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), div);

      // 라벨.
      final span = TextSpan(
        text: c.label,
        style: c.emphasize ? emphasizeStyle : baseStyle,
      );
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      final tx = (c.x + c.width / 2 - painter.width / 2).clamp(
        2.0,
        size.width - painter.width - 2,
      );
      final ty = (size.height - painter.height) / 2;
      painter.paint(canvas, Offset(tx, ty));

      // 일 단위에서 요일 약자(작게 위에). 폭이 충분할 때만.
      if (zoom == GanttZoomLevel.day && c.width >= 26) {
        final wd = weekdayShortLabel(c.date);
        final wdSpan = TextSpan(
          text: wd,
          style: TextStyle(
            color: c.isWeekend
                ? baseline.error
                : labelColor.withValues(alpha: 0.6),
            fontSize: 9,
          ),
        );
        final wdPainter = TextPainter(
          text: wdSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        final wdx = (c.x + c.width / 2 - wdPainter.width / 2);
        wdPainter.paint(canvas, Offset(wdx, 4));
      }
    }

    // 헤더 하단 구분선.
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = dividerColor
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _HeaderPainter old) =>
      old.cells != cells ||
      old.zoom != zoom ||
      old.baseline != baseline ||
      old.dividerColor != dividerColor ||
      old.labelColor != labelColor ||
      old.weekendColor != weekendColor;
}

// ---------------------------------------------------------------------------
// 주말 배경(본체 영역)
// ---------------------------------------------------------------------------

class _WeekendBackground extends StatelessWidget {
  final GanttMetrics metrics;
  const _WeekendBackground({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _WeekendPainter(
        offsets: weekendDayOffsets(metrics),
        dayWidth: metrics.dayWidth,
        color: scheme.errorContainer.withValues(alpha: 0.35),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _WeekendPainter extends CustomPainter {
  final List<int> offsets;
  final double dayWidth;
  final Color color;
  const _WeekendPainter({
    required this.offsets,
    required this.dayWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final o in offsets) {
      final x = o * dayWidth;
      canvas.drawRect(Rect.fromLTWH(x, 0, dayWidth, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekendPainter old) =>
      old.offsets != offsets || old.dayWidth != dayWidth || old.color != color;
}

// ---------------------------------------------------------------------------
// 오늘 세로선
// ---------------------------------------------------------------------------

class _TodayOverlay extends StatelessWidget {
  final GanttMetrics metrics;
  final PlanDate today;
  const _TodayOverlay({required this.metrics, required this.today});

  @override
  Widget build(BuildContext context) {
    final x = metrics.xForToday(today);
    if (!metrics.containsDate(today)) return const SizedBox.shrink();
    return Positioned(
      left: x,
      top: 0,
      bottom: 0,
      width: 2.0,
      child: IgnorePointer(
        // 2px 선 + 선 위에 겹쳐 그리는 '오늘' 라벨. 라벨이 선 폭(2px)에
        // 눌려 잘리지 않도록 clip 없는 Stack 으로 구성.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: ColoredBox(color: kTodayColor)),
            Positioned(
              left: -1,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: const BoxDecoration(
                  color: kTodayColor,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(3),
                    bottomRight: Radius.circular(3),
                  ),
                ),
                child: const Text(
                  '오늘',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 행 + 바
// ---------------------------------------------------------------------------

class _TimelineRow extends StatelessWidget {
  final FlatRow row;
  final PlanTree tree;
  final GanttMetrics metrics;
  final PlanStore? store;
  final bool selected;

  /// "오늘". 열린 기간(종료일 미정) 노드의 막대를 "오늘"까지 그리기 위해 쓴다.
  /// 위젯 안에서 DateTime.now() 로 직접 만들지 않고 [GanttTimeline] 으로부터
  /// 주입받는다(테스트에서 날짜를 고정할 수 있어야 한다).
  final PlanDate today;
  const _TimelineRow({
    required this.row,
    required this.tree,
    required this.metrics,
    this.store,
    this.selected = false,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final node = row.node;
    // rollup 은 두 분기(마일스톤/일반 bar) 모두에서 "이 행이 자식 기반 요약인가"
    // 를 판단하는 데 쓰인다 — 한 번만 계산해서 공유한다.
    final rollup = computeRollup(tree, node.id);
    final isParentSummary = rollup.computedFromChildren;

    // **날짜 드래그/리사이즈 허용 여부**(렌더링과는 분리된 개념).
    // rollup 요약(computedFromChildren==true) 행은 화면에 보이는 기간이 자식들로부터
    // "계산된" 값이라 사용자가 직접 저장한 원본 날짜가 아니다 — 이걸 드래그로 바꾸면
    // 실제로는 아무 Task 도 바뀌지 않거나(요약이라 원본이 없음), 의도와 다른 자식의
    // 날짜가 암묵적으로 바뀌는 것처럼 보일 수 있다. 그래서 요약 행은 드래그를 막는다.
    // (effective_dates.dart 의 isDateDerived 와는 별개 개념이다 — 그건 화면 표시용
    // 파생값이고, autoRollup 여부와 무관하게 항상 계산된다. 이 canDragDate 는
    // rollup 의 computedFromChildren, 즉 "이 행이 지금 화면에 보여주는 날짜가
    // 사용자가 저장한 원본이 맞는가" 를 뜻한다 — 오늘 기준 실제 bar/마커 드래그를
    // 허용할지 결정하는 유일한 기준이다. 두 개념을 섞지 않는다.)
    final canDragDate = store != null && !isParentSummary;

    // 마일스톤은 완전히 다른 표시 분기다 — 기존 bar 로직을 억지로 재사용하지 않는다.
    // (기준일: endDate 우선, 없으면 startDate, 둘 다 없으면 Gantt 에 표시 안 함)
    if (node.isMilestone) {
      final anchor = node.endDate ?? node.startDate;
      return _rowFrame(
        context,
        child: anchor == null
            ? const _NoDateLabel()
            : _MilestoneMarker(
                key: ValueKey('milestone-marker-${node.id}'),
                metrics: metrics,
                date: anchor,
                status: node.status,
                title: node.title,
                nodeId: node.id,
                originalStart: node.startDate,
                originalEnd: node.endDate,
                barColor: node.barColor,
                // 마일스톤은 "기간" 이 아니라 "시점" 이므로 리사이즈 개념이 없다
                // (canResizeDate 는 항상 false — 좌우 핸들 자체를 만들지 않는다).
                // 좌우 이동(canDragDate)만 허용한다.
                canDrag: canDragDate,
                store: store,
              ),
      );
    }

    final effectiveStart = rollup.computedFromChildren
        ? rollup.startDate
        : node.startDate;
    final effectiveEnd = rollup.computedFromChildren
        ? rollup.endDate
        : node.endDate;
    final effectiveProgress = rollup.progress;
    final isDone = rollup.isDone;

    // 자손 마일스톤은 요약 바 위에 겹쳐 그린다 — 부모를 접어도 기점이 보이게.
    // (마일스톤 자기 행은 위쪽 분기에서 이미 처리됐으므로 여기 오지 않는다)
    final descendantMilestones = collectDescendantMilestones(tree, node.id);

    // **열린 기간**(시작일은 있고 종료일이 미정) 인가?
    // leaf 노드는 startDate 만 있을 때, rollup 요약은 자식들로부터 계산된
    // endDate 가 없을 때(start 는 있음) 열린 기간으로 본다. 이때 막대를
    // start~오늘 까지 그린다(단 오늘이 start 이전이면 start 당일 하루치만).
    // 단, 시작만 미정이고 종료만 있는 경우는 이번 작업 범위가 아니므로 그대로
    // "날짜 미정" 라벨을 유지한다.
    final isOpenEnded = effectiveStart != null && effectiveEnd == null;

    Widget barChild;
    if (effectiveStart != null && effectiveEnd != null) {
      barChild = _GanttBar(
        // 막대를 테스트에서 좌표로 집어내기 위한 키. semantics 라벨로 찾으면
        // 막대 안쪽 제목 Text 의 semantics 가 병합되어 엉뚱한 상위 노드가
        // 잡히므로(그 노드의 사각형은 행 전체다) 키로 찾는 편이 정확하다.
        key: ValueKey('gantt-bar-${node.id}'),
        metrics: metrics,
        start: effectiveStart,
        end: effectiveEnd,
        progress: effectiveProgress,
        done: isDone,
        // 요약(rollup) bar 는 기존 2상태(완료/미완료) 유지 — status 는
        // leaf(또는 autoRollup=false) 노드에서만 4상태로 표시한다.
        status: isParentSummary ? null : node.status,
        isSummary: isParentSummary,
        title: node.title,
        nodeId: node.id,
        // 드래그는 노드 원본 기간 기준(rollup 요약은 드래그 대상 아님).
        // (canDragDate 와 !isSummary 는 store!=null 여부만 다를 뿐 동일한 정책.
        //  _GanttBar 내부의 _canDrag 가 이미 이 판단을 하므로 그대로 둔다.)
        draggableStart: node.startDate,
        draggableEnd: node.endDate,
        barColor: node.barColor,
        store: store,
      );
    } else if (isOpenEnded) {
      // 열린 기간 막대: start~오늘 (오늘이 start 이전이면 start 하루치만).
      // 오른쪽 끝은 사용자가 저장한 값이 아니라 "오늘"이라는 계산값이므로 드래그/
      // 리사이즈를 막는다(store 를 넘기지 않는다 → 어떤 날짜도 커밋되지 않는다).
      final openEnd = daysBetween(effectiveStart, today) >= 0
          ? today
          : effectiveStart;
      barChild = _GanttBar(
        key: ValueKey('gantt-bar-${node.id}'),
        metrics: metrics,
        start: effectiveStart,
        end: openEnd,
        progress: effectiveProgress,
        done: isDone,
        status: isParentSummary ? null : node.status,
        isSummary: isParentSummary,
        title: node.title,
        nodeId: node.id,
        // 노드 원본 기간(rollup 요약이면 null 일 수 있음)을 그대로 전달하되,
        // store 를 넘기지 않고 [openEnded]==true 이므로 _canDrag 가 false 가 되어
        // 어떤 날짜도 커밋되지 않는다(오른쪽 끝은 "오늘"이라는 계산값이므로 드래그 금지).
        draggableStart: node.startDate,
        draggableEnd: node.endDate,
        barColor: node.barColor,
        openEnded: true,
        store: null,
      );
    } else {
      barChild = const _NoDateLabel();
    }

    return _rowFrame(
      context,
      overlays: [
        for (final m in descendantMilestones)
          _SummaryMilestoneMarker(
            key: ValueKey('summary-milestone-${node.id}-${m.id}'),
            metrics: metrics,
            info: m,
          ),
      ],
      child: barChild,
    );
  }

  Widget _rowFrame(
    BuildContext context, {
    required Widget child,
    List<Widget> overlays = const [],
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      // 필터 중 매칭되지 않고 조상(맥락)으로만 보이는 행은 은은하게 dim
      // 처리한다(TreePanel 과 동일한 정책).
      child: Opacity(
        opacity: row.isContextAncestor ? 0.55 : 1.0,
        child: Stack(children: [child, ...overlays]),
      ),
    );
  }
}

/// "날짜 미정" 라벨. 날짜가 없는 노드(마일스톤 포함)의 공통 표시.
class _NoDateLabel extends StatelessWidget {
  const _NoDateLabel();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 6,
      top: 0,
      bottom: 0,
      child: Center(child: Text('날짜 미정', style: TextStyle(fontSize: 10))),
    );
  }
}

/// 마일스톤 마커. bar 대신 마름모(다이아몬드) 로 표시한다.
///
/// [date] 는 기준일(호출부에서 endDate 우선, 없으면 startDate 로 결정해서 전달) —
/// 마커의 화면 위치 계산에 쓴다. [originalStart]/[originalEnd] 는 드래그 커밋 시
/// 실제로 옮길 노드의 원본 날짜 필드다.
///
/// 상태(done/onHold 등)에 따라 색을 구분하되, done 처럼 보이지 않아야 하는
/// onHold 는 별도 색([statusAccentColor])을 쓴다.
///
/// **좌우 이동만 가능하고 리사이즈는 불가능**하다(마일스톤은 "기간"이 아니라
/// "시점"이므로 늘리고 줄인다는 개념 자체가 없음 — 좌우 핸들을 아예 만들지 않는다).
/// 날짜가 하나도 없는 마일스톤은 애초에 이 위젯이 만들어지지 않는다([_TimelineRow]
/// 에서 anchor==null 이면 [_NoDateLabel] 을 대신 그린다).
class _MilestoneMarker extends StatefulWidget {
  final GanttMetrics metrics;
  final PlanDate date;
  final TaskStatus status;
  final String title;
  final String nodeId;
  final PlanDate? originalStart;
  final PlanDate? originalEnd;

  /// 사용자가 고른 막대 색. [BarColor.none] 이면 기존 [statusAccentColor] 를 그대로
  /// 쓴다. 마일스톤 마커에도 일반 막대와 같은 색 규칙을 적용한다.
  final BarColor barColor;

  /// 드래그(이동) 허용 여부. rollup 요약 행이면 false(상위 [_TimelineRow] 판단).
  final bool canDrag;

  final PlanStore? store;

  const _MilestoneMarker({
    super.key,
    required this.metrics,
    required this.date,
    required this.status,
    required this.title,
    required this.nodeId,
    required this.originalStart,
    required this.originalEnd,
    required this.canDrag,
    this.barColor = BarColor.none,
    this.store,
  });

  @override
  State<_MilestoneMarker> createState() => _MilestoneMarkerState();
}

class _MilestoneMarkerState extends State<_MilestoneMarker> {
  static const double _size = 16.0;

  bool _dragging = false;
  double _accumDx = 0.0;
  PlanDate? _previewDate;

  bool get _canDrag =>
      widget.canDrag &&
      widget.store != null &&
      (widget.originalStart != null || widget.originalEnd != null);

  PlanDate get _displayDate => _previewDate ?? widget.date;

  void _onDragStart() {
    setState(() {
      _dragging = true;
      _accumDx = 0.0;
      _previewDate = widget.date;
    });
  }

  void _onDragUpdate(double dx) {
    _accumDx += dx;
    final dayDelta = dayDeltaFromPixels(_accumDx, widget.metrics.dayWidth);
    setState(() {
      _previewDate = widget.date.addDays(dayDelta);
    });
  }

  void _onDragEnd() {
    final dayDelta = dayDeltaFromPixels(_accumDx, widget.metrics.dayWidth);
    final store = widget.store;
    setState(() {
      _dragging = false;
      _accumDx = 0.0;
      _previewDate = null;
    });
    if (store == null || dayDelta == 0) return;
    store.updateNode(widget.nodeId, (cur) {
      // shiftRange 는 null-safe: start/end 중 있는 것만 옮긴다.
      // (마일스톤은 한쪽만 있을 수도, 둘 다 있을 수도 있다 — 있는 것만 이동)
      final r = shiftRange(cur.startDate, cur.endDate, dayDelta);
      return cur.copyWith(startDate: r.start, endDate: r.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = _displayDate;
    // 마커는 "그 날짜 칸"의 가운데에 오도록 dayWidth 절반만큼 보정한다.
    final centerX = widget.metrics.xForDate(date) + widget.metrics.dayWidth / 2;
    // 일반 막대와 같은 우선순위 규칙: 완료면 사용자 색 무시. 그 외 barColor 가 있으면
    // 사용자 색, 없으면 기존 status 색([statusAccentColor]).
    final isDone = widget.status == TaskStatus.done;
    final color = isDone
        ? barFillColor(context, done: true)
        : (barColorOf(context, widget.barColor) ??
            statusAccentColor(context, widget.status));
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: centerX - _size / 2,
      top: (kRowHeight - _size) / 2,
      width: _size,
      height: _size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _canDrag ? (_) => _onDragStart() : null,
        onHorizontalDragUpdate: _canDrag
            ? (d) => _onDragUpdate(d.delta.dx)
            : null,
        onHorizontalDragEnd: _canDrag ? (_) => _onDragEnd() : null,
        child: MouseRegion(
          cursor: _canDrag ? SystemMouseCursors.click : MouseCursor.defer,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                label: '${widget.title} (마일스톤, ${date.toIso()})',
                child: Tooltip(
                  message: '마일스톤: ${widget.title}\n${date.toIso()}',
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: scheme.surface, width: 1),
                      ),
                    ),
                  ),
                ),
              ),
              // 드래그 중 실제 날짜 tooltip(오버레이) — bar 드래그와 동일 정책.
              if (_dragging)
                Positioned(
                  left: -20,
                  bottom: _size + 4,
                  child: _DragTooltip(
                    start: date,
                    end: date,
                    mode: _BarDragMode.move,
                    singleDate: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 요약(부모) 바 위에 겹쳐 그리는 **자손 마일스톤** 마커.
///
/// [_MilestoneMarker] 와 달리 **읽기 전용**이다 — 드래그로 옮길 수 없다.
/// 여기서 옮길 수 있게 하면 "부모 행에서 만졌는데 실제로는 자식이 바뀌는"
/// 혼란이 생긴다. 이동은 마일스톤 자기 행에서만 한다.
///
/// 자기 행 마커보다 살짝 작게 그려서, 요약 바 위의 파생 표시임이 드러나게 한다.
class _SummaryMilestoneMarker extends StatelessWidget {
  final GanttMetrics metrics;
  final MilestoneMarkerInfo info;

  static const double _size = 9;

  const _SummaryMilestoneMarker({
    super.key,
    required this.metrics,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    final centerX = metrics.xForDate(info.date) + metrics.dayWidth / 2;
    final color = statusAccentColor(context, info.status);
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: centerX - _size / 2,
      top: (kRowHeight - _size) / 2,
      width: _size,
      height: _size,
      // 요약 바의 드래그를 이 마커가 가로채지 않도록 포인터 이벤트를 흘려보낸다.
      child: IgnorePointer(
        child: Semantics(
          label: '${info.title} (하위 마일스톤, ${info.date.toIso()})',
          child: Transform.rotate(
            angle: math.pi / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: scheme.surface, width: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// bar 드래그 모드.
enum _BarDragMode { move, resizeStart, resizeEnd }

/// 단일 Gantt 바. 3단계: 드래그(이동)/양끝 핸들(리사이즈).
///
/// 정책:
/// - **autoRollup 부모 요약 바(rollup.computedFromChildren)==true** 는 드래그/리사이즈
///   대상에서 **제외**한다(계산값을 직접 끌면 값이 사라지는 것처럼 보임).
/// - **날짜가 null 인 노드** 는 바 자체가 없으므로 대상 아님.
/// - 드래그 중에는 미리보기(preview) 만 갱신하고, **손을 뗐을 때** store 에 커밋.
///   변위=0 이면 커밋하지 않는다(불필요한 저장/알림 차단).
/// - 이동/리사이즈의 날짜 변화량은 절대 좌표가 아니라 **드래그 변위**로 계산
///   (dayDeltaFromPixels(dx, dayWidth) → shiftRange / resizeStart / resizeEnd).
///   절대 좌표 재계산은 누적 오차 + 하루 밀림의 원인.
class _GanttBar extends StatefulWidget {
  final GanttMetrics metrics;
  final PlanDate start;
  final PlanDate end;
  final double progress;
  final bool done;

  /// leaf(또는 autoRollup=false) 노드의 4상태 표시용. 요약(rollup) bar 는
  /// null 을 넘겨 기존 2상태(완료/미완료) 색상([barFillColor])을 그대로 쓴다.
  final TaskStatus? status;

  final bool isSummary;
  final String title;
  final String nodeId;

  /// 사용자가 고른 막대 색. [BarColor.none] 이면 기존 status/done 색 로직을 그대로
  /// 쓴다. 단 **완료(done)==true 면 사용자 색을 무시**하고 완료 색을 쓴다 —
  /// 쨍한 사용자 색이 남으면 완료 여부를 한눈에 알 수 없기 때문이다(아래 build 의
  /// 채움색 결정 참고).
  final BarColor barColor;

  /// 드래그 기준이 되는 노드 **원본** 기간(rollup 요약이면 null 일 수 있음).
  final PlanDate? draggableStart;
  final PlanDate? draggableEnd;

  /// **열린 기간**(종료일 미정) 막대인지.
  ///
  /// true 면 오른쪽 끝이 사용자가 저장한 종료일이 아니라 "오늘"이라는 계산값이므로,
  /// - 오른쪽 끝이 확정된 종료일이 아님을 시각적으로 드러내기 위해 알파 그라데이션
  ///   (오른쪽으로 갈수록 투명)을 입힌다.
  /// - 드래그/리사이즈를 아예 비활성화한다(끝을 끌면 사용자가 입력한 적 없는
  ///   endDate 가 조용히 저장되어 버린다). [store] 가 null 로 넘어오는 것과
  ///   [_canDrag] 가 false 인 것으로 이중 보장한다.
  /// - Semantics 라벨에 [kOpenEndedSemantics] 문구를 포함한다.
  final bool openEnded;

  final PlanStore? store;

  const _GanttBar({
    super.key,
    required this.metrics,
    required this.start,
    required this.end,
    required this.progress,
    required this.done,
    this.status,
    required this.isSummary,
    required this.title,
    required this.nodeId,
    required this.draggableStart,
    required this.draggableEnd,
    this.barColor = BarColor.none,
    this.openEnded = false,
    this.store,
  });

  @override
  State<_GanttBar> createState() => _GanttBarState();
}

class _GanttBarState extends State<_GanttBar> {
  // 드래그 상태
  _BarDragMode? _mode;
  double _accumDx = 0.0;
  // 드래그 중 미리보기(없으면 widget.start/end 사용)
  PlanDate? _previewStart;
  PlanDate? _previewEnd;

  /// 리사이즈 핸들 히트영역 폭(마우스/스타일러스 등 정밀 포인터 기준, 권장 20~24px).
  static const double _handleWidth = 22.0;

  /// 터치 전용 히트영역 폭. **시각적 핸들 표식(4px 스트라이프)은 그대로 두고
  /// 히트테스트 판정 폭만 넓힌다** — 손가락 터치 슬롭(touch slop) 때문에
  /// 실제 터치 지점이 좁은 핸들 경계를 살짝 벗어나도 여전히 리사이즈로
  /// 인식되도록 여유를 준다. 마우스 정밀도에는 영향 없음([_effectiveHandleWidth]).
  static const double _touchHandleWidth = 32.0;

  /// 현재 포인터 종류에 따라 [_pointerKind] 캡처 시점의 로컬 dx.
  /// **[onHorizontalDragStart] 의 `details.globalPosition` 대신 이 값을 쓴다** —
  /// `onHorizontalDragStart` 는 이미 터치 슬롭을 넘어선 뒤의 위치라서, 그 값으로
  /// move/resize 를 판정하면 핸들 경계 바로 안쪽을 정확히 눌러도 슬롭만큼 밀린
  /// 위치 때문에 move 로 오판될 수 있다(실제 Android 버그로 지적된 지점).
  /// [Listener.onPointerDown] 은 슬롭 적용 전 원시 좌표를 주므로 이 문제가 없다.
  double? _pointerDownDx;
  PointerDeviceKind? _pointerKind;

  double _effectiveHandleWidth(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.touch ? _touchHandleWidth : _handleWidth;

  bool get _canDrag =>
      widget.store != null &&
      !widget.isSummary && // rollup 요약 바는 드래그 제외
      !widget.openEnded && // 열린 기간(오늘로 계산된 끝) 은 드래그/리사이즈 제외
      widget.draggableStart != null &&
      widget.draggableEnd != null;

  @override
  void didUpdateWidget(_GanttBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 노드 기간이 외부에서 바뀌면(rollup 갱신 등) 드래그 중이 아니면 미리보기 초기화.
    if (_mode == null) {
      _previewStart = null;
      _previewEnd = null;
    }
  }

  /// 현재 표시할 start/end(미리보기 우선).
  PlanDate get _displayStart => _previewStart ?? widget.start;
  PlanDate get _displayEnd => _previewEnd ?? widget.end;

  void _onDragStart(_BarDragMode mode) {
    setState(() {
      _mode = mode;
      _accumDx = 0.0;
      _previewStart = widget.start;
      _previewEnd = widget.end;
    });
  }

  void _onDragUpdate(double dx) {
    _accumDx += dx;
    final dayDelta = dayDeltaFromPixels(_accumDx, widget.metrics.dayWidth);
    final origS = widget.draggableStart!;
    final origE = widget.draggableEnd!;
    setState(() {
      switch (_mode) {
        case _BarDragMode.move:
          final r = shiftRange(origS, origE, dayDelta);
          _previewStart = r.start;
          _previewEnd = r.end;
          break;
        case _BarDragMode.resizeStart:
          _previewStart = resizeStart(origS, origE, dayDelta);
          _previewEnd = origE;
          break;
        case _BarDragMode.resizeEnd:
          _previewStart = origS;
          _previewEnd = resizeEnd(origS, origE, dayDelta);
          break;
        case null:
          break;
      }
    });
  }

  void _onDragEnd() {
    final mode = _mode;
    final dayDelta = dayDeltaFromPixels(_accumDx, widget.metrics.dayWidth);
    final store = widget.store;
    setState(() {
      _mode = null;
      _accumDx = 0.0;
      _previewStart = null;
      _previewEnd = null;
    });
    if (mode == null || store == null) return;
    // 변위 0 이면 커밋하지 않는다(불필요한 저장/알림 차단).
    if (dayDelta == 0) return;
    final origS = widget.draggableStart;
    final origE = widget.draggableEnd;
    if (origS == null || origE == null) return;
    store.updateNode(widget.nodeId, (cur) {
      // 현재 저장값 기준으로 적용(드래그 중 다른 곳에서 바뀌었을 수도 있으니
      // 안전망으로 cur 사용; 보통은 orig 와 동일).
      final curS = cur.startDate;
      final curE = cur.endDate;
      if (curS == null || curE == null) return cur;
      // mode 는 위에서 null 체크를 통과했으므로 여기서는 non-null.
      switch (mode) {
        case _BarDragMode.move:
          final r = shiftRange(curS, curE, dayDelta);
          return cur.copyWith(startDate: r.start, endDate: r.end);
        case _BarDragMode.resizeStart:
          return cur.copyWith(startDate: resizeStart(curS, curE, dayDelta));
        case _BarDragMode.resizeEnd:
          return cur.copyWith(endDate: resizeEnd(curS, curE, dayDelta));
      }
    });
  }

  /// localPosition.dx 에 따라 모드 결정.
  /// bar 폭이 좁을 때는 핸들 끼리 겹치지 않게 move 만 허용.
  /// [kind] 가 터치면 더 넓은 히트영역([_touchHandleWidth])을 쓴다.
  _BarDragMode _modeForLocalDx(
    double localDx,
    double barWidth,
    PointerDeviceKind? kind,
  ) {
    final hw = _effectiveHandleWidth(kind);
    if (barWidth < hw * 2) return _BarDragMode.move;
    if (localDx <= hw) return _BarDragMode.resizeStart;
    if (localDx >= barWidth - hw) return _BarDragMode.resizeEnd;
    return _BarDragMode.move;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final start = _displayStart;
    final end = _displayEnd;
    final left = m.xForDate(start);
    final width = m.widthForRange(start, end);
    final scheme = Theme.of(context).colorScheme;

    final double barH = widget.isSummary
        ? kRowHeight * kSummaryBarHeightRatio
        : kRowHeight * kLeafBarHeightRatio;
    final clampedP = widget.progress.clamp(0.0, 1.0);

    final isDragging = _mode != null;

    return Positioned(
      left: left,
      top: (kRowHeight - barH) / 2,
      width: width <= 0 ? 1.0 : width,
      height: barH,
      child: Semantics(
        label: widget.openEnded
            ? '${widget.title} ($kOpenEndedSemantics)'
            : widget.done
            ? '${widget.title} ($kDoneSemantics)'
            : widget.status == TaskStatus.onHold
            ? '${widget.title} ($kOnHoldSemantics)'
            : widget.title,
        child: Material(
          color: Colors.transparent,
          child: Listener(
            // 슬롭이 적용되기 전의 원시 접촉 지점 + 포인터 종류를 잡아둔다
            // (onHorizontalDragStart 시점엔 이미 슬롭이 적용된 뒤라 늦다).
            onPointerDown: _canDrag
                ? (event) {
                    final box = context.findRenderObject() as RenderBox;
                    _pointerDownDx = box.globalToLocal(event.position).dx;
                    _pointerKind = event.kind;
                  }
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 가로 드래그만(세로 스크롤과 충돌 회피).
              onHorizontalDragStart: _canDrag
                  ? (details) {
                      final box = context.findRenderObject() as RenderBox;
                      final fallback = box
                          .globalToLocal(details.globalPosition)
                          .dx;
                      _onDragStart(
                        _modeForLocalDx(
                          _pointerDownDx ?? fallback,
                          width,
                          _pointerKind,
                        ),
                      );
                    }
                  : null,
              onHorizontalDragUpdate: _canDrag
                  ? (details) => _onDragUpdate(details.delta.dx)
                  : null,
              onHorizontalDragEnd: _canDrag ? (_) => _onDragEnd() : null,
              child: MouseRegion(
                cursor: _canDrag ? SystemMouseCursors.click : MouseCursor.defer,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(kBarRadius),
                      child: Stack(
                        children: [
                          // 트랙(미충족). 사용자가 색을 지정했으면 그 색의 옅은 버전,
                          // 아니면 기존 [barTrackColor].
                          Container(
                            color: customBarTrackColor(context, widget.barColor) ??
                                barTrackColor(context),
                          ),
                          // 진행 영역.
                          //
                          // 색 우선순위:
                          // 1. 완료(done)==true 면 **사용자 색을 무시**하고 기존 완료
                          //    색(barFillColor(done:true))을 쓴다. 쨍한 사용자 색으로
                          //    남으면 완료 여부를 한눈에 알 수 없기 때문이다.
                          // 2. barColor != none 이면 사용자가 고른 색([barColorOf]).
                          // 3. 그 외는 기존 로직(status 색 / done 색) 을 그대로.
                          //
                          // done 판단을 맨 앞에 둬 barColor 와 관계없이 항상 완료 색이
                          // 이긴다(핵심 정책).
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: clampedP,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.done
                                      ? barFillColor(context, done: true)
                                      : (barColorOf(context, widget.barColor) ??
                                          (widget.status != null
                                              ? statusBarFillColor(
                                                  context,
                                                  widget.status!,
                                                )
                                              : barFillColor(
                                                  context,
                                                  done: widget.done,
                                                ))),
                                  border: widget.isSummary
                                      ? Border.all(
                                          color: scheme.primary.withValues(
                                            alpha: 0.8,
                                          ),
                                          width: 1,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          // 라벨(폭이 충분할 때만).
                          if (width >= 36 && !isDragging)
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // onHold 는 색만으로는 done 과 헷갈릴 수
                                      // 있어 아이콘으로 한 번 더 명확히 구분한다.
                                      if (widget.status ==
                                          TaskStatus.onHold) ...[
                                        Icon(
                                          Icons.pause,
                                          size: 11,
                                          color: scheme.onSurface,
                                        ),
                                        const SizedBox(width: 2),
                                      ],
                                      Flexible(
                                        child: Text(
                                          widget.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            // 사용자 지정 색 위에서도 글자가
                                            // 읽히도록: barColor 가 있으면 배경
                                            // 밝기 기준 검정/흰색, 아니면 기존 로직.
                                            color: widget.done
                                                ? scheme.onSurface.withValues(
                                                    alpha: 0.45,
                                                  )
                                                : (onCustomBarTextColor(
                                                          context,
                                                          widget.barColor,
                                                        ) ??
                                                    (widget.status ==
                                                            TaskStatus.onHold
                                                        ? scheme.onSurface
                                                        : scheme.onPrimary)),
                                            decoration: widget.done
                                                ? TextDecoration.lineThrough
                                                : null,
                                            fontWeight: widget.isSummary
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 열린 기간(종료일 미정) 표시: 오른쪽 끝은 확정된 종료일이
                    // 아니라 "오늘"이라는 계산값임을 한눈에 보여주기 위해 오른쪽
                    // 가장자리를 향해 투명도를 낮추는 그라데이션을 막대 전체
                    // (트랙+진행+라벨) 위에 겹쳐 입힌다. 새 색을 만들지 않고 막대의
                    // 배경(트랙) 색으로 페이드 인시켜 오른쪽이 녹아 들어가듯 보이게
                    // 한다. 막대가 충분히 넓을 때만(좁으면 그라데이션이 의미 없으므로)
                    // 적용한다. [IgnorePointer] 로 감싸 이 오버레이가 드래그/히트를
                    // 가로채지 않도록 한다(드래그 자체는 어차피 비활성).
                    if (widget.openEnded && width >= 12)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0.55, 1.0],
                                colors: [
                                  Colors.transparent,
                                  customBarTrackColor(context, widget.barColor) ??
                                      barTrackColor(context),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 리사이즈 핸들 시각 표식(호버 힌트). 드래그 중이면 생략.
                    if (_canDrag && !isDragging && width >= _handleWidth * 2)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 4,
                        child: ColoredBox(
                          color: scheme.onPrimary.withValues(alpha: 0.35),
                        ),
                      ),
                    if (_canDrag && !isDragging && width >= _handleWidth * 2)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 4,
                        child: ColoredBox(
                          color: scheme.onPrimary.withValues(alpha: 0.35),
                        ),
                      ),
                    // 드래그 중 미리보기 tooltip (요구사항).
                    if (isDragging)
                      Positioned(
                        left: 0,
                        bottom: barH + 2,
                        child: FractionalTranslation(
                          translation: const Offset(-0.0, -0.0),
                          child: Transform.translate(
                            // 말풍선이 bar 왼쪽으로 넘치지 않게.
                            offset: const Offset(0, 0),
                            child: _DragTooltip(
                              start: _previewStart!,
                              end: _previewEnd!,
                              mode: _mode!,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 드래그 중 날짜 미리보기 말풍선.
class _DragTooltip extends StatelessWidget {
  final PlanDate start;
  final PlanDate end;
  final _BarDragMode mode;

  /// true 면 하나의 날짜만 표시(마일스톤 드래그용). false(기본) 면 기존처럼
  /// "start ~ end" 범위로 표시(기간 bar 드래그).
  final bool singleDate;

  const _DragTooltip({
    required this.start,
    required this.end,
    required this.mode,
    this.singleDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modeLabel = switch (mode) {
      _BarDragMode.move => '이동',
      _BarDragMode.resizeStart => '시작일',
      _BarDragMode.resizeEnd => '종료일',
    };
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            singleDate
                ? '$modeLabel  ${start.toIso()}'
                : '$modeLabel  ${start.toIso()} ~ ${end.toIso()}',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onInverseSurface,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
