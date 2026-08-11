/// OneDrive(Microsoft) 로그인 — 인가 코드 + PKCE 흐름.
///
/// client secret 을 쓰지 않는다([pkce.dart] 참고). 토큰은
/// flutter_secure_storage 에 넣는다(Android=EncryptedSharedPreferences,
/// Windows=DPAPI) — 평문 파일에 refresh token 을 두면 그 파일 하나로 계정
/// 접근이 뚫린다.
///
/// **[kOneDriveClientId] 를 채워야 동작한다.** 값이 비어 있으면 로그인을
/// 시도하지 않고 [OneDriveAuthException] 을 던져, UI 가 "설정이 필요합니다"
/// 를 안내할 수 있게 한다(빈 값으로 Microsoft 에 요청을 보내 의미를 알 수 없는
/// 오류 화면을 띄우지 않는다).
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'pkce.dart';

/// Azure 포털에서 앱을 등록하면 나오는 "애플리케이션(클라이언트) ID".
///
/// 빌드할 때 `--dart-define=ONEDRIVE_CLIENT_ID=<값>` 으로 넣을 수도 있고,
/// 아래 기본값에 직접 적어도 된다. 비밀 값이 아니다(공용 클라이언트 ID 는
/// 공개돼도 안전하며, 그래서 PKCE 를 쓴다).
const String kOneDriveClientId = String.fromEnvironment(
  'ONEDRIVE_CLIENT_ID',
  defaultValue: '872ec0ef-8aef-4088-94ea-af2ba526bb3c',
);

/// 설정이 끝났는지. false 면 UI 는 동기화 기능을 잠그고 안내만 띄운다.
bool get isOneDriveConfigured => kOneDriveClientId.isNotEmpty;

/// **리디렉션 방식은 플랫폼마다 다르다.**
///
/// - Android: 사용자 지정 스킴(`planbook://auth`). 매니페스트 intent-filter 가
///   받는다.
/// - Windows/Linux: flutter_web_auth_2 의 데스크톱 구현은 127.0.0.1 에 임시
///   HTTP 서버를 띄워 콜백을 받는 방식이라, 콜백이 **반드시**
///   `http://localhost:{포트}` 여야 한다(커스텀 스킴을 주면 ArgumentError 를
///   던진다). 그래서 데스크톱은 루프백 주소를 쓴다.
///
/// 두 주소 **모두** Azure 앱 등록의 리디렉션 URI 에 들어가 있어야 한다.
const String kMobileRedirectScheme = 'planbook';
const String kMobileRedirectUri = '$kMobileRedirectScheme://auth';

/// 데스크톱 루프백 포트. Azure 에 등록한 값과 반드시 같아야 한다
/// (포트를 매번 바꾸면 등록된 URI 와 달라져 로그인이 거부된다).
const int kDesktopLoopbackPort = 43823;
const String kDesktopRedirectUri = 'http://localhost:$kDesktopLoopbackPort';

/// 인가 요청에 넣을 redirect_uri. [isMobile] 은 테스트에서 양쪽을 다 검증하기
/// 위한 주입점이다.
String redirectUriFor({required bool isMobile}) =>
    isMobile ? kMobileRedirectUri : kDesktopRedirectUri;

/// [FlutterWebAuth2.authenticate] 에 넘길 callbackUrlScheme.
/// 데스크톱에서는 스킴이 아니라 루프백 주소 전체를 넘겨야 한다.
String callbackSchemeFor({required bool isMobile}) =>
    isMobile ? kMobileRedirectScheme : kDesktopRedirectUri;

/// 현재 플랫폼이 사용자 지정 스킴 방식인지(Android/iOS).
bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

/// 요청하는 권한.
/// - `Files.ReadWrite.AppFolder` : **앱 전용 폴더만**. 사용자의 다른 파일은 못 본다.
/// - `offline_access` : refresh token(재로그인 없이 갱신)용.
const List<String> kScopes = [
  'Files.ReadWrite.AppFolder',
  'offline_access',
];

const String _authorizeEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
const String _tokenEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/token';

class OneDriveAuthException implements Exception {
  final String message;
  const OneDriveAuthException(this.message);
  @override
  String toString() => message;
}

/// 저장되는 토큰 묶음.
class OneDriveTokens {
  final String accessToken;
  final String refreshToken;

  /// 액세스 토큰 만료 시각(UTC).
  final DateTime expiresAt;

  const OneDriveTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// 만료 [skew] 이내면 만료된 것으로 본다 — 요청 도중 만료돼 401 이 나는 것을
  /// 피하려고 조금 일찍 갱신한다.
  bool isExpired({Duration skew = const Duration(minutes: 2)}) =>
      DateTime.now().toUtc().add(skew).isAfter(expiresAt);

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  /// 형식이 깨졌으면 null(예외 X) — 저장소가 손상돼도 앱이 죽지 않고
  /// "로그아웃 상태" 로 시작하면 된다.
  static OneDriveTokens? fromJson(Map<String, Object?> json) {
    final a = json['accessToken']?.toString();
    final r = json['refreshToken']?.toString();
    final e = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (a == null || a.isEmpty || r == null || r.isEmpty || e == null) {
      return null;
    }
    return OneDriveTokens(accessToken: a, refreshToken: r, expiresAt: e);
  }
}

