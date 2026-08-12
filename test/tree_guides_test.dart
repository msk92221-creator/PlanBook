import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';
import 'package:planbook/ui/plan/tree_panel.dart';

/// Phase: "이 항목이 상위 항목에 속해 있다"는 걸 트리에서 시각적으로 보여주는
/// 계층 안내선(ㄴ/├ 모양) 회귀 테스트. 실제 페인팅 모양까지는 검증하지
/// 않지만(골든 테스트가 아님), 최상위(depth 0) 행에는 안내선이 전혀 없고
/// 하위 행에는 있다는 것, 그리고 깊이가 깊을수록 안내선 세그먼트가 늘어나는
/// 것은 크래시 없이 확인할 수 있다.
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

Future<void> _pumpTreePanel(WidgetTester tester, PlanStore store) async {
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
}

/// [title] 행의 조상 개수(row.depth) 만큼 그려지는 CustomPaint 안내선 개수.
/// (그 행 전체에 딸린 CustomPaint 는 안내선뿐이므로 개수 비교가 안전하다.)
int _guidePaintCountFor(WidgetTester tester, String title) {
  final rowFinder = find.ancestor(
    of: find.text(title),
    matching: find.byType(Row),
  );
  return find
      .descendant(of: rowFinder.first, matching: find.byType(CustomPaint))
      .evaluate()
      .length;
}

void main() {
  testWidgets('최상위(depth 0) 행에는 계층 안내선이 없다', (tester) async {
    final store = await _emptyStore();
    store.addNode(title: 'ROOT');
    await store.flush();

    await _pumpTreePanel(tester, store);

    expect(_guidePaintCountFor(tester, 'ROOT'), 0);
  });

  testWidgets('depth 1 자식 행에는 안내선이 1개 그려진다', (tester) async {
    final store = await _emptyStore();
    final root = store.addNode(title: 'ROOT');
    store.addNode(parentId: root.id, title: 'CHILD');
    await store.flush();

    await _pumpTreePanel(tester, store);

    expect(_guidePaintCountFor(tester, 'CHILD'), 1);
  });

  testWidgets(
      'depth 2 손자 행: 조상(ROOT)에 형제가 남아 있으면 안내선이 2개(이어지는 세로선 + 자기 것)',
      (tester) async {
    final store = await _emptyStore();
    final root = store.addNode(title: 'ROOT');
    final child = store.addNode(parentId: root.id, title: 'CHILD');
    store.addNode(parentId: child.id, title: 'GRANDCHILD');
    // ROOT 뒤에 형제를 하나 더 둬야 ROOT 칸의 세로선이 "이어지는 중"으로
    // 그려진다 — ROOT 가 유일한 루트(=마지막 자식)면 그 아래로 이어질 형제가
    // 없으므로 그 칸은 빈 채로 남는다(정상 동작).
    store.addNode(title: 'ROOT2');
    await store.flush();

    await _pumpTreePanel(tester, store);

    expect(_guidePaintCountFor(tester, 'GRANDCHILD'), 2);
  });

  testWidgets(
      'depth 2 손자 행: 조상(ROOT)이 유일한 루트(마지막 자식)면 그 칸은 비고 안내선은 1개뿐',
      (tester) async {
    final store = await _emptyStore();
    final root = store.addNode(title: 'ROOT');
    final child = store.addNode(parentId: root.id, title: 'CHILD');
    store.addNode(parentId: child.id, title: 'GRANDCHILD');
    await store.flush();

    await _pumpTreePanel(tester, store);

    expect(_guidePaintCountFor(tester, 'GRANDCHILD'), 1);
  });

  testWidgets('형제가 여럿이어도 크래시 없이 렌더된다(마지막/중간 자식 모두)',
      (tester) async {
    final store = await _emptyStore();
    final root = store.addNode(title: 'ROOT');
    store.addNode(parentId: root.id, title: 'FIRST');
    store.addNode(parentId: root.id, title: 'MIDDLE');
    store.addNode(parentId: root.id, title: 'LAST');
    await store.flush();

    await _pumpTreePanel(tester, store);

    expect(find.text('FIRST'), findsOneWidget);
    expect(find.text('MIDDLE'), findsOneWidget);
    expect(find.text('LAST'), findsOneWidget);
    expect(_guidePaintCountFor(tester, 'FIRST'), 1);
    expect(_guidePaintCountFor(tester, 'MIDDLE'), 1);
    expect(_guidePaintCountFor(tester, 'LAST'), 1);
  });
}
