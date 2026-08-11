/// OAuth 2.0 PKCE (RFC 7636) 값 생성 — 순수 함수라 테스트 가능하다.
///
/// **왜 PKCE 인가**: 데스크톱/모바일 앱은 client secret 을 안전하게 숨길 수
/// 없다(앱 바이너리에서 뽑아낼 수 있다). 그래서 Microsoft 는 이런 앱을
/// "공용 클라이언트(public client)"로 분류하고, secret 대신 PKCE 로 인가
/// 코드가 가로채이는 것을 막는다. 이 앱에는 secret 을 넣지 않는다.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// code_verifier 에 쓸 수 있는 문자 집합(RFC 7636 unreserved).
const String _kVerifierChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// RFC 7636 이 요구하는 code_verifier 길이 범위.
const int kMinVerifierLength = 43;
const int kMaxVerifierLength = 128;

/// code_verifier 를 만든다. 기본 길이 [kMinVerifierLength].
///
/// [random] 은 테스트에서 고정 시드를 넣기 위한 주입점이다. 실제 실행에서는
/// 반드시 [Random.secure] 가 쓰이도록 기본값을 그렇게 뒀다 — 예측 가능한
/// verifier 는 PKCE 를 무의미하게 만든다.
String generateCodeVerifier({int length = kMinVerifierLength, Random? random}) {
  if (length < kMinVerifierLength || length > kMaxVerifierLength) {
    throw ArgumentError.value(
      length,
      'length',
      'code_verifier 길이는 $kMinVerifierLength~$kMaxVerifierLength 여야 한다',
    );
  }
  final rng = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.write(_kVerifierChars[rng.nextInt(_kVerifierChars.length)]);
  }
  return buf.toString();
}

/// S256 방식 code_challenge = BASE64URL(SHA256(verifier)), 패딩(`=`) 없음.
String codeChallengeS256(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// CSRF 방지용 state 값. 인가 요청에 넣고, 돌아온 값과 같은지 반드시 확인한다.
String generateState({Random? random}) =>
    generateCodeVerifier(length: kMinVerifierLength, random: random);
