import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/plan_export_import.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/project.dart';

Directory _tmp(String n) =>
    Directory.systemTemp.createTempSync('planbook_export_$n');

void main() {
  group('exportSnapshotToJsonString / parseImportJson 라운드트립', () {
    test('내보낸 JSON 을 다시 가져오면 노드/프로젝트가 그대로 복원된다', () {
      final snap = PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: [
          PlanNode(id: 'a', title: '작업 A', projectId: 'p1'),
          PlanNode(id: 'b', parentId: 'a', title: '하위 작업'),
        ],
        projects: const [Project(id: 'p1', name: '업무')],
      );
      final json = exportSnapshotToJsonString(snap);
      final result = parseImportJson(json);

      expect(result.isSuccess, isTrue);
      expect(result.snapshot!.nodes.map((n) => n.id).toSet(), {'a', 'b'});
      expect(result.snapshot!.projects.single.name, '업무');
    });
  });

  group('parseImportJson 검증', () {
    test('빈 문자열은 실패', () {
      final r = parseImportJson('');
      expect(r.isSuccess, isFalse);
      expect(r.error, isNotNull);
    });

    test('깨진 JSON 은 실패', () {
      final r = parseImportJson('{ not valid json ,,');
      expect(r.isSuccess, isFalse);
    });

    test('JSON 이긴 하지만 배열이면 실패(최상위는 객체여야 함)', () {
      final r = parseImportJson('[1,2,3]');
      expect(r.isSuccess, isFalse);
    });

    test('"nodes" 필드가 없는 무관한 JSON 은 실패(오파일 방지)', () {
      final r = parseImportJson(jsonEncode({'hello': 'world'}));
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('nodes'));
    });

    test('구버전(v1, schemaVersion 없음/category 문자열) 백업도 마이그레이션되어 성공한다',
        () {
      final r = parseImportJson(jsonEncode({
        'nodes': [
          {'id': 'x', 'title': 'old task', 'category': '업무', 'isDone': true},
        ],
      }));
      expect(r.isSuccess, isTrue);
      final node = r.snapshot!.nodes.single;
      expect(node.status.name, 'done');
      expect(node.projectId, isNotNull);
      expect(r.snapshot!.projects.single.name, '업무');
    });

    test('일부 노드가 깨져 있어도 나머지는 살아남는다(전체 실패 아님)', () {
      final r = parseImportJson(jsonEncode({
        'nodes': [
          {'id': 'good', 'title': 'ok'},
          {'noId': 'broken'},
        ],
      }));
      expect(r.isSuccess, isTrue);
      expect(r.snapshot!.nodes.map((n) => n.id), ['good']);
    });
  });

  group('exportSnapshotToFile / readAndParseImportFile (실제 파일 I/O)', () {
    test('내보낸 파일을 다시 읽어 그대로 복원한다', () async {
      final dir = _tmp('roundtrip');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}backup.json');
      final snap = PlanSnapshot(
        schemaVersion: PlanSnapshot.currentSchemaVersion,
        nodes: [PlanNode(id: 'a', title: '내보내기 테스트')],
      );
      await exportSnapshotToFile(snap, file);
      expect(await file.exists(), isTrue);

      final result = await readAndParseImportFile(file);
      expect(result.isSuccess, isTrue);
      expect(result.snapshot!.nodes.single.title, '내보내기 테스트');
    });

    test('존재하지 않는 파일은 실패 사유를 반환한다(예외 없음)', () async {
      final dir = _tmp('missing');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}nope.json');
      final result = await readAndParseImportFile(file);
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });
  });
}
