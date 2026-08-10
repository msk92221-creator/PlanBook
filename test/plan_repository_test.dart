import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';

Directory _freshTempDir(String name) {
  final base = Directory.systemTemp.createTempSync('planbook_$name');
  return base;
}

PlanNode _sampleNode() => PlanNode(
      id: 'node-1',
      parentId: null,
      title: '샘플',
      startDate: PlanDate(2024, 8, 12),
      endDate: PlanDate(2024, 8, 16),
      progress: 0.5,
      status: TaskStatus.inProgress,
      priority: Priority.high,
      projectId: 'proj-work',
      tagIds: const ['tag-a', 'tag-b'],
      isMilestone: true,
      memo: '메모',
      estimate: 4,
      actual: 2,
      sortOrder: 3.0,
      isCollapsed: true,
      nodeKind: NodeKind.project,
      autoRollup: false,
    );

void main() {
  late Directory dir;
  late JsonPlanRepository repo;

  setUp(() {
    dir = _freshTempDir('repo');
    repo = JsonPlanRepository(directory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('round-trip', () {
    test('save then load preserves all fields (id/parentId included)', () async {
      final snap = PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: [_sampleNode()],
      );
      await repo.save(snap);

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, PlanSnapshot.currentSchemaVersion);
      expect(loaded.nodes.length, 1);

      final n = loaded.nodes.first;
      final original = _sampleNode();
      expect(n.id, original.id);
      expect(n.parentId, original.parentId);
      expect(n.title, original.title);
      expect(n.startDate, original.startDate);
      expect(n.endDate, original.endDate);
      expect(n.progress, original.progress);
      expect(n.status, original.status);
      expect(n.isDone, original.isDone);
      expect(n.priority, original.priority);
      expect(n.projectId, original.projectId);
      expect(n.tagIds, original.tagIds);
      expect(n.isMilestone, original.isMilestone);
      expect(n.memo, original.memo);
      expect(n.estimate, original.estimate);
      expect(n.actual, original.actual);
      expect(n.sortOrder, original.sortOrder);
      expect(n.isCollapsed, original.isCollapsed);
      expect(n.nodeKind, original.nodeKind);
      expect(n.autoRollup, original.autoRollup);
    });

    test('multiple nodes with hierarchy preserved', () async {
      final nodes = [
        PlanNode(id: 'root', title: 'r', sortOrder: 0),
        PlanNode(id: 'a', parentId: 'root', title: 'a', sortOrder: 0),
        PlanNode(id: 'b', parentId: 'root', title: 'b', sortOrder: 1),
        PlanNode(id: 'a1', parentId: 'a', title: 'a1', sortOrder: 0),
      ];
      await repo.save(
          PlanSnapshot(schemaVersion: 1, nodes: nodes));
      final loaded = await repo.load();
      expect(loaded!.nodes.map((n) => n.id).toSet(), {'root', 'a', 'b', 'a1'});
      expect(loaded.nodes.firstWhere((n) => n.id == 'a1').parentId, 'a');
    });
  });

  group('missing / empty file', () {
    test('load returns null when file does not exist', () async {
      final loaded = await repo.load();
      expect(loaded, isNull);
    });

    test('load returns null for empty file', () async {
      await File('${dir.path}${Platform.pathSeparator}plan_store.json')
          .writeAsString('');
      final loaded = await repo.load();
      expect(loaded, isNull);
    });
  });

  group('corrupt recovery', () {
    test('malformed JSON -> null (no exception, no crash)', () async {
      await File('${dir.path}${Platform.pathSeparator}plan_store.json')
          .writeAsString('{ this is : not valid json ,,');
      final loaded = await repo.load();
      expect(loaded, isNull);
    });

    test('JSON object but not the expected shape -> null/empty', () async {
      await File('${dir.path}${Platform.pathSeparator}plan_store.json')
          .writeAsString('{"hello":"world"}');
      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.nodes, isEmpty);
    });

    test('one malformed node entry is skipped, others load', () async {
      await File('${dir.path}${Platform.pathSeparator}plan_store.json')
          .writeAsString('{"schemaVersion":1,"nodes":['
              '{"id":"good","title":"ok"},'
              '{"noId":"missing-required-id"},'
              '{"id":"good2","title":"ok2"}'
              ']}');
      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.nodes.map((n) => n.id).toSet(), {'good', 'good2'});
    });

    test('unknown fields are ignored (forward-compat)', () async {
      await File('${dir.path}${Platform.pathSeparator}plan_store.json')
          .writeAsString('{"schemaVersion":1,"unknownTop":42,"nodes":['
              '{"id":"x","title":"x","futureField":[1,2,3],"extra":{"k":1}}'
              ']}');
      final loaded = await repo.load();
      expect(loaded!.nodes.single.id, 'x');
    });
  });

  group('atomic write', () {
    test('save creates the target file (not just the tmp)', () async {
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [_sampleNode()]));
      final f = File('${dir.path}${Platform.pathSeparator}plan_store.json');
      expect(await f.exists(), isTrue);
    });

    test('save replaces existing content (overwrite)', () async {
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [
        PlanNode(id: 'first', title: '1'),
      ]));
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [
        PlanNode(id: 'second', title: '2'),
      ]));
      final loaded = await repo.load();
      expect(loaded!.nodes.single.id, 'second');
    });

    test('directory is created if missing', () async {
      final nested = Directory('${dir.path}${Platform.pathSeparator}deep');
      final nestedRepo = JsonPlanRepository(directory: nested);
      await nestedRepo.save(PlanSnapshot(schemaVersion: 1, nodes: const []));
      expect(nested.existsSync(), isTrue);
    });
  });

  group('custom filename', () {
    test('uses provided filename', () async {
      final customRepo =
          JsonPlanRepository(directory: dir, fileName: 'custom.json');
      await customRepo.save(PlanSnapshot(schemaVersion: 1, nodes: const []));
      expect(
          await File('${dir.path}${Platform.pathSeparator}custom.json')
              .exists(),
          isTrue);
    });
  });

  // ---- 버그 #4 회귀 테스트: 원자적 쓰기 / 크래시 복구 ----
  group('atomic write / crash recovery (regression for bug #4)', () {
    String tmpPathOf(Directory d) =>
        '${d.path}${Platform.pathSeparator}plan_store.json.tmp';
    String mainPathOf(Directory d) =>
        '${d.path}${Platform.pathSeparator}plan_store.json';

    test('save() leaves no .tmp file behind in the directory', () async {
      await repo.save(
          PlanSnapshot(schemaVersion: 1, nodes: [_sampleNode()]));
      expect(await File(tmpPathOf(dir)).exists(), isFalse,
          reason: '.tmp must be renamed away atomically on save');
    });

    test(
        'crash recovery: main file missing but valid .tmp present '
        '-> load() recovers data (not null)', () async {
      // 1) 정상 저장
      await repo.save(
          PlanSnapshot(schemaVersion: 1, nodes: [_sampleNode()]));
      // 2) 크래시 재현: 실제 저장 파일 삭제 + 유효한 .tmp 만 남긴 상태.
      await File(mainPathOf(dir)).delete();
      await File(tmpPathOf(dir)).writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'nodes': [
            {'id': 'recovered', 'title': 'recovered'},
          ],
        }),
      );
      final loaded = await repo.load();
      expect(loaded, isNotNull,
          reason: 'load() must recover from a valid .tmp when main is gone');
      expect(loaded!.nodes.single.id, 'recovered');
    });

    test(
        'both main and .tmp corrupted -> null safely (no exception, no data)',
        () async {
      await File(mainPathOf(dir)).writeAsString('{ broken json');
      await File(tmpPathOf(dir)).writeAsString('{ also broken json');
      final loaded = await repo.load();
      expect(loaded, isNull);
    });

    test(
        'save() overwrites a pre-existing main file '
        '(rename replaces existing target)', () async {
      // 사전 조건: 옛 버전 등으로 이미 main 파일이 존재.
      await File(mainPathOf(dir))
          .writeAsString('{"schemaVersion":1,"nodes":[]}');
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [
        PlanNode(id: 'fresh', title: 'fresh'),
      ]));
      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.nodes.single.id, 'fresh');
      // rename 이 기존 main 를 덮어썼으므로 .tmp 도 남지 않는다.
      expect(await File(tmpPathOf(dir)).exists(), isFalse);
    });
  });

  group('workload 필드(unit/nodeKind=quantity·effort) 라운드트립', () {
    test('quantity 노드의 unit/estimate/actual 이 보존된다', () async {
      final dir = _freshTempDir('workload_qty');
      addTearDown(() { if (dir.existsSync()) dir.deleteSync(recursive: true); });
      final repo = JsonPlanRepository(directory: dir);
      final node = PlanNode(
        id: 'q1',
        title: '책 읽기',
        nodeKind: NodeKind.quantity,
        estimate: 300,
        actual: 80,
        unit: 'page',
      );
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [node]));
      final loaded = await repo.load();
      final back = loaded!.nodes.single;
      expect(back.nodeKind, NodeKind.quantity);
      expect(back.estimate, 300);
      expect(back.actual, 80);
      expect(back.unit, 'page');
    });

    test('effort 노드도 동일하게 보존된다', () async {
      final dir = _freshTempDir('workload_effort');
      addTearDown(() { if (dir.existsSync()) dir.deleteSync(recursive: true); });
      final repo = JsonPlanRepository(directory: dir);
      final node = PlanNode(
        id: 'e1',
        title: '공부',
        nodeKind: NodeKind.effort,
        estimate: 20,
        actual: 6,
        unit: '시간',
      );
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [node]));
      final loaded = await repo.load();
      final back = loaded!.nodes.single;
      expect(back.nodeKind, NodeKind.effort);
      expect(back.unit, '시간');
    });

    test('unit 이 없는 기존(구버전) 데이터도 안전하게 읽힌다(unit=null)', () {
      final json = <String, Object?>{'id': 'a', 'title': 'a', 'nodeKind': 'quantity'};
      final n = PlanNode.fromJson(json);
      expect(n.nodeKind, NodeKind.quantity);
      expect(n.unit, isNull);
    });
  });

  group('반복(recurring) 필드 라운드트립', () {
    test('weekly 규칙 + occurrence 완료 기록이 보존된다', () async {
      final dir = _freshTempDir('recurring_weekly');
      addTearDown(() { if (dir.existsSync()) dir.deleteSync(recursive: true); });
      final repo = JsonPlanRepository(directory: dir);
      final node = PlanNode(
        id: 'rw1',
        title: '월/수/금 운동',
        nodeKind: NodeKind.recurring,
        recurrenceFreq: 'weekly',
        recurrenceWeekdays: const [1, 3, 5],
        recurrenceCompletedDates: const ['2026-08-10', '2026-08-12'],
      );
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [node]));
      final loaded = await repo.load();
      final back = loaded!.nodes.single;
      expect(back.nodeKind, NodeKind.recurring);
      expect(back.recurrenceFreq, 'weekly');
      expect(back.recurrenceWeekdays, [1, 3, 5]);
      expect(back.recurrenceCompletedDates, ['2026-08-10', '2026-08-12']);
    });

    test('monthly 규칙의 dayOfMonth 가 보존된다', () async {
      final dir = _freshTempDir('recurring_monthly');
      addTearDown(() { if (dir.existsSync()) dir.deleteSync(recursive: true); });
      final repo = JsonPlanRepository(directory: dir);
      final node = PlanNode(
        id: 'rm1',
        title: '매월 정산',
        nodeKind: NodeKind.recurring,
        recurrenceFreq: 'monthly',
        recurrenceDayOfMonth: 15,
      );
      await repo.save(PlanSnapshot(schemaVersion: 1, nodes: [node]));
      final loaded = await repo.load();
      final back = loaded!.nodes.single;
      expect(back.recurrenceFreq, 'monthly');
      expect(back.recurrenceDayOfMonth, 15);
    });

    test('반복 필드가 없는 기존(구버전) 데이터도 안전하게 읽힌다', () {
      final json = <String, Object?>{'id': 'a', 'title': 'a'};
      final n = PlanNode.fromJson(json);
      expect(n.recurrenceFreq, isNull);
      expect(n.recurrenceWeekdays, isEmpty);
      expect(n.recurrenceDayOfMonth, isNull);
      expect(n.recurrenceCompletedDates, isEmpty);
    });
  });
}
