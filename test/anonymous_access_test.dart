/// 「匿名访问」到底匿名到什么程度 —— 用真实请求路径把它钉死。
///
/// 未配置凭据时，请求头里只有两个**字面量占位值**
/// （`Authorization: Bearer 0`、`X-ND-AUTH: MAC id="0",nonce="0",mac="0"`），
/// 不含 access_token、mac_key、账号 id 或任何 Cookie。
///
/// 这组用例刻意**拦截真实发出的 HTTP 请求**（`MockClient` 注入 `PlatformApi`），
/// 而不是自己拼一个 map 再断言 —— 后者只能证明测试代码写了什么，证明不了
/// `getJson` / `sendGet` 实际发出去的是什么。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tchmaterial_quick_viewer/src/core/api_client.dart';
import 'package:tchmaterial_quick_viewer/src/core/nd_auth.dart';
import 'package:tchmaterial_quick_viewer/src/models/credentials.dart';

const String _token = 'SECRETTOKEN_abcdefghijklmnop0123456789';
const String _macKey = 'SECRET_MAC_KEY';

/// 记录被拦截请求的头，并返回一个最小可用的响应。
({PlatformApi api, List<Map<String, String>> sent}) apiWith(
  Credentials credentials, {
  String body = '{"hierarchies":[]}',
}) {
  final sent = <Map<String, String>>[];
  final client = MockClient((request) async {
    sent.add(Map<String, String>.from(request.headers));
    return http.Response(body, 200);
  });
  return (
    api: PlatformApi(credentials: () => credentials, client: client),
    sent: sent,
  );
}

void main() {
  group('匿名请求头（走真实 getJson 路径）', () {
    test('Authorization 是字面量 Bearer 0，不是真 token', () async {
      final h = apiWith(Credentials.empty);
      await h.api.getJson(PlatformEndpoints.tagTree);

      expect(h.sent, hasLength(1));
      expect(h.sent.single['Authorization'], 'Bearer 0');
    });

    test('X-ND-AUTH 退化为占位头', () async {
      final h = apiWith(Credentials.empty);
      await h.api.getJson(PlatformEndpoints.tagTree);

      expect(h.sent.single['X-ND-AUTH'], 'MAC id="0",nonce="0",mac="0"');
    });

    test('整组头里不含任何凭据材料', () async {
      final h = apiWith(Credentials.empty);
      await h.api.getJson(PlatformEndpoints.tagTree);

      final blob = h.sent.single.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n')
          .toLowerCase();

      for (final forbidden in [
        _token.toLowerCase(),
        _macKey.toLowerCase(),
        'cookie',
        'uc_token',
        'access_token',
        'mac_key',
        'x-edu-web-role',
      ]) {
        expect(blob, isNot(contains(forbidden)),
            reason: '匿名请求头里不应出现 $forbidden');
      }
    });
  });

  group('公开接口不泄露凭据（走真实 getJson 路径）', () {
    test('即使配置了完整凭据，公开 JSON 接口仍然只发占位头', () async {
      final h = apiWith(
        const Credentials(accessToken: _token, macKey: _macKey, diff: 11),
      );
      // getJson 默认 sign:false —— 分类树、教材列表、详情都走这条路径。
      await h.api.getJson(PlatformEndpoints.tagTree);

      final headers = h.sent.single;
      expect(headers['X-ND-AUTH'], 'MAC id="0",nonce="0",mac="0"');
      expect(headers['Authorization'], 'Bearer 0');
      final blob = headers.values.join(' ');
      expect(blob, isNot(contains(_token)));
      expect(blob, isNot(contains(_macKey)));
    });

    test('私有 CDN 下载才使用真实签名，且签名随 URL 变化', () async {
      final h = apiWith(
        const Credentials(accessToken: _token, macKey: _macKey, diff: 0),
      );

      await h.api.sendGet('https://r1-ndr-private.example.com/a/b.pdf');
      await h.api.sendGet('https://r1-ndr-private.example.com/a/c.pdf');

      expect(h.sent, hasLength(2));
      final first = h.sent[0]['X-ND-AUTH']!;
      final second = h.sent[1]['X-ND-AUTH']!;

      expect(first, contains(_token));
      expect(first, contains('mac="'));
      expect(first, isNot(contains('mac="0"')));
      expect(first, isNot(second), reason: '不同 URL 必须得到不同签名');
    });

    test('只给 access_token 时不会伪造出真实 mac', () async {
      final h = apiWith(const Credentials(accessToken: _token));
      await h.api.sendGet('https://r1-ndr-private.example.com/a.pdf');

      final auth = h.sent.single['X-ND-AUTH']!;
      expect(auth, 'MAC id="$_token",nonce="0",mac="0"');
      expect(auth, isNot(contains(_macKey)));
    });
  });

  group('公开签名实现与参考项目一致', () {
    test('没有 mac_key 时 buildNdAuth 绝不产生真实 mac', () {
      final header = buildNdAuth(
        url: 'https://r1.example.com/secret.pdf',
        accessToken: _token,
        macKey: null,
      );
      expect(header, 'MAC id="$_token",nonce="0",mac="0"');
    });

    test('空 access_token 时 id 退化为 "0"', () {
      final header = buildNdAuth(
        url: 'https://r1.example.com/a.pdf',
        accessToken: '',
        macKey: _macKey,
      );
      expect(header, startsWith('MAC id="0",nonce="'));
    });
  });

  group('错误文案', () {
    test('未配置凭据时 403 提示先去配凭据，而不是断言凭据失效', () async {
      final sent = <Map<String, String>>[];
      final client = MockClient((request) async {
        sent.add(Map<String, String>.from(request.headers));
        return http.Response('forbidden', 403);
      });
      final api = PlatformApi(
        credentials: () => Credentials.empty,
        client: client,
      );

      await expectLater(
        api.getJson('https://example.com/a.json'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('粘贴登录 Cookie')),
        ),
      );
    });

    test('已配置凭据时 403 说明是平台未开放直链，不误导用户去重贴 Cookie', () async {
      final client = MockClient(
        (request) async => http.Response('forbidden', 403),
      );
      final api = PlatformApi(
        credentials: () =>
            const Credentials(accessToken: _token, macKey: _macKey),
        client: client,
      );

      await expectLater(
        api.getJson('https://example.com/a.json'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('凭据本身有效'))
              .having((e) => e.message, 'message', isNot(contains('重新粘贴'))),
        ),
      );
    });
  });
}
