/// 凭据解析测试。
///
/// 覆盖平台真实存在的三种粘贴形式，尤其是浏览器里复制出来的整条 Cookie。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/models/credentials.dart';

/// 构造与平台 `ND_UC_AUTH-*&token` 结构一致的 Cookie 串。
String cookieWith(Map<String, dynamic> payload) {
  final encoded = base64.encode(utf8.encode(jsonEncode(payload)));
  return 'sf=1789145706747; '
      'UC_TOKEN-11111111-2222-3333-4444-555555555555-ncet-xedu=$encoded; '
      'X-EDU-WEB-ROLE=452716404133:STUDENT';
}

void main() {
  final token = List.filled(112, 'A').join();
  // 全部为合成的假值：测试只需要格式正确，绝不能把真实凭据写进仓库。
  const macKey = 'TESTMACKEY01';

  group('parseCredentials', () {
    test('空文本表示清除凭据', () {
      expect(parseCredentials('').isEmpty, isTrue);
      expect(parseCredentials('   ').isEmpty, isTrue);
    });

    test('解析纯 JSON', () {
      final creds = parseCredentials(
        '{"access_token":"$token","mac_key":"$macKey","diff":11}',
      );
      expect(creds.accessToken, token);
      expect(creds.macKey, macKey);
      expect(creds.diff, 11);
      expect(creds.canSign, isTrue);
    });

    test('解析带一层引号的 JSON（控制台 copy 常见）', () {
      final raw = jsonEncode(
        jsonEncode({'access_token': token, 'mac_key': macKey, 'diff': 11}),
      );
      expect(parseCredentials(raw).accessToken, token);
    });

    test('解析整条 Cookie 串', () {
      final creds = parseCredentials(cookieWith({
        'access_token': token,
        'mac_key': macKey,
        'diff': 11,
        'user_id': '452716404133',
        'expires_at': '2099-09-19T00:55:04.984+08:00',
      }));
      expect(creds.accessToken, token);
      expect(creds.macKey, macKey);
      expect(creds.diff, 11);
      expect(creds.userId, '452716404133');
      expect(creds.canSign, isTrue);
      expect(creds.isExpired, isFalse);
    });

    test('Cookie 顺序变化也能取到 token', () {
      final encoded =
          base64.encode(utf8.encode(jsonEncode({'access_token': token})));
      final raw = 'X-EDU-WEB-ROLE=1:STUDENT; UC_TOKEN-abc-def=$encoded; sf=123';
      expect(parseCredentials(raw).accessToken, token);
    });

    test('裸 Base64 token（没有 UC_TOKEN 前缀）', () {
      final encoded = base64.encode(
        utf8.encode(jsonEncode({'access_token': token, 'mac_key': macKey})),
      );
      expect(parseCredentials(encoded).accessToken, token);
    });

    test('只给 access_token 时仍可用，但无法真实签名', () {
      final creds = parseCredentials(token);
      expect(creds.accessToken, token);
      expect(creds.macKey, isNull);
      expect(creds.canSign, isFalse);
    });

    test('过期时间能被识别', () {
      final creds = parseCredentials(cookieWith({
        'access_token': token,
        'mac_key': macKey,
        'expires_at': '2000-01-01T00:00:00.000+08:00',
      }));
      expect(creds.isExpired, isTrue);
    });

    test('无法识别的内容抛出可读错误', () {
      expect(
        () => parseCredentials('这显然不是凭据'),
        throwsA(isA<CredentialsFormatException>()),
      );
      expect(
        () => parseCredentials('{"mac_key":"x"}'),
        throwsA(isA<CredentialsFormatException>()),
      );
    });

    test('diff 缺失或非数字时按 0 处理', () {
      expect(
        parseCredentials('{"access_token":"$token","diff":"abc"}').diff,
        0,
      );
      expect(parseCredentials('{"access_token":"$token"}').diff, 0);
    });
  });

  group('extractUcTokenCookie', () {
    test('取出 Base64 值本身', () {
      final value = extractUcTokenCookie(cookieWith({'access_token': token}));
      expect(value, isNotNull);
      expect(base64.decode(base64UrlToBase64(value!)), isNotEmpty);
    });

    test('没有 UC_TOKEN 时返回 null', () {
      expect(extractUcTokenCookie('sf=1; other=2'), isNull);
    });
  });

  group('序列化', () {
    test('JSON 往返保持一致', () {
      final original = Credentials(
        accessToken: token,
        macKey: macKey,
        diff: 7,
        userId: 'u1',
      );
      final restored = Credentials.fromJson(original.toJson());
      expect(restored.accessToken, token);
      expect(restored.macKey, macKey);
      expect(restored.diff, 7);
      expect(restored.userId, 'u1');
    });

    test('access_token 与 mac_key 会去掉首尾空白', () {
      final creds = parseCredentials(
        '{"access_token":"  $token  ","mac_key":"  $macKey  ","diff":0}',
      );
      expect(creds.accessToken, token);
      expect(creds.macKey, macKey);
    });
  });
}
