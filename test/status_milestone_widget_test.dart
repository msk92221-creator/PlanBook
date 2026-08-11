import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/ui/plan/gantt_theme.dart';
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
    nowProvider: () => DateTime(2026, 8, 10),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  // load() 가 기본 프로젝트 시드를 위해 예약한 autosave Timer 를 즉시 비운다.
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

void main() {
  group('TaskStatus 4상태 시각화', () {
    testWidgets('4개 상태가 서로 다른 아이콘으로 트리에 렌더된다', (tester) async {
      final store = await _emptyStore();
      // 기본 시드 프로젝트가 있어도 무관 — 별도 leaf Task 4개만 만든다.
      store.addNode(
        title: '미시작',
        status: TaskStatus.notStarted,
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 2),
      );
      store.addNode(
        title: '진행중',
        status: TaskStatus.inProgress,
        startDate: PlanDate(2026, 8, 3),
        endDate: PlanDate(2026, 8, 4),
      );
      store.addNode(
        title: '완료',
        status: TaskStatus.done,
        startDate: PlanDate(2026, 8, 5),
        endDate: PlanDate(2026, 8, 6),
      );
      store.addNode(
        title: '보류',
        status: TaskStatus.onHold,
        startDate: PlanDate(2026, 8, 7),
        endDate: PlanDate(2026, 8, 8),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(
        find.byWidgetPredicate(
            (w) => w is Icon && w.icon == statusIconData(TaskStatus.notStarted)),
        findsWidgets,
        reason: 'notStarted 아이콘(circle_outlined) 이 있어야 한다',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is Icon && w.icon == statusIconData(TaskStatus.inProgress)),
        findsWidgets,
        reason: 'inProgress 아이콘(donut_large) 이 있어야 한다',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is Icon && w.icon == statusIconData(TaskStatus.done)),
        findsWidgets,
        reason: 'done 아이콘(check_circle) 이 있어야 한다',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is Icon && w.icon == statusIconData(TaskStatus.onHold)),
        findsWidgets,
        reason: 'onHold 아이콘(pause_circle_filled) 이 있어야 한다',
      );
    });

    testWidgets('onHold 는 done 과 다른 semantics 라벨을 갖는다(완료처럼 보이지 않음)',
        (tester) async {
      final store = await _emptyStore();
      store.addNode(
        title: '완료작업',
        status: TaskStatus.done,
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 3),
      );
      store.addNode(
        title: '보류작업',
        status: TaskStatus.onHold,
        startDate: PlanDate(2026, 8, 5),
        endDate: PlanDate(2026, 8, 7),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(find.bySemanticsLabel('완료작업 ($kDoneSemantics)'), findsWidgets);
      expect(find.bySemanticsLabel('보류작업 ($kOnHoldSemantics)'), findsWidgets);
      // 서로 다른 라벨 문구를 쓰는지(상수 값 자체의 회귀 방지).
      expect(kDoneSemantics == kOnHoldSemantics, isFalse);
    });
  });

  group('Milestone 표시', () {
    testWidgets('날짜가 있는 마일스톤은 Gantt 에 마커로 표시된다', (tester) async {
      final store = await _emptyStore();
      final m = store.addNode(
        title: '중간 발표',
        isMilestone: true,
        endDate: PlanDate(2026, 8, 20),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(find.byKey(ValueKey('milestone-marker-${m.id}')), findsOneWidget);
      // 이 노드는 마일스톤이므로 "날짜 미정" 이 아니라 마커가 보여야 한다.
      expect(find.text('날짜 미정'), findsNothing);
    });

    testWidgets('날짜가 없는 마일스톤은 Gantt 마커 없이 Tree 아이콘만 보인다',
        (tester) async {
      final store = await _emptyStore();
      final m = store.addNode(title: '날짜 미정 마일스톤', isMilestone: true);
      await store.flush();
      await _pumpWide(tester, store);

      expect(find.byKey(ValueKey('milestone-marker-${m.id}')), findsNothing);
      // Gantt 쪽엔 "날짜 미정" 텍스트로만 표시.
      expect(find.text('날짜 미정'), findsWidgets);
      // Tree 쪽 마일스톤 아이콘은 날짜 유무와 무관하게 항상 보인다.
      expect(find.byIcon(Icons.diamond_outlined), findsWidgets);
    });

    testWidgets('일반 Task(마일스톤 아님)는 마름모 마커를 쓰지 않는다', (tester) async {
      final store = await _emptyStore();
      final normal = store.addNode(
        title: '일반 작업',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(find.byKey(ValueKey('milestone-marker-${normal.id}')), findsNothing);
      expect(find.byIcon(Icons.diamond_outlined), findsNothing);
    });
  });

  group('요약(부모) 바 위의 자손 마일스톤 표시', () {
    testWidgets('자식 마일스톤이 부모 행에도 마커로 겹쳐 표시된다', (tester) async {
      final store = await _emptyStore();
      final parent = store.addNode(
        title: 'PA장비',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 28),
      );
      final m = store.addNode(
        parentId: parent.id,
        title: '착수회의',
        isMilestone: true,
        endDate: PlanDate(2026, 8, 12),
      );
      await store.flush();
      await _pumpWide(tester, store);

      // 마일스톤 자기 행의 마커는 그대로 있고,
      expect(find.byKey(ValueKey('milestone-marker-${m.id}')), findsOneWidget);
      // 부모 행에도 파생 마커가 하나 더 생긴다.
      expect(
        find.byKey(ValueKey('summary-milestone-${parent.id}-${m.id}')),
        findsOneWidget,
      );
    });

    testWidgets('부모를 접어도 자손 마일스톤 마커는 부모 행에 남는다', (tester) async {
      final store = await _emptyStore();
      final parent = store.addNode(
        title: 'PA장비',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 28),
      );
      final m = store.addNode(
        parentId: parent.id,
        title: '착수회의',
        isMilestone: true,
        endDate: PlanDate(2026, 8, 12),
      );
      store.setAllCollapsed(true);
      await store.flush();
      await _pumpWide(tester, store);

      // 접혔으므로 마일스톤 자기 행은 사라지지만,
      expect(find.byKey(ValueKey('milestone-marker-${m.id}')), findsNothing);
      // 부모 행 마커로 기점은 계속 보인다 — 이게 이 기능의 핵심이다.
      expect(
        find.byKey(ValueKey('summary-milestone-${parent.id}-${m.id}')),
        findsOneWidget,
      );
    });

    testWidgets('손자 마일스톤도 최상위 부모 행에 표시된다', (tester) async {
      final store = await _emptyStore();
      final root = store.addNode(
        title: 'PA장비',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 28),
      );
      final sub = store.addNode(parentId: root.id, title: '1단계');
      final m = store.addNode(
        parentId: sub.id,
        title: '납품',
        isMilestone: true,
        endDate: PlanDate(2026, 8, 15),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(
        find.byKey(ValueKey('summary-milestone-${root.id}-${m.id}')),
        findsOneWidget,
      );
    });

    testWidgets('자손에 마일스톤이 없으면 부모 행에 파생 마커가 생기지 않는다',
        (tester) async {
      final store = await _emptyStore();
      final parent = store.addNode(title: 'PA장비');
      store.addNode(
        parentId: parent.id,
        title: '일반 자식',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 5),
      );
      await store.flush();
      await _pumpWide(tester, store);

      expect(
        find.byKey(ValueKey('summary-milestone-${parent.id}-')),
        findsNothing,
      );
    });
  });
}
