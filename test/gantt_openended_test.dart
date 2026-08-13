import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';
import 'package:planbook/ui/plan/gantt_theme.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

/// "열린 기간"(시작일만 있고 종료일이 미정) 노드가 Gantt 에서 start~오늘 막대로
/// 그려지는지, 그 막대가 드래그되지 않는지를 검증하는 위젯 테스트.
/// [GanttTimeline] 을 직접 pump 한다(PlanPage 를 거치지 않음) —
/// gantt_drag_widget_test.dart 와 같은 이유(가로 스크롤 오프셋 비결정성 회피).
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
  zoom: GanttZoomLevel.day,
);

Future<Offset> _pumpTimeline(
  WidgetTester tester,
  PlanStore store, {
  // PlanDate 는 생성자에서 월/일 범위를 검증하므로 const 가 아니다.
  // 따라서 기본값으로 직접 넣을 수 없어 nullable 로 받고 아래에서 채운다.
  PlanDate? today,
}) async {
  final effectiveToday = today ?? PlanDate(2026, 1, 1);
  // 드래그/좌표 검증을 위해 전체 날짜 폭이 한 화면에 다 보이도록 뷰를 content 폭에
  // 맞춘다. 뷰가 content 보다 좁으면 가로 스크롤이 생겨 일부 막대(예: 1/10 시작)가
  // 화면 오른쪽으로 잘려 hit-test 가 안 된다(드래그가 빗나가 store 가 갱신되지 않음).
  // content 폭 그대로 뷰를 잡으면 스크롤 오프셋이 항상 0 이라 모든 막대의 화면 좌표를
  // 정확히 예측할 수 있다(파일 헤더 주석과 같은 취지).
  final viewWidth = _metrics.totalWidth;
  tester.view.physicalSize = Size(viewWidth, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = flattenVisibleRows(store.tree);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: viewWidth,
          height: 600,
          child: GanttTimeline(
            tree: store.tree,
            rows: rows,
            metrics: _metrics,
            today: effectiveToday,
            store: store,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getTopLeft(find.byType(GanttTimeline));
}

double _rowCenterY(Offset origin, int rowIndex) =>
    origin.dy + kHeaderHeight + rowIndex * kRowHeight + kRowHeight / 2;

double _xFor(Offset origin, PlanDate d) => origin.dx + _metrics.xForDate(d);

/// 막대의 화면상 사각형을 구한다. [nodeId] 는 막대가 속한 노드의 id.
///
/// **semantics 라벨이 아니라 키로 찾는 이유**: 막대가 충분히 넓으면 안쪽에 제목
/// Text 가 함께 그려지는데, 그 Text 의 semantics 가 바깥 `Semantics(label:)`
/// 과 **병합**되어 실제 semantics 노드의 라벨이 '진행중 (종료일 미정)\n진행중'
/// 처럼 줄바꿈으로 이어붙은 하나의 라벨이 된다. 그래서 semantics 라벨로 찾으면
/// 완전 일치는 0개, 부분 일치(RegExp)로 찾으면 **병합된 상위 노드**(사각형이
/// 행 전체라 left=0)가 잡혀서 막대가 아니라 행 전체의 사각형이 돌아온다.
/// 즉 semantics 라벨로 막대 좌표를 재는 것 자체가 불가능하다.
/// 대신 구현부가 `_GanttBar` 에 붙여둔 `ValueKey('gantt-bar-$nodeId')` 로 찾으면
/// 항상 막대 자체의 사각형을 얻을 수 있다.
Rect _barRect(WidgetTester tester, String nodeId) =>
    tester.getRect(find.byKey(ValueKey('gantt-bar-$nodeId')));

void main() {
  group('열린 기간(종료일 미정) 막대 렌더링', () {
    testWidgets('시작일만 있는 노드는 start~오늘 까지 막대로 그려진다', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '진행중',
        startDate: PlanDate(2025, 12, 25), // 오늘(1/1)보다 이전 시작.
        // endDate 미정.
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final today = PlanDate(2026, 1, 1);

      // "날짜 미정" 라벨이 아니라 막대로 표시되어야 한다.
      expect(find.text('날짜 미정'), findsNothing);

      // 막대가 start~today inclusive 폭으로 그려진다(12/25~1/1 = 8일).
      final expectedLeft = _xFor(origin, task.startDate!);
      final expectedWidth = _metrics.widthForRange(task.startDate, today);
      expect(expectedWidth, _metrics.dayWidth * 8);

      final barRect = _barRect(tester, task.id);
      expect(barRect.left, closeTo(expectedLeft, 1.0));
      expect(barRect.width, closeTo(expectedWidth, 1.0));
    });

    testWidgets('오늘이 startDate 이전이면 하루치 막대만 그려진다', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '미래시작',
        startDate: PlanDate(2026, 1, 10), // 오늘(1/1)보다 이후 시작.
        // endDate 미정.
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);

      // start 당일 하루치 폭(dayWidth 1개) 만 그려진다(오늘까지 거꾸로 그리지 않음).
      final expectedLeft = _xFor(origin, task.startDate!);
      final expectedWidth = _metrics.dayWidth; // 같은 날 = 1일치

      final barRect = _barRect(tester, task.id);
      expect(barRect.left, closeTo(expectedLeft, 1.0));
      expect(barRect.width, closeTo(expectedWidth, 1.0));
    });

    testWidgets('막대 Semantics 라벨에 "종료일 미정" 이 포함된다', (tester) async {
      final store = await _emptyStore();
      store.addNode(
        title: '종료미정작업',
        startDate: PlanDate(2025, 12, 25),
      );
      await store.flush();
      // semantics 라벨 검증에만 필요하므로 이 테스트 안에서 직접 켠다.
      final semantics = tester.ensureSemantics();
      await _pumpTimeline(tester, store);

      // semantics 라벨은 막대 안쪽 제목 Text 와 병합되어
      // '종료미정작업 (종료일 미정)\n종료미정작업' 처럼 이어붙으므로 부분 일치로 검사한다.
      // 좌표가 아니라 "문구가 포함되는가" 만 본다(좌표는 위에서 키로 잰다).
      expect(
        find.bySemanticsLabel(RegExp('종료일 미정')),
        findsWidgets,
      );
      // SemanticsHandle 은 반드시 직접 dispose 해야 end-of-test 검증을 통과한다.
      semantics.dispose();
    });
  });

  group('열린 기간 막대는 드래그/리사이즈 금지', () {
    testWidgets('열린 기간 막대를 드래그해도 store 에 어떤 날짜도 커밋되지 않는다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '진행중',
        startDate: PlanDate(2025, 12, 25),
        // endDate 미정.
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth =
          _metrics.widthForRange(task.startDate, PlanDate(2026, 1, 1));
      final midX = barLeft + barWidth / 2;
      final y = _rowCenterY(origin, 0);

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // 막대 중앙에서 +3일치 픽셀만큼 드래그 시도.
      await tester.dragFrom(
          Offset(midX, y), const Offset(120, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      // 알림 자체가 발생하지 않아야 한다(=store 가 건드리지 않음).
      expect(notifyCount, 0);
      // 원본 startDate 는 그대로, endDate 도 여전히 null.
      expect(store.tree[task.id]!.startDate, PlanDate(2025, 12, 25));
      expect(store.tree[task.id]!.endDate, isNull);
    });

    testWidgets('열린 기간 막대 우측 끝을 끌어도 endDate 가 커밋되지 않는다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '진행중',
        startDate: PlanDate(2025, 12, 25),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth =
          _metrics.widthForRange(task.startDate, PlanDate(2026, 1, 1));
      // 우측 끝(오른쪽 가장자리)에서 드래그 시도.
      final rightHandleX = barLeft + barWidth - 4;
      final y = _rowCenterY(origin, 0);

      await tester.dragFrom(Offset(rightHandleX, y), const Offset(40, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(store.tree[task.id]!.endDate, isNull,
          reason: '열린 기간 막대의 오른쪽 끝은 계산값이므로 드래그해도 저장되면 안 된다');
    });
  });

  group('기존 양쪽 날짜 막대는 영향 없음', () {
    testWidgets('양쪽 날짜가 다 있는 막대는 여전히 드래그로 이동한다', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: '확정기간',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final midX = barLeft + barWidth / 2;
      final y = _rowCenterY(origin, 0);

      await tester.dragFrom(
          Offset(midX, y), const Offset(80, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 12));
      expect(updated.endDate, PlanDate(2026, 1, 17));
    });

    testWidgets('양쪽 날짜 막대에는 "종료일 미정" semantics 가 붙지 않는다',
        (tester) async {
      final store = await _emptyStore();
      store.addNode(
        title: '확정기간',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      await store.flush();
      // semantics 라벨 검증에만 필요하므로 이 테스트 안에서 직접 켠다.
      final semantics = tester.ensureSemantics();
      await _pumpTimeline(tester, store);

      // 양쪽 날짜가 확정된 막대에는 "종료일 미정" 문구가 semantics 에 없어야 한다.
      // 부분 일치로 검사한다(라벨 병합 가능성과 무관하게 문구 자체가 없어야 함).
      expect(find.bySemanticsLabel(RegExp('종료일 미정')), findsNothing);
      // SemanticsHandle 은 반드시 직접 dispose 해야 end-of-test 검증을 통과한다.
      semantics.dispose();
    });
  });

  group('rollup 요약 행의 열린 기간', () {
    testWidgets('자식이 전부 열린 기간이면 부모 요약 막대도 start~오늘 로 그려진다',
        (tester) async {
      final store = await _emptyStore();
      final parent = store.addNode(
        title: '부모',
        autoRollup: true,
      );
      store.addNode(
        parentId: parent.id,
        title: '자식1',
        startDate: PlanDate(2025, 12, 25),
        // endDate 미정 → rollup.endDate 도 null.
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final today = PlanDate(2026, 1, 1);

      // 부모 요약 막대는 자식 start(12/25)~오늘(1/1) inclusive 폭.
      final expectedLeft = _xFor(origin, PlanDate(2025, 12, 25));
      final expectedWidth =
          _metrics.widthForRange(PlanDate(2025, 12, 25), today);

      // row 0 = parent(요약). 요약 막대도 열린 기간 semantics 를 갖는다.
      final barRect = _barRect(tester, parent.id);
      expect(barRect.left, closeTo(expectedLeft, 1.0));
      expect(barRect.width, closeTo(expectedWidth, 1.0));
    });
  });
}
