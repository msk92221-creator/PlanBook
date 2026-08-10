/// 노드 삭제 확인 다이얼로그 (3단계).
///
/// 정책(DESIGN.md §5):
/// - 삭제 시 항상 **자손 수(descendantCount)** 를 미리 보여주는 확인창을 띄운다.
///   "이 항목과 하위 N개도 함께 삭제됩니다."
/// - 자손이 있으면 cascade / promote 중 선택. 자손이 없으면 단순 확인.
///
/// 반환값: 사용자가 선택한 삭제 방식. 취소 시 null.
library;

import 'package:flutter/material.dart';

import '../../domain/plan_tree.dart';

/// 삭제 방식 선택.
enum DeleteChoice { cancel, cascade, promote }

/// 삭제 확인 다이얼로그를 띄운다.
/// - 자손이 없으면 단순 확인(cascade 와 동일한 결과).
/// - 자손이 있으면 cascade / promote 중 선택.
/// 취소 시 [DeleteChoice.cancel] 반환.
Future<DeleteChoice> showDeleteConfirmDialog(
  BuildContext context, {
  required PlanTree tree,
  required String id,
}) async {
  final node = tree[id];
  if (node == null) return DeleteChoice.cancel;
  final descendants = tree.descendantCount(id);

  // 자손이 없으면 단순 확인.
  if (descendants == 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('항목 삭제'),
        content: Text('"${node.title}" 을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return ok == true ? DeleteChoice.cascade : DeleteChoice.cancel;
  }

  // 자손이 있으면 cascade / promote 선택.
  final choice = await showDialog<DeleteChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('항목 삭제'),
      content: Text(
        '"${node.title}" 과(와) 하위 항목 $descendants 개가 영향을 받습니다.\n'
        '삭제 방식을 선택하세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(DeleteChoice.cancel),
          child: const Text('취소'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(DeleteChoice.promote),
          child: const Text('하위 승격(promote)'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(DeleteChoice.cascade),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
            foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
          ),
          child: const Text('모두 삭제(cascade)'),
        ),
      ],
    ),
  );
  return choice ?? DeleteChoice.cancel;
}
