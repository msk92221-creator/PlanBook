import 'package:flutter_test/flutter_test.dart';
import 'package:planbook/data/sync/onedrive_auth.dart';

void main() {
  group('플랫폼별 리디렉션 주소', () {
    test('모바일은 사용자 지정 스킴을 쓴다', () {
      expect(redirectUriFor(isMobile: true), 'planbook://auth');
      expect(callbackSchemeFor(isMobile: true), 'planbook');
    });

    test('데스크톱은 루프백 주소를 쓴다 — 커스텀 스킴은 데스크톱에서 거부된다', () {
      expect(redirectUriFor(isMobile: false), 'http://localhost:43823');
      // flutter_web_auth_2 데스크톱 구현은 callbackUrlScheme 이
      // http://localhost:{port} 형태가 아니면 ArgumentError 를 던진다.
      final scheme = Uri.parse(callbackSchemeFor(isMobile: false));
      expect(scheme.scheme, 'http');
      expect(scheme.host, 'localhost');
      expect(scheme.hasPort, isTrue);
    });

    test('두 리디렉션 주소는 서로 다르다(둘 다 Azure 에 등록해야 한다)', () {
      expect(redirectUriFor(isMobile: true),
          isNot(redirectUriFor(isMobile: false)));
    });
  });

  group('buildAuthorizationUrl', () {
    Uri build({String redirectUri = 'planbook://auth'}) =>
        buildAuthorizationUrl(
          clientId: 'client-1',
          codeChallenge: 'challenge-1',
          state: 'state-1',
          redirectUri: redirectUri,
        );

    test('Microsoft 인가 엔드포인트를 가리킨다', () {
      final u = build();
      expect(u.host, 'login.microsoftonline.com');
      expect(u.path, contains('/oauth2/v2.0/authorize'));
    });

    test('PKCE S256 파라미터가 들어간다(secret 대신 쓰는 값)', () {
      final q = build().queryParameters;
      expect(q['code_challenge'], 'challenge-1');
      expect(q['code_challenge_method'], 'S256');
    });

    test('client_secret 은 절대 들어가지 않는다', () {
      expect(build().queryParameters.containsKey('client_secret'), isFalse);
    });

    test('앱 폴더 권한과 offline_access 만 요청한다', () {
      final scope = build().queryParameters['scope']!;
      expect(scope, contains('Files.ReadWrite.AppFolder'));
      expect(scope, contains('offline_access'));
      expect(scope, isNot(contains('Files.ReadWrite.All')),
          reason: '사용자의 OneDrive 전체 권한을 요구해서는 안 된다');
    });

    test('플랫폼별 redirect_uri 가 그대로 실린다', () {
      expect(build(redirectUri: 'http://localhost:43823')
          .queryParameters['redirect_uri'], 'http://localhost:43823');
    });
  });

  group('extractAuthorizationCode', () {
    test('정상 콜백에서 코드를 꺼낸다', () {
      expect(
        extractAuthorizationCode('planbook://auth?code=abc&state=s1', 's1'),
        'abc',
      );
    });

    test('state 가 다르면 거부한다(CSRF 방어)', () {
      expect(
        () => extractAuthorizationCode(
            'planbook://auth?code=abc&state=attacker', 's1'),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('사용자가 취소하면(error) 사유를 담아 던진다', () {
      expect(
        () => extractAuthorizationCode(
            'planbook://auth?error=access_denied&error_description=거부됨', 's1'),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('코드가 없으면 던진다', () {
      expect(
        () => extractAuthorizationCode('planbook://auth?state=s1', 's1'),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('루프백 콜백도 똑같이 처리된다(데스크톱)', () {
      expect(
        extractAuthorizationCode(
            'http://localhost:43823/?code=xyz&state=s2', 's2'),
        'xyz',
      );
    });
  });

  group('parseTokenResponse', () {
    test('토큰과 만료 시각을 계산한다', () {
      final t = parseTokenResponse(
        {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600},
        now: DateTime.utc(2026, 8, 12, 0, 0, 0),
      );
      expect(t.accessToken, 'a');
      expect(t.refreshToken, 'r');
      expect(t.expiresAt, DateTime.utc(2026, 8, 12, 1, 0, 0));
    });

    test('갱신 응답에 refresh_token 이 없으면 기존 것을 유지한다', () {
      final t = parseTokenResponse(
        {'access_token': 'a2', 'expires_in': 3600},
        previousRefreshToken: 'old-refresh',
      );
      expect(t.refreshToken, 'old-refresh',
          reason: '없다고 지우면 다음 갱신에서 재로그인을 요구하게 된다');
    });

    test('access_token 이 없으면 오류 설명을 담아 던진다', () {
      expect(
        () => parseTokenResponse(
            {'error': 'invalid_grant', 'error_description': '만료됨'}),
        throwsA(isA<OneDriveAuthException>()),
      );
    });

    test('refresh_token 이 아예 없으면 던진다', () {
      expect(
        () => parseTokenResponse({'access_token': 'a', 'expires_in': 60}),
        throwsA(isA<OneDriveAuthException>()),
      );
    });
  });

  group('OneDriveTokens 만료 판정', () {
    test('만료 시각이 지났으면 만료로 본다', () {
      final t = OneDriveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(t.isExpired(), isTrue);
    });

    test('아직 여유가 많으면 유효하다', () {
      final t = OneDriveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      expect(t.isExpired(), isFalse);
    });

    test('만료 직전(여유 시간 이내)이면 미리 만료로 처리한다', () {
      final t = OneDriveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      );
      expect(t.isExpired(), isTrue,
          reason: '요청 도중 만료돼 401 이 나는 것을 피하려고 조금 일찍 갱신한다');
    });

    test('JSON 라운드트립으로 값이 보존된다', () {
      final t = OneDriveTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2026, 9, 1),
      );
      final back = OneDriveTokens.fromJson(t.toJson())!;
      expect(back.accessToken, 'a');
      expect(back.refreshToken, 'r');
      expect(back.expiresAt, DateTime.utc(2026, 9, 1));
    });

    test('저장값이 깨져 있으면 null — 앱이 죽지 않고 로그아웃 상태로 시작한다', () {
      expect(OneDriveTokens.fromJson({'accessToken': 'a'}), isNull);
      expect(OneDriveTokens.fromJson({}), isNull);
    });
  });

  test('Client ID 가 설정되어 있다', () {
    expect(isOneDriveConfigured, isTrue);
  });
}
