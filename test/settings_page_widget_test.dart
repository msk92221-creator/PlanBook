import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';
import 'package:planbook/ui/settings/settings_page.dart';

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
  await tester.pumpWidget(MaterialApp(home: SettingsPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('"마지막 화면 복원" 토글을 켜면 설정에 반영된다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    expect(store.settings.restoreLastScreen, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await store.flush();

    expect(store.settings.restoreLastScreen, isTrue);
  });

  testWidgets('테마를 다크로 바꾸면 설정에 반영된다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    expect(store.settings.themeMode, ThemeMode.system);
    await tester.tap(find.text('다크'));
    await tester.pump();
    await store.flush();

    expect(store.settings.themeMode, ThemeMode.dark);
  });

  testWidgets('기본 줌을 주 단위로 바꾸면 설정에 반영된다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    expect(store.settings.defaultZoom, GanttZoomLevel.day);
    await tester.tap(find.text('주'));
    await tester.pump();
    await store.flush();

    expect(store.settings.defaultZoom, GanttZoomLevel.week);
  });

  testWidgets('주 시작 요일을 일요일로 바꾸면 설정에 반영된다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    expect(store.settings.weekStart, DateTime.monday);
    await tester.tap(find.text('일요일'));
    await tester.pump();
    await store.flush();

    expect(store.settings.weekStart, DateTime.sunday);
  });

  testWidgets('동기화 섹션이 보인다(path_provider 채널이 없어도 화면은 죽지 않는다)',
      (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('동기화'), 200);
    await tester.pump();

    expect(find.text('동기화'), findsOneWidget);
  });

  testWidgets('백업 섹션에 내보내기/가져오기 항목이 보인다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    // ListView 는 뷰포트 밖 항목을 지연 생성하므로, 하단의 백업 섹션은
    // 스크롤해서 실제로 보이게 만든 뒤 확인해야 한다.
    await tester.scrollUntilVisible(find.text('가져오기'), 200);
    await tester.pump();

    expect(find.text('백업'), findsOneWidget);
    expect(find.text('내보내기'), findsOneWidget);
    expect(find.text('가져오기'), findsOneWidget);
  });

  testWidgets('가져오기를 탭하면 경로 입력 다이얼로그가 뜨고, 취소하면 아무 것도 바뀌지 않는다',
      (tester) async {
    final store = await _emptyStore();
    store.addNode(title: '기존 작업');
    await store.flush();
    await _pump(tester, store);

    await tester.scrollUntilVisible(find.text('가져오기'), 200);
    await tester.pump();
    await tester.tap(find.text('가져오기'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('불러오기'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 취소했으니 파일 I/O 는 전혀 일어나지 않고 기존 데이터가 그대로 남는다.
    expect(store.tree.allNodes.map((n) => n.title), ['기존 작업']);
  });

  testWidgets('앱 정보 섹션에 업데이트 확인 항목이 보인다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    await tester.scrollUntilVisible(find.text('업데이트 확인'), 200);
    await tester.pump();

    expect(find.text('업데이트 확인'), findsOneWidget);
  });

  testWidgets('디버그 무결성 검사: 정상 데이터면 "이상 없음"이 뜬다', (tester) async {
    final store = await _emptyStore();
    store.addNode(title: '정상 작업');
    await store.flush();
    await _pump(tester, store);

    await tester.scrollUntilVisible(find.text('데이터 무결성 검사'), 200);
    await tester.pump();
    await tester.tap(find.text('데이터 무결성 검사'));
    await tester.pumpAndSettle();

    expect(find.text('이상 없음'), findsOneWidget);
  });

  testWidgets('디버그 무결성 검사: 끊긴 참조가 있으면 문제 건수가 표시된다', (tester) async {
    final store = await _emptyStore();
    // updateNode 로 존재하지 않는 parentId 를 직접 주입(정상 UI 흐름으로는
    // 만들어질 수 없는 상태를 검증하기 위한 의도적 테스트 셋업).
    final node = store.addNode(title: '작업');
    store.updateNode(node.id, (n) => n.copyWith(parentId: '존재하지않음'));
    await store.flush();
    await _pump(tester, store);

    await tester.scrollUntilVisible(find.text('데이터 무결성 검사'), 200);
    await tester.pump();
    await tester.tap(find.text('데이터 무결성 검사'));
    await tester.pumpAndSettle();

    expect(find.textContaining('문제'), findsOneWidget);
    expect(find.textContaining('상위 항목'), findsOneWidget);
  });
}
