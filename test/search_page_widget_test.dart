import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/search/search_page.dart';

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

Future<void> _pump(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: SearchPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('검색어가 비어 있으면 안내 문구만 표시된다(전체 덤프 금지)', (tester) async {
    final store = await _emptyStore();
    store.addNode(title: '아무 작업');
    await store.flush();
    await _pump(tester, store);

    expect(find.text('검색어를 입력하세요.'), findsOneWidget);
    expect(find.text('아무 작업'), findsNothing);
  });

  testWidgets('제목으로 검색하면 결과가 뜨고, 없으면 안내 문구가 뜬다', (tester) async {
    final store = await _emptyStore();
    store.addNode(title: 'Complex Filter 완성');
    store.addNode(title: '건강검진 예약');
    await store.flush();
    await _pump(tester, store);

    await tester.enterText(find.byType(TextField), 'complex');
    await tester.pump();
    expect(find.text('Complex Filter 완성'), findsOneWidget);
    expect(find.text('건강검진 예약'), findsNothing);

    await tester.enterText(find.byType(TextField), '존재하지않음');
    await tester.pump();
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
  });

  testWidgets('프로젝트/태그 이름으로도 검색된다', (tester) async {
    final store = await _emptyStore();
    final work = store.projects.firstWhere((p) => p.name == '업무');
    final tag = store.createTag('급함');
    store.addNode(title: '보고서 작성', projectId: work.id);
    store.addNode(title: '별도 작업', tagIds: [tag.id]);
    await store.flush();
    await _pump(tester, store);

    await tester.enterText(find.byType(TextField), '업무');
    await tester.pump();
    expect(find.text('보고서 작성'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '급함');
    await tester.pump();
    expect(find.text('별도 작업'), findsOneWidget);
  });
}
