import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/ui/common/dialog_insets.dart';

/// 팝업이 시스템 바(상태바/제스처바)에 답답하게 붙지 않는지 검증한다.
///
/// **반드시 알아야 할 함정**: `find.byType(AlertDialog)` 로 재면 안 된다.
/// AlertDialog 는 insetPadding 을 적용하는 [Dialog] 의 **바깥** 위젯이라 항상
/// 안전영역 전체를 차지해서, 여백을 아무리 바꿔도 rect 가 변하지 않는다
/// (실제로 이걸로 재다가 "여백 0px" 이라는 잘못된 진단을 한 적이 있다).
/// 실제 보이는 흰 카드는 **Dialog 아래의 첫 Material** 이다.
const double _statusBar = 48.0;
const double _navBar = 24.0;

void _setPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding =
      const FakeViewPadding(top: _statusBar, bottom: _navBar);
  tester.view.viewPadding =
      const FakeViewPadding(top: _statusBar, bottom: _navBar);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// 실제로 보이는 팝업 카드의 사각형.
Rect _cardRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Material),
          )
          .first,
    );

Future<void> _open(
  WidgetTester tester, {
  required double contentHeight,
  EdgeInsets? inset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  insetPadding: inset ?? safeDialogInsetPadding(ctx),
                  title: const Text('제목'),
                  content: SizedBox(height: contentHeight, width: 200),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('확인')),
                  ],
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  group('팝업 여백', () {
    testWidgets('내용이 아주 긴 팝업도 시스템 바에서 24px 넘게 떨어진다', (tester) async {
      _setPhone(tester);
      await _open(tester, contentHeight: 2000);
      final card = _cardRect(tester);

      final topMargin = card.top - _statusBar;
      final bottomMargin = (800 - _navBar) - card.bottom;
      expect(topMargin, greaterThan(24.0),
          reason: 'Material 기본(24) 보다 넓어야 개선이다');
      expect(bottomMargin, greaterThan(24.0));
      // 과하게 벌어져 팝업이 쓸모없이 작아지지도 않아야 한다.
      expect(topMargin, lessThanOrEqualTo(48.0));
      expect(bottomMargin, lessThanOrEqualTo(48.0));
    });

    testWidgets('헬퍼가 Material 기본값보다 넓은 여백을 준다(회귀 방지)',
        (tester) async {
      _setPhone(tester);
      await _open(
        tester,
        contentHeight: 2000,
        inset: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      );
      final defaultTop = _cardRect(tester).top;

      // 트리를 한 번 비운다. 그냥 pumpWidget 을 다시 부르면 Navigator 가 재사용되어
      // 먼저 띄운 팝업 라우트가 살아남고, 그러면 아래에서 **같은 팝업을 다시 재게 된다**
      // (실제로 두 값이 똑같이 나와서 이 테스트가 처음엔 통과하지 못했다).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await _open(tester, contentHeight: 2000);
      final helperTop = _cardRect(tester).top;

      expect(helperTop, greaterThan(defaultTop),
          reason: '헬퍼가 기본값보다 여백이 좁으면 오히려 답답해진다');
    });

    testWidgets('짧은 팝업은 화면 가운데에 뜨고 시스템 바를 침범하지 않는다',
        (tester) async {
      _setPhone(tester);
      await _open(tester, contentHeight: 60);
      final card = _cardRect(tester);

      expect(card.top, greaterThan(_statusBar));
      expect(card.bottom, lessThan(800 - _navBar));
    });

    testWidgets('시스템 인셋이 0인 환경(데스크톱)에서도 화면 밖으로 나가지 않는다',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _open(tester, contentHeight: 2000);
      final card = _cardRect(tester);

      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.bottom, lessThanOrEqualTo(700));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(900));
    });
  });

  group('본문 최대 높이', () {
    testWidgets('안전영역 높이의 비율로 상한이 계산된다', (tester) async {
      _setPhone(tester);
      late double maxH;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              maxH = maxDialogContentHeight(context);
              return const SizedBox();
            },
          ),
        ),
      );
      // 안전영역 = 800 - 48 - 24 = 728, 기본 비율 0.8
      expect(maxH, closeTo(728 * 0.8, 0.5));
    });
  });
}
