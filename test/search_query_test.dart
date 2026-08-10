import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/domain/search_query.dart';

void main() {
  final today = PlanDate(2026, 8, 11);
  String? projectName(String? id) => switch (id) {
        'proj-work' => '업무',
        'proj-health' => '건강',
        _ => null,
      };
  String tagName(String id) => switch (id) {
        'tag-urgent' => '급함',
        'tag-review' => '검토',
        _ => id,
      };

  group('matchesSearchExtended', () {
    test('빈 검색어는 항상 매칭(true)', () {
      final n = PlanNode(id: 'a', title: '아무거나');
      expect(
        matchesSearchExtended(n, '',
            projectName: projectName, tagName: tagName, today: today),
        isTrue,
      );
    });

    test('제목 매칭(대소문자 무시)', () {
      final n = PlanNode(id: 'a', title: 'Complex Filter 완성');
      expect(
        matchesSearchExtended(n, 'complex',
            projectName: projectName, tagName: tagName, today: today),
        isTrue,
      );
    });

    test('메모 매칭', () {
      final n = PlanNode(id: 'a', title: '작업', memo: '이건 급하게 처리해야 함');
      expect(
        matchesSearchExtended(n, '급하게',
            projectName: projectName, tagName: tagName, today: today),
        isTrue,
      );
    });

    test('프로젝트 이름 매칭', () {
      final n = PlanNode(id: 'a', title: '작업', projectId: 'proj-health');
      expect(
        matchesSearchExtended(n, '건강',
            projectName: projectName, tagName: tagName, today: today),
        isTrue,
      );
    });

    test('태그 이름 매칭', () {
      final n = PlanNode(id: 'a', title: '작업', tagIds: const ['tag-urgent']);
      expect(
        matchesSearchExtended(n, '급함',
            projectName: projectName, tagName: tagName, today: today),
        isTrue,
      );
    });

    test('어디에도 없으면 false', () {
      final n = PlanNode(
        id: 'a',
        title: '작업',
        memo: '메모',
        projectId: 'proj-work',
        tagIds: const ['tag-review'],
      );
      expect(
        matchesSearchExtended(n, '존재하지않는단어',
            projectName: projectName, tagName: tagName, today: today),
        isFalse,
      );
    });
  });

  group('searchNodes', () {
    test('빈 검색어는 빈 결과(전체 덤프 금지)', () {
      final tree = PlanTree.fromNodes([PlanNode(id: 'a', title: 'a')]);
      expect(
        searchNodes(tree, '',
            projectName: projectName, tagName: tagName, today: today),
        isEmpty,
      );
    });

    test('제목 오름차순으로 정렬된다', () {
      final tree = PlanTree.fromNodes([
        PlanNode(id: 'z', title: 'zebra 필터'),
        PlanNode(id: 'a', title: 'apple 필터'),
      ]);
      final r = searchNodes(tree, '필터',
          projectName: projectName, tagName: tagName, today: today);
      expect(r.map((n) => n.id), ['a', 'z']);
    });

    test('제목/메모/프로젝트/태그에 흩어진 매칭을 모두 찾는다', () {
      final tree = PlanTree.fromNodes([
        PlanNode(id: 'byTitle', title: '급함 처리'),
        PlanNode(id: 'byMemo', title: 'x', memo: '급함 표시'),
        PlanNode(id: 'byProject', title: 'y', projectId: 'proj-work'),
        PlanNode(id: 'byTag', title: 'z', tagIds: const ['tag-urgent']),
        PlanNode(id: 'none', title: '관계없음'),
      ]);
      final r = searchNodes(tree, '급함',
          projectName: projectName, tagName: tagName, today: today);
      // byProject 는 "업무" 이름에 "급함" 이 없으므로 매칭 안 됨.
      expect(r.map((n) => n.id).toSet(), {'byTitle', 'byMemo', 'byTag'});
    });
  });
}
