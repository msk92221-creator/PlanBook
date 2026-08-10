import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_integrity.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/project.dart';
import 'package:planbook/domain/tag.dart';

void main() {
  group('checkIntegrity — 정상 데이터', () {
    test('건강한 트리는 이슈가 없다', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'root', title: 'root', projectId: 'p1', sortOrder: 0),
          PlanNode(
              id: 'child',
              parentId: 'root',
              title: 'child',
              tagIds: const ['t1'],
              sortOrder: 0,
              startDate: PlanDate(2026, 8, 1),
              endDate: PlanDate(2026, 8, 5)),
        ],
        projects: const [Project(id: 'p1', name: '업무')],
        tags: const [Tag(id: 't1', name: '급함')],
      );
      expect(report.isClean, isTrue);
      expect(report.hasErrors, isFalse);
    });
  });

  group('checkIntegrity — 중복 id', () {
    test('같은 id 의 Task 가 2개면 duplicate_node_id 에러', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'dup', title: 'a'),
          PlanNode(id: 'dup', title: 'b'),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'duplicate_node_id'), isTrue);
    });

    test('같은 id 의 Project 가 2개면 duplicate_project_id 에러', () {
      final report = checkIntegrity(
        nodes: const [],
        projects: const [Project(id: 'p', name: 'a'), Project(id: 'p', name: 'b')],
        tags: const [],
      );
      expect(
          report.errors.any((i) => i.code == 'duplicate_project_id'), isTrue);
    });

    test('같은 id 의 Tag 가 2개면 duplicate_tag_id 에러', () {
      final report = checkIntegrity(
        nodes: const [],
        projects: const [],
        tags: const [Tag(id: 't', name: 'a'), Tag(id: 't', name: 'b')],
      );
      expect(report.errors.any((i) => i.code == 'duplicate_tag_id'), isTrue);
    });
  });

  group('checkIntegrity — dangling 참조', () {
    test('존재하지 않는 parentId 는 dangling_parent 에러', () {
      final report = checkIntegrity(
        nodes: [PlanNode(id: 'a', parentId: '없음', title: 'a')],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'dangling_parent'), isTrue);
    });

    test('존재하지 않는 projectId 는 dangling_project 에러(삭제된 프로젝트를 여전히 참조)',
        () {
      final report = checkIntegrity(
        nodes: [PlanNode(id: 'a', title: 'a', projectId: '삭제된-프로젝트')],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'dangling_project'), isTrue);
    });

    test('존재하지 않는 tagId 는 dangling_tag 에러(삭제된 태그를 여전히 참조)', () {
      final report = checkIntegrity(
        nodes: [PlanNode(id: 'a', title: 'a', tagIds: const ['삭제된-태그'])],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'dangling_tag'), isTrue);
    });

    test('projectId==null(미분류) 은 정상 — dangling 아님', () {
      final report = checkIntegrity(
        nodes: [PlanNode(id: 'a', title: 'a', projectId: null)],
        projects: const [],
        tags: const [],
      );
      expect(report.isClean, isTrue);
    });
  });

  group('checkIntegrity — 순환 참조', () {
    test('서로를 부모로 삼는 2-노드 순환은 cycle 에러', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'a', parentId: 'b', title: 'a'),
          PlanNode(id: 'b', parentId: 'a', title: 'b'),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'cycle'), isTrue);
    });

    test('자기 자신을 부모로 삼으면 cycle 에러', () {
      final report = checkIntegrity(
        nodes: [PlanNode(id: 'a', parentId: 'a', title: 'a')],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'cycle'), isTrue);
    });

    test('정상적인 3단계 깊이 체인은 순환이 아니다', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'root', title: 'root'),
          PlanNode(id: 'mid', parentId: 'root', title: 'mid'),
          PlanNode(id: 'leaf', parentId: 'mid', title: 'leaf'),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.errors.any((i) => i.code == 'cycle'), isFalse);
    });
  });

  group('checkIntegrity — 날짜/마일스톤 정책', () {
    test('시작일이 종료일보다 늦으면 invalid_date_range 에러', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(
            id: 'a',
            title: 'a',
            startDate: PlanDate(2026, 8, 10),
            endDate: PlanDate(2026, 8, 5),
          ),
        ],
        projects: const [],
        tags: const [],
      );
      expect(
          report.errors.any((i) => i.code == 'invalid_date_range'), isTrue);
    });

    test('마일스톤인데 시작일!=종료일 이면 warning(에러 아님)', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(
            id: 'a',
            title: 'a',
            isMilestone: true,
            startDate: PlanDate(2026, 8, 1),
            endDate: PlanDate(2026, 8, 5),
          ),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.hasErrors, isFalse);
      expect(
          report.warnings.any((i) => i.code == 'milestone_date_mismatch'),
          isTrue);
    });

    test('마일스톤이고 시작일==종료일 이면 정상', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(
            id: 'a',
            title: 'a',
            isMilestone: true,
            startDate: PlanDate(2026, 8, 1),
            endDate: PlanDate(2026, 8, 1),
          ),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.isClean, isTrue);
    });
  });

  group('checkIntegrity — sortOrder', () {
    test('같은 부모의 형제끼리 sortOrder 가 중복되면 warning', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'a', title: 'a', sortOrder: 0),
          PlanNode(id: 'b', title: 'b', sortOrder: 0),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.hasErrors, isFalse);
      expect(
          report.warnings.any((i) => i.code == 'duplicate_sort_order'),
          isTrue);
    });

    test('다른 부모 아래라면 같은 sortOrder 값이어도 문제 없다', () {
      final report = checkIntegrity(
        nodes: [
          PlanNode(id: 'p1', title: 'p1', sortOrder: 0),
          PlanNode(id: 'p2', title: 'p2', sortOrder: 1),
          PlanNode(id: 'a', parentId: 'p1', title: 'a', sortOrder: 0),
          PlanNode(id: 'b', parentId: 'p2', title: 'b', sortOrder: 0),
        ],
        projects: const [],
        tags: const [],
      );
      expect(report.warnings, isEmpty);
    });
  });
}
