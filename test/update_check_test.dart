import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planbook/data/update_check.dart';

void main() {
  group('isNewerVersion', () {
    test('major 가 더 크면 최신', () {
      expect(isNewerVersion('1.0.0', '2.0.0'), isTrue);
    });
    test('minor 가 더 크면 최신', () {
      expect(isNewerVersion('1.0.0', '1.1.0'), isTrue);
    });
    test('patch 가 더 크면 최신', () {
      expect(isNewerVersion('1.0.0', '1.0.1'), isTrue);
    });
    test('같은 버전이면 최신이 아니다', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });
    test('더 낮은 버전이면 최신이 아니다', () {
      expect(isNewerVersion('1.2.0', '1.1.9'), isFalse);
    });
    test('태그 앞의 v 는 무시한다', () {
      expect(isNewerVersion('1.0.0', 'v1.0.1'), isTrue);
    });
    test('pubspec 의 +buildNumber 는 비교에서 제외한다', () {
      expect(isNewerVersion('1.0.0+5', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0+5', '1.0.1'), isTrue);
    });
    test('파싱할 수 없는 형식이면 false(오탐 방지)', () {
      expect(isNewerVersion('1.0.0', 'not-a-version'), isFalse);
      expect(isNewerVersion('garbage', '1.0.0'), isFalse);
    });
  });

  group('pickAssetForPlatform', () {
    const release = ReleaseInfo(
      tagName: 'v1.0.0',
      htmlUrl: 'https://github.com/x/y/releases/tag/v1.0.0',
      assets: [
        ReleaseAsset(name: 'planbook-windows.zip', downloadUrl: 'https://x/planbook-windows.zip'),
        ReleaseAsset(name: 'planbook-android.apk', downloadUrl: 'https://x/planbook-android.apk'),
      ],
    );

    test('안드로이드는 .apk 자산을 고른다', () {
      final a = pickAssetForPlatform(release, isAndroid: true);
      expect(a?.name, 'planbook-android.apk');
    });

    test('윈도우는 .zip 자산을 고른다', () {
      final a = pickAssetForPlatform(release, isAndroid: false);
      expect(a?.name, 'planbook-windows.zip');
    });

    test('맞는 자산이 없으면 null', () {
      const empty = ReleaseInfo(tagName: 'v1.0.0', htmlUrl: 'https://x', assets: []);
      expect(pickAssetForPlatform(empty, isAndroid: true), isNull);
    });
  });

  group('fetchLatestRelease', () {
    test('정상 응답을 파싱한다', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            'https://api.github.com/repos/o/r/releases/latest');
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.2.0',
            'html_url': 'https://github.com/o/r/releases/tag/v1.2.0',
            'assets': [
              {
                'name': 'app-android.apk',
                'browser_download_url': 'https://example.com/app-android.apk',
              },
            ],
          }),
          200,
        );
      });

      final release =
          await fetchLatestRelease(owner: 'o', repo: 'r', client: client);
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.0');
      expect(release.assets.single.name, 'app-android.apk');
    });

    test('404(릴리스 없음)면 null', () async {
      final client = MockClient((request) async => http.Response('', 404));
      final release =
          await fetchLatestRelease(owner: 'o', repo: 'r', client: client);
      expect(release, isNull);
    });

    test('네트워크 예외가 나도 null(크래시 없음)', () async {
      final client = MockClient((request) async => throw Exception('no network'));
      final release =
          await fetchLatestRelease(owner: 'o', repo: 'r', client: client);
      expect(release, isNull);
    });

    test('JSON 형식이 예상과 다르면 null', () async {
      final client = MockClient((request) async => http.Response('[]', 200));
      final release =
          await fetchLatestRelease(owner: 'o', repo: 'r', client: client);
      expect(release, isNull);
    });
  });
}
