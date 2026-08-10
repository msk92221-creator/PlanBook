import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/domain/plan_node.dart';
import 'package:planbook/domain/plan_tree.dart';

PlanNode _n(String id, {String? parent, String title = '', double sortOrder = 0}) =>
    PlanNode(
      id: id,
      parentId: parent,
      title: title.isEmpty ? id : title,
      sortOrder: sortOrder,
    );

void main() {
  group('build & traversal', () {
    test('3+ depth tree: roots/children/ancestors/subtree', () {
      // root -> a -> a1 -> a1a
      //     \-> b
      final tree = PlanTree.fromNodes([
        _n('root', sortOrder: 0),
        _n('a', parent: 'root', sortOrder: 0),
        _n('b', parent: 'root', sortOrder: 1),
        _n('a1', parent: 'a', sortOrder: 0),
        _n('a1a', parent: 'a1', sortOrder: 0),
      ]);
      expect(tree.length, 5);
      expect(tree.roots.map((n) => n.id), ['root']);
      expect(tree.childrenOf('root').map((n) => n.id), ['a', 'b']);
      expect(tree.childrenOf('a').map((n) => n.id), ['a1']);
      expect(tree.childrenOf('a1').map((n) => n.id), ['a1a']);
      expect(tree.ancestorsOf('a1a').map((n) => n.id), ['a1', 'a', 'root']);
      expect(tree.subtree('a').map((n) => n.id), ['a', 'a1', 'a1a']);
      expect(tree.isLeaf('a1a'), isTrue);
      expect(tree.isLeaf('a'), isFalse);
    });
  });

  group('cycle prevention', () {
    test('moving a node under itself is rejected', () {
      final tree = PlanTree.fromNodes([
        _n('a'),
        _n('b', parent: 'a'),
      ]);
      expect(() => tree.move('a', 'a'), throwsA(isA<PlanTreeException>()));
      // unchanged
      expect(tree['a']!.parentId, isNull);
    });

    test('moving a node under its descendant is rejected', () {
      // a -> b -> c ; moving a under c should fail
      final tree = PlanTree.fromNodes([
        _n('a'),
        _n('b', parent: 'a'),
        _n('c', parent: 'b'),
      ]);
      expect(() => tree.move('a', 'c'), throwsA(isA<PlanTreeException>()));
      expect(() => tree.move('a', 'b'), throwsA(isA<PlanTreeException>()));
      expect(tree['a']!.parentId, isNull);
    });

    test('wouldCreateCycle detection helpers', () {
      final tree = PlanTree.fromNodes([
        _n('a'),
        _n('b', parent: 'a'),
        _n('c', parent: 'b'),
      ]);
      expect(tree.wouldCreateCycle('a', 'c'), isTrue);
      expect(tree.wouldCreateCycle('a', 'b'), isTrue);
      expect(tree.wouldCreateCycle('a', 'a'), isTrue);
      expect(tree.wouldCreateCycle('a', null), isFalse); // to root: ok
      expect(tree.wouldCreateCycle('c', 'a'), isFalse); // moving leaf up: ok
    });
  });

  group('move', () {
    test('moving to another parent updates hierarchy', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('a', parent: 'root', sortOrder: 0),
        _n('b', parent: 'root', sortOrder: 1),
        _n('leaf', parent: 'a', sortOrder: 0),
      ]);
      tree.move('leaf', 'b');
      expect(tree['leaf']!.parentId, 'b');
      expect(tree.childrenOf('a').map((n) => n.id), isEmpty);
      expect(tree.childrenOf('b').map((n) => n.id), ['leaf']);
    });

    test('promote to root (parentId=null)', () {
      final tree = PlanTree.fromNodes([
        _n('a'),
        _n('b', parent: 'a'),
      ]);
      tree.move('b', null);
      expect(tree.roots.map((n) => n.id), containsAll(['a', 'b']));
      expect(tree['b']!.parentId, isNull);
    });
  });

  group('reorder (ID-based before/after)', () {
    test('move before a sibling reorders within same parent', () {
      final tree = PlanTree.fromNodes([
        _n('p'),
        _n('a', parent: 'p', sortOrder: 0),
        _n('b', parent: 'p', sortOrder: 1),
        _n('c', parent: 'p', sortOrder: 2),
        _n('d', parent: 'p', sortOrder: 3),
      ]);
      // move d before b -> [a, d, b, c]
      tree.insertAt('d',
          newParentId: 'p',
          referenceSiblingId: 'b',
          position: InsertPosition.before);
      expect(tree.childrenOf('p').map((n) => n.id), ['a', 'd', 'b', 'c']);
      // sortOrder recomputed to 0,1,2,3
      final siblings = tree.childrenOf('p');
      for (var i = 0; i < siblings.length; i++) {
        expect(siblings[i].sortOrder, i.toDouble());
      }
    });

    test('move after a sibling', () {
      final tree = PlanTree.fromNodes([
        _n('p'),
        _n('a', parent: 'p', sortOrder: 0),
        _n('b', parent: 'p', sortOrder: 1),
        _n('c', parent: 'p', sortOrder: 2),
      ]);
      // move a after c -> [b, c, a]
      tree.insertAt('a',
          newParentId: 'p',
          referenceSiblingId: 'c',
          position: InsertPosition.after);
      expect(tree.childrenOf('p').map((n) => n.id), ['b', 'c', 'a']);
    });

    test('move to new parent with before position', () {
      final tree = PlanTree.fromNodes([
        _n('p1'),
        _n('p2'),
        _n('x', parent: 'p1', sortOrder: 0),
        _n('y', parent: 'p2', sortOrder: 0),
        _n('z', parent: 'p2', sortOrder: 1),
      ]);
      // move x into p2 before z -> p2: [y, x, z]
      tree.insertAt('x',
          newParentId: 'p2',
          referenceSiblingId: 'z',
          position: InsertPosition.before);
      expect(tree['x']!.parentId, 'p2');
      expect(tree.childrenOf('p2').map((n) => n.id), ['y', 'x', 'z']);
      expect(tree.childrenOf('p1').map((n) => n.id), isEmpty);
    });

    test('reference sibling under wrong parent is rejected', () {
      final tree = PlanTree.fromNodes([
        _n('p1'),
        _n('p2'),
        _n('x', parent: 'p1', sortOrder: 0),
        _n('y', parent: 'p2', sortOrder: 0),
      ]);
      expect(
          () => tree.insertAt('x',
              newParentId: 'p1', // x stays in p1 but ref y is in p2
              referenceSiblingId: 'y',
              position: InsertPosition.before),
          throwsA(isA<PlanTreeException>()));
    });
  });

  group('delete', () {
    test('cascade removes descendants only of target branch', () {
      // root -> a -> a1 -> a1a
      //     \-> b -> b1
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('a', parent: 'root', sortOrder: 0),
        _n('b', parent: 'root', sortOrder: 1),
        _n('a1', parent: 'a'),
        _n('a1a', parent: 'a1'),
        _n('b1', parent: 'b'),
      ]);
      final removed = tree.deleteCascade('a');
      // removed: a, a1, a1a = 3
      expect(removed, 3);
      expect(tree.contains('a'), isFalse);
      expect(tree.contains('a1'), isFalse);
      expect(tree.contains('a1a'), isFalse);
      // other branch untouched
      expect(tree.contains('root'), isTrue);
      expect(tree.contains('b'), isTrue);
      expect(tree.contains('b1'), isTrue);
      expect(tree.length, 3);
    });

    test('descendantCount before delete', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('a', parent: 'root'),
        _n('a1', parent: 'a'),
        _n('a1a', parent: 'a1'),
      ]);
      expect(tree.descendantCount('a'), 2); // a1, a1a
    });

    test('deletePromote reparents children to grandparent preserving order', () {
      final tree = PlanTree.fromNodes([
        _n('root'),
        _n('a', parent: 'root', sortOrder: 0),
        _n('b', parent: 'root', sortOrder: 1),
        _n('c', parent: 'root', sortOrder: 2),
        _n('x', parent: 'b', sortOrder: 0),
        _n('y', parent: 'b', sortOrder: 1),
      ]);
      final removed = tree.deletePromote('b');
      expect(removed, 1);
      expect(tree.contains('b'), isFalse);
      // x, y now under root, in place of b
      expect(tree.childrenOf('root').map((n) => n.id), ['a', 'x', 'y', 'c']);
      expect(tree['x']!.parentId, 'root');
      expect(tree['y']!.parentId, 'root');
    });
  });

  // ---- 踰꾧렇 #1, #2 ?뚭? ?뚯뒪??----
  group('move append-to-end (regression for bug #1)', () {
    test(
        'move() appends moved node to END of new parent children '
        '(stale sortOrder collides with existing child)', () {
      // X has sortOrder=0 under P1. New parent P2 has A(0), B(1), C(2).
      // X's old sortOrder (0) ties with A(0). Before the fix X landed in the
      // middle ([A, X, B, C]) because the stale-sortOrder list was reindexed.
      final tree = PlanTree.fromNodes([
        _n('P1', sortOrder: 0),
        _n('P2', sortOrder: 1),
        _n('X', parent: 'P1', sortOrder: 0),
        _n('A', parent: 'P2', sortOrder: 0),
        _n('B', parent: 'P2', sortOrder: 1),
        _n('C', parent: 'P2', sortOrder: 2),
      ]);
      tree.move('X', 'P2');
      expect(tree.childrenOf('P2').map((n) => n.id), ['A', 'B', 'C', 'X']);
      expect(tree.childrenOf('P1').map((n) => n.id), isEmpty);
      expect(tree['X']!.parentId, 'P2');
      // sortOrder reassigned tightly 0,1,2,3.
      final siblings = tree.childrenOf('P2');
      for (var i = 0; i < siblings.length; i++) {
        expect(siblings[i].sortOrder, i.toDouble());
      }
    });

    test('move() to root appends to end of roots', () {
      final tree = PlanTree.fromNodes([
        _n('A', sortOrder: 0),
        _n('B', sortOrder: 1),
        _n('C', sortOrder: 2),
        _n('p', sortOrder: 3),
        _n('x', parent: 'p', sortOrder: 5), // stale, large sortOrder
      ]);
      tree.move('x', null);
      expect(tree.roots.map((n) => n.id), ['A', 'B', 'C', 'p', 'x']);
    });

    test(
        'after cross-parent move, remaining old-parent children have tight '
        'sortOrder 0,1,2,...', () {
      // P1 has children [a(0), b(1), c(2), d(3)]; move c out ??remainder must
      // reindex to 0,1,2 with no gap.
      final tree = PlanTree.fromNodes([
        _n('P1'),
        _n('P2'),
        _n('a', parent: 'P1', sortOrder: 0),
        _n('b', parent: 'P1', sortOrder: 1),
        _n('c', parent: 'P1', sortOrder: 2),
        _n('d', parent: 'P1', sortOrder: 3),
        _n('z', parent: 'P2', sortOrder: 0),
      ]);
      tree.move('c', 'P2');
      final remaining = tree.childrenOf('P1');
      expect(remaining.map((n) => n.id), ['a', 'b', 'd']);
      for (var i = 0; i < remaining.length; i++) {
        expect(remaining[i].sortOrder, i.toDouble(),
            reason: 'old parent children must reindex to 0,1,2,...');
      }
    });
  });

  group('deletePromote splice (regression for bug #2)', () {
    test('deleted node is FIRST sibling ??children splice into its slot', () {
      // root children: M(0), A(1), Z(2); M children: c1(0), c2(1).
      // Before the fix this produced [c1, A, c2, Z] due to stale sortOrder.
      final tree = PlanTree.fromNodes([
        _n('M', sortOrder: 0),
        _n('A', sortOrder: 1),
        _n('Z', sortOrder: 2),
        _n('c1', parent: 'M', sortOrder: 0),
        _n('c2', parent: 'M', sortOrder: 1),
      ]);
      final removed = tree.deletePromote('M');
      expect(removed, 1);
      expect(tree.contains('M'), isFalse);
      expect(tree.childrenOf(null).map((n) => n.id), ['c1', 'c2', 'A', 'Z']);
      expect(tree['c1']!.parentId, isNull);
      expect(tree['c2']!.parentId, isNull);
      final siblings = tree.childrenOf(null);
      for (var i = 0; i < siblings.length; i++) {
        expect(siblings[i].sortOrder, i.toDouble());
      }
    });

    test('deleted node is MIDDLE sibling ??children splice into its slot', () {
      // root children: A(0), M(1), Z(2); M children: c1(0), c2(1).
      final tree = PlanTree.fromNodes([
        _n('A', sortOrder: 0),
        _n('M', sortOrder: 1),
        _n('Z', sortOrder: 2),
        _n('c1', parent: 'M', sortOrder: 0),
        _n('c2', parent: 'M', sortOrder: 1),
      ]);
      tree.deletePromote('M');
      expect(tree.childrenOf(null).map((n) => n.id), ['A', 'c1', 'c2', 'Z']);
    });

    test('deleted node is LAST sibling ??children splice into its slot', () {
      // root children: A(0), Z(1), M(2); M children: c1(0), c2(1).
      final tree = PlanTree.fromNodes([
        _n('A', sortOrder: 0),
        _n('Z', sortOrder: 1),
        _n('M', sortOrder: 2),
        _n('c1', parent: 'M', sortOrder: 0),
        _n('c2', parent: 'M', sortOrder: 1),
      ]);
      tree.deletePromote('M');
      expect(tree.childrenOf(null).map((n) => n.id), ['A', 'Z', 'c1', 'c2']);
    });

    test('promoted children relative order preserved with many siblings', () {
      // root: [A, M, B, Z]; M has [c1, c2, c3] ??expect [A, c1, c2, c3, B, Z].
      final tree = PlanTree.fromNodes([
        _n('A', sortOrder: 0),
        _n('M', sortOrder: 1),
        _n('B', sortOrder: 2),
        _n('Z', sortOrder: 3),
        _n('c1', parent: 'M', sortOrder: 0),
        _n('c2', parent: 'M', sortOrder: 1),
        _n('c3', parent: 'M', sortOrder: 2),
      ]);
      tree.deletePromote('M');
      expect(tree.childrenOf(null).map((n) => n.id),
          ['A', 'c1', 'c2', 'c3', 'B', 'Z']);
      final siblings = tree.childrenOf(null);
      for (var i = 0; i < siblings.length; i++) {
        expect(siblings[i].sortOrder, i.toDouble());
      }
    });
  });

  // ---- 踰꾧렇 #5 ?뚭? ?뚯뒪?? insertAt() ??遺紐??ъ깋??----
  group('insertAt cross-parent reindex (regression for bug #5)', () {
    // P1 ?먯떇 = a(0), b(1), c(2), d(3) / P2 ?먯떇 = z(0)
    // c 瑜?P2 ??z ?욎쑝濡??대룞 -> P2=[c,z], P1=[a,b,d].
    PlanTree buildScenario() => PlanTree.fromNodes([
          _n('P1'),
          _n('P2'),
          _n('a', parent: 'P1', sortOrder: 0),
          _n('b', parent: 'P1', sortOrder: 1),
          _n('c', parent: 'P1', sortOrder: 2),
          _n('d', parent: 'P1', sortOrder: 3),
          _n('z', parent: 'P2', sortOrder: 0),
        ]);

    test(
        'after insertAt() cross-parent move, remaining OLD-parent children '
        'reindex to 0,1,2,... (no gap)', () {
      final tree = buildScenario();
      tree.insertAt('c',
          newParentId: 'P2',
          referenceSiblingId: 'z',
          position: InsertPosition.before);
      final remaining = tree.childrenOf('P1');
      expect(remaining.map((n) => n.id), ['a', 'b', 'd']);
      for (var i = 0; i < remaining.length; i++) {
        expect(remaining[i].sortOrder, i.toDouble(),
            reason: 'old parent children must reindex to 0,1,2,...');
      }
    });

    test(
        'after insertAt() cross-parent move, NEW-parent children sortOrder '
        'is tight 0,1,2,...', () {
      final tree = buildScenario();
      tree.insertAt('c',
          newParentId: 'P2',
          referenceSiblingId: 'z',
          position: InsertPosition.before);
      final newSiblings = tree.childrenOf('P2');
      expect(newSiblings.map((n) => n.id), ['c', 'z']);
      for (var i = 0; i < newSiblings.length; i++) {
        expect(newSiblings[i].sortOrder, i.toDouble(),
            reason: 'new parent children must reindex to 0,1,2,...');
      }
    });

    test('여러 번 반복된 reorder/reparent 후에도 양쪽 sortOrder 가 항상 tight 하다',
        () {
      // Drag&Drop 을 여러 번 반복하는 실제 사용 패턴을 흉내낸다.
      final tree = buildScenario();

      void assertTight(String? parentId) {
        final siblings = tree.childrenOf(parentId);
        for (var i = 0; i < siblings.length; i++) {
          expect(siblings[i].sortOrder, i.toDouble(),
              reason: '$parentId 의 자식 sortOrder 가 매 연산 후 tight 해야 한다');
        }
      }

      // 1) c: P1 -> P2(z 앞).
      tree.insertAt('c',
          newParentId: 'P2', referenceSiblingId: 'z', position: InsertPosition.before);
      assertTight('P1');
      assertTight('P2');

      // 2) a: P1 -> P2(c 뒤).
      tree.insertAt('a',
          newParentId: 'P2', referenceSiblingId: 'c', position: InsertPosition.after);
      assertTight('P1');
      assertTight('P2');

      // 3) z: P2 -> P1(b 앞) — 다시 반대 방향으로.
      tree.insertAt('z',
          newParentId: 'P1', referenceSiblingId: 'b', position: InsertPosition.before);
      assertTight('P1');
      assertTight('P2');

      // 4) 같은 부모(P2) 내에서 순서만 변경.
      tree.insertAt('a',
          newParentId: 'P2', referenceSiblingId: 'c', position: InsertPosition.before);
      assertTight('P2');

      // 최종 순서도 기대대로인지(연산이 누적 적용됐는지) 확인.
      expect(tree.childrenOf('P1').map((n) => n.id), ['z', 'b', 'd']);
      expect(tree.childrenOf('P2').map((n) => n.id), ['a', 'c']);
    });
  });

  group('upsert / update', () {
    test('update mutates via copyWith', () {
      final tree = PlanTree.fromNodes([_n('a')]);
      tree.update('a', (c) => c.copyWith(title: 'hello'));
      expect(tree['a']!.title, 'hello');
    });
    test('update unknown throws', () {
      final tree = PlanTree();
      expect(() => tree.update('nope', (c) => c),
          throwsA(isA<PlanTreeException>()));
    });
  });
}
