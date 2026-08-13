import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/domain/bar_color.dart';

void main() {
  group('BarColor.fromName', () {
    test('알려진 이름은 해당 값으로 매핑된다', () {
      expect(BarColor.fromName('none'), BarColor.none);
      expect(BarColor.fromName('red'), BarColor.red);
      expect(BarColor.fromName('orange'), BarColor.orange);
      expect(BarColor.fromName('yellow'), BarColor.yellow);
      expect(BarColor.fromName('green'), BarColor.green);
      expect(BarColor.fromName('blue'), BarColor.blue);
      expect(BarColor.fromName('purple'), BarColor.purple);
      expect(BarColor.fromName('gray'), BarColor.gray);
    });

    test('null 은 none 으로 폴백한다', () {
      expect(BarColor.fromName(null), BarColor.none);
    });

    test('알 수 없는 이름은 none 으로 조용히 폴백한다(forward-compat)', () {
      // 미래 버전에서 추가될 수 있는 색(예: 'teal')이나, 온전히 잘못된 한글 문자열.
      expect(BarColor.fromName('teal'), BarColor.none);
      expect(BarColor.fromName('존재하지않는색'), BarColor.none);
      expect(BarColor.fromName(''), BarColor.none);
    });
  });

  group('BarColor.label', () {
    test('각 값이 지정된 한글 라벨을 갖는다', () {
      expect(BarColor.none.label, '없음');
      expect(BarColor.red.label, '빨강');
      expect(BarColor.orange.label, '주황');
      expect(BarColor.yellow.label, '노랑');
      expect(BarColor.green.label, '초록');
      expect(BarColor.blue.label, '파랑');
      expect(BarColor.purple.label, '보라');
      expect(BarColor.gray.label, '회색');
    });
  });

  test('name 문자열 라운드트립: fromName(v.name) == v', () {
    for (final v in BarColor.values) {
      expect(BarColor.fromName(v.name), v);
    }
  });

  test('none 이 기본값(첫 번째 값)이다', () {
    expect(BarColor.values.first, BarColor.none);
  });
}
