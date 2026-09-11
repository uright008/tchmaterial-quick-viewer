/// 国家中小学智慧教育平台（basic.smartedu.cn）接口客户端。
///
/// 端点与签名规则参照 happycola233/tchMaterial-parser `api.py` / `network.py`：
/// `s-file-*.ykt.cbern.com.cn` 上的 JSON 元数据是公开的，用占位 `X-ND-AUTH`
/// 即可；而 `*-ndr-private.ykt.cbern.com.cn` 上的实体文件必须按 URL 现算真实
/// HMAC 签名，所以这里的每个请求都按目标 URL 单独签名。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'nd_auth.dart';
import '../models/credentials.dart';

/// 连接 / 读取超时，与参考实现的 `REQUEST_TIMEOUT = (10, 60)` 对齐。
const Duration kConnectTimeout = Duration(seconds: 10);
const Duration kReadTimeout = Duration(seconds: 60);

const String kOrigin = 'https://basic.smartedu.cn';
const String kUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/150.0.0.0 Safari/537.36';

/// 公开 JSON 接口主机（占位签名即可）。
const String kFileHost1 = 'https://s-file-1.ykt.cbern.com.cn';
const String kFileHost2 = 'https://s-file-2.ykt.cbern.com.cn';

/// `cs_path:${ref-path}` 的替换前缀（参考实现使用 r1）。
const String kPrivateAssetPrefix =
    'https://r1-ndr-private.ykt.cbern.com.cn';

/// 平台接口地址集合。
class PlatformEndpoints {
  const PlatformEndpoints._();

  /// 教材分类树。
  static const String tagTree = '$kFileHost1/zxx/ndrs/tags/tch_material_tag.json';

  /// 教材列表分片清单。
  static const String materialDataVersion =
      '$kFileHost1/zxx/ndrs/resources/tch_material/version/data_version.json';

  /// 教材详情（含 `ti_items` 下载直链）。
  static String materialDetail(String contentId) =>
      '$kFileHost1/zxx/ndrv2/resources/tch_material/details/$contentId.json';


  static String qualityCourseDetail(String contentId) =>
      '$kFileHost1/zxx/ndrv2/resources/$contentId.json';



  static String specialEduDetail(String contentId) =>
      '$kFileHost1/zxx/ndrs/special_edu/resources/details/$contentId.json';


  /// 教材配套音频（英语听力等）。
  static String relationAudios(String contentId) =>
      '$kFileHost1/zxx/ndrs/resources/$contentId/relation_audios.json';

  /// 电子教材章节树。
  static String ebookTree(String ebookId) =>
      '$kFileHost1/zxx/ndrv2/national_lesson/trees/$ebookId.json';

  /// 教材详情页（供「打开原文」使用）。
  static String materialPage(String contentId) =>
      '$kOrigin/tchMaterial/detail?contentType=assets_document&contentId=$contentId';
}

/// 网络层错误，带上面向用户的中文说明。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.url});

  final String message;
  final int? statusCode;
  final String? url;

  @override
  String toString() => message;
}

/// 带平台鉴权头的 HTTP 客户端。
class PlatformApi {
  PlatformApi({required Credentials Function() credentials, http.Client? client})
      // 具名参数不能以下划线开头，所以无法写成 `required this._credentials`。
      // ignore: prefer_initializing_formals
      : _credentials = credentials,
        _client = client ?? http.Client();

  final Credentials Function() _credentials;
  final http.Client _client;

  void close() => _client.close();

  Credentials get credentials => _credentials();

  /// 默认请求头。`X-ND-AUTH` 只是占位，真正发请求时按 URL 现算覆盖。
  Map<String, String> baseHeaders() => {
        'Authorization': 'Bearer 0',
        'Origin': kOrigin,
        'Referer': '$kOrigin/',
        'User-Agent': kUserAgent,
        'Accept': 'application/json, text/plain, */*',
      };

