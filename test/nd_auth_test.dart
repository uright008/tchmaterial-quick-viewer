/// X-ND-AUTH 签名测试。
///
/// 期望值由参考实现 `tchMaterial-parser/src/tchmaterial_parser/auth.py`
/// 在固定 nonce 下生成，两边必须逐字节一致，否则私有 CDN 会返回 400。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/core/nd_auth.dart';

const _mac = 'test-mac-key';
const _token = 'TESTTOKEN123';
const _nonce = '1700000000000:ABCD1234';

void main() {
  group('signatureString', () {
    test('普通英文路径 + 末尾空行', () {
      expect(
        signatureString(
          'https://s-file-1.ykt.cbern.com.cn/zxx/ndrs/tags/tch_material_tag.json',
          'GET',
          _nonce,
        ),
        '$_nonce\n'
        'GET\n'
        '/zxx/ndrs/tags/tch_material_tag.json\n'
        's-file-1.ykt.cbern.com.cn\n',
      );
    });

    test('中文文件名先 percent-decode 再签名', () {
      expect(
        signatureString(
          'https://r1-ndr-private.ykt.cbern.com.cn/edu_product/esp/assets/'
          'bdc00134-465d-454b-a541-dcd0cec4d86e.pkg/'
          '%E4%B9%89%E5%8A%A1%E6%95%99%E8%82%B2%E6%95%99%E7%A7%91%E4%B9%A6'
          '%20%E8%AF%AD%E6%96%87_1756191813436.pdf',
          'GET',
          _nonce,
        ),
        '$_nonce\n'
        'GET\n'
        '/edu_product/esp/assets/'
        'bdc00134-465d-454b-a541-dcd0cec4d86e.pkg/'
        '义务教育教科书 语文_1756191813436.pdf\n'
        'r1-ndr-private.ykt.cbern.com.cn\n',
      );
    });

    test('%2F 也会被解码（与 Python unquote 一致）', () {
      expect(
        signatureString(
          'https://r2-ndr.ykt.cbern.com.cn/a/b%2Fc/d.pdf',
          'GET',
          _nonce,
        ),
        '$_nonce\nGET\n/a/b/c/d.pdf\nr2-ndr.ykt.cbern.com.cn\n',
      );
    });

    test('query 原样保留，不做解码', () {
      expect(
        signatureString(
          'https://basic.smartedu.cn/tchMaterial/detail?id=1&x=%E4%B8%AD',
          'GET',
          _nonce,
        ),
        '$_nonce\nGET\n/tchMaterial/detail?id=1&x=%E4%B8%AD\nbasic.smartedu.cn\n',
      );
    });

    test('host 不含端口', () {
      expect(
        signatureString('https://example.com:8443/a/b', 'GET', _nonce),
        '$_nonce\nGET\n/a/b\nexample.com\n',
      );
    });

    test('method 统一大写', () {
      expect(
        signatureString('https://e.com/a', 'post', _nonce),
        contains('\nPOST\n'),
      );
    });
  });

  group('signMac', () {
    test('与 Python HmacSHA256 + Base64 结果一致', () {
      expect(
        signMac(
          '$_nonce\nGET\n/zxx/ndrs/tags/tch_material_tag.json\n'
          's-file-1.ykt.cbern.com.cn\n',
          _mac,
        ),
        'uRKQoVfQs4XBXCXvEfKZ7J0IMPIfNEvVikHi6Dv0qoM=',
      );
      expect(
        signMac(
          '$_nonce\nGET\n/a/b/c/d.pdf\nr2-ndr.ykt.cbern.com.cn\n',
          _mac,
        ),
        'IpmY22gZTHPmoDk8bf/gTn5QE7wHQgeA7qTTsDnaj+o=',
      );
    });

    test('中文签名的 MAC 与参考实现一致', () {
      expect(
        signMac(
          '$_nonce\nGET\n/edu_product/esp/assets/'
          'bdc00134-465d-454b-a541-dcd0cec4d86e.pkg/'
          '义务教育教科书 语文_1756191813436.pdf\n'
          'r1-ndr-private.ykt.cbern.com.cn\n',
          _mac,
        ),
        '2NqHIpsx8gCaznZCVfYSMnsgY8KfEyktDzrmTPZpLu4=',
      );
    });

    test('POST 方法参与签名', () {
      expect(
        signMac(
          '$_nonce\nPOST\n/edu_product/esp/assets/'
          'bdc00134-465d-454b-a541-dcd0cec4d86e.pkg/'
          '义务教育教科书 语文_1756191813436.pdf\n'
          'r1-ndr-private.ykt.cbern.com.cn\n',
          _mac,
        ),
        'V00Dst82b0kzktIp0bjZJvtUeSAUofzBzemIQ+dyOtQ=',
      );
    });
  });

  group('buildNdAuth', () {
    test('输出 MAC 头格式', () {
      expect(
        buildNdAuth(
          url: 'https://s-file-1.ykt.cbern.com.cn/zxx/ndrs/tags/'
              'tch_material_tag.json',
          method: 'GET',
          accessToken: _token,
          macKey: _mac,
          nonce: _nonce,
        ),
        'MAC id="TESTTOKEN123",nonce="1700000000000:ABCD1234",'
        'mac="uRKQoVfQs4XBXCXvEfKZ7J0IMPIfNEvVikHi6Dv0qoM="',
      );
    });

    test('缺少 mac_key 时退回占位头', () {
      expect(
        buildNdAuth(
          url: 'https://example.com/a',
          accessToken: _token,
          macKey: null,
        ),
        'MAC id="TESTTOKEN123",nonce="0",mac="0"',
      );
      expect(
        buildNdAuth(url: 'https://example.com/a', macKey: ''),
        'MAC id="0",nonce="0",mac="0"',
      );
    });

    test('同 URL 每次生成的 nonce 都不同', () {
      final first = buildNdAuth(
        url: 'https://example.com/a',
        accessToken: _token,
        macKey: _mac,
      );
      final second = buildNdAuth(
        url: 'https://example.com/a',
        accessToken: _token,
        macKey: _mac,
      );
      expect(first, isNot(second));
    });
  });

  group('generateNonce', () {
    test('形如 <毫秒时间戳>:<8 位大写字母数字>', () {
      final nonce = generateNonce(
        diff: 11,
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(nonce, matches(RegExp(r'^1700000000011:[0-9A-Z]{8}$')));
    });

    test('字符表下标落在 1..35，不会是 0', () {
      final random = Random(42);
      for (var i = 0; i < 400; i++) {
        final nonce = generateNonce(random: random);
        final suffix = nonce.split(':')[1];
        for (final char in suffix.split('')) {
          expect(kNonceAlphabet.indexOf(char), greaterThan(0));
        }
      }
    });

    test('diff 参与时间戳偏移', () {
      final base = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
      expect(
        generateNonce(diff: 500, now: base).split(':').first,
        '1500',
      );
    });
  });

  group('unquote', () {
    test('解码 UTF-8 中文', () {
      expect(unquote('%E4%B8%AD%E6%96%87'), '中文');
    });

    test('保留加号（不同于 form-urlencoded 解码）', () {
      expect(unquote('a+b'), 'a+b');
    });

    test('非法转义静默降级而不抛异常', () {
      expect(() => unquote('%ZZ%'), returnsNormally);
      expect(unquote('abc%'), 'abc%');
    });

    test('无转义时原样返回', () {
      expect(unquote('already/plain'), 'already/plain');
    });
  });
}
