import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';
import 'package:planbook/ui/plan/gantt_timeline.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';

/// 헤더 라벨이 자기 칸을 침범하지 않는지 검증.
///
/// 축소 시 연도 라벨(예: "2025")이 표시 범위보다 앞에서 시작하는 셀에 그려지면서
/// 옆 칸("2026") 영역까지 밀고 들어가 겹쳐 보이는 버그의 회귀 방지.
/// `_HeaderPainter` 는 private 이라 직접 호출할 수 없으므로, `GanttTimeline` 을
/// pump 해서 _HeaderPainter.paint() 가 예외 없이 그려지는지(= clamp 가 화면 끝이
/// 아니라 셀 가시 영역으로 잡혔는지) 를 확인하고, 별도로 `buildHeaderCells` 의
/// 순수 계산으로 "첫 셀의 x 가 음수" 라는 버그 재현 조건 자체를 고정한다.
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

/// 버그 재현용 표시 범위: 연도 중간(2025-11-20)에서 시작한다. 그러면 연 단위
/// 셀은 2025-01-01 에서 시작하므로 first 셀의 x 가 음수가 된다.
// PlanDate 는 const 생성자가 아니라 const top-level 로 둘 수 없다.
final _firstDay = PlanDate(2025, 11, 20);
final _lastDay = PlanDate(2026, 12, 31);

Future<void> _pump(WidgetTester tester, GanttMetrics metrics) async {
  final store = await _store();
  store.addNode(
    title: '작업',
    startDate: PlanDate(2026, 2, 1),
    endDate: PlanDate(2026, 8, 31),
  );
  await store.flush();

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
            metrics: metrics,
            today: PlanDate(2026, 1, 1),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('헤더 연도 라벨 침범', () {
    testWidgets('표시 범위가 연도 중간에서 시작 + 최소 축척에서 예외 없이 렌더',
        (tester) async {
      // dayWidth = kMinDayWidth(0.25) → 연 단위 눈금. 첫 셀(2025) 의 x 가 음수라
      // 예전 코드는 clamp 하한(2.0) 으로 라벨을 끌어당겨 이웃 칸을 침범했다.
      // 이제 셀 가시 영역으로 clamp 하므로 예외 없이 그려져야 한다.
      final m = GanttMetrics(
        firstDay: _firstDay,
        lastDay: _lastDay,
        dayWidth: kMinDayWidth,
      );
      await _pump(tester, m);
      // _HeaderPainter.paint() 가 던지지 않고 정상 완료됐으면 GanttTimeline 이
      // 트리에 존재한다.
      expect(find.byType(GanttTimeline), findsOneWidget);
    });

    test('buildHeaderCells 의 첫 셀 x 가 음수다(버그 재현 조건 고정)', () {
      // 이 조건이 깨지면(첫 셀이 음수가 아니면) 더 이상 이 버그가 재현되는
      // 상황이 아니므로 테스트 의미 자체가 사라진다. 회귀 방지용 단언.
      final m = GanttMetrics(
        firstDay: _firstDay,
        lastDay: _lastDay,
        dayWidth: kMinDayWidth,
      );
      final cells = buildHeaderCells(m);
      // 연 단위 눈금이 선택됐는지 확인(0.25px/일 → year).
      expect(m.zoom, GanttZoomLevel.year);
      // 첫 셀은 2025.
      expect(cells.first.label, '2025');
      // 2025-01-01 은 firstDay(2025-11-20) 보다 앞이므로 x 가 음수.
      expect(cells.first.x, lessThan(0),
          reason: '연도 중간에서 시작하면 첫 연도 셀은 범위 앞에서 시작해 x<0');
    });

    testWidgets('넓은 축척(dayWidth=40)에서는 라벨이 정상적으로 그려진다', (tester) async {
      // dayWidth=40 → 일 단위. 라벨이 충분히 들어가는 정상 케이스(크래시 없음).
      final m = GanttMetrics(
        firstDay: _firstDay,
        lastDay: _lastDay,
        dayWidth: 40,
      );
      await _pump(tester, m);
      expect(find.byType(GanttTimeline), findsOneWidget);
    });
  });
}
