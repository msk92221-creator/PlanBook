import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';
import 'package:planbook/domain/project_filter.dart';

PlanNode _n(String id, {String? parent, String? project, double order = 0}) =>
    PlanNode(id: id, parentId: parent, title: id, projectId: project, sortOrder: order);

void main() {
  group('ProjectFilter.matches', () {
    test('all 은 어떤 projectId 든 통과', () {
      const f = ProjectFilter.all();
      expect(f.matches(null), isTrue);
      expect(f.matches('p1'), isTrue);
    });

    test('unclassified 는 projectId == null 만 통과', () {
      const f = ProjectFilter.unclassified();
      expect(f.matches(null), isTrue);
      expect(f.matches('p1'), isFalse);
    });

    test('byId 는 정확히 같은 id 만 통과', () {
      const f = ProjectFilter.byId('p1');
      expect(f.matches('p1'), isTrue);
      expect(f.matches('p2'), isFalse);
      expect(f.matches(null), isFalse);
    });

    test('동등성: 같은 kind/projectId 면 == ', () {
      expect(const ProjectFilter.byId('p1'), const ProjectFilter.byId('p1'));
      expect(const ProjectFilter.byId('p1') == const ProjectFilter.byId('p2'),
          isFalse);
      expect(const ProjectFilter.all(), const ProjectFilter.all());
    });
  });

  group('visibleIdsForProjectFilter', () {
    test('전체 필터는 모든 노드를 포함', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1'),
        _n('b', project: 'p2'),
        _n('c'),
      ]);
      final ids = visibleIdsForProjectFilter(tree, const ProjectFilter.all());
      expect(ids, {'a', 'b', 'c'});
    });

    test('특정 프로젝트 필터: 해당 projectId 노드만', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1'),
        _n('b', project: 'p2'),
        _n('c', project: 'p1'),
      ]);
      final ids =
          visibleIdsForProjectFilter(tree, const ProjectFilter.byId('p1'));
      expect(ids, {'a', 'c'});
    });

    test('미분류 필터: projectId == null 인 노드만', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'p1'),
        _n('b'),
        _n('c'),
      ]);
      final ids =
          visibleIdsForProjectFilter(tree, const ProjectFilter.unclassified());
      expect(ids, {'b', 'c'});
    });

    test('사용자가 추가한(임의 id) 프로젝트도 동일하게 동작', () {
      final tree = PlanTree.fromNodes([
        _n('a', project: 'user-created-xyz'),
        _n('b', project: 'p1'),
      ]);
      final ids = visibleIdsForProjectFilter(
          tree, const ProjectFilter.byId('user-created-xyz'));
      expect(ids, {'a'});
    });

    test('계층 보존: 매칭된 노드의 조상은 매칭 안 해도 포함된다', () {
      // root(project=null) -> mid(project=p1) -> leaf(project=p1)
      final tree = PlanTree.fromNodes([
        _n('root'), // 매칭 안 됨(다른/없는 project)
        _n('mid', parent: 'root', project: 'p1'),
        _n('leaf', parent: 'mid', project: 'p1'),
      ]);
      final ids =
          visibleIdsForProjectFilter(tree, const ProjectFilter.byId('p1'));
      expect(ids, {'root', 'mid', 'leaf'},
          reason: 'root 는 매칭되지 않아도 mid/leaf 의 조상이므로 포함되어야 한다');
    });

    test('방어적 처리: 자식이 매칭되는데 부모가 다른 project 인 비정상 데이터', () {
      // root(project=p2, 다른 프로젝트!) -> child(project=p1, 필터 대상)
      final tree = PlanTree.fromNodes([
        _n('root', project: 'p2'),
        _n('child', parent: 'root', project: 'p1'),
      ]);
      final ids =
          visibleIdsForProjectFilter(tree, const ProjectFilter.byId('p1'));
      // 크래시 없이, child 는 포함되고 root 도 계층 유지를 위해 포함된다.
      expect(ids, {'root', 'child'});
    });

    test('매칭도 아니고 매칭의 조상도 아닌 가지는 제외된다', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('branchA', parent: 'root', project: 'p1'),
        _n('branchB', parent: 'root', project: 'p2'), // 무관한 가지
        _n('leafB', parent: 'branchB', project: 'p2'),
      ]);
      final ids =
          visibleIdsForProjectFilter(tree, const ProjectFilter.byId('p1'));
      expect(ids, {'root', 'branchA'});
      expect(ids.contains('branchB'), isFalse);
      expect(ids.contains('leafB'), isFalse);
    });
  });
}
