/// Gantt/트리 UI 공통 상수와 색상.
///
/// 다크/라이트 모두에서 읽히도록 가능한 한 Theme 에서 색을 유도하고,
/// 상수 색은 보수적으로만 사용한다.
library;

import 'package:flutter/material.dart';

import '../../domain/bar_color.dart';
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

// ---------------------------------------------------------------------------
// 막대 색상(고정 팔레트) → 실제 Color 매핑
//
// `BarColor` enum 은 도메인 계층에서 "안정적인 키 + 한글 라벨" 만 갖고 실제 Color
// 값을 갖지 않는다(라이트/다크 대응은 UI 계층 책임 — bar_color.dart 상단 주석 참고).
// 그래서 Color 해석은 이 파일 한 곳에 모은다. 팔레트는 라이트/다크 양쪽에서
// 흰 글자가 충분히 읽히는 채도/명도로 골랐다(이 파일 상단 원칙: "다크/라이트 모두에서
// 읽히도록").
// ---------------------------------------------------------------------------

/// 사용자가 고른 막대 색([BarColor]) 의 실제 Color.
///
/// [BarColor.none] 은 "색 지정 안 함" 이라 여기서 다루지 않는다 — 호출부는
/// [barColorOf] 가 null 을 반환하면 기존 로직([statusBarFillColor]/[barFillColor]) 으로
/// 폴백한다. 이 방식이 기존 동작을 가장 덜 건드린다(none 일 때의 색을 여기서
/// 임의로 재현할 필요가 없다).
///
/// 각 색은 라이트/다크 양쪽에서 흰 글자가 읽히도록 채도/명도를 잡았다. 다크 모드에서는
/// 같은 색이 약간 더 밝게(트랙과의 대비를 살리기 위해) 조정된다.
Color? barColorOf(BuildContext context, BarColor color) {
  if (color == BarColor.none) return null; // 기존 색 로직으로 폴백하라는 신호.
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return switch (color) {
    BarColor.none => null,
    BarColor.red => isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F),
    BarColor.orange => isDark ? const Color(0xFFFF9800) : const Color(0xFFE65100),
    BarColor.yellow =>
      // 노랑은 명도가 높아 흰 글자가 안 읽힌다 — 채도를 올리고 명도를 낮춰
      // 흰 글자 대비를 확보한다(일반적인 Material yellow 500 은 검정 글자용).
      isDark ? const Color(0xFFF9A825) : const Color(0xFFF57F17),
    BarColor.green => isDark ? const Color(0xFF43A047) : const Color(0xFF2E7D32),
    BarColor.blue => isDark ? const Color(0xFF1E88E5) : const Color(0xFF1565C0),
    BarColor.purple => isDark ? const Color(0xFF8E24AA) : const Color(0xFF6A1B9A),
    BarColor.gray => isDark ? const Color(0xFF757575) : const Color(0xFF616161),
  };
}

/// 사용자 지정 막대 색 위에서 쓸 텍스트/아이콘 색.
///
/// 배경 밝기를 직접 재서 검정/흰색을 고른다(고정 팔렛트라 상수로 박아도 되지만,
/// 라이트/다크 색차가 있어 계산이 더 견고하다). `color` 가 [BarColor.none] 이면
/// null 을 반환해 호출부가 기존 [onBarTextColor] 로 폴백하게 한다.
Color? onCustomBarTextColor(BuildContext context, BarColor color) {
  final bg = barColorOf(context, color);
  if (bg == null) return null; // 기존 글자색 로직으로 폴백.
  // 상대 휘도(relative luminance) 근사치로 밝기 판정. 흰 글자가 더 잘 읽히면 흰색.
  // (0.299/0.587/0.114 가중 — sRGB 근사로 충분하다.)
  final r = (bg.r * 255.0).round().clamp(0, 255);
  final g = (bg.g * 255.0).round().clamp(0, 255);
  final b = (bg.b * 255.0).round().clamp(0, 255);
  final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
  return luminance < 140 ? Colors.white : Colors.black87;
}

/// 사용자 지정 막대 색의 "트랙(미충족 영역)" 색 — 지정 색의 옅은 버전.
///
/// `color` 가 [BarColor.none] 이면 null 을 반환해 기존 [barTrackColor] 로 폴백한다.
Color? customBarTrackColor(BuildContext context, BarColor color) {
  final bg = barColorOf(context, color);
  if (bg == null) return null; // 기존 트랙 색으로 폴백.
  return bg.withValues(alpha: 0.22);
}
