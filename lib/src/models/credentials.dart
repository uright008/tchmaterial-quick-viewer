/// 登录凭据：Access Token + mac_key + 时钟差。
///
/// 平台把凭据写在 localStorage 的 `ND_UC_AUTH-*&token` 里，形如
/// `{"access_token":"…","mac_key":"…","diff":11,…}` 的 Base64。
/// 用户实际能拿到的往往是一整条 Cookie 串，因此这里同时接受三种粘贴形式：
///
/// 1. 纯 JSON：`{"access_token":"…","mac_key":"…","diff":11}`
/// 2. 整个 Cookie 串：`sf=…; UC_TOKEN-<uuid>-ncet-xedu=eyJ…; X-EDU-WEB-ROLE=…`
/// 3. 裸 Access Token（无 mac_key，只能生成占位签名）
library;

import 'dart:convert';

class Credentials {
  const Credentials({
    required this.accessToken,
    this.macKey,
    this.diff = 0,
    this.userId,
    this.expiresAt,
  });

  final String accessToken;

  /// 没有它就只能生成占位 `X-ND-AUTH`，部分私有 CDN 资源会 400。
  final String? macKey;

  /// 本地时钟相对 UC 服务器的毫秒差，加进 nonce 时间戳。
  final int diff;

  final String? userId;
  final DateTime? expiresAt;

  static const Credentials empty = Credentials(accessToken: '');

  bool get isEmpty => accessToken.isEmpty;

  /// 能生成真实 HMAC 签名（而非占位头）。
  bool get canSign => accessToken.isNotEmpty && (macKey?.isNotEmpty ?? false);

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  String get idPrefix => accessToken.length <= 8
      ? accessToken
      : '${accessToken.substring(0, 8)}…';

  Credentials copyWith({
    String? accessToken,
    String? macKey,
    int? diff,
    String? userId,
    DateTime? expiresAt,
    bool clearMacKey = false,
  }) {
    return Credentials(
      accessToken: accessToken ?? this.accessToken,
      macKey: clearMacKey ? null : (macKey ?? this.macKey),
      diff: diff ?? this.diff,
      userId: userId ?? this.userId,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (macKey != null) 'mac_key': macKey,
        'diff': diff,
        if (userId != null) 'user_id': userId,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  factory Credentials.fromJson(Map<String, dynamic> json) {
    final rawExpires = json['expires_at'];
    DateTime? expires;
    if (rawExpires is String && rawExpires.isNotEmpty) {
      expires = DateTime.tryParse(rawExpires)?.toUtc();
    } else if (rawExpires is num) {
      // 有的接口把过期时间给成秒级时间戳。
      expires = DateTime.fromMillisecondsSinceEpoch(rawExpires.toInt() * 1000,
              isUtc: true);
    }

    final token = json['access_token'];
    return Credentials(
      accessToken: token is String ? token.trim() : '',
      macKey: _nonEmptyString(json['mac_key']),
      diff: _asInt(json['diff']),
      userId: _nonEmptyString(json['user_id']) ??
          _nonEmptyString(json['account_id']),
      expiresAt: expires,
    );
  }

  @override
  String toString() => 'Credentials(id: $idPrefix, signed: $canSign)';
}

/// 粘贴内容无法解析成凭据。
class CredentialsFormatException implements Exception {
  CredentialsFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _nonEmptyString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return null;
}

int _asInt(Object? value) {
  if (value is bool) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// 从用户粘贴的文本解析凭据。空文本表示 “清除凭据”。
Credentials parseCredentials(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return Credentials.empty;

  // 1) 纯 JSON。
  final direct = _tryDecodeJsonObject(text);
  if (direct != null) return _fromMapping(direct, raw);

  // 2) 整个 Cookie 串 —— 找到 UC_TOKEN-* 的值再解一次。
  final cookieToken = extractUcTokenCookie(text);
  if (cookieToken != null) {
    final decoded = _tryDecodeBase64Json(cookieToken);
    if (decoded != null) return _fromMapping(decoded, raw);
    throw CredentialsFormatException(
      'Cookie 里的 UC_TOKEN 不是合法的 Base64 JSON，请重新从浏览器复制。',
    );
  }

  // 3) 看起来像 Base64 JSON（可能被引号包住）。
  final unwrapped = _stripWrappingQuotes(text);
  final asBase64 = _tryDecodeBase64Json(unwrapped);
  if (asBase64 != null) return _fromMapping(asBase64, raw);

  // 4) 裸 Access Token：长度像 token 就接受，只是无法真实签名。
  if (RegExp(r'^[A-Za-z0-9_\-\.=]+$').hasMatch(unwrapped) &&
      unwrapped.length >= 16) {
    return Credentials(accessToken: unwrapped);
  }

  throw CredentialsFormatException(
    '无法识别的凭据格式。请粘贴含 access_token 与 mac_key 的 JSON，'
    '或直接粘贴浏览器 Cookie（其中包含 UC_TOKEN-*）。',
  );
}

/// 从 Cookie 串里取出 `UC_TOKEN-…` 的值（Base64，未解码）。
///
/// 只认带 `UC_TOKEN…=` 前缀的显式写法。曾经这里对「没有 `=` 且长度 > 64 的整串
/// 输入」也按 token 处理，结果把裸 Access Token 也当成 Base64 去解、解码失败后
/// 直接抛错，反而让最简单的粘贴方式失效 —— 裸 token 现在由 [parseCredentials]
/// 的最后一步兜住。
String? extractUcTokenCookie(String cookieHeader) {
  for (final part in cookieHeader.split(';')) {
    final segment = part.trim();
    if (!segment.toUpperCase().startsWith('UC_TOKEN')) continue;
    final eq = segment.indexOf('=');
    if (eq < 0) continue;
    final value = segment.substring(eq + 1).trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

Credentials _fromMapping(Map<String, dynamic> data, String rawForFallback) {
  final creds = Credentials.fromJson(data);
  if (creds.accessToken.isEmpty) {
    throw CredentialsFormatException('凭据里 access_token 为空。');
  }
  return creds;
}

Map<String, dynamic>? _tryDecodeJsonObject(String text) {
  final decoded = _tryJson(text);
  if (decoded is Map<String, dynamic>) return decoded;
  // 控制台复制 JSON.stringify 结果时常常多包一层引号。
  if (decoded is String) {
    final inner = _tryJson(decoded);
    if (inner is Map<String, dynamic>) return inner;
  }
  return null;
}

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _tryDecodeBase64Json(String text) {
  final normalized = base64UrlToBase64(text);
  try {
    final bytes = base64.decode(normalized);
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is String) return _tryDecodeJsonObject(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// Base64URL → 标准 Base64，并补齐 `=` 填充。
String base64UrlToBase64(String input) {
  var s = input.replaceAll('-', '+').replaceAll('_', '/').trim();
  final remainder = s.length % 4;
  if (remainder == 2) {
    s = '$s==';
  } else if (remainder == 3) {
    s = '$s=';
  } else if (remainder == 1) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String _stripWrappingQuotes(String text) {
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    return text.substring(1, text.length - 1);
  }
  return text;
}
