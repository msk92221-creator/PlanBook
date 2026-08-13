/// Gantt 막대 색상(고정 팔레트).
///
/// **왜 enum 만 있고 실제 `Color` 값은 없는가** — 이 앱은 라이트/다크 테마를 모두
/// 지원한다. 사용자가 임의의 ARGB 색을 고르면 한쪽 테마에서 대비가 무너져 막대의
/// 글자가 안 보이게 된다. 그래서 색을 고정 팔레트로 제한하고, 각 색의 라이트/다크
/// 대응값은 **UI 계층**(`ui/plan/gantt_theme.dart`)에서 매핑한다.
///
/// 도메인 계층은 여기서 안정적인 키(enum 의 name)와 한글 라벨만 갖는다.
/// 따라서 이 파일은 `package:flutter/material.dart` 를 import 하지 않는다 —
/// 도메인이 Flutter 에 의존하는 것을 피하고, 실제 `Color` 해석 책임을 UI 와
/// 명확히 나누기 위해서다.
///
/// `PlanNode.toJson`/`fromJson` 을 통해 `name` 문자열로 직렬화된다.
/// (`Priority`/`TaskStatus`/`NodeKind` 와 동일한 방식.)
library;

/// 막대 색상. [none] 이 기본값이며 "색 지정 안 함(기존 상태 색을 그대로 사용)"을 뜻한다.
enum BarColor {
  none,
  red,
  orange,
  yellow,
  green,
  blue,
  purple,
  gray;

  static BarColor fromName(String? name) {
    if (name == null) return BarColor.none;
    for (final v in BarColor.values) {
      if (v.name == name) return v;
    }
    return BarColor.none;
  }

  /// UI 표시용 한글 라벨.
  String get label => switch (this) {
        BarColor.none => '없음',
        BarColor.red => '빨강',
        BarColor.orange => '주황',
        BarColor.yellow => '노랑',
        BarColor.green => '초록',
        BarColor.blue => '파랑',
        BarColor.purple => '보라',
        BarColor.gray => '회색',
      };
}
