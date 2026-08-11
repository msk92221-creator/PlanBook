import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planbook/data/sync/graph_client.dart';

/// 요청을 기록하면서 정해진 응답을 돌려주는 가짜 HTTP 클라이언트.
class _Recorder {
  final List<http.Request> requests = [];

  MockClient client(
      Future<http.Response> Function(http.Request req) handler) {
    return MockClient((req) async {
      requests.add(req);
      return handler(req);
    });
  }
}

http.Response _metaResponse({String eTag = 'e1'}) => http.Response(
      jsonEncode({
        'eTag': eTag,
        'lastModifiedDateTime': '2026-08-11T10:00:00Z',
      }),
      200,
    );

void main() {
  group('fetchInfo', () {
    test('파일이 없으면(404) 예외가 아니라 null 을 준다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      expect(await c.fetchInfo(), isNull);
    });

    test('eTag 와 수정시각을 파싱한다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((_) async => _metaResponse(eTag: 'abc')),
      );
      final info = await c.fetchInfo();
      expect(info!.eTag, 'abc');
      expect(info.lastModified, DateTime.utc(2026, 8, 11, 10));
    });

    test('Authorization 헤더에 토큰을 실어 보낸다', () async {
      final rec = _Recorder();
      final c = GraphClient(
        accessToken: () async => 'secret-token',
        httpClient: rec.client((_) async => _metaResponse()),
      );
      await c.fetchInfo();
      expect(rec.requests.single.headers['Authorization'],
          'Bearer secret-token');
    });

    test('앱 전용 폴더(approot) 경로만 건드린다', () async {
      final rec = _Recorder();
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: rec.client((_) async => _metaResponse()),
      );
      await c.fetchInfo();
      expect(rec.requests.single.url.path, contains('special/approot'));
    });

    test('401 이면 isUnauthorized 로 구분되는 예외를 던진다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('nope', 401)),
      );
      await expectLater(
        c.fetchInfo(),
        throwsA(isA<GraphException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });
  });

  group('download', () {
    test('파일이 없으면 null', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      expect(await c.download(), isNull);
    });

    test('본문과 eTag 를 함께 돌려준다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/content')) {
            return http.Response(jsonEncode({'nodes': []}), 200);
          }
          return _metaResponse(eTag: 'v9');
        }),
      );
      final got = await c.download();
      expect(got!.eTag, 'v9');
      expect(jsonDecode(got.body), {'nodes': []});
    });

    test('한글이 깨지지 않는다(UTF-8)', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/content')) {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'nodes': [], 'note': 'PA장비 도입'})),
              200,
            );
          }
          return _metaResponse();
        }),
      );
      final got = await c.download();
      expect(jsonDecode(got!.body)['note'], 'PA장비 도입');
    });
  });

  group('upload', () {
    test('새 eTag 를 돌려준다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'eTag': 'new'}), 200)),
      );
      expect(await c.upload('{}'), 'new');
    });

    test('ifMatchETag 를 주면 If-Match 헤더로 보낸다', () async {
      final rec = _Recorder();
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: rec.client(
            (_) async => http.Response(jsonEncode({'eTag': 'new'}), 200)),
      );
      await c.upload('{}', ifMatchETag: 'old');
      expect(rec.requests.single.headers['If-Match'], 'old');
    });

    test('ifMatchETag 가 없으면 If-Match 를 보내지 않는다(최초 업로드)', () async {
      final rec = _Recorder();
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: rec.client(
            (_) async => http.Response(jsonEncode({'eTag': 'new'}), 201)),
      );
      await c.upload('{}');
      expect(rec.requests.single.headers.containsKey('If-Match'), isFalse);
    });

    test('412 면 충돌로 구분되는 예외를 던진다(조용히 덮어쓰지 않는다)', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((_) async => http.Response('', 412)),
      );
      await expectLater(
        c.upload('{}', ifMatchETag: 'old'),
        throwsA(isA<GraphException>()
            .having((e) => e.isConflict, 'isConflict', isTrue)),
      );
    });

    test('응답에 eTag 가 없으면 메타데이터로 다시 확인한다', () async {
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: MockClient((req) async {
          if (req.method == 'PUT') return http.Response('{}', 200);
          return _metaResponse(eTag: 'from-meta');
        }),
      );
      expect(await c.upload('{}'), 'from-meta');
    });

    test('한글 본문을 UTF-8 바이트로 올린다', () async {
      final rec = _Recorder();
      final c = GraphClient(
        accessToken: () async => 'tok',
        httpClient: rec.client(
            (_) async => http.Response(jsonEncode({'eTag': 'x'}), 200)),
      );
      await c.upload(jsonEncode({'note': '착수회의'}));
      final sent = utf8.decode(rec.requests.single.bodyBytes);
      expect(jsonDecode(sent)['note'], '착수회의');
    });
  });
}
