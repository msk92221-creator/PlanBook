import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_filter.dart';
import 'package:planbook/ui/today/today_page.dart';

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
  // load() 가 기본 프로젝트 시드를 위해 예약한 autosave Timer 를 즉시 비운다.
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Future<void> _pump(WidgetTester tester, PlanStore store,
    {void Function({PlanFilterState? filter, String? focusNodeId})?
        onOpenInGantt}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: TodayPage(store: store, onOpenInGantt: onOpenInGantt),
  ));
  await tester.pump();
}

void main() {
  testWidgets('leaf 작업이 breadcrumb 과 함께 "오늘 진행할 작업" 에 표시된다',
      (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');
    final goal = store.addNode(title: 'Complex Filter 완성', projectId: work.id);
    final sub = store.addNode(parentId: goal.id, title: '알고리즘 구현', projectId: work.id);
    store.addNode(
      parentId: sub.id,
      title: 'Complex BPF 계수 생성',
      projectId: work.id,
      startDate: PlanDate(2026, 8, 9),
      endDate: PlanDate(2026, 8, 12),
    );
    await store.flush();

    await _pump(tester, store);

    expect(find.text('오늘 진행할 작업'), findsOneWidget);
    expect(find.text('Complex BPF 계수 생성'), findsOneWidget);
    expect(find.text('Complex Filter 완성'), findsNothing,
        reason: '부모 Goal 이름이 아니라 leaf 작업이 표시되어야 한다');
    expect(find.textContaining('업무 > Complex Filter 완성 > 알고리즘 구현'),
        findsOneWidget);
  });

  testWidgets('오늘 마감/지연/다가오는 작업 섹션이 각각 표시된다', (tester) async {
    final store = await _emptyStore();
    store.addNode(
      title: '오늘 마감 작업',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 11),
    );
    store.addNode(title: '지연 작업', endDate: PlanDate(2026, 8, 5));
    store.addNode(title: '예정된 작업', startDate: PlanDate(2026, 8, 15));
    await store.flush();

    await _pump(tester, store);

    expect(find.text('오늘 마감'), findsOneWidget);
    expect(find.text('오늘 마감 작업'), findsOneWidget);
    expect(find.text('지연'), findsOneWidget);
    expect(find.text('지연 작업'), findsOneWidget);
    expect(find.textContaining('일 지연'), findsOneWidget);
    expect(find.text('다가오는 작업'), findsOneWidget);
    expect(find.text('예정된 작업'), findsOneWidget);
  });

  testWidgets('완료 체크하면 status=done 이 되고 화면에서 사라진다', (tester) async {
    final store = await _emptyStore();
    final n = store.addNode(
      title: '체크할 작업',
      startDate: PlanDate(2026, 8, 10),
      endDate: PlanDate(2026, 8, 12),
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('체크할 작업'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();

    expect(store.tree[n.id]!.isDone, isTrue);
    expect(find.text('체크할 작업'), findsNothing);
    // setNodeDone 이 예약한 autosave(debounce) Timer 를 테스트 종료 전에 비운다.
    await store.flush();
  });

  test('완료 해제 시 progress>0 이면 inProgress, 아니면 notStarted로 돌아간다',
      () async {
    final store = await _emptyStore();
    final withProgress = store.addNode(title: 'p', progress: 0.5);
    final noProgress = store.addNode(title: 'q', progress: 0.0);
    store.setNodeDone(withProgress.id, true);
    store.setNodeDone(noProgress.id, true);

    store.setNodeDone(withProgress.id, false);
    store.setNodeDone(noProgress.id, false);

    expect(store.tree[withProgress.id]!.status.name, 'inProgress');
    expect(store.tree[noProgress.id]!.status.name, 'notStarted');
    await store.flush();
  });

  testWidgets('할 일이 모두 정리되면 안내 카드가 보인다', (tester) async {
    final store = await _emptyStore();
    await store.flush();
    await _pump(tester, store);
    expect(find.text('오늘 할 일이 모두 정리되었습니다.'), findsOneWidget);
  });

  testWidgets('"Gantt 에서 보기" 를 누르면 onOpenInGantt 가 해당 focusNodeId 로 호출된다',
      (tester) async {
    final store = await _emptyStore();
    final n = store.addNode(
      title: '이동할 작업',
      startDate: PlanDate(2026, 8, 10),
      endDate: PlanDate(2026, 8, 12),
    );
    await store.flush();

    String? focused;
    await _pump(tester, store,
        onOpenInGantt: ({filter, focusNodeId}) => focused = focusNodeId);

    await tester.tap(find.byIcon(Icons.view_timeline_outlined).first);
    await tester.pump();
    expect(focused, n.id);
  });
}
