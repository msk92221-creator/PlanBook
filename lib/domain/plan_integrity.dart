/// 전체 데이터 무결성 검증(디버그/테스트용).
///
/// 앱 정상 동작 중에는 [PlanTree]/[PlanStore] 의 각 메서드(cycle 방지, cascade
/// delete, dangling reference 정리)가 이미 아래 불변식들을 지키도록 설계돼
/// 있다. 이 파일은 **그 불변식이 실제로 계속 지켜지고 있는지 사후 검증**하는
/// 별도의 순수 함수다 — 정상 흐름에서 호출을 강제하지 않는다(디버그 도구/테스트
/// 전용, UI 정상 동작에 영향 주지 않음).
library;

import '../core/date/plan_date.dart';
import 'plan_node.dart';
import 'project.dart';
import 'tag.dart';

enum IntegritySeverity { error, warning }

class IntegrityIssue {
  /// 짧은 분류 코드(테스트에서 종류별로 걸러낼 때 사용).
  final String code;
  final IntegritySeverity severity;
  final String message;
  final String? nodeId;

  const IntegrityIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.nodeId,
  });

  @override
  String toString() =>
      '[${severity.name}] $code${nodeId != null ? '($nodeId)' : ''}: $message';
}

class IntegrityReport {
  final List<IntegrityIssue> issues;
  const IntegrityReport(this.issues);

  bool get isClean => issues.isEmpty;
  bool get hasErrors => issues.any((i) => i.severity == IntegritySeverity.error);
  List<IntegrityIssue> get errors =>
      issues.where((i) => i.severity == IntegritySeverity.error).toList();
  List<IntegrityIssue> get warnings =>
      issues.where((i) => i.severity == IntegritySeverity.warning).toList();
}

/// [nodes]/[projects]/[tags] 전체를 검사해 [IntegrityReport] 를 만든다.
///
/// 검사 항목(요구사항 매핑):
/// - Task/Project/Tag id 중복 없음
/// - parentId/projectId/tagId 가 가리키는 대상이 실제로 존재함(dangling 없음)
///   → "Project 삭제는 Task 를 안 지운다"/"Tag 삭제는 참조를 정리한다" 정책이
///   실제로 지켜지고 있다면 dangling 참조가 하나도 없어야 한다.
/// - 순환 참조 없음(parentId 체인을 따라가도 자기 자신으로 돌아오지 않음)
/// - startDate <= endDate
/// - 마일스톤은 시작일/종료일이 있다면 같아야 한다(단일 시점 정책)
/// - 같은 부모의 형제끼리 sortOrder 중복 없음(순서 모호성 방지)
IntegrityReport checkIntegrity({
  required List<PlanNode> nodes,
  required List<Project> projects,
  required List<Tag> tags,
}) {
  final issues = <IntegrityIssue>[];

  void countDuplicates<T>(
    Iterable<T> ids,
    String code,
    String Function(T id) messageFor,
  ) {
    final counts = <T, int>{};
    for (final id in ids) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    counts.forEach((id, count) {
      if (count > 1) {
        issues.add(IntegrityIssue(
          code: code,
          severity: IntegritySeverity.error,
          message: messageFor(id),
        ));
      }
    });
  }

  countDuplicates(nodes.map((n) => n.id), 'duplicate_node_id',
      (id) => 'Task id가 중복됩니다: $id');
  countDuplicates(projects.map((p) => p.id), 'duplicate_project_id',
      (id) => 'Project id가 중복됩니다: $id');
  countDuplicates(tags.map((t) => t.id), 'duplicate_tag_id',
      (id) => 'Tag id가 중복됩니다: $id');

  // 이후 조회는 맵 기준(중복이 있었다면 마지막 값이 남음 — PlanTree.upsert 와
  // 동일한 정책이라 실제 런타임 동작과 일치하는 결과를 준다).
  final byId = <String, PlanNode>{for (final n in nodes) n.id: n};
  final projectIds = {for (final p in projects) p.id};
  final tagIds = {for (final t in tags) t.id};

  for (final n in byId.values) {
    if (n.parentId != null && !byId.containsKey(n.parentId)) {
      issues.add(IntegrityIssue(
        code: 'dangling_parent',
        severity: IntegritySeverity.error,
        message: '"${n.title}" 의 상위 항목(parentId=${n.parentId})이 존재하지 않습니다.',
        nodeId: n.id,
      ));
    }
    if (n.projectId != null && !projectIds.contains(n.projectId)) {
      issues.add(IntegrityIssue(
        code: 'dangling_project',
        severity: IntegritySeverity.error,
        message:
            '"${n.title}" 이(가) 존재하지 않는 프로젝트(projectId=${n.projectId})를 참조합니다.',
        nodeId: n.id,
      ));
    }
    for (final tid in n.tagIds) {
      if (!tagIds.contains(tid)) {
        issues.add(IntegrityIssue(
          code: 'dangling_tag',
          severity: IntegritySeverity.error,
          message: '"${n.title}" 이(가) 존재하지 않는 태그(tagId=$tid)를 참조합니다.',
          nodeId: n.id,
        ));
      }
    }

    final s = n.startDate;
    final e = n.endDate;
    if (s != null && e != null && daysBetween(s, e) < 0) {
      issues.add(IntegrityIssue(
        code: 'invalid_date_range',
        severity: IntegritySeverity.error,
        message: '"${n.title}" 의 시작일(${s.toIso()})이 종료일(${e.toIso()})보다 늦습니다.',
        nodeId: n.id,
      ));
    }
    if (n.isMilestone && s != null && e != null && s != e) {
      issues.add(IntegrityIssue(
        code: 'milestone_date_mismatch',
        severity: IntegritySeverity.warning,
        message: '"${n.title}" 은 마일스톤인데 시작일과 종료일이 다릅니다(단일 시점 권장).',
        nodeId: n.id,
      ));
    }
  }

  // 순환 참조: parentId 체인을 따라가며 이미 방문한 id 가 다시 나오면 순환.
  for (final n in byId.values) {
    final visited = <String>{n.id};
    var curParentId = n.parentId;
    while (curParentId != null) {
      if (!visited.add(curParentId)) {
        issues.add(IntegrityIssue(
          code: 'cycle',
          severity: IntegritySeverity.error,
          message: '"${n.title}" 의 상위 체인에 순환 참조가 있습니다.',
          nodeId: n.id,
        ));
        break;
      }
      final parent = byId[curParentId];
      if (parent == null) break; // dangling_parent 로 이미 보고됨.
      curParentId = parent.parentId;
    }
  }

  // 형제 sortOrder 중복.
  final byParent = <String?, List<PlanNode>>{};
  for (final n in byId.values) {
    byParent.putIfAbsent(n.parentId, () => <PlanNode>[]).add(n);
  }
  for (final siblings in byParent.values) {
    final seenOrders = <double>{};
    for (final s in siblings) {
      if (!seenOrders.add(s.sortOrder)) {
        issues.add(IntegrityIssue(
          code: 'duplicate_sort_order',
          severity: IntegritySeverity.warning,
          message: '"${s.title}" 의 sortOrder(${s.sortOrder})가 형제와 중복됩니다.',
          nodeId: s.id,
        ));
      }
    }
  }

  return IntegrityReport(issues);
}
