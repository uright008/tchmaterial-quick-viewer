/// X-ND-AUTH 签名 —— happycola233/tchMaterial-parser `auth.py` 的 Dart 移植。
///
/// 平台登录后把凭据写入 localStorage 的 `ND_UC_AUTH-*&token`。网页里的
/// `getAuthHeader` / `getAuthHeaderAsync` 对 **每个请求** 现算签名，而不是复用
/// 抓包里那一整段头，因此这里也必须按当前 URL 现算。
///
/// 对应关系：
///   Fe(diff)  -> nonce = (Date.now() + diff) + ":" + Ze(8)
///   ze(url)   -> HMAC-SHA256(mac_key, 签名原文) 再 Base64
///   He(...)   -> MAC id="{access_token}",nonce="...",mac="..."
///
/// 签名原文（四段都以 `\n` 分隔，**末尾必须有空行**）：
///   {nonce}\n{METHOD}\n{解码后的 path}{?query}\n{hostname}\n
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 官网 `Ze()` 的字符表。下标用 `Math.ceil(35 * Math.random())`，0 几乎抽不到，
/// 1–35 对应 1-9A-Z。
const String kNonceAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

final Random _random = Random.secure();

/// 复刻 Python `urllib.parse.unquote`：把所有 `%XX` 解码为字节再按 UTF-8 还原。
///
/// 不能用 [Uri.decodeComponent] 直接顶替 —— 它遇到非法转义会抛异常，而官网
/// 对带中文文件名的路径签名时，**必须先 unquote 再签名**，非法序列需要按
/// `errors="replace"` 静默降级，不能因为一个坏字节就让整个请求失败。
String unquote(String input) {
  if (!input.contains('%')) return input;

  final bytes = <int>[];
  final codeUnits = input.codeUnits;
  for (var i = 0; i < codeUnits.length; i++) {
    final c = codeUnits[i];
    if (c == 0x25 /* % */ && i + 2 < codeUnits.length) {
      final hi = _hexValue(codeUnits[i + 1]);
      final lo = _hexValue(codeUnits[i + 2]);
      if (hi >= 0 && lo >= 0) {
        bytes.add((hi << 4) | lo);
        i += 2;
        continue;
      }
    }
    // 非转义位置上的字符按 UTF-8 拆回字节，保证后面统一解码。
    bytes.addAll(utf8.encode(String.fromCharCode(c)));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

int _hexValue(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37; // A-F
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57; // a-f
  return -1;
}

/// 按官网 `Fe(diff)` 生成 nonce：用（近似）服务器时间，避免本地时钟偏差被拒。
///
/// [now] 仅用于测试注入固定时间。
String generateNonce({int diff = 0, Random? random, DateTime? now}) {
  final rnd = random ?? _random;
  final suffix = StringBuffer();
  for (var i = 0; i < 8; i++) {
    // Math.ceil(35 * Math.random()) 的 Dart 等价写法。
    suffix.write(kNonceAlphabet[(35 * rnd.nextDouble()).ceil()]);
  }
  final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return '${millis + diff}:$suffix';
}

/// 构造官网 `ze()` 的 HMAC 原文。path 先解码，query 原样保留，host 不含端口。
String signatureString(String url, String method, String nonce) {
  final uri = Uri.parse(url);
  final relative =
      unquote(uri.path) + (uri.query.isEmpty ? '' : '?${uri.query}');
  return '$nonce\n${method.toUpperCase()}\n$relative\n${uri.host}\n';
}

/// `CryptoJS.HmacSHA256(mac_key, text).toString(Base64)`
String signMac(String text, String macKey) {
  final digest = Hmac(sha256, utf8.encode(macKey)).convert(utf8.encode(text));
  return base64.encode(digest.bytes);
}

/// 生成当前 URL 的 `X-ND-AUTH` 头。
///
/// 没有 `mac_key` 时退回旧占位头 `nonce="0",mac="0"`（兼容只保存了 Access Token
/// 的用户）；此时部分私有资源仍可能 400，需要重新粘贴含 mac_key 的完整凭据。
String buildNdAuth({
  required String url,
  String method = 'GET',
  String? accessToken,
  String? macKey,
  int diff = 0,
  String? nonce,
}) {
  final id = (accessToken == null || accessToken.isEmpty) ? '0' : accessToken;
  if (macKey == null || macKey.isEmpty) {
    return 'MAC id="$id",nonce="0",mac="0"';
  }
  final effectiveNonce = nonce ?? generateNonce(diff: diff);
  final mac = signMac(signatureString(url, method, effectiveNonce), macKey);
  return 'MAC id="$id",nonce="$effectiveNonce",mac="$mac"';
}
