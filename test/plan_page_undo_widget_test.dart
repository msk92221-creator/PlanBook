import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<PlanStore> _emptyStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

Future<void> _pump(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('변경이 없으면 실행취소/다시실행 버튼이 비활성화 상태다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    final undoBtn =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo));
    final redoBtn =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo));
    expect(undoBtn.onPressed, isNull);
    expect(redoBtn.onPressed, isNull);
  });

  testWidgets('mutation 이후 실행취소 버튼이 활성화되고, 탭하면 되돌아간다', (tester) async {
    final store = await _emptyStore();
    await _pump(tester, store);

    final node = store.addNode(title: '새 작업');
    await tester.pump();

    var undoBtn =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo));
    expect(undoBtn.onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.undo));
    await tester.pump();
    await store.flush();

    expect(store.tree.contains(node.id), isFalse);

    var redoBtn =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.redo));
    expect(redoBtn.onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.redo));
    await tester.pump();
    await store.flush();
    expect(store.tree.contains(node.id), isTrue);
  });
}
