/// 요약(부모) 행에 겹쳐 그릴 **자손 마일스톤** 수집.
///
/// Gantt 에서 부모 바는 자식 전체를 감싸는 요약이므로, 그 안에 있는 마일스톤이
/// 부모 바 위에도 보여야 "이 구간에 어떤 기점이 있는지"를 접힌 상태에서도 알 수
/// 있다. 마일스톤 노드 자신의 행에만 그리면, 부모를 접는 순간 기점이 화면에서
/// 통째로 사라진다.
///
/// 표시 전용이다 — 여기서 모은 값으로 드래그하거나 저장하지 않는다(이동은
/// 마일스톤 자기 행에서만 한다).
library;

import '../core/date/plan_date.dart';
import 'plan_enums.dart';
import 'plan_tree.dart';

/// 요약 바 위에 찍을 마커 하나.
class MilestoneMarkerInfo {
  final String id;
  final String title;

  /// 기준일. 마일스톤은 "기간"이 아니라 "시점"이라 하루만 갖는다
  /// (endDate 우선, 없으면 startDate — Gantt 본문의 규칙과 동일하다).
  final PlanDate date;

  final TaskStatus status;

  const MilestoneMarkerInfo({
    required this.id,
    required this.title,
    required this.date,
    required this.status,
  });

  @override
  bool operator ==(Object other) =>
      other is MilestoneMarkerInfo &&
      other.id == id &&
      other.title == title &&
      other.date == date &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, title, date, status);

  @override
  String toString() => 'MilestoneMarkerInfo($id,$title,${date.toIso()})';
}

/// [nodeId] 의 **자손 전체**(손자 이하 포함)에서 마일스톤을 모은다.
///
/// - [nodeId] 자신은 포함하지 않는다(자기 행은 이미 자기 마커를 그린다).
/// - 날짜가 하나도 없는 마일스톤은 찍을 위치가 없으므로 제외한다.
/// - 날짜 오름차순으로 정렬해서 돌려준다(같은 날짜면 id 순 — 렌더 순서가
///   실행마다 흔들리지 않게).
List<MilestoneMarkerInfo> collectDescendantMilestones(
  PlanTree tree,
  String nodeId,
) {
  final out = <MilestoneMarkerInfo>[];

  void visit(String parentId) {
    for (final child in tree.childrenOf(parentId)) {
      if (child.isMilestone) {
        final anchor = child.endDate ?? child.startDate;
        if (anchor != null) {
          out.add(MilestoneMarkerInfo(
            id: child.id,
            title: child.title,
            date: anchor,
            status: child.status,
          ));
        }
      }
      visit(child.id);
    }
  }

  visit(nodeId);

  out.sort((a, b) {
    final d = daysBetween(b.date, a.date);
    if (d != 0) return d > 0 ? 1 : -1;
    return a.id.compareTo(b.id);
  });
  return out;
}
