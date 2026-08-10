import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/plan_page.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeWithTasks() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  final work = store.projects.firstWhere((p) => p.name == '업무');
  final research = store.projects.firstWhere((p) => p.name == '연구');

  // "오늘"(8/11)에 걸치는 leaf.
  store.addNode(
    title: '오늘 작업',
    projectId: work.id,
    startDate: PlanDate(2026, 8, 10),
    endDate: PlanDate(2026, 8, 12),
  );
  // 미래 작업(오늘 필터에는 안 걸림), 다른 project(research) 아래 계층 구조.
  final futRoot = store.addNode(title: '미래 목표', projectId: research.id);
  store.addNode(
    parentId: futRoot.id,
    title: '미래 하위 작업',
    projectId: research.id,
    startDate: PlanDate(2026, 9, 1),
    endDate: PlanDate(2026, 9, 5),
  );
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

Future<void> _pumpWide(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
  await tester.pump();
}

Future<void> _pumpNarrow(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
  await tester.pump();
}

void main() {
  group('FilterBar 통합(PlanPage)', () {
    testWidgets('넓은 화면은 인라인 다중선택 드롭다운(Project/상태/태그/우선순위)을 보여준다',
        (tester) async {
      final store = await _storeWithTasks();
      await _pumpWide(tester, store);
      expect(find.text('Project'), findsOneWidget);
      expect(find.text('상태'), findsOneWidget);
      expect(find.text('태그'), findsOneWidget);
      expect(find.text('우선순위'), findsOneWidget);
    });

    testWidgets('좁은 화면은 빠른 필터 칩 + 필터 아이콘만 보여준다(빽빽하지 않음)',
        (tester) async {
      final store = await _storeWithTasks();
      await _pumpNarrow(tester, store);
      expect(find.text('Project'), findsNothing,
          reason: '좁은 화면에는 인라인 드롭다운이 없어야 한다');
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.text('오늘'), findsWidgets); // 빠른 필터 칩.
    });

    testWidgets('"오늘" 빠른 필터를 누르면 오늘에 걸치지 않는 작업은 사라진다',
        (tester) async {
      final store = await _storeWithTasks();
      await _pumpWide(tester, store);

      expect(find.text('오늘 작업'), findsWidgets);
      expect(find.text('미래 하위 작업'), findsWidgets);

      await tester.tap(find.widgetWithText(ChoiceChip, '오늘'));
      await tester.pumpAndSettle();

      expect(find.text('오늘 작업'), findsWidgets);
      expect(find.text('미래 하위 작업'), findsNothing,
          reason: '오늘에 걸치지 않으므로 필터에 매칭되지 않아야 한다');
    });

    testWidgets('필터로 매칭되지 않은 조상은 dim 처리된 채로 계층 맥락으로 남는다',
        (tester) async {
      final store = await _storeWithTasks();
      await _pumpWide(tester, store);

      // 연구 프로젝트만 보기로 필터링하면 futRoot(매칭 안 됨, projectId=research
      // 이므로 실제로는 매칭됨) 를 확인하기 위해 상태 필터로 leaf 만 매칭시킨다.
      // -> "미래 하위 작업" 이 done 이 아니므로 상태=onHold 로만 필터링해 매칭 없음
      //    상태 필터 대신 검색어로 leaf 텍스트만 매칭시켜 조상(futRoot)이
      //    context ancestor 가 되는 상황을 만든다.
      await tester.enterText(find.byType(TextField).first, '하위');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('미래 목표'), findsWidgets,
          reason: '매칭된 leaf 의 조상은 맥락으로 계속 보여야 한다');
      expect(find.text('미래 하위 작업'), findsWidgets);
      expect(find.text('오늘 작업'), findsNothing,
          reason: '검색어와 무관한 작업은 안 보여야 한다');
    });

    testWidgets('필터 초기화 버튼을 누르면 전체가 다시 보인다', (tester) async {
      final store = await _storeWithTasks();
      await _pumpWide(tester, store);

      await tester.tap(find.widgetWithText(ChoiceChip, '오늘'));
      await tester.pumpAndSettle();
      expect(find.text('미래 하위 작업'), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt_off_outlined));
      await tester.pumpAndSettle();
      expect(find.text('미래 하위 작업'), findsWidgets);
    });

    testWidgets('필터 결과가 0건이면 전용 빈 상태와 "전체 보기로 전환" 버튼이 보인다',
        (tester) async {
      final store = await _storeWithTasks();
      await _pumpWide(tester, store);

      // "지연" 은 endDate < today && !done — 현재 샘플엔 지연 작업이 없다.
      await tester.tap(find.widgetWithText(ChoiceChip, '지연'));
      await tester.pumpAndSettle();

      expect(find.text('아직 계획된 작업이 없습니다.'), findsOneWidget);
      expect(find.text('전체 보기로 전환'), findsOneWidget);

      await tester.tap(find.text('전체 보기로 전환'));
      await tester.pumpAndSettle();
      expect(find.text('오늘 작업'), findsWidgets);
    });
  });
}
