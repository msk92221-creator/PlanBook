import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/ui/today/today_page.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _storeOn(DateTime date) async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => date,
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

Future<void> _pump(WidgetTester tester, PlanStore store) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(MaterialApp(home: TodayPage(store: store)));
  await tester.pump();
}

void main() {
  testWidgets('매일 반복 Task 는 오늘의 반복 작업 섹션에 표시된다', (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    store.addNode(
      title: '매일 영어 30분',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'daily',
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('오늘의 반복 작업'), findsOneWidget);
    expect(find.text('매일 영어 30분'), findsOneWidget);
    expect(find.text('매일'), findsOneWidget);
  });

  testWidgets('요일이 안 맞는 weekly 반복 Task 는 오늘 표시되지 않는다', (tester) async {
    // 2026-08-11 은 화요일.
    final store = await _storeOn(DateTime(2026, 8, 11));
    store.addNode(
      title: '월/수/금 운동',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'weekly',
      recurrenceWeekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday],
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('오늘의 반복 작업'), findsNothing);
    expect(find.text('월/수/금 운동'), findsNothing);
  });

  testWidgets('요일이 맞는 weekly 반복 Task 는 오늘 표시된다', (tester) async {
    // 2026-08-12 는 수요일.
    final store = await _storeOn(DateTime(2026, 8, 12));
    store.addNode(
      title: '월/수/금 운동',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'weekly',
      recurrenceWeekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday],
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('월/수/금 운동'), findsOneWidget);
    expect(find.text('월,수,금'), findsOneWidget);
  });

  testWidgets(
      '반복 occurrence 완료 체크는 해당 날짜에만 기록되고, 원본 status/다른 날짜에는 영향이 없다',
      (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    final node = store.addNode(
      title: '매일 스트레칭',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'daily',
    );
    await store.flush();
    await _pump(tester, store);

    // 체크박스(완료 토글) 탭.
    final toggle = find.descendant(
      of: find.ancestor(
          of: find.text('매일 스트레칭'), matching: find.byType(Card)),
      matching: find.byType(IconButton),
    );
    await tester.tap(toggle.first);
    await tester.pump();
    await store.flush();

    final updated = store.tree[node.id]!;
    expect(updated.status, TaskStatus.notStarted,
        reason: '원본 status 는 occurrence 완료와 무관하게 유지되어야 한다');
    expect(updated.recurrenceCompletedDates, ['2026-08-11']);

    // 다른 날짜에는 영향 없음(직접 도메인 함수로 확인).
    expect(updated.recurrenceCompletedDates.contains('2026-08-12'), isFalse);
  });

  testWidgets('반복 Task 는 시작/종료일이 있어도 일반 A~D 섹션에는 중복으로 뜨지 않는다', (tester) async {
    final store = await _storeOn(DateTime(2026, 8, 11));
    store.addNode(
      title: '매일 물 마시기',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'daily',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 11), // 오늘이 endDate — 일반 로직이면 "오늘 마감"에 뜬다.
    );
    await store.flush();
    await _pump(tester, store);

    expect(find.text('오늘 마감'), findsNothing,
        reason: '반복형은 dueToday 등 일반 섹션 로직을 타면 안 된다');
    expect(find.text('매일 물 마시기'), findsOneWidget); // 반복 섹션에만 1번.
  });
}
