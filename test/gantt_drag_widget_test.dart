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

/// 이 파일은 [GanttTimeline] 을 **직접** pump 한다(PlanPage 를 거치지 않음).
/// PlanPage 는 "오늘" 위치로 자동 스크롤하는 postFrame 로직이 있어 가로 스크롤
/// 오프셋이 비결정적이라, bar 의 정확한 픽셀 위치를 계산해 드래그를 시뮬레이션하는
/// 이 테스트에는 부적합하다. GanttTimeline 은 horizontalController 를 주지
/// 않으면 오프셋 0 에서 시작하므로 좌표를 정확히 예측할 수 있다.
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
  // load() 가 기본 프로젝트 시드를 위해 예약한 autosave Timer 를 즉시 비운다.
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

final _metrics = GanttMetrics(
  firstDay: PlanDate(2026, 1, 1),
  lastDay: PlanDate(2026, 3, 1),
  dayWidth: 40.0,
  zoom: GanttZoomLevel.day,
);

/// [GanttTimeline] 을 고정 크기로 pump 한다. 반환값은 위젯의 화면상 top-left
/// (드래그 좌표 계산의 원점).
Future<Offset> _pumpTimeline(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = flattenVisibleRows(store.tree);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
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
  await tester.pump();
  return tester.getTopLeft(find.byType(GanttTimeline));
}

double _rowCenterY(Offset origin, int rowIndex) =>
    origin.dy + kHeaderHeight + rowIndex * kRowHeight + kRowHeight / 2;

double _xFor(Offset origin, PlanDate d) => origin.dx + _metrics.xForDate(d);

