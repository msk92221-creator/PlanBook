import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planbook/data/sync/onedrive_auth.dart';

/// 메모리에 저장하는 [FlutterSecureStorage] 가짜 구현. [OneDriveAuth.signIn] 의
/// 성공 경로가 _saveTokens 를 거치므로 플랫폼 채널 없이 동작하게 한다.
class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
    required String key,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
    required String key,
    required String? value,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
    required String key,
  }) async =>
      _store.remove(key);
}

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

  group('canceledAuthMessage', () {
    test('데스크톱은 데스크톱 리디렉션 주소를 안내에 포함한다', () {
      final msg = canceledAuthMessage(isMobile: false);
      expect(msg, contains('http://localhost:43823'));
      expect(msg, contains('인증'));
      expect(msg, contains('모바일 및 데스크톱 애플리케이션'));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('모바일은 짧은 취소 메시지만 준다', () {
      final msg = canceledAuthMessage(isMobile: true);
      expect(msg, contains('취소'));
      expect(msg, isNot(contains('http://localhost:43823')));
    });
  });

  group('signIn 예외 처리', () {
    /// CANCELED 를 흉내 내는 주입용 authenticate.
    WebAuthenticate canceledAuth() => ({
          required String url,
          required String callbackUrlScheme,
        }) async {
          throw PlatformException(
            code: 'CANCELED',
            message: 'User canceled',
          );
        };

    test('데스크톱에서 CANCELED 시 실행 가능한 안내로 바꿔 던진다', () async {
      final auth = OneDriveAuth(
        storage: _MemorySecureStorage(),
        authenticate: canceledAuth(),
        isMobileOverride: false,
        clientId: 'test-client-id',
      );

      late final Object caught;
      try {
        await auth.signIn();
        fail('예외가 던져져야 한다');
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<OneDriveAuthException>());
      final msg = caught.toString();
      // 완료 기준 1: 데스크톱 리디렉션 주소가 메시지에 들어 있다.
      expect(msg, contains('http://localhost:43823'));
      // 완료 기준 2: 날것의 PlatformException 문구가 노출되지 않는다.
      expect(msg, isNot(contains('PlatformException')));
      // signIn 이 실제로 canceledAuthMessage 를 쓰는지 확인 —
      // 모바일이면 데스크톱 주소가 빠지므로, 데스크톱 주소가 있다는 것 자체가
      // 그 함수를 탔다는 증거다.
      auth.close();
    });

    test('모바일에서 CANCELED 시 짧은 취소 메시지로 바꾼다', () async {
      final auth = OneDriveAuth(
        storage: _MemorySecureStorage(),
        authenticate: canceledAuth(),
        isMobileOverride: true,
        clientId: 'test-client-id',
      );

      late final Object caught;
      try {
        await auth.signIn();
        fail('예외가 던져져야 한다');
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<OneDriveAuthException>());
      final msg = caught.toString();
      expect(msg, contains('취소'));
      expect(msg, isNot(contains('PlatformException')));
      auth.close();
    });

    test('CANCELED 가 아닌 PlatformException 도 code/message 를 담아 감싼다',
        () async {
      final auth = OneDriveAuth(
        storage: _MemorySecureStorage(),
        authenticate: ({
          required String url,
          required String callbackUrlScheme,
        }) async {
          throw PlatformException(code: 'NETWORK', message: '연결 실패');
        },
        isMobileOverride: false,
        clientId: 'test-client-id',
      );

      late final Object caught;
      try {
        await auth.signIn();
        fail('예외가 던져져야 한다');
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<OneDriveAuthException>());
      expect(caught.toString(), contains('NETWORK'));
      expect(caught.toString(), contains('연결 실패'));
      auth.close();
    });

    test('성공 경로는 토큰을 저장하고 반환한다(주입 기본값이 동작을 안 바꾼다)',
        () async {
      // 정상 콜백을 반환하는 주입용 authenticate. signIn 이 기본 흐름을
      // 그대로 유지하는지(주입이 동작을 바꾸지 않는지)를 확인한다.
      String? capturedScheme;
      WebAuthenticate okAuth() => ({
            required String url,
            required String callbackUrlScheme,
          }) async {
            capturedScheme = callbackUrlScheme;
            final state =
                Uri.parse(url).queryParameters['state'] ?? '';
            return 'http://localhost:43823/?code=AUTHCODE&state=$state';
          };

      final http.Client tokenClient = MockClient((req) async {
        // 토큰 교환 응답.
        return http.Response(
          jsonEncode({
            'access_token': 'AT',
            'refresh_token': 'RT',
            'expires_in': 3600,
          }),
          200,
        );
      });

      final storage = _MemorySecureStorage();
      final auth = OneDriveAuth(
        storage: storage,
        httpClient: tokenClient,
        authenticate: okAuth(),
        isMobileOverride: false,
        clientId: 'test-client-id',
      );

      final tokens = await auth.signIn();

      // 완료 기준 3: 주입 기본값이 동작을 안 바꾼다 — 데스크톱 경로라면
      // callbackUrlScheme 이 루프백 주소여야 한다.
      expect(capturedScheme, 'http://localhost:43823');
      expect(tokens.accessToken, 'AT');
      expect(tokens.refreshToken, 'RT');
      // 토큰이 저장소에 들어갔다(성공 경로가 끝까지 갔다). toJson 은
      // camelCase 키를 쓴다(parseTokenResponse 와 다르다).
      final saved = await storage.read(key: 'onedrive_tokens');
      expect(saved, isNotNull);
      expect(jsonDecode(saved!)['accessToken'], 'AT');
      auth.close();
    });
  });
}
