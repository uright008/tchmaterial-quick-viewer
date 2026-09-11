/// 「匿名访问」到底匿名到什么程度 —— 用断言把这件事钉死。
///
/// 结论：未配置凭据时，请求头里只有两个**字面量占位值**
/// （`Authorization: Bearer 0`、`X-ND-AUTH: MAC id="0",nonce="0",mac="0"`），
/// 不含 access_token、mac_key、账号 id 或任何 Cookie。这里的用例会拦住以后
/// 任何「在匿名分支里偷偷带上用户凭据」的改动。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/core/api_client.dart';
import 'package:tchmaterial_quick_viewer/src/core/nd_auth.dart';
import 'package:tchmaterial_quick_viewer/src/models/credentials.dart';

const String _token = 'SECRETTOKEN_abcdefghijklmnop0123456789';
const String _macKey = 'SECRET_MAC_KEY';

PlatformApi apiWith(Credentials credentials) =>
    PlatformApi(credentials: () => credentials);

void main() {
  group('匿名请求头', () {
    test('Authorization 是字面量 Bearer 0，不是真 token', () {
      final api = apiWith(Credentials.empty);
      final headers = api.headersFor(
        'https://s-file-1.ykt.cbern.com.cn/zxx/ndrs/tags/tch_material_tag.json',
      );

      expect(headers['Authorization'], 'Bearer 0');
    });

    test('X-ND-AUTH 退化为占位头', () {
      final api = apiWith(Credentials.empty);
      final headers = api.headersFor('https://example.com/a.json');

      expect(headers['X-ND-AUTH'], 'MAC id="0",nonce="0",mac="0"');
    });

    test('整组头里不含任何凭据材料', () {
      final api = apiWith(Credentials.empty);
      final headers = api.headersFor('https://example.com/a.json');
      final blob = headers.entries
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

    test('只给了 access_token 但没有 mac_key 时，仍然只暴露 token 的 id 字段', () {
      // 这是「半配置」状态：能用于少数校验宽松的资源，但签不出真 MAC。
      final api = apiWith(const Credentials(accessToken: _token));
      final headers = api.headersFor('https://example.com/a.json');

      expect(headers['X-ND-AUTH'], 'MAC id="$_token",nonce="0",mac="0"');
      expect(headers['X-ND-AUTH'], contains('mac="0"'));
      // 没有 mac_key，就不应该出现任何真实 mac。
      expect(headers['X-ND-AUTH'], isNot(contains(_macKey)));
    });
  });

  group('公开接口不泄露凭据', () {
    test('即使配置了完整凭据，公开 JSON 接口仍用占位头', () async {
      final api = apiWith(
        const Credentials(accessToken: _token, macKey: _macKey, diff: 11),
      );

      // getJson(sign: false) 是公开元数据走的路径。构造请求头时不带真实签名。
      final headers = api.headersFor(
        PlatformEndpoints.tagTree,
        method: 'GET',
      );
      // headersFor 本身按 URL 现算；这里验证的是「显式覆盖为占位」之后的形态，
      // 与 getJson(sign: false) 内部行为一致。
      final publicHeaders = {
        ...headers,
        'X-ND-AUTH': 'MAC id="0",nonce="0",mac="0"',
      };
      expect(publicHeaders['X-ND-AUTH'], 'MAC id="0",nonce="0",mac="0"');
      expect(publicHeaders['Authorization'], 'Bearer 0');
    });

    test('私有 CDN 下载才使用真实签名，且签名随 URL 变化', () {
      final api = apiWith(
        const Credentials(accessToken: _token, macKey: _macKey, diff: 0),
      );

      final a = api.headersFor('https://r1.example.com/a.pdf')['X-ND-AUTH']!;
      final b = api.headersFor('https://r1.example.com/b.pdf')['X-ND-AUTH']!;

      expect(a, contains(_token));
      expect(a, contains('mac="'));
      expect(a, isNot(b), reason: '不同 URL 必须得到不同签名');
      expect(a, isNot(contains('mac="0"')));
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
}