/// 토큰 응답(JSON)을 [OneDriveTokens] 로. 순수 함수 — 테스트 가능하다.
///
/// [previousRefreshToken] 은 갱신 응답에 refresh_token 이 빠져 있을 때 쓴다
/// (Microsoft 는 회전시키지 않으면 생략한다 — 이때 기존 것을 계속 써야 한다.
/// 없다고 지워버리면 다음 갱신에서 재로그인을 요구하게 된다).
OneDriveTokens parseTokenResponse(
  Map<String, Object?> json, {
  String? previousRefreshToken,
  DateTime? now,
}) {
  final access = json['access_token']?.toString();
  if (access == null || access.isEmpty) {
    final err = json['error_description'] ?? json['error'] ?? '알 수 없는 오류';
    throw OneDriveAuthException('토큰 응답에 access_token 이 없습니다: $err');
  }
  final refresh = json['refresh_token']?.toString() ?? previousRefreshToken;
  if (refresh == null || refresh.isEmpty) {
    throw const OneDriveAuthException('refresh_token 을 받지 못했습니다.');
  }
  final rawExpires = json['expires_in'];
  final seconds = rawExpires is num
      ? rawExpires.toInt()
      : int.tryParse(rawExpires?.toString() ?? '') ?? 3600;
  final base = (now ?? DateTime.now()).toUtc();
  return OneDriveTokens(
    accessToken: access,
    refreshToken: refresh,
    expiresAt: base.add(Duration(seconds: seconds)),
  );
}

/// 인가 URL 을 만든다. 순수 함수 — 테스트 가능하다.
Uri buildAuthorizationUrl({
  required String clientId,
  required String codeChallenge,
  required String state,
  required String redirectUri,
  List<String> scopes = kScopes,
}) =>
    Uri.parse(_authorizeEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'response_mode': 'query',
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

/// 콜백 URL 에서 인가 코드를 꺼낸다. [expectedState] 와 다르면 거부한다.
///
/// state 검증을 건너뛰면 공격자가 만든 콜백을 그대로 받아들일 수 있다(CSRF).
String extractAuthorizationCode(String callbackUrl, String expectedState) {
  final uri = Uri.parse(callbackUrl);
  final error = uri.queryParameters['error'];
  if (error != null) {
    final desc = uri.queryParameters['error_description'] ?? error;
    throw OneDriveAuthException('로그인이 거부되었습니다: $desc');
  }
  final gotState = uri.queryParameters['state'];
  if (gotState != expectedState) {
    throw const OneDriveAuthException('로그인 응답의 state 가 일치하지 않습니다.');
  }
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw const OneDriveAuthException('로그인 응답에 인가 코드가 없습니다.');
  }
  return code;
}

/// 로그인 상태와 토큰 갱신을 관리한다.
class OneDriveAuth {
  final FlutterSecureStorage _storage;
  final http.Client _http;
  final String clientId;

  static const String _storageKey = 'onedrive_tokens';

  OneDriveAuth({
    FlutterSecureStorage? storage,
    http.Client? httpClient,
    this.clientId = kOneDriveClientId,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  OneDriveTokens? _cached;

  /// 저장된 토큰을 읽는다. 없거나 손상됐으면 null.
  Future<OneDriveTokens?> loadTokens() async {
    if (_cached != null) return _cached;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return _cached = OneDriveTokens.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTokens(OneDriveTokens tokens) async {
    _cached = tokens;
    await _storage.write(key: _storageKey, value: jsonEncode(tokens.toJson()));
  }

  /// 로그인되어 있는지.
  Future<bool> get isSignedIn async => (await loadTokens()) != null;

  /// 로그아웃 — 저장된 토큰을 지운다.
  Future<void> signOut() async {
    _cached = null;
    await _storage.delete(key: _storageKey);
  }

  void _requireConfigured() {
    if (clientId.isEmpty) {
      throw const OneDriveAuthException(
        'OneDrive 클라이언트 ID 가 설정되지 않았습니다. '
        'Azure 앱 등록 후 ONEDRIVE_CLIENT_ID 를 지정해야 동기화를 쓸 수 있습니다.',
      );
    }
  }

  /// 브라우저를 띄워 로그인시키고 토큰을 저장한다.
  Future<OneDriveTokens> signIn() async {
    _requireConfigured();
    final verifier = generateCodeVerifier();
    final state = generateState();
    final isMobile = _isMobilePlatform;
    final redirectUri = redirectUriFor(isMobile: isMobile);
    final url = buildAuthorizationUrl(
      clientId: clientId,
      codeChallenge: codeChallengeS256(verifier),
      state: state,
      redirectUri: redirectUri,
    );

    final result = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: callbackSchemeFor(isMobile: isMobile),
    );
    final code = extractAuthorizationCode(result, state);

    final res = await _http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
        'scope': kScopes.join(' '),
      },
    );
    final tokens = parseTokenResponse(_decode(res));
    await _saveTokens(tokens);
    return tokens;
  }

  /// 유효한 액세스 토큰을 준다. 만료됐으면 조용히 갱신하고, 갱신도 실패하면
  /// [OneDriveAuthException] — 이때 UI 는 재로그인을 안내해야 한다.
  Future<String> accessToken() async {
    _requireConfigured();
    final tokens = await loadTokens();
    if (tokens == null) {
      throw const OneDriveAuthException('OneDrive 에 로그인되어 있지 않습니다.');
    }
    if (!tokens.isExpired()) return tokens.accessToken;

    final res = await _http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': tokens.refreshToken,
        'redirect_uri': redirectUriFor(isMobile: _isMobilePlatform),
        'scope': kScopes.join(' '),
      },
    );
    final refreshed = parseTokenResponse(
      _decode(res),
      previousRefreshToken: tokens.refreshToken,
    );
    await _saveTokens(refreshed);
    return refreshed.accessToken;
  }

  Map<String, Object?> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // 아래에서 공통 처리.
    }
    throw OneDriveAuthException(
        '로그인 서버 응답을 해석할 수 없습니다 (HTTP ${res.statusCode}).');
  }

  void close() => _http.close();
}
