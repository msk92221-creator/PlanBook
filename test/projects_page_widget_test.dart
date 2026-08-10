import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_filter.dart';
import 'package:planbook/ui/common/navigation.dart';
import 'package:planbook/ui/projects/projects_page.dart';

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

Future<void> _pump(WidgetTester tester, PlanStore store,
    {OpenInGantt? onOpenInGantt}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: ProjectsPage(store: store, onOpenInGantt: onOpenInGantt),
  ));
  await tester.pump();
}

void main() {
  testWidgets('기본 프로젝트 5개가 카드로 보이고 통계가 표시된다', (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');
    store.addNode(title: 'A', projectId: work.id, status: TaskStatus.done);
    store.addNode(title: 'B', projectId: work.id);
    await store.flush();

    await _pump(tester, store);

    expect(find.text('업무'), findsOneWidget);
    expect(find.text('전체 2'), findsOneWidget);
    expect(find.text('완료 1'), findsOneWidget);
    expect(find.text('미완료 1'), findsOneWidget);
  });

  testWidgets('카드를 누르면 onOpenInGantt 가 해당 Project 필터로 호출된다',
      (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');

    PlanFilterState? gotFilter;
    await _pump(tester, store,
        onOpenInGantt: ({filter, focusNodeId}) => gotFilter = filter);

    await tester.tap(find.text('업무'));
    await tester.pump();

    expect(gotFilter, isNotNull);
    expect(gotFilter!.projectIds, {work.id});
  });

  testWidgets('프로젝트를 추가할 수 있다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '새 프로젝트');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('새 프로젝트'), findsOneWidget);
    expect(store.projects.any((p) => p.name == '새 프로젝트'), isTrue);
    await store.flush();
  });

  testWidgets('이름을 변경할 수 있다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    await tester.tap(find.text('업무'));
    // 카드 탭이 onOpenInGantt 호출로 소비되므로, 메뉴는 별도로 연다.
    await tester.pump();

    final menuButton = find.descendant(
      of: find.ancestor(of: find.text('업무'), matching: find.byType(Card)).first,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이름/색상 변경'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '업무(변경됨)');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('업무(변경됨)'), findsOneWidget);
    await store.flush();
  });

  testWidgets('삭제하면 Task 는 남고 projectId 만 null 이 된다(기본 프로젝트도 동일)',
      (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');
    final n = store.addNode(title: '살아남을 작업', projectId: work.id);
    await store.flush();

    await _pump(tester, store);

    final menuButton = find.descendant(
      of: find.ancestor(of: find.text('업무'), matching: find.byType(Card)).first,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    // 확인 다이얼로그에 영향받는 Task 수가 안내된다.
    expect(find.textContaining('1개'), findsOneWidget);
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(store.projects.any((p) => p.name == '업무'), isFalse);
    expect(store.tree.contains(n.id), isTrue, reason: 'Task 는 삭제되면 안 된다');
    expect(store.tree[n.id]!.projectId, isNull);
    await store.flush();
  });

  testWidgets('Archive 하면 기본 목록에서 빠지고, 보관함에서 다시 볼 수 있다',
      (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    final menuButton = find.descendant(
      of: find.ancestor(of: find.text('업무'), matching: find.byType(Card)).first,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('업무'), findsNothing);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('업무'), findsOneWidget);
    await store.flush();
  });
}
