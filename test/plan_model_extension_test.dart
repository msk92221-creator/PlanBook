import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/json_plan_repository.dart';
import 'package:planbook/data/plan_migration.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/app_settings.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/project.dart';
import 'package:planbook/domain/tag.dart';
import 'package:planbook/ui/plan/gantt_metrics.dart';

Directory _tmp(String n) => Directory.systemTemp.createTempSync('planbook_$n');

/// 저장 파일에 구버전(v1) JSON 을 직접 써 넣는다.
void _writeLegacy(Directory dir, Map<String, Object?> payload) {
  File('${dir.path}${Platform.pathSeparator}plan_store.json')
      .writeAsStringSync(jsonEncode(payload));
}

void main() {
  group('Project / Tag / AppSettings JSON 라운드트립', () {
    test('Project 모든 필드 보존', () {
      const p = Project(
        id: 'p1',
        name: '업무',
        color: 0xFF112233,
        sortOrder: 3.5,
        isArchived: true,
      );
      final back = Project.fromJson(p.toJson());
      expect(back, p);
    });

    test('Tag 모든 필드 보존', () {
      const t = Tag(id: 't1', name: '급함', color: 0xFFAABBCC);
      expect(Tag.fromJson(t.toJson()), t);
    });

    test('AppSettings 모든 필드 보존', () {
      const s = AppSettings(
        themeMode: ThemeMode.dark,
        defaultZoom: GanttZoomLevel.month,
        lastScreen: AppScreen.projects,
        weekStart: DateTime.sunday,
        seededDefaultProjects: true,
        restoreLastScreen: true,
      );
      expect(AppSettings.fromJson(s.toJson()), s);
    });

    test('AppSettings 기본값: 최초 진입 화면은 Today, 마지막 화면 복원은 꺼짐', () {
      const s = AppSettings();
      expect(s.lastScreen, AppScreen.today);
      expect(s.seededDefaultProjects, isFalse);
      expect(s.restoreLastScreen, isFalse);
      // 알 수 없는 화면 이름이 저장돼 있어도 Today 로 안전 복귀.
      expect(AppScreen.fromName('nonexistent'), AppScreen.today);
      expect(AppScreen.fromName(null), AppScreen.today);
    });

    test('restoreLastScreen 이 없는 기존(구버전) 설정 데이터도 안전하게 읽힌다(기본 false)',
        () {
      final s = AppSettings.fromJson({'themeMode': 'dark'});
      expect(s.restoreLastScreen, isFalse);
      expect(s.themeMode, ThemeMode.dark);
    });
  });

  group('확장 스냅샷 저장/로드', () {
    test('projects/tags/settings 와 Task 신규 필드가 라운드트립된다', () async {
      final dir = _tmp('snap');
      addTearDown(() => dir.deleteSync(recursive: true));
      final repo = JsonPlanRepository(directory: dir);

      final snap = PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: [
          PlanNode(
            id: 'n1',
            title: '작업',
            projectId: 'p1',
            status: TaskStatus.onHold,
            tagIds: const ['t1', 't2'],
            isMilestone: true,
          ),
        ],
        projects: const [Project(id: 'p1', name: '업무')],
        tags: const [Tag(id: 't1', name: 'a'), Tag(id: 't2', name: 'b')],
        settings: const AppSettings(
          themeMode: ThemeMode.light,
          seededDefaultProjects: true,
        ),
      );
      await repo.save(snap);

      final loaded = await repo.load();
      expect(loaded, isNotNull);
      expect(loaded!.projects.single.name, '업무');
      expect(loaded.tags.map((t) => t.name), ['a', 'b']);
      expect(loaded.settings.themeMode, ThemeMode.light);
      expect(loaded.settings.seededDefaultProjects, isTrue);

      final n = loaded.nodes.single;
      expect(n.projectId, 'p1');
      expect(n.status, TaskStatus.onHold);
      expect(n.tagIds, ['t1', 't2']);
      expect(n.isMilestone, isTrue);
    });
  });

  group('v1 -> v2 마이그레이션', () {
    test('category 문자열이 Project 로 승격되고 projectId 로 연결된다', () async {
      final dir = _tmp('mig_cat');
      addTearDown(() => dir.deleteSync(recursive: true));
      _writeLegacy(dir, {
        'schemaVersion': 1,
        'nodes': [
          {'id': 'a', 'title': 'A', 'category': '업무'},
          {'id': 'b', 'title': 'B', 'category': '업무'},
          {'id': 'c', 'title': 'C', 'category': '연구'},
        ],
      });

      final loaded = await JsonPlanRepository(directory: dir).load();
      expect(loaded, isNotNull);
      expect(loaded!.projects.map((p) => p.name).toSet(), {'업무', '연구'});

      final byId = {for (final n in loaded.nodes) n.id: n};
      // 같은 이름은 같은 Project 하나로 합쳐져야 한다.
      expect(byId['a']!.projectId, isNotNull);
      expect(byId['a']!.projectId, byId['b']!.projectId);
      expect(byId['c']!.projectId, isNot(byId['a']!.projectId));
    });

    test('tags 문자열 배열이 Tag 로 승격되고 tagIds 로 연결된다', () async {
      final dir = _tmp('mig_tag');
      addTearDown(() => dir.deleteSync(recursive: true));
      _writeLegacy(dir, {
        'schemaVersion': 1,
        'nodes': [
          {
            'id': 'a',
            'title': 'A',
            'tags': ['급함', '검토'],
          },
          {
            'id': 'b',
            'title': 'B',
            'tags': ['급함'],
          },
        ],
      });

      final loaded = await JsonPlanRepository(directory: dir).load();
      expect(loaded!.tags.map((t) => t.name).toSet(), {'급함', '검토'});

      final byId = {for (final n in loaded.nodes) n.id: n};
      expect(byId['a']!.tagIds.length, 2);
      expect(byId['b']!.tagIds.length, 1);
      // 같은 이름 태그는 같은 id 를 공유해야 한다.
      expect(byId['b']!.tagIds.single, byId['a']!.tagIds.first);
    });

    test('isDone 이 status 로 변환된다 (true→done, false+진행률→inProgress)',
        () async {
      final dir = _tmp('mig_done');
      addTearDown(() => dir.deleteSync(recursive: true));
      _writeLegacy(dir, {
        'schemaVersion': 1,
        'nodes': [
          {'id': 'done', 'title': 'D', 'isDone': true},
          {'id': 'started', 'title': 'S', 'isDone': false, 'progress': 0.4},
          {'id': 'fresh', 'title': 'F', 'isDone': false, 'progress': 0.0},
        ],
      });

      final loaded = await JsonPlanRepository(directory: dir).load();
      final byId = {for (final n in loaded!.nodes) n.id: n};
      expect(byId['done']!.status, TaskStatus.done);
      expect(byId['done']!.isDone, isTrue);
      expect(byId['started']!.status, TaskStatus.inProgress);
      expect(byId['fresh']!.status, TaskStatus.notStarted);
    });

    test('마이그레이션 후 저장하면 schemaVersion 이 v2 로 기록된다', () async {
      final dir = _tmp('mig_ver');
      addTearDown(() => dir.deleteSync(recursive: true));
      _writeLegacy(dir, {
        'schemaVersion': 1,
        'nodes': [
          {'id': 'a', 'title': 'A', 'category': '업무'},
        ],
      });
      final repo = JsonPlanRepository(directory: dir);
      final loaded = await repo.load();
      expect(loaded!.schemaVersion, PlanSnapshot.currentSchemaVersion);
    });

    test('구버전 파싱은 알 수 없는 필드를 무시하고 깨진 노드만 건너뛴다', () {
      final snap = snapshotFromJson({
        'schemaVersion': 1,
        'unknownTopLevel': 123,
        'nodes': [
          {'id': 'ok', 'title': 'OK', 'someFutureField': true},
          {'title': 'id 없음 → 건너뜀'},
          'not a map',
        ],
      });
      expect(snap.nodes.map((n) => n.id), ['ok']);
    });
  });

  group('status <-> isDone 파생 관계', () {
    test('done 일 때만 isDone true, onHold 는 완료가 아니다', () {
      const base = PlanNode(id: 'x', title: 'x');
      expect(base.copyWith(status: TaskStatus.done).isDone, isTrue);
      expect(base.copyWith(status: TaskStatus.onHold).isDone, isFalse);
      expect(base.copyWith(status: TaskStatus.inProgress).isDone, isFalse);
      expect(base.copyWith(status: TaskStatus.notStarted).isDone, isFalse);
    });
  });

  group('PlanStore: projects / tags / settings', () {
    late Directory dir;
    late PlanStore store;

    setUp(() async {
      dir = _tmp('store');
      store = PlanStore(
        repository: JsonPlanRepository(directory: dir),
        nowProvider: () => DateTime(2026, 8, 10),
      );
    });

    tearDown(() {
      store.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('최초 로드에서 기본 프로젝트 5개를 시드한다', () async {
      await store.load();
      expect(store.projects.map((p) => p.name), kDefaultProjectNames);
      expect(store.settings.seededDefaultProjects, isTrue);
    });

    test('사용자가 지운 기본 프로젝트는 재실행해도 되살아나지 않는다', () async {
      await store.load();
      final work = store.projects.firstWhere((p) => p.name == '업무');
      store.deleteProject(work.id);
      await store.flush();
      expect(store.projects.any((p) => p.name == '업무'), isFalse);

      // 같은 저장소로 새 store 를 만들어 재실행을 흉내낸다.
      final store2 = PlanStore(
        repository: JsonPlanRepository(directory: dir),
        nowProvider: () => DateTime(2026, 8, 10),
      );
      addTearDown(store2.dispose);
      await store2.load();
      expect(store2.projects.any((p) => p.name == '업무'), isFalse,
          reason: '시드는 1회만. 지운 기본 프로젝트가 부활하면 안 된다');
      expect(store2.projects.length, kDefaultProjectNames.length - 1);
    });

    test('reorderProjects 는 주어진 순서대로 sortOrder 를 재부여한다', () async {
      await store.load();
      final ids = store.projects.map((p) => p.id).toList();
      final reversed = ids.reversed.toList();

      store.reorderProjects(reversed);

      expect(store.projects.map((p) => p.id).toList(), reversed);
    });

    test('reorderProjects 는 존재하지 않는 id 를 조용히 무시한다(크래시 없음)', () async {
      await store.load();
      final ids = store.projects.map((p) => p.id).toList();

      store.reorderProjects(['없는-id', ...ids]);

      expect(store.projects.map((p) => p.id).toSet(), ids.toSet());
    });

    test('deleteProject 는 Task 를 지우지 않고 projectId 만 null 로 만든다', () async {
      await store.load();
      final p = store.projects.first;
      final keep = store.addNode(title: '살아남아야 함', projectId: p.id);
      final other = store.addNode(title: '무관', projectId: store.projects[1].id);

      final detached = store.deleteProject(p.id);

      expect(detached, 1);
      expect(store.tree[keep.id], isNotNull, reason: 'Task 는 삭제되면 안 된다');
      expect(store.tree[keep.id]!.projectId, isNull);
      expect(store.tree[other.id]!.projectId, isNotNull,
          reason: '다른 프로젝트 Task 는 영향받지 않는다');
    });

    test('deleteTag 는 모든 Task 의 tagIds 에서 제거한다', () async {
      await store.load();
      final t1 = store.createTag('급함');
      final t2 = store.createTag('검토');
      final a = store.addNode(title: 'A', tagIds: [t1.id, t2.id]);
      final b = store.addNode(title: 'B', tagIds: [t2.id]);

      final affected = store.deleteTag(t2.id);

      expect(affected, 2);
      expect(store.tags.map((t) => t.id), [t1.id]);
      expect(store.tree[a.id]!.tagIds, [t1.id]);
      expect(store.tree[b.id]!.tagIds, isEmpty);
    });

    test('Project/Tag/Settings 변경이 저장되고 재로드된다', () async {
      await store.load();
      final p = store.createProject('신규프로젝트', color: 0xFF010203);
      store.createTag('태그');
      store.updateSettings((s) => s.copyWith(
            themeMode: ThemeMode.dark,
            lastScreen: AppScreen.gantt,
          ));
      await store.flush();

      final store2 = PlanStore(repository: JsonPlanRepository(directory: dir));
      addTearDown(store2.dispose);
      await store2.load();
      expect(store2.projects.any((x) => x.id == p.id), isTrue);
      expect(store2.tags.map((t) => t.name), contains('태그'));
      expect(store2.settings.themeMode, ThemeMode.dark);
      expect(store2.settings.lastScreen, AppScreen.gantt);
    });

    test('updateProject / updateTag 가 반영된다', () async {
      await store.load();
      final p = store.projects.first;
      store.updateProject(p.id, (cur) => cur.copyWith(name: '이름변경'));
      expect(store.projectById(p.id)!.name, '이름변경');

      final t = store.createTag('old');
      store.updateTag(t.id, (cur) => cur.copyWith(name: 'new'));
      expect(store.tagById(t.id)!.name, 'new');
    });
  });
}
