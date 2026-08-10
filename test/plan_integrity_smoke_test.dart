import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/core/date/plan_date.dart';
import 'package:planbook/data/plan_repository.dart';
import 'package:planbook/data/plan_store.dart';
import 'package:planbook/domain/plan_enums.dart';
import 'package:planbook/domain/plan_integrity.dart';
import 'package:planbook/domain/plan_tree.dart' show InsertPosition;
import 'package:planbook/domain/reschedule.dart';

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
    nowProvider: () => DateTime(2026, 8, 11),
    autosaveDelay: Duration.zero,
  );
  await store.load();
  await store.flush();
  return store;
}

/// 실제 앱에서 벌어질 법한 변경들을 한 세션에 몰아서 실행한 뒤, 최종 상태가
/// 구조적으로 깨끗한지(dangling/중복/순환 없음) 검증한다. 개별 기능(Phase
/// 1~16)은 각자 단위 테스트가 있지만, "여러 기능을 조합해서 오래 써도 구조가
/// 안 깨지는가" 는 이 스모크 테스트가 담당한다.
void main() {
  test('샘플 생성 + 이동/재정렬/태그/프로젝트/삭제/반복/재조정을 거쳐도 무결성 위반이 없다',
      () async {
    final store = await _emptyStore();
    final rootIds = store.createSampleData();
    await store.flush();

    final research = store.createProject('연구소');
    final tagA = store.createTag('급함');
    final tagB = store.createTag('검토');

    final root1 = rootIds.first;
    final children = store.tree.childrenOf(root1);
    expect(children, isNotEmpty);
    final firstChild = children.first;

    // 태그 부착.
    store.updateNode(firstChild.id,
        (n) => n.copyWith(tagIds: [tagA.id, tagB.id]));

    // reparent: 첫 자식을 두 번째 자식 아래로.
    if (children.length >= 2) {
      store.moveNode(children[1].id, firstChild.id);
    }

    // reorder: 형제 순서 변경.
    final siblings = store.tree.childrenOf(root1);
    if (siblings.length >= 2) {
      store.reorderSibling(siblings.last.id,
          referenceSiblingId: siblings.first.id,
          position: InsertPosition.before);
    }

    // 반복 Task 추가.
    store.addNode(
      title: '매일 스트레칭',
      nodeKind: NodeKind.recurring,
      recurrenceFreq: 'daily',
      projectId: research.id,
    );

    // 프로젝트 삭제(Task 는 남고 projectId 만 null 이 되어야 함).
    store.deleteProject(research.id);

    // 태그 하나 삭제(참조 정리되어야 함).
    store.deleteTag(tagA.id);

    // 지연 Task 재조정.
    final overdue = store.addNode(
      title: '밀린 작업',
      startDate: PlanDate(2026, 8, 1),
      endDate: PlanDate(2026, 8, 5),
    );
    store.rescheduleNode(overdue.id, RescheduleOption.autoRedistribute);

    // 일부 삭제(cascade/promote 둘 다 실행).
    if (siblings.length >= 2) {
      store.deletePromote(siblings.last.id);
    }
    store.deleteCascade(rootIds.last);

    await store.flush();

    final report = checkIntegrity(
      nodes: store.tree.allNodes,
      projects: store.projects,
      tags: store.tags,
    );

    if (!report.isClean) {
      // 실패 시 원인을 바로 알 수 있도록 이슈 목록을 메시지에 포함한다.
      fail('무결성 위반 발견:\n${report.issues.join('\n')}');
    }
    expect(report.isClean, isTrue);
    store.dispose();
  });
}
