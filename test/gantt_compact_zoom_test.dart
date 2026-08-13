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

/// 축소 단계(분기/년)의 **간략 모드** 검증.
///
/// 하루가 2px 도 안 되는 축척에서는 진행률 분할·라벨·마일스톤 마름모를 다 그려도
/// 뭉개지기만 한다. 그래서 단색 한 덩어리로만 그리고 드래그도 막는다.
class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _store() async {
  final s = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 1, 1),
    autosaveDelay: Duration.zero,
  );
  await s.load();
  await s.flush();
  addTearDown(s.dispose);
  return s;
}

GanttMetrics _metrics(GanttZoomLevel zoom) => GanttMetrics(
      firstDay: PlanDate(2026, 1, 1),
      lastDay: PlanDate(2026, 12, 31),
      dayWidth: zoom.dayWidth,
      zoom: zoom,
    );

Future<Offset> _pump(
  WidgetTester tester,
  PlanStore store,
  GanttZoomLevel zoom,
) async {
  tester.view.physicalSize = const Size(900, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: GanttTimeline(
            tree: store.tree,
            rows: flattenVisibleRows(store.tree),
            metrics: _metrics(zoom),
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

void main() {
  group('간략 모드 판정', () {
    test('분기/년만 간략 모드다', () {
      expect(GanttZoomLevel.day.isCompact, isFalse);
      expect(GanttZoomLevel.week.isCompact, isFalse);
      expect(GanttZoomLevel.month.isCompact, isFalse);
      expect(GanttZoomLevel.quarter.isCompact, isTrue);
      expect(GanttZoomLevel.year.isCompact, isTrue);
    });
  });

  group('간략 모드 렌더링', () {
    testWidgets('년 줌에서는 막대 안에 제목 라벨을 그리지 않는다', (tester) async {
      final store = await _store();
      store.addNode(
        title: '아주긴제목의작업입니다',
        startDate: PlanDate(2026, 2, 1),
        endDate: PlanDate(2026, 8, 31), // 7개월 = 년 줌에서도 100px 이상
      );
      await store.flush();

      await _pump(tester, store, GanttZoomLevel.year);
      expect(find.text('아주긴제목의작업입니다'), findsNothing,
          reason: '간략 모드에서는 막대 안 라벨을 생략한다');
    });

    testWidgets('일 줌에서는 같은 막대에 제목 라벨이 보인다(대조군)', (tester) async {
      final store = await _store();
      store.addNode(
        title: '보이는제목',
        startDate: PlanDate(2026, 2, 1),
        endDate: PlanDate(2026, 2, 20),
      );
      await store.flush();

      await _pump(tester, store, GanttZoomLevel.day);
      expect(find.text('보이는제목'), findsOneWidget,
          reason: '일 줌은 간략 모드가 아니므로 기존대로 라벨을 그린다');
    });

    testWidgets('하루짜리 일정도 최소 폭만큼은 보인다', (tester) async {
      final store = await _store();
      final task = store.addNode(
        title: '하루',
        startDate: PlanDate(2026, 6, 10),
        endDate: PlanDate(2026, 6, 10), // 하루 = 0.6px
      );
      await store.flush();

      await _pump(tester, store, GanttZoomLevel.year);
      final rect =
          tester.getRect(find.byKey(ValueKey('gantt-bar-${task.id}')));
      expect(rect.width, greaterThanOrEqualTo(kCompactMinBarWidth),
          reason: '0.6px 로 그리면 사실상 안 보이므로 최소 폭을 확보한다');
    });

    testWidgets('자손 마일스톤 마름모를 요약 막대 위에 겹쳐 그리지 않는다', (tester) async {
      final store = await _store();
      final parent = store.addNode(title: '부모', autoRollup: true);
      store.addNode(
        parentId: parent.id,
        title: '자식작업',
        startDate: PlanDate(2026, 2, 1),
        endDate: PlanDate(2026, 5, 1),
      );
      store.addNode(
        parentId: parent.id,
        title: '자식마일스톤',
        startDate: PlanDate(2026, 3, 15),
        endDate: PlanDate(2026, 3, 15),
        isMilestone: true,
      );
      await store.flush();

      // 일 줌에서는 요약 막대 위에 자손 마일스톤이 겹쳐 그려진다.
      await _pump(tester, store, GanttZoomLevel.day);
      final dayMarkers = find
          .byKey(ValueKey('summary-milestone-${parent.id}-'
              '${store.tree.childrenOf(parent.id).last.id}'))
          .evaluate()
          .length;
      expect(dayMarkers, 1, reason: '일 줌에서는 자손 마일스톤이 겹쳐 보인다');

      // 년 줌(간략 모드)에서는 생략된다.
      await _pump(tester, store, GanttZoomLevel.year);
      final yearMarkers = find
          .byKey(ValueKey('summary-milestone-${parent.id}-'
              '${store.tree.childrenOf(parent.id).last.id}'))
          .evaluate()
          .length;
      expect(yearMarkers, 0,
          reason: '간략 모드에서는 마름모가 서로 뭉개지므로 생략한다');
    });
  });

  group('간략 모드에서는 막대를 드래그할 수 없다', () {
    testWidgets('년 줌에서 막대를 끌어도 날짜가 바뀌지 않는다', (tester) async {
      final store = await _store();
      final task = store.addNode(
        title: '작업',
        startDate: PlanDate(2026, 3, 1),
        endDate: PlanDate(2026, 6, 30),
      );
      await store.flush();

      final origin = await _pump(tester, store, GanttZoomLevel.year);
      final m = _metrics(GanttZoomLevel.year);
      final barLeft = origin.dx + m.xForDate(task.startDate!);
      final barW = m.widthForRange(task.startDate, task.endDate);
      final y = origin.dy + kHeaderHeight + kRowHeight / 2;

      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      await tester.dragFrom(
        Offset(barLeft + barW / 2, y),
        const Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(notifyCount, 0, reason: '간략 모드에서는 드래그 커밋 자체가 없어야 한다');
      expect(store.tree[task.id]!.startDate, PlanDate(2026, 3, 1));
      expect(store.tree[task.id]!.endDate, PlanDate(2026, 6, 30));
    });
  });
}
