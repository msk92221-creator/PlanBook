import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/sync/pkce.dart';

void main() {
  group('generateCodeVerifier', () {
    test('기본 길이는 RFC 최소값(43)', () {
      expect(generateCodeVerifier().length, kMinVerifierLength);
    });

    test('RFC 허용 문자만 쓴다', () {
      final v = generateCodeVerifier(length: 128, random: Random(1));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    });

    test('길이가 범위를 벗어나면 거부한다', () {
      expect(() => generateCodeVerifier(length: 42), throwsArgumentError);
      expect(() => generateCodeVerifier(length: 129), throwsArgumentError);
    });

    test('호출할 때마다 다른 값이 나온다', () {
      final set = {for (var i = 0; i < 50; i++) generateCodeVerifier()};
      expect(set.length, 50, reason: '예측 가능한 verifier 는 PKCE 를 무의미하게 만든다');
    });
  });

  group('codeChallengeS256', () {
    test('BASE64URL(SHA256(verifier)) 이고 패딩이 없다', () {
      const verifier = 'abc123';
      final expected = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      expect(codeChallengeS256(verifier), expected);
      expect(codeChallengeS256(verifier), isNot(contains('=')));
    });

    test('RFC 7636 부록 B 예시와 일치한다', () {
      // RFC 7636 Appendix B 의 공식 테스트 벡터.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(
        codeChallengeS256(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('같은 verifier 는 항상 같은 challenge 를 만든다', () {
      expect(codeChallengeS256('same'), codeChallengeS256('same'));
    });

    test('다른 verifier 는 다른 challenge 를 만든다', () {
      expect(codeChallengeS256('a'), isNot(codeChallengeS256('b')));
    });

    test('URL 에 그대로 넣어도 안전한 문자만 나온다', () {
      for (var i = 0; i < 20; i++) {
        final c = codeChallengeS256(generateCodeVerifier());
        expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(c), isTrue);
      }
    });
  });

  group('generateState', () {
    test('매번 다른 값이 나온다(CSRF 방지용)', () {
      final set = {for (var i = 0; i < 50; i++) generateState()};
      expect(set.length, 50);
    });
  });
}