void main() {
  group('터치 히트박스 확장(Phase 12) — 마우스 정밀도는 그대로, 터치만 넓힌다', () {
    testWidgets('터치는 22px~32px 사이(마우스 핸들 밖) 에서도 리사이즈로 인식된다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 20), // 10일 → 400px, 터치 핸들(32px*2) 여유 충분.
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final y = _rowCenterY(origin, 0);
      // 26px 는 마우스 핸들(22px) 밖이지만 터치 핸들(32px) 안.
      final handleX = barLeft + 26;

      await tester.dragFrom(
          Offset(handleX, y), const Offset(40, 0), kind: PointerDeviceKind.touch); // +1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 11),
          reason: '터치는 확장된 32px 히트박스 안이라 resizeStart 로 인식돼야 한다');
      expect(updated.endDate, PlanDate(2026, 1, 20), reason: 'endDate 는 불변');
    });

    testWidgets('같은 26px 지점이라도 마우스는 여전히 move(22px 핸들 밖)로 처리된다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 20),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final y = _rowCenterY(origin, 0);
      final handleX = barLeft + 26;

      await tester.dragFrom(
          Offset(handleX, y), const Offset(40, 0), kind: PointerDeviceKind.mouse); // +1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      // move 모드였다면 start/end 가 함께 +1일 이동한다(리사이즈라면 start 만 변함).
      expect(updated.startDate, PlanDate(2026, 1, 11));
      expect(updated.endDate, PlanDate(2026, 1, 21),
          reason: '마우스는 여전히 22px 핸들만 인정하므로 26px 지점은 move 로 처리돼야 한다');
    });

    testWidgets('터치로 우측 핸들(엄지 슬롭 보정 영역) 을 끌어도 resizeEnd 로 인식된다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 20),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final y = _rowCenterY(origin, 0);
      // 우측 끝에서 26px 안쪽(마우스 핸들 밖, 터치 핸들 안).
      final handleX = barLeft + barWidth - 26;

      await tester.dragFrom(
          Offset(handleX, y), const Offset(-40, 0), kind: PointerDeviceKind.touch); // -1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 10), reason: 'startDate 는 불변');
      expect(updated.endDate, PlanDate(2026, 1, 19));
    });
  });

  group('Gantt bar 드래그(이동)', () {
    testWidgets('bar 전체를 +2일치 픽셀만큼 끌면 start/end 가 동일하게 +2일 이동한다',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final midX = barLeft + barWidth / 2; // 핸들(22px) 영역 바깥 = move 모드
      final y = _rowCenterY(origin, 0);

      await tester.dragFrom(Offset(midX, y), const Offset(80, 0), kind: PointerDeviceKind.mouse); // +2일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 12));
      expect(updated.endDate, PlanDate(2026, 1, 17));
    });

    testWidgets('-1일치 픽셀만큼 끌면 start/end 가 동일하게 -1일 이동한다', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final midX = barLeft + barWidth / 2;
      final y = _rowCenterY(origin, 0);

      await tester.dragFrom(Offset(midX, y), const Offset(-40, 0), kind: PointerDeviceKind.mouse); // -1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 9));
      expect(updated.endDate, PlanDate(2026, 1, 14));
    });

    testWidgets('좌측 핸들 드래그는 startDate 만 바꾼다(endDate 불변)', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 25), // 넉넉히 길게(핸들 겹침 방지)
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final y = _rowCenterY(origin, 0);
      // 좌측 핸들 영역(0~22px) 안의 한 점.
      final handleX = barLeft + 8;

      await tester.dragFrom(Offset(handleX, y), const Offset(40, 0), kind: PointerDeviceKind.mouse); // +1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 11));
      expect(updated.endDate, PlanDate(2026, 1, 25),
          reason: '좌측 핸들 드래그는 endDate 를 바꾸지 않아야 한다');
    });

    testWidgets('우측 핸들 드래그는 endDate 만 바꾼다(startDate 불변)', (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 25),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final y = _rowCenterY(origin, 0);
      // 우측 핸들 영역 안의 한 점.
      final handleX = barLeft + barWidth - 8;

      await tester.dragFrom(Offset(handleX, y), const Offset(-40, 0), kind: PointerDeviceKind.mouse); // -1일
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 10),
          reason: '우측 핸들 드래그는 startDate 를 바꾸지 않아야 한다');
      expect(updated.endDate, PlanDate(2026, 1, 24));
    });

    testWidgets('우측 핸들을 크게 당겨도 startDate 이전으로 넘어가지 않는다(최소 1일)',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 12), // 짧은 3일 bar
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final y = _rowCenterY(origin, 0);
      final handleX = barLeft + barWidth - 8;

      // -10일치 픽셀 — startDate 보다 훨씬 이전으로 밀어붙인다.
      await tester.dragFrom(Offset(handleX, y), const Offset(-400, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.endDate, updated.startDate,
          reason: 'clamp 되어 최소 1일(start==end) 을 유지해야 한다');
      expect(updated.startDate, PlanDate(2026, 1, 10),
          reason: 'startDate 자체는 바뀌지 않아야 한다');
    });

    testWidgets('좌측 핸들을 크게 밀어도 endDate 이후로 넘어가지 않는다(최소 1일)',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 12),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final y = _rowCenterY(origin, 0);
      final handleX = barLeft + 8;

      await tester.dragFrom(Offset(handleX, y), const Offset(400, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      final updated = store.tree[task.id]!;
      expect(updated.startDate, updated.endDate);
      expect(updated.endDate, PlanDate(2026, 1, 12));
    });

    testWidgets('한 번의 드래그는 store 변경 알림을 정확히 1회만 발생시킨다(자동저장 폭주 없음)',
        (tester) async {
      final store = await _emptyStore();
      final task = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      await store.flush();

      final origin = await _pumpTimeline(tester, store);
      final barLeft = _xFor(origin, task.startDate!);
      final barWidth = _metrics.widthForRange(task.startDate, task.endDate);
      final midX = barLeft + barWidth / 2;
      final y = _rowCenterY(origin, 0);

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      await tester.dragFrom(Offset(midX, y), const Offset(80, 0), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(notifyCount, 1,
          reason: '드래그 중 매 프레임 커밋되면 안 되고, 놓을 때 단 1회만 커밋되어야 한다');
    });

    for (final zoom in GanttZoomLevel.values) {
      testWidgets('${zoom.label} 줌에서도 드래그 결과 날짜 이동량이 일관된다(+3일)',
          (tester) async {
        final store = await _emptyStore();
        final task = store.addNode(
          title: 'Task',
          startDate: PlanDate(2026, 1, 10),
          endDate: PlanDate(2026, 1, 15),
        );
        await store.flush();

        final metrics = GanttMetrics(
          firstDay: PlanDate(2026, 1, 1),
          lastDay: PlanDate(2026, 3, 1),
          dayWidth: zoom.dayWidth,
          zoom: zoom,
        );
        tester.view.physicalSize = const Size(1400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final rows = flattenVisibleRows(store.tree);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1400,
                height: 600,
                child: GanttTimeline(
                  tree: store.tree,
                  rows: rows,
                  metrics: metrics,
                  today: PlanDate(2026, 1, 1),
                  store: store,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final origin = tester.getTopLeft(find.byType(GanttTimeline));

        final barLeft = origin.dx + metrics.xForDate(task.startDate!);
        final barWidth = metrics.widthForRange(task.startDate, task.endDate);
        final y = origin.dy + kHeaderHeight + kRowHeight / 2;
        // 핸들 폭(22px) 보다 bar 가 너무 좁아지는 줌(month=5px/day)에서는
        // move 판정 기준이 "핸들 2개보다 좁으면 무조건 move" 이므로 그대로 동작.
        final midX = barLeft + barWidth / 2;

        await tester.dragFrom(
            Offset(midX, y), Offset(3 * metrics.dayWidth, 0), kind: PointerDeviceKind.mouse); // +3일
        await tester.pumpAndSettle();

        final updated = store.tree[task.id]!;
        expect(updated.startDate, PlanDate(2026, 1, 13));
        expect(updated.endDate, PlanDate(2026, 1, 18));
      });
    }
  });

  group('derived/rollup 요약 bar 는 드래그되지 않는다', () {
    testWidgets('autoRollup 부모(자식 기간에서 계산된 bar)를 드래그해도 아무것도 바뀌지 않는다',
        (tester) async {
      final store = await _emptyStore();
      final parent = store.addNode(title: '부모', autoRollup: true);
      final child1 = store.addNode(
        parentId: parent.id,
        title: '자식1',
        startDate: PlanDate(2026, 1, 5),
        endDate: PlanDate(2026, 1, 10),
      );
      final child2 = store.addNode(
        parentId: parent.id,
        title: '자식2',
        startDate: PlanDate(2026, 1, 12),
        endDate: PlanDate(2026, 1, 20),
      );
      await store.flush();

      // rows: [parent(depth0, 요약), child1, child2] — parent 는 접혀있지 않음.
      final origin = await _pumpTimeline(tester, store);
      // 부모의 요약 bar 는 자식 min~max = 1/5 ~ 1/20.
      final barLeft = _xFor(origin, PlanDate(2026, 1, 5));
      final barWidth =
          _metrics.widthForRange(PlanDate(2026, 1, 5), PlanDate(2026, 1, 20));
      final midX = barLeft + barWidth / 2;
      final y = _rowCenterY(origin, 0); // parent 는 첫 행(depth0).

      await tester.dragFrom(Offset(midX, y), const Offset(120, 0), kind: PointerDeviceKind.mouse); // +3일 시도
      await tester.pumpAndSettle();

      // 부모/자식 어느 것도 원본 저장값이 바뀌지 않아야 한다.
      expect(store.tree[parent.id]!.startDate, isNull);
      expect(store.tree[parent.id]!.endDate, isNull);
      expect(store.tree[child1.id]!.startDate, PlanDate(2026, 1, 5));
      expect(store.tree[child1.id]!.endDate, PlanDate(2026, 1, 10));
      expect(store.tree[child2.id]!.startDate, PlanDate(2026, 1, 12));
      expect(store.tree[child2.id]!.endDate, PlanDate(2026, 1, 20));
    });
  });

  group('milestone 드래그', () {
    testWidgets('마일스톤을 좌우로 끌면 이동한다(+2일)', (tester) async {
      final store = await _emptyStore();
      final m = store.addNode(
        title: '마일스톤',
        isMilestone: true,
        endDate: PlanDate(2026, 1, 10),
      );
      await store.flush();

      await _pumpTimeline(tester, store);
      final key = ValueKey('milestone-marker-${m.id}');
      final centerBefore = tester.getCenter(find.byKey(key));
      await tester.dragFrom(centerBefore, const Offset(80, 0), kind: PointerDeviceKind.mouse); // +2일
      await tester.pumpAndSettle();

      expect(store.tree[m.id]!.endDate, PlanDate(2026, 1, 12));
    });

    testWidgets('날짜가 없는 마일스톤은 마커 자체가 없어 드래그할 수 없다', (tester) async {
      final store = await _emptyStore();
      final m = store.addNode(title: '날짜없는 마일스톤', isMilestone: true);
      await store.flush();
      await _pumpTimeline(tester, store);

      expect(find.byKey(ValueKey('milestone-marker-${m.id}')), findsNothing);
    });

    testWidgets('마일스톤은 리사이즈가 없다 — 가장자리를 끌어도 항상 이동(move)일 뿐이다',
        (tester) async {
      final store = await _emptyStore();
      final m = store.addNode(
        title: '마일스톤',
        startDate: PlanDate(2026, 1, 10),
        endDate: PlanDate(2026, 1, 15),
      );
      store.updateNode(m.id, (n) => n.copyWith(isMilestone: true));
      await store.flush();

      await _pumpTimeline(tester, store);
      final key = ValueKey('milestone-marker-${m.id}');
      // 마커의 "가장자리"(왼쪽 끝) 에서 드래그를 시작해도 리사이즈 핸들이 없으므로
      // 그냥 이동으로 처리되어 start/end 가 함께 shift 된다.
      final markerBox = tester.getRect(find.byKey(key));
      final edgePoint = Offset(markerBox.left + 1, markerBox.center.dy);

      await tester.dragFrom(edgePoint, const Offset(40, 0), kind: PointerDeviceKind.mouse); // +1일
      await tester.pumpAndSettle();

      final updated = store.tree[m.id]!;
      expect(updated.startDate, PlanDate(2026, 1, 11));
      expect(updated.endDate, PlanDate(2026, 1, 16),
          reason: '리사이즈가 없으므로 endDate 도 startDate 와 함께 이동해야 한다');
    });
  });
}
