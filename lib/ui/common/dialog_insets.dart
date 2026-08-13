/// 팝업(AlertDialog) 여백 헬퍼.
///
/// **왜 필요한가**: 긴 팝업(특히 작업 편집 다이얼로그)이 화면 위아래를 꽉 채워
/// 상태바/네비게이션바에 딱 붙어 버린다. 사용자는 "위아래 꽉 찼다, 숨 쉴 틈이
/// 없다" 고 느낀다. 이 헬퍼로 시스템 바로부터 최소 16px 여백을 보장한다.
///
/// **이중 적용에 주의 (실측으로 확인한 사실)**: [showDialog] 의 기본값
/// `useSafeArea: true` 때문에 다이얼로그 오버레이 자체가 **안전영역**(시스템
/// 바를 뺀 영역) 안에 깔린다. 즉 [Dialog] 의 `insetPadding` 은 **그 안전영역
/// 가장자리로부터의 여백**을 뜻한다 — 시스템 바 높이는 이미 빠져 있다.
///
/// 그래서 `viewPadding.top + margin` 처럼 시스템 바 높이를 다시 더하면
/// **여백이 두 번 적용**된다. 여기서는 시스템 바 높이를 더하지 않고
/// **[margin] 이 그대로 시스템 바와 팝업 사이의 여백**이 된다.
///
/// **[margin] 기본값이 왜 32 인가 (실측)**: Material 기본 insetPadding 의 세로값이
/// 24 라, 긴 팝업은 시스템 바에서 24px 떨어진 채 화면 높이의 85% 를 차지한다.
/// 그게 "위아래 꽉 찼다" 는 인상을 준다. 32 로 넓혀 숨 틈을 키우고, 본문 높이는
/// [maxDialogContentHeight] 로 따로 제한한다. **기본값(24) 보다 작게 잡으면
/// 오히려 답답해지므로 24 미만으로 내리지 말 것.**
///
/// 실측 검증은 test/dialog_insets_test.dart 를 볼 것.
library;

import 'package:flutter/material.dart';

/// 팝업이 시스템 바(상태바/제스처바)에 딱 붙지 않도록 여백을 더한 insetPadding.
///
/// [MediaQuery.viewPaddingOf] 를 읽어 현재 기기의 시스템 인셋을 확인한 뒤,
/// **[margin] 만큼만** 추가로 여백을 더한다(위 "이중 적용" 주석 참고).
/// 가로는 Material 기본(40) 보다 약간 좁게(24) 잡되, 시스템 인셋이 큰 기기에서는
/// 그 인셋보다는 항상 넓게 둬 좁은 폰에서 팝업이 너무 작아지지 않게 한다.
EdgeInsets safeDialogInsetPadding(BuildContext context, {double margin = 32}) {
  final viewPadding = MediaQuery.viewPaddingOf(context);
  // 세로: 오버레이가 이미 안전영역이라 시스템 바 높이는 빠져 있으므로,
  // margin 만 더하면 시스템 바와 팝업 사이 여백이 정확히 margin 이 된다.
  // 가로: 시스템 가로 인셋(노치 등) 보다 margin 만큼 더 넓게 둔다.
  final horizontal =
      (viewPadding.left > viewPadding.right ? viewPadding.left : viewPadding.right) +
          margin;
  return EdgeInsets.symmetric(
    horizontal: horizontal < 24 ? 24 : horizontal,
    // Material 기본 세로 여백(24) 보다 좁아지면 지금보다 답답해진다 — 하한을 건다.
    vertical: margin < 24 ? 24 : margin,
  );
}

/// 팝업 본문이 가질 수 있는 최대 높이(안전영역 높이의 일정 비율).
///
/// 내용이 긴 팝업(편집 다이얼로그 등)이 화면을 꽉 채우지 않도록 본문 높이에 상한을
/// 둔다. [ConstrainedBox] 의 `maxHeight` 등에 사용한다. 안전영역(시스템 바를 뺀
/// 실제 사용 가능 높이) 의 [ratio] 배.
double maxDialogContentHeight(BuildContext context, {double ratio = 0.8}) {
  assert(ratio > 0 && ratio <= 1);
  final mq = MediaQuery.of(context);
  final safeHeight = mq.size.height - mq.padding.top - mq.padding.bottom;
  return safeHeight * ratio;
}
