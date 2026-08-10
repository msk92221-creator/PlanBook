import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/recurrence.dart';
import 'package:planbook/ui/plan/node_edit_dialog.dart';

class _MemoryRepo implements PlanRepository {
  PlanSnapshot? _snap;
  @override
  Future<PlanSnapshot?> load() async => _snap;
  @override
  Future<void> save(PlanSnapshot snapshot) async => _snap = snapshot;
}

Future<PlanStore> _seededStore() async {
  final store = PlanStore(
    repository: _MemoryRepo(),
    nowProvider: () => DateTime(2026, 8, 10),
    autosaveDelay: Duration.zero,
  );
  await store.load(); // 기본 프로젝트 5개 시드됨.
  // load() 가 시드를 위해 예약한 autosave Timer 를 즉시 비운다.
  await store.flush();
  addTearDown(store.dispose);
  return store;
}

void main() {
  group('NodeEditResult.applyTo (순수 로직)', () {
    test('projectId / tagIds / status / isMilestone 를 노드에 반영한다', () {
      const src = PlanNode(id: 'n1', title: '원본');
      const result = NodeEditResult(
        title: '수정됨',
        newParentId: null,
        startDate: null,
        endDate: null,
        progress: 0.5,
        status: TaskStatus.inProgress,
        priority: Priority.medium,
        isMilestone: true,
        projectId: 'proj-1',
        tagIds: ['tag-a', 'tag-b'],
        memo: null,
        estimate: null,
        actual: null,
        autoRollup: true,
      );
      final applied = result.applyTo(src);
      expect(applied.projectId, 'proj-1');
      expect(applied.tagIds, ['tag-a', 'tag-b']);
      expect(applied.status, TaskStatus.inProgress);
      expect(applied.isMilestone, isTrue);
      // id/parentId 는 보존.
      expect(applied.id, 'n1');
    });

    test('projectId 를 null 로 지정하면 실제로 지워진다(미분류로)', () {
      const src = PlanNode(id: 'n1', title: '원본', projectId: 'proj-old');
      const result = NodeEditResult(
        title: '원본',
        newParentId: null,
        startDate: null,
        endDate: null,
        progress: 0.0,
        status: TaskStatus.notStarted,
        priority: Priority.none,
        isMilestone: false,
        projectId: null,
        tagIds: [],
        memo: null,
        estimate: null,
        actual: null,
        autoRollup: true,
      );
      expect(result.applyTo(src).projectId, isNull);
    });
  });

  group('NodeEditDialog 위젯 상호작용', () {
    testWidgets('Project 드롭다운에서 선택하면 결과의 projectId 가 바뀐다',
        (tester) async {
      final store = await _seededStore();
      final node = store.addNode(title: 'Task', projectId: null);
      NodeEditResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 프로젝트 드롭다운 열기 → "연구" 선택.
      await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String?>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(1)); // 0=상위목표, 1=프로젝트
      await tester.pumpAndSettle();
      await tester.tap(find.text('연구').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      final research = store.projects.firstWhere((p) => p.name == '연구');
      expect(result, isNotNull);
      expect(result!.projectId, research.id);
    });

    testWidgets('Project 를 "미분류" 로 되돌리면 projectId 가 null 이 된다',
        (tester) async {
      final store = await _seededStore();
      final work = store.projects.firstWhere((p) => p.name == '업무');
      final node = store.addNode(title: 'Task', projectId: work.id);
      NodeEditResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
          find.byType(DropdownButtonFormField<String?>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(1)); // 0=상위목표, 1=프로젝트
      await tester.pumpAndSettle();
      await tester.tap(find.text('미분류').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result!.projectId, isNull);
    });

    testWidgets('Tag 칩을 여러 개 선택하면 tagIds 에 복수로 반영된다', (tester) async {
      final store = await _seededStore();
      final tagA = store.createTag('급함');
      final tagB = store.createTag('검토');
      final node = store.addNode(title: 'Task');

      NodeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 다이얼로그가 스크롤 가능한 컬럼이라 태그 영역이 뷰포트 밖일 수 있다 —
      // 탭하기 전에 반드시 스크롤로 노출시킨다.
      await tester.ensureVisible(find.widgetWithText(FilterChip, '급함'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '급함'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilterChip, '검토'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '검토'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result!.tagIds.toSet(), {tagA.id, tagB.id});
    });

    testWidgets('status 드롭다운 변경과 마일스톤 토글이 결과에 반영된다', (tester) async {
      final store = await _seededStore();
      final node = store.addNode(
        title: 'Task',
        startDate: PlanDate(2026, 8, 1),
        endDate: PlanDate(2026, 8, 2),
      );

      NodeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 상태: 보류로 변경.
      await tester.tap(find.byType(DropdownButtonFormField<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TaskStatus.onHold.label).last);
      await tester.pumpAndSettle();

      // 마일스톤 토글 켜기.
      await tester.tap(find.widgetWithText(SwitchListTile, '마일스톤'));
      await tester.pump();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result!.status, TaskStatus.onHold);
      expect(result!.isMilestone, isTrue);
    });

    testWidgets('상위 목표 드롭다운에는 자기 자신/자손이 후보로 나오지 않는다',
        (tester) async {
      final store = await _seededStore();
      final parent = store.addNode(title: '부모');
      final child = store.addNode(parentId: parent.id, title: '자식');
      store.addNode(parentId: child.id, title: '손자');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showNodeEditDialog(
                context,
                tree: store.tree,
                node: parent,
                store: store,
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();

      // 자기 자신(부모) 은 후보에 없어야 하고, 자손(자식/손자)도 없어야 한다
      // (순환 방지) — 메뉴에는 "없음(최상위)" 만 보여야 한다.
      expect(find.text('없음(최상위)'), findsWidgets);
      expect(find.text('자식').hitTestable(), findsNothing);
      expect(find.text('손자').hitTestable(), findsNothing);
    });

    testWidgets('상위 목표를 바꾸면 commitNodeEdit 이 moveNode 로 반영한다',
        (tester) async {
      final store = await _seededStore();
      final oldParent = store.addNode(title: '옛 부모');
      final newParent = store.addNode(title: '새 부모');
      final child = store.addNode(parentId: oldParent.id, title: '이동할 작업');

      NodeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: child,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('새 부모').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result!.newParentId, newParent.id);

      commitNodeEdit(store, child, result!);
      expect(store.tree[child.id]!.parentId, newParent.id);
      expect(store.tree.childrenOf(oldParent.id), isEmpty);
      await store.flush();
    });

    testWidgets('작업 유형을 반복형으로 바꾸고 요일을 선택하면 결과에 반영된다',
        (tester) async {
      final store = await _seededStore();
      final node = store.addNode(title: '운동');

      NodeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showNodeEditDialog(
                  context,
                  tree: store.tree,
                  node: node,
                  store: store,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      // 작업 유형 → 반복형.
      await tester.ensureVisible(find.byType(DropdownButtonFormField<NodeKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<NodeKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NodeKind.recurring.label).last);
      await tester.pumpAndSettle();

      // 반복 규칙 → 매주(요일 선택).
      await tester.ensureVisible(
          find.byType(DropdownButtonFormField<RecurrenceFreq>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<RecurrenceFreq>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(RecurrenceFreq.weekly.label).last);
      await tester.pumpAndSettle();

      // 월, 금 선택.
      await tester.ensureVisible(find.widgetWithText(FilterChip, '월'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '월'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '금'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(result!.nodeKind, NodeKind.recurring);
      expect(result!.recurrenceRule?.freq, RecurrenceFreq.weekly);
      expect(result!.recurrenceRule?.weekdays,
          {DateTime.monday, DateTime.friday});

      commitNodeEdit(store, node, result!);
      final saved = store.tree[node.id]!;
      expect(saved.nodeKind, NodeKind.recurring);
      expect(saved.recurrenceFreq, 'weekly');
      expect(saved.recurrenceWeekdays.toSet(),
          {DateTime.monday, DateTime.friday});
      await store.flush();
    });
  });
}
