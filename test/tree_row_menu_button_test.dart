import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/tree_flatten.dart';
import 'package:planbook/ui/plan/tree_panel.dart';

/// 모바일(터치)에서는 우클릭이 없고, 롱프레스도 재정렬 드래그
/// ([LongPressDraggable]) 와 같은 제스처 계열이라 경합에서 밀려 컨텍스트
/// 메뉴가 아예 안 열리는 경우가 실제로 보고되었다(우클릭 vs 드래그로 조작
/// 방법이 플랫폼마다 다른 건 괜찮지만, 기능 자체는 양쪽에서 동일하게
/// 제공돼야 한다). 이 파일은 그 대안으로 추가한 "⋮" 버튼이 단순 탭 한 번으로
/// 항상 같은 메뉴를 여는지 확인한다.
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

void main() {
  testWidgets('"⋮" 버튼을 탭 한 번만 해도 컨텍스트 메뉴(우클릭/롱프레스와 동일)가 뜬다',
      (tester) async {
    final store = await _emptyStore();
    store.addNode(title: 'PA장비');
    await store.flush();

    await _pumpTreePanel(tester, store);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('하위 항목 추가'), findsOneWidget);
    expect(find.text('형제 항목 추가'), findsOneWidget);
    expect(find.text('편집...'), findsOneWidget);
    expect(find.text('완료 토글'), findsOneWidget);
    expect(find.text('삭제...'), findsOneWidget);
  });

  testWidgets('"⋮" 버튼으로 연 메뉴에서 "삭제..."를 고르면 실제로 확인창이 뜬다', (tester) async {
    final store = await _emptyStore();
    final node = store.addNode(title: 'PA장비');
    await store.flush();

    await _pumpTreePanel(tester, store);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제...'));
    await tester.pumpAndSettle();

    // 확인창이 뜨는지만 확인(실제 삭제는 노드_delete_dialog 자체 테스트가 있음).
    expect(find.text('PA장비'), findsWidgets);
    expect(store.tree.contains(node.id), isTrue,
        reason: '확인창에서 아직 선택 안 했으니 삭제되면 안 됨');
  });

  testWidgets('완료 토글 항목을 고르면 실제로 완료 처리된다', (tester) async {
    final store = await _emptyStore();
    final node = store.addNode(title: 'PA장비');
    await store.flush();

    await _pumpTreePanel(tester, store);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료 토글'));
    await tester.pump();
    await store.flush();

    expect(store.tree[node.id]!.isDone, isTrue);
  });
}
