import 'package:flutter/gestures.dart';
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

Future<PlanStore> _store() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 10),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  store.addNode(
    title: 'PA장비',
    startDate: PlanDate(2026, 8, 1),
    endDate: PlanDate(2026, 8, 20),
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

/// 우클릭(보조 버튼) 제스처를 특정 좌표에 보낸다.
Future<void> _rightClickAt(WidgetTester tester, Offset pos) async {
  final gesture = await tester.startGesture(pos, buttons: kSecondaryButton);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Gantt 막대를 우클릭하면 컨텍스트 메뉴가 뜬다', (tester) async {
    final store = await _store();
    await _pumpWide(tester, store);

    // Gantt 막대(제목이 라벨로 들어간 위젯)를 찾아 우클릭한다.
    final bar = find.byKey(ValueKey('gantt-bar-${store.tree.allNodes.first.id}'));
    final target = bar.evaluate().isNotEmpty
        ? tester.getCenter(bar)
        // 키가 다르면 Gantt 영역의 임의 지점(오른쪽 절반)에서 시도한다.
        : const Offset(1000, 200);
    await _rightClickAt(tester, target);

    expect(find.text('편집...'), findsOneWidget);
    expect(find.text('삭제...'), findsOneWidget);
    expect(find.text('하위 항목 추가'), findsOneWidget);
  });

  testWidgets('Gantt 우클릭 메뉴에서 편집을 고르면 편집 다이얼로그가 열린다', (tester) async {
    final store = await _store();
    await _pumpWide(tester, store);

    await _rightClickAt(tester, const Offset(1000, 200));
    expect(find.text('편집...'), findsOneWidget);

    await tester.tap(find.text('편집...'));
    await tester.pumpAndSettle();

    expect(find.text('항목 편집'), findsOneWidget);
  });

  testWidgets('우클릭 메뉴는 목록과 Gantt 가 같은 항목을 보여준다', (tester) async {
    final store = await _store();
    await _pumpWide(tester, store);

    // 왼쪽 목록의 실제 행(제목 텍스트) 위에서 우클릭.
    final titleInTree = find.text('PA장비').first;
    await _rightClickAt(tester, tester.getCenter(titleInTree));
    final treeItems = [
      for (final t in ['하위 항목 추가', '형제 항목 추가', '편집...', '완료 토글', '삭제...'])
        find.text(t).evaluate().length,
    ];
    // 메뉴를 닫는다.
    await tester.tapAt(const Offset(700, 700));
    await tester.pumpAndSettle();

    // 오른쪽 Gantt 에서 우클릭.
    await _rightClickAt(tester, const Offset(1000, 200));
    final ganttItems = [
      for (final t in ['하위 항목 추가', '형제 항목 추가', '편집...', '완료 토글', '삭제...'])
        find.text(t).evaluate().length,
    ];

    expect(ganttItems, treeItems,
        reason: '같은 Task 를 두 곳에서 보는데 조작 메뉴가 달라서는 안 된다');
  });
}
