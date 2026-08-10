/// Today/Calendar 가 공유하는 Task 한 줄 표시 위젯.
///
/// 완료 체크박스, 소속 breadcrumb, 날짜(또는 커스텀 subtitle — 예: "N일 지연"),
/// "Gantt 에서 보기" 버튼을 표준화한다. 화면마다 각자 다시 만들지 않는다.
library;

import 'package:flutter/material.dart';

import '../../domain/plan_node.dart';

class TaskRow extends StatelessWidget {
  final PlanNode node;

  /// 소속 표시(프로젝트 이름 + 조상 제목들, root→parent 순서). 비어있으면 숨김.
  final List<String> breadcrumb;

  /// 날짜 범위 대신 보여줄 문구(예: "3일 지연"). null 이면 날짜 범위를 보여준다.
  final String? subtitle;

  final VoidCallback onToggleDone;
  final VoidCallback onTap;

  /// null 이면 "Gantt 에서 보기" 버튼을 숨긴다.
  final VoidCallback? onOpenInGantt;

  /// null 이 아니면 "일정 재조정" 버튼을 보여준다(주로 지연된 Task 에만 표시).
  /// 실제 재조정 옵션 메뉴는 호출자가 연다 — 여기서는 진입점만 제공한다.
  final VoidCallback? onReschedule;

  /// 완료 체크박스 표시값을 [node.isDone] 대신 이 값으로 덮어쓴다.
  /// 반복형 Task 의 occurrence 별 완료 표시에 쓴다(원본 [PlanNode.status] 와
  /// occurrence 완료는 별개이므로 [node.isDone] 을 그대로 쓰면 안 된다).
  final bool? doneOverride;

  const TaskRow({
    super.key,
    required this.node,
    required this.breadcrumb,
    this.subtitle,
    required this.onToggleDone,
    required this.onTap,
    this.onOpenInGantt,
    this.onReschedule,
    this.doneOverride,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = doneOverride ?? node.isDone;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        leading: node.isMilestone
            ? Icon(Icons.diamond_outlined, color: scheme.tertiary)
            : IconButton(
                icon: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? scheme.primary : scheme.outline,
                ),
                onPressed: onToggleDone,
                tooltip: '완료 토글',
              ),
        title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (breadcrumb.isNotEmpty)
              Text(
                breadcrumb.join(' > '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            Text(
              subtitle ?? _dateRangeLabel(node),
              style: TextStyle(
                fontSize: 11,
                color: subtitle != null ? scheme.error : scheme.outline,
              ),
            ),
          ],
        ),
        trailing: (onReschedule == null && onOpenInGantt == null)
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onReschedule != null)
                    IconButton(
                      iconSize: 18,
                      tooltip: '일정 재조정',
                      icon: const Icon(Icons.event_repeat_outlined),
                      onPressed: onReschedule,
                    ),
                  if (onOpenInGantt != null)
                    IconButton(
                      iconSize: 18,
                      tooltip: 'Gantt 에서 보기',
                      icon: const Icon(Icons.view_timeline_outlined),
                      onPressed: onOpenInGantt,
                    ),
                ],
              ),
      ),
    );
  }

  String _dateRangeLabel(PlanNode n) {
    final s = n.startDate?.toIso();
    final e = n.endDate?.toIso();
    if (s == null && e == null) return '';
    return '${s ?? '?'} ~ ${e ?? '?'}';
  }
}
