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

import '../../core/date/plan_date.dart';
import '../../data/plan_store.dart';
import '../../domain/plan_enums.dart';
import '../../domain/plan_rollup.dart';
import '../../domain/plan_tree.dart';
import 'gantt_metrics.dart';
import 'gantt_theme.dart';
import 'tree_flatten.dart';

/// 우측 Gantt 타임라인 패널.
///
/// [verticalController] 는 좌측 트리 패널과 동기화되는 세로 스크롤 컨트롤러(외부 주입).
/// [horizontalController] 는 가로 스크롤 컨트롤러(초기 "오늘" 위치 보정에도 사용).
class GanttTimeline extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight;
        final contentWidth = metrics.totalWidth;
        return Scrollbar(
          controller: horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: horizontalController,
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
                          controller: verticalController,
                          itemExtent: kRowHeight,
                          itemCount: rows.length,
                          padding: EdgeInsets.zero,
                          itemBuilder: (context, i) => _TimelineRow(
                            row: rows[i],
                            tree: tree,
                            metrics: metrics,
                            store: store,
                            selected: rows[i].id == selectedNodeId,
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
                  _TodayOverlay(metrics: metrics, today: today),
                ],
              ),
            ),
          ),
        );
      },
    );
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
  const _TimelineRow({
    required this.row,
    required this.tree,
    required this.metrics,
    this.store,
    this.selected = false,
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

    return _rowFrame(
      context,
      child: (effectiveStart != null && effectiveEnd != null)
          ? _GanttBar(
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
              store: store,
            )
          : const _NoDateLabel(),
    );
  }

  Widget _rowFrame(BuildContext context, {required Widget child}) {
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
        child: Stack(children: [child]),
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
    final color = statusAccentColor(context, widget.status);
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

  /// 드래그 기준이 되는 노드 **원본** 기간(rollup 요약이면 null 일 수 있음).
  final PlanDate? draggableStart;
  final PlanDate? draggableEnd;

  final PlanStore? store;

  const _GanttBar({
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
        label: widget.done
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
                          // 트랙(미충족).
                          Container(color: barTrackColor(context)),
                          // 진행 영역.
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: clampedP,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.status != null
                                      ? statusBarFillColor(
                                          context,
                                          widget.status!,
                                        )
                                      : barFillColor(
                                          context,
                                          done: widget.done,
                                        ),
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
                                            color: widget.done
                                                ? scheme.onSurface.withValues(
                                                    alpha: 0.45,
                                                  )
                                                : (widget.status ==
                                                          TaskStatus.onHold
                                                      ? scheme.onSurface
                                                      : scheme.onPrimary),
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
