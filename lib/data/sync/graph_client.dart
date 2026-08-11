/// Microsoft Graph 를 통한 OneDrive 파일 읽기/쓰기.
///
/// **앱 전용 폴더(App Folder)만 쓴다** — `/me/drive/special/approot`.
/// 사용자의 OneDrive 전체가 아니라 `OneDrive/앱/PlanBook/` 안에만 접근하므로
/// 필요한 권한이 `Files.ReadWrite.AppFolder` 하나로 끝나고, 동의 화면에서
/// "내 모든 파일" 을 요구하지 않는다. 폴더를 사용자가 고를 필요도 없어
/// Windows/Android 양쪽에서 동작이 완전히 같아진다.
///
/// **eTag 를 항상 함께 다룬다**: 동기화 판단([decideSyncAction])이 "내가
/// 마지막으로 본 뒤 원격이 바뀌었는가" 를 eTag 비교로 하기 때문이다.
/// 업로드할 때도 eTag 를 If-Match 로 보내 마지막 순간에 끼어든 다른 기기의
/// 쓰기를 덮어쓰지 않는다(412 를 받으면 충돌로 처리).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// 원격 파일의 메타데이터.
class RemoteFileInfo {
  /// 변경 감지에 쓰는 태그. 내용이 바뀌면 값이 달라진다.
  final String eTag;

  /// 마지막 수정 시각(표시용). 파싱 실패 시 null.
  final DateTime? lastModified;

  const RemoteFileInfo({required this.eTag, this.lastModified});
}

/// 내려받은 내용 + 그 시점의 eTag.
class RemoteContent {
  final String body;
  final String eTag;
  const RemoteContent({required this.body, required this.eTag});
}

/// Graph 호출이 실패했을 때 던진다. [statusCode] 로 호출부가 분기한다.
class GraphException implements Exception {
  final int? statusCode;
  final String message;
  const GraphException(this.message, {this.statusCode});

  /// 토큰이 만료/무효 — 갱신하거나 다시 로그인해야 한다.
  bool get isUnauthorized => statusCode == 401;

  /// If-Match 불일치 — 내가 알던 사이에 원격이 바뀌었다(충돌).
  bool get isConflict => statusCode == 412 || statusCode == 409;

  @override
  String toString() => 'GraphException($statusCode): $message';
}

class GraphClient {
  /// 액세스 토큰을 돌려주는 콜백. 매 호출마다 물어보므로, 갱신 로직은
  /// 이 콜백 뒤(=인증 계층)에 숨기고 여기서는 신경 쓰지 않는다.
  final Future<String> Function() accessToken;

  final http.Client _http;

  /// 앱 폴더 안에 쓸 파일 이름. 로컬 저장 파일과 같은 포맷/같은 이름이다
  /// (별도 동기화 전용 포맷을 만들지 않는다는 기존 원칙 그대로).
  final String fileName;

  GraphClient({
    required this.accessToken,
    http.Client? httpClient,
    this.fileName = 'plan_store.json',
  }) : _http = httpClient ?? http.Client();

  static const String _base = 'https://graph.microsoft.com/v1.0';

  Uri get _metaUri => Uri.parse('$_base/me/drive/special/approot:/$fileName');
  Uri get _contentUri =>
      Uri.parse('$_base/me/drive/special/approot:/$fileName:/content');

  Future<Map<String, String>> _headers([Map<String, String>? extra]) async {
    final token = await accessToken();
    return {
      'Authorization': 'Bearer $token',
      ...?extra,
    };
  }

  /// 원격 파일의 메타데이터. **파일이 아직 없으면 null**(예외 아님) —
  /// "한 번도 올린 적 없음" 은 정상 상태이지 오류가 아니다.
  Future<RemoteFileInfo?> fetchInfo() async {
    final res = await _http.get(_metaUri, headers: await _headers());
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw GraphException('메타데이터 조회 실패: ${res.body}',
          statusCode: res.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, Object?>) {
      throw const GraphException('메타데이터 형식이 올바르지 않습니다.');
    }
    final tag = (decoded['eTag'] ?? decoded['cTag'])?.toString();
    if (tag == null) {
      throw const GraphException('응답에 eTag 가 없습니다.');
    }
    return RemoteFileInfo(
      eTag: tag,
      lastModified:
          DateTime.tryParse(decoded['lastModifiedDateTime']?.toString() ?? ''),
    );
  }

  /// 원격 파일 내용을 내려받는다. 파일이 없으면 null.
  Future<RemoteContent?> download() async {
    final res = await _http.get(_contentUri, headers: await _headers());
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw GraphException('다운로드 실패: ${res.body}', statusCode: res.statusCode);
    }
    // 내용 응답의 eTag 헤더는 따옴표로 감싸여 오기도 한다 — 비교 일관성을 위해
    // 메타데이터에서 다시 읽는다(항상 같은 출처의 값끼리만 비교한다).
    final info = await fetchInfo();
    if (info == null) {
      throw const GraphException('다운로드 직후 파일이 사라졌습니다.');
    }
    return RemoteContent(body: utf8.decode(res.bodyBytes), eTag: info.eTag);
  }

  /// [body] 를 올리고 새 eTag 를 돌려준다.
  ///
  /// [ifMatchETag] 를 주면 원격이 그 eTag 일 때만 쓴다. 그 사이 다른 기기가
  /// 올렸다면 412 가 오고 [GraphException.isConflict] 로 구분된다 —
  /// 이때 조용히 덮어쓰지 않고 호출부가 충돌 처리를 해야 한다.
  Future<String> upload(String body, {String? ifMatchETag}) async {
    final res = await _http.put(
      _contentUri,
      // ifMatchETag 가 null 이면 If-Match 자체를 보내지 않는다(최초 업로드).
      headers: await _headers({
        'Content-Type': 'application/json',
        ...?(ifMatchETag == null ? null : {'If-Match': ifMatchETag}),
      }),
      body: utf8.encode(body),
    );
    if (res.statusCode == 412 || res.statusCode == 409) {
      throw GraphException('업로드 중 원격이 먼저 바뀌었습니다.',
          statusCode: res.statusCode);
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GraphException('업로드 실패: ${res.body}', statusCode: res.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map<String, Object?>) {
      final tag = (decoded['eTag'] ?? decoded['cTag'])?.toString();
      if (tag != null) return tag;
    }
    // 응답에 eTag 가 없으면 메타데이터로 한 번 더 확인한다.
    final info = await fetchInfo();
    if (info == null) {
      throw const GraphException('업로드 후 파일을 찾을 수 없습니다.');
    }
    return info.eTag;
  }

  void close() => _http.close();
}
