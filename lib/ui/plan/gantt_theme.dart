/// Gantt/트리 UI 공통 상수와 색상.
///
/// 다크/라이트 모두에서 읽히도록 가능한 한 Theme 에서 색을 유도하고,
/// 상수 색은 보수적으로만 사용한다.
library;

import 'package:flutter/material.dart';

import '../../domain/plan_enums.dart';

/// 행 높이. 좌측 트리/우측 Gantt 가 같은 행 높이를 써야 정렬된다.
const double kRowHeight = 44.0;

/// 헤더 높이.
const double kHeaderHeight = 52.0;

/// 좌측 트리 패널 폭(2분할 모드).
const double kTreePaneWidth = 300.0;

/// 이 폭(논리 px) 이상이면 좌우 2분할, 미만이면 트리/타임라인 전환 모드.
const double kTwoPaneBreakpoint = 720.0;

/// Gantt 바 모서리 반경.
const double kBarRadius = 6.0;

/// 부모 요약 바(얇은) 의 두께 비율(행 높이 대비).
const double kSummaryBarHeightRatio = 0.34;

/// 리프 바의 두께 비율.
const double kLeafBarHeightRatio = 0.6;

/// "오늘" 세로선 색.
const Color kTodayColor = Color(0xFFE53935);

/// 완료 상태 semantics 라벨(위젯 테스트에서 검증용).
const String kDoneSemantics = '완료됨';

/// 보류 상태 semantics 라벨(위젯 테스트에서 검증용).
/// onHold 는 완료가 아니므로 [kDoneSemantics] 와 절대 같은 문구를 쓰지 않는다.
const String kOnHoldSemantics = '보류';

/// 바의 채워진(진행) 영역 색.
Color barFillColor(BuildContext context, {required bool done}) {
  final c = Theme.of(context).colorScheme;
  return done ? c.outline : c.primary;
}

/// 바의 미충족(트랙) 영역 색.
Color barTrackColor(BuildContext context) {
  return Theme.of(context).colorScheme.primary.withValues(alpha: 0.22);
}

/// 바 위 텍스트 색.
Color onBarTextColor(BuildContext context, {required bool done}) {
  final c = Theme.of(context).colorScheme;
  return done
      ? c.onSurface.withValues(alpha: 0.45)
      : c.onPrimary;
}

// ---------------------------------------------------------------------------
// TaskStatus 4상태 시각화
//
// **rollup(부모 요약) bar/아이콘은 건드리지 않는다** — rollup 은 done 여부만
// 집계할 뿐 4상태 개념이 없다(자식 중 하나라도 보류여도 "보류로 집계"라는 개념은
// 없음). 아래 헬퍼는 **leaf 노드(또는 autoRollup=false 노드)의 자기 자신 status**
// 를 표시할 때만 쓴다. 색상은 기존 팔레트(primary/outline/tertiary)만 재사용해
// 과도한 색상 추가를 피한다.
// ---------------------------------------------------------------------------

/// 상태별 아이콘. notStarted/inProgress/done/onHold 를 모양으로 구분한다.
/// (색상만으로 구분하지 않음 — 색약 접근성 및 흑백 캡처에도 구분 가능하도록)
IconData statusIconData(TaskStatus status) => switch (status) {
      TaskStatus.notStarted => Icons.circle_outlined,
      TaskStatus.inProgress => Icons.donut_large,
      TaskStatus.done => Icons.check_circle,
      TaskStatus.onHold => Icons.pause_circle_filled,
    };

/// 상태별 아이콘/강조 색.
/// **onHold 는 절대 done 과 같은 색을 쓰지 않는다** — 보류가 완료처럼 보이면 안 된다.
Color statusAccentColor(BuildContext context, TaskStatus status) {
  final c = Theme.of(context).colorScheme;
  return switch (status) {
    TaskStatus.notStarted => c.outline,
    TaskStatus.inProgress => c.primary,
    TaskStatus.done => c.primary,
    TaskStatus.onHold => c.tertiary,
  };
}

/// Gantt bar 채움색(leaf 전용). 요약(rollup) bar 는 기존 [barFillColor] 를 그대로 쓴다.
Color statusBarFillColor(BuildContext context, TaskStatus status) {
  final c = Theme.of(context).colorScheme;
  return switch (status) {
    // notStarted 는 진행중보다 옅게 — 아직 손대지 않았음을 은은하게 표시.
    TaskStatus.notStarted => c.primary.withValues(alpha: 0.55),
    TaskStatus.inProgress => c.primary,
    // done 은 기존 barFillColor(done:true) 와 동일한 색(outline) 유지.
    TaskStatus.done => c.outline,
    TaskStatus.onHold => c.tertiary,
  };
}
