import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_theme.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';
import 'package:planbook/ui/plan/tree_panel.dart';

/// [TreePanel] 자체의 드래그앤드롭(재정렬/reparent)을 **실제 제스처
/// 시뮬레이션**으로 검증한다. 기존 reparent_stabilization_test.dart 는
/// PlanStore.moveNode/reorderSibling 을 직접 호출해 결과만 확인했을 뿐,
/// LongPressDraggable + DragTarget 제스처 자체는 한 번도 시뮬레이션한 적이
/// 없었다(Phase 17 감사에서 발견한 커버리지 공백).
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
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

/// [TreePanel] 을 고정 크기로 직접 pump 한다(PlanPage 를 거치지 않아 픽셀
/// 좌표를 정확히 예측할 수 있다 — gantt_drag_widget_test.dart 와 동일 전략).
/// 반환값은 TreePanel 의 화면상 top-left(행 Y 좌표 계산의 기준점).
Future<Offset> _pumpTreePanel(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(600, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = flattenVisibleRows(store.tree);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: TreePanel(
            tree: store.tree,
            rows: rows,
            onToggleCollapse: (_) {},
            store: store,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getTopLeft(find.byType(TreePanel));
}

/// 드래그를 **시작**할 좌표는 실제 렌더된 제목 텍스트의 중심을 그대로 쓴다 —
/// 자식이 없는 행은 접기/펼치기 아이콘 자리가 높이 0 인 빈 SizedBox 라 그
/// 위치를 손으로 계산하면 히트테스트가 안 된다(LongPressDraggable 이 아예
/// 시작되지 않는다).
Offset _dragStartPoint(WidgetTester tester, String title) =>
    tester.getCenter(find.text(title));

/// 드롭 **목표** 좌표는 반대로 텍스트 위치가 아니라 [origin] 기준 절대 좌표로
/// 계산한다 — 이미 시작된 드래그의 이동/드롭 판정은 행 전체를 감싸는
/// DragTarget 이 처리하므로 x 는 행 안이면 어디든 괜찮고(여기서는 왼쪽 여백
/// 부분을 쓴다), y 만 행 내부 상대 위치(before/child/after 존)를 정확히
/// 맞추면 된다.
const double _kDropTargetX = 15.0;

double _rowCenterY(Offset origin, int rowIndex) =>
    origin.dy + kHeaderHeight + rowIndex * kRowHeight + kRowHeight / 2;

Future<void> _dragRow(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
}) async {
  final gesture = await tester.startGesture(from);
  // LongPressDraggable(delay: 250ms) 활성화까지 기다린다.
  await tester.pump(const Duration(milliseconds: 300));
  // 한 번에 목표 지점으로 점프하지 않고 여러 스텝으로 나눠 이동한다(실제
  // 사용자 드래그와 더 비슷하고, DragTarget.onMove 갱신이 안정적으로 관찰됨).
  const steps = 6;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    await gesture.moveTo(Offset.lerp(from, to, t)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('TreePanel 드래그앤드롭(실제 제스처 시뮬레이션)', () {
    testWidgets('행 위쪽(20%)에 드롭하면 그 형제 앞으로 재정렬된다(before)',
        (tester) async {
      final store = await _emptyStore();
      final a = store.addNode(title: 'A');
      final b = store.addNode(title: 'B');
      await store.flush();
      expect(store.tree.childrenOf(null).map((n) => n.id), [a.id, b.id]);

      final origin = await _pumpTreePanel(tester, store);
      final bStart = _dragStartPoint(tester, 'B');
      // A 행의 맨 위 5% 지점(before 존).
      final aTop = Offset(
        _kDropTargetX,
        origin.dy + kHeaderHeight + kRowHeight * 0.05,
      );

      await _dragRow(tester, from: bStart, to: aTop);
      await store.flush();

      expect(store.tree.childrenOf(null).map((n) => n.id), [b.id, a.id],
          reason: 'B 를 A 행 위쪽에 놓았으니 B 가 A 앞으로 와야 한다');
    });

    testWidgets('행 가운데에 드롭하면 그 형제의 자식으로 편입된다(reparent)',
        (tester) async {
      final store = await _emptyStore();
      final a = store.addNode(title: 'A');
      final b = store.addNode(title: 'B');
      await store.flush();

      final origin = await _pumpTreePanel(tester, store);
      final bStart = _dragStartPoint(tester, 'B');
      final aMiddle = Offset(_kDropTargetX, _rowCenterY(origin, 0));

      await _dragRow(tester, from: bStart, to: aMiddle);
      await store.flush();

      expect(store.tree[b.id]!.parentId, a.id,
          reason: 'B 를 A 행 가운데에 놓았으니 B 가 A 의 자식이 되어야 한다');
    });

    testWidgets('자기 자신 위에 드롭해도 순환/크래시 없이 무시된다', (tester) async {
      final store = await _emptyStore();
      final a = store.addNode(title: 'A');
      await store.flush();

      final origin = await _pumpTreePanel(tester, store);
      final aStart = _dragStartPoint(tester, 'A');
      final aTarget = Offset(_kDropTargetX, _rowCenterY(origin, 0));

      await _dragRow(tester, from: aStart, to: aTarget);
      await store.flush();

      // 크래시 없이 그대로(부모 없음, 유일한 루트).
      expect(store.tree.childrenOf(null).map((n) => n.id), [a.id]);
    });
  });
}