  /// 为 [url] 现算 `X-ND-AUTH`。
  String authHeaderFor(String url, String method) {
    final creds = _credentials();
    return buildNdAuth(
      url: url,
      method: method,
      accessToken: creds.accessToken.isEmpty ? null : creds.accessToken,
      macKey: creds.macKey,
      diff: creds.diff,
    );
  }

  Map<String, String> headersFor(String url, {String method = 'GET'}) => {
        ...baseHeaders(),
        'X-ND-AUTH': authHeaderFor(url, method),
      };

  /// GET 一个 JSON 接口。[sign] 为 true 时按 URL 真实签名（私有 CDN 必须）。
  Future<dynamic> getJson(String url, {bool sign = false}) async {
    final headers = headersFor(url);
    if (!sign) {
      // 公开 JSON 不需要真实签名，留占位头即可，省一次 HMAC。
      headers['X-ND-AUTH'] = 'MAC id="0",nonce="0",mac="0"';
    }

    http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(kReadTimeout);
    } on TimeoutException {
      throw ApiException('请求超时，请检查网络后重试。', url: url);
    } catch (error) {
      throw ApiException('网络请求失败：$error', url: url);
    }

    if (response.statusCode != 200) {
      throw ApiException(
        _statusMessage(response.statusCode),
        statusCode: response.statusCode,
        url: url,
      );
    }

    try {
      // 平台返回 UTF-8；显式解码避免中文教材名乱码。
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw ApiException('返回内容不是合法 JSON：$error', url: url);
    }
  }

  /// 流式 GET，用于大文件下载并汇报进度。
  Future<http.StreamedResponse> sendGet(String url, {bool sign = true}) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headersFor(url));
    if (!sign) {
      request.headers['X-ND-AUTH'] = 'MAC id="0",nonce="0",mac="0"';
    }
    try {
      final response = await _client.send(request).timeout(kConnectTimeout);
      return response;
    } on TimeoutException {
      throw ApiException('连接超时，请检查网络后重试。', url: url);
    } catch (error) {
      throw ApiException('网络请求失败：$error', url: url);
    }
  }

  /// 下载一个小文本资源（如 `ebook_mapping.txt`）。
  Future<String> getText(String url, {bool sign = true}) async {
    final response = await sendGet(url, sign: sign);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw ApiException(
        _statusMessage(response.statusCode),
        statusCode: response.statusCode,
        url: url,
      );
    }
    final bytes = await response.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 把 HTTP 状态码翻译成可操作的中文说明。
  ///
  /// 403 要分两种情况说：**实测确认**，带上真实 Cookie 后「体育与健康教师用书」
  /// 一类资源仍然 403（对 tch_material / special_edu / resources 等多个端点、
  /// 串行与并发、匿名与登录都试过，全部 403）。所以它不代表「凭据失效」，
  /// 而是平台压根没给这类资源开放直链；把用户引去「重新粘贴 Cookie」是错的。
  String _statusMessage(int status) {
    switch (status) {
      case 400:
        final signed = _credentials().canSign;
        return signed
            ? '平台拒绝了该请求（400），可能资源地址已失效。'
            : '平台拒绝了该请求（400）。该资源需要真实签名，请在设置中粘贴'
                '含 mac_key 的完整 Cookie 后重试。';
      case 401:
        return '登录凭据已失效（401），请在设置中重新粘贴 Cookie。';
      case 403:
        return _credentials().accessToken.isEmpty
            ? '平台拒绝访问（403）。可先在设置中粘贴登录 Cookie 重试；'
                '若仍是 403，说明平台未对这本教材开放直链，'
                '只能在平台网页端阅读。'
            : '平台拒绝访问该资源（403）。凭据本身有效 —— 这类资源'
                '（多为「体育与健康教师用书」等教师用书）平台未开放直链，'
                '需要登录 basic.smartedu.cn 在网页端阅读。';
      case 404:
        return '资源不存在（404），可能已下架。';
      case 429:
        return '请求过于频繁（429），请稍后再试。';
      default:
        return '接口返回异常状态码 $status。';
    }
  }
}
