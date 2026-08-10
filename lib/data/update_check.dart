/// GitHub Releases 기반 업데이트 확인.
///
/// **서버를 새로 두지 않는다** — GitHub Releases API(공개, 인증 불필요)를
/// 그대로 조회한다. 저장소가 public 이어야 릴리스에 첨부된 파일을 별도
/// 인증 없이 바로 내려받을 수 있다(private 저장소는 토큰이 필요해 앱에
/// 토큰을 내장해야 하므로 쓰지 않는다).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  const ReleaseAsset({required this.name, required this.downloadUrl});
}

class ReleaseInfo {
  final String tagName;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
  const ReleaseInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
  });
}

/// GitHub Releases API 에서 최신 릴리스를 가져온다. 실패하면(네트워크 오류,
/// 릴리스 없음, 형식 불일치 등) null — 예외를 던지지 않는다. 업데이트 확인은
/// 부가 기능이라 실패해도 앱 사용 자체에는 지장이 없어야 한다.
Future<ReleaseInfo?> fetchLatestRelease({
  required String owner,
  required String repo,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final uri =
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
    final res = await c
        .get(uri, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, Object?>) return null;

    final tagName = decoded['tag_name']?.toString();
    final htmlUrl = decoded['html_url']?.toString();
    if (tagName == null || htmlUrl == null) return null;

    final assets = <ReleaseAsset>[];
    final assetsRaw = decoded['assets'];
    if (assetsRaw is List) {
      for (final a in assetsRaw) {
        if (a is Map<String, Object?>) {
          final name = a['name']?.toString();
          final url = a['browser_download_url']?.toString();
          if (name != null && url != null) {
            assets.add(ReleaseAsset(name: name, downloadUrl: url));
          }
        }
      }
    }
    return ReleaseInfo(tagName: tagName, htmlUrl: htmlUrl, assets: assets);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// [tagName](예: "v1.2.0"/"1.2.0")이 [currentVersion](예: "1.0.0")보다
/// semver 상 최신인지. 두 값 다 `major.minor.patch` 형태로 파싱 가능해야
/// 하고, 실패하면 false(업데이트 없음으로 안전하게 처리 — 오탐으로 사용자를
/// 불필요하게 재촉하지 않는다).
bool isNewerVersion(String currentVersion, String tagName) {
  List<int>? parse(String v) {
    final trimmed = v.trim();
    final cleaned = trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
    final withoutBuild = cleaned.split('+').first; // pubspec 의 "+buildNumber" 제외.
    final parts = withoutBuild.split('.');
    if (parts.isEmpty) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      nums.add(n);
    }
    return nums;
  }

  final cur = parse(currentVersion);
  final latest = parse(tagName);
  if (cur == null || latest == null) return false;

  final len = cur.length > latest.length ? cur.length : latest.length;
  for (var i = 0; i < len; i++) {
    final c = i < cur.length ? cur[i] : 0;
    final l = i < latest.length ? latest[i] : 0;
    if (l != c) return l > c;
  }
  return false;
}

/// 현재 플랫폼(Windows/Android)에 맞는 릴리스 자산을 고른다. 못 찾으면 null
/// (호출부가 [ReleaseInfo.htmlUrl](릴리스 페이지)로 대체하면 된다).
ReleaseAsset? pickAssetForPlatform(ReleaseInfo release, {required bool isAndroid}) {
  final suffix = isAndroid ? '.apk' : '.zip';
  for (final a in release.assets) {
    if (a.name.toLowerCase().endsWith(suffix)) return a;
  }
  return null;
}
