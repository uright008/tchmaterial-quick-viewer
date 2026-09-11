/// 教材目录与详情的获取、缓存、解析。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';


import '../core/api_client.dart';
import '../models/category.dart';
import '../models/textbook.dart';
import 'catalog_index.dart';
import 'local_store.dart';

/// 目录加载阶段。
enum CatalogStage { checking, tagTree, bookList, indexing, done }

class CatalogProgress {
  const CatalogProgress(this.stage, this.message, [this.fraction]);

  final CatalogStage stage;
  final String message;

  /// 0..1，未知时为 null。
  final double? fraction;

  bool get isDone => stage == CatalogStage.done;
}

/// 目录缓存文件的格式版本，结构变更时递增即可让旧缓存自动失效。
const int _cacheSchemaVersion = 1;

class CatalogRepository {
  CatalogRepository({required PlatformApi api, required CacheStore cache})
      // 具名参数不能以下划线开头，所以无法写成 `required this._api`。
      // ignore: prefer_initializing_formals
      : _api = api,
        // ignore: prefer_initializing_formals
        _cache = cache;

  final PlatformApi _api;
  final CacheStore _cache;

  /// 加载教材目录。优先读磁盘缓存，`forceRefresh` 或平台版本变化时重新拉取。
  Future<CatalogIndex> load({
    bool forceRefresh = false,
    bool allowCache = true,
    void Function(CatalogProgress)? onProgress,
  }) async {
    void report(CatalogStage stage, String message, [double? fraction]) =>
        onProgress?.call(CatalogProgress(stage, message, fraction));

    report(CatalogStage.checking, '正在检查教材版本…');
    final cachedVersion = await _tryFetchModuleVersion();

    if (allowCache && !forceRefresh) {
      final cached = await _readCache(cachedVersion);
      if (cached != null) {
        report(CatalogStage.done, '已从本地缓存载入 ${cached.bookCount} 本教材');
        return cached;
      }
    }

    report(CatalogStage.tagTree, '正在获取分类树…', 0.05);
    final tagJson = await _api.getJson(PlatformEndpoints.tagTree);
    final hierarchies = (tagJson is Map ? tagJson['hierarchies'] : null);
    final root = parseTagHierarchy(
      hierarchies is List ? hierarchies : const [],
    );

    report(CatalogStage.bookList, '正在获取教材列表…', 0.15);
    final meta = await _fetchDataVersion();
    final partUrls = meta.partUrls;
    if (partUrls.isEmpty) {
      throw ApiException('平台未返回任何教材列表分片，可能是接口结构调整。');
    }

    final books = <Textbook>[];
    final failedParts = <String>[];
    var completed = 0;
    // 分片之间互不依赖，并发拉取；每个分片约 10 MB，并发 3 路足够且不至于被限流。
    const parallelism = 3;
    for (var start = 0; start < partUrls.length; start += parallelism) {
      final batch = partUrls.skip(start).take(parallelism).toList();
      final results = await Future.wait(
        batch.map((url) async {
          try {
            return _parseBookList(await _api.getJson(url));
          } catch (_) {
            // 记下来，但不要静默吞掉：少一个分片就是少约 1/4 的教材。
            failedParts.add(url);
            return const <Textbook>[];
          }
        }),
      );
      for (final list in results) {
        books.addAll(list);
      }
      completed += batch.length;
      report(
        CatalogStage.bookList,
        '正在获取教材列表…（$completed/${partUrls.length}）',
        0.15 + 0.65 * (completed / partUrls.length),
      );
    }

    if (books.isEmpty) {
      throw ApiException('教材列表为空，平台接口可能已变更。');
    }

    report(CatalogStage.indexing, '正在解析分类…', 0.85);
    final index = buildCatalogIndex(
      root: root,
      books: books,
      version: meta.version ?? 0,
      failedParts: failedParts.length,
    );

    // 只有完整拿到全部分片才写缓存。
    // 残缺数据一旦以「当前平台版本号」落盘，下次启动会因为版本号相同而被直接
    // 采用，用户会永久少掉那部分教材且毫无察觉。
    if (failedParts.isEmpty && meta.version != null) {
      unawaited(_writeCache(index).catchError((_) {}));
    }

    report(
      CatalogStage.done,
      failedParts.isEmpty
          ? '已载入 ${index.bookCount} 本教材'
          : '已载入 ${index.bookCount} 本教材（${failedParts.length}/'
              '${partUrls.length} 个分片失败，本次结果不写入缓存）',
    );
    return index;
  }

  /// 一次请求同时取回平台版本号与分片地址（两者本来就在同一个文件里）。
  ///
  /// 以前这里发了两次一模一样的 GET，白白多一次大接口往返。
  Future<({int? version, List<String> partUrls})> _fetchDataVersion() async {
    final json = await _api.getJson(PlatformEndpoints.materialDataVersion);
    if (json is! Map) {
      throw ApiException('平台版本接口返回了非预期结构。');
    }
    final rawVersion = json['module_version'];
    final rawUrls = json['urls'];
    return (
      version: rawVersion is num ? rawVersion.toInt() : null,
      partUrls: rawUrls is String
          ? rawUrls
              .split(',')
              .map((u) => u.trim())
              .where((u) => u.isNotEmpty)
              .toList()
          : const <String>[],
    );
  }

  Future<int?> _tryFetchModuleVersion() async {
    try {
      final json = await _api.getJson(PlatformEndpoints.materialDataVersion);
      final version = json is Map ? json['module_version'] : null;
      return version is num ? version.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  List<Textbook> _parseBookList(dynamic json) {
    if (json is! List) return const [];
    final result = <Textbook>[];
    for (final raw in json) {
      if (raw is! Map) continue;
      final book = _parseBook(raw.cast<String, dynamic>());
      if (book != null) result.add(book);
    }
    return result;
  }

  Textbook? _parseBook(Map<String, dynamic> raw) {
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;

    final title = _localizedText(raw['global_title']) ??
        (raw['title'] as String?)?.trim() ??
        '（未命名教材 $id）';

    final shortTitle = _shortLabel(raw['global_label']);

    final tagIds = <String>[];
    final tagPaths = raw['tag_paths'];
    if (tagPaths is List && tagPaths.isNotEmpty) {
      final first = tagPaths.first;
      if (first is String && first.isNotEmpty) {
        tagIds.addAll(first.split('/').where((s) => s.isNotEmpty));
      }
    }

    final dimensions = <String, String>{};
    final tagList = raw['tag_list'];
    if (tagList is List) {
      for (final tag in tagList) {
        if (tag is! Map) continue;
        final dim = tag['tag_dimension_id'];
        final name = tag['tag_name'];
        if (dim is String && name is String && name.isNotEmpty) {
          dimensions.putIfAbsent(dim, () => name);
        }
      }
    }

    final covers = _coverUrls(raw['custom_properties']);

    return Textbook(
      id: id,
      title: title,
      shortTitle: shortTitle,
      tagIds: tagIds,
      dimensions: dimensions,
      coverUrl: covers.isEmpty ? null : covers.first,
      coverUrls: covers,
      resourceTypeCode: raw['resource_type_code'] as String?,
      updateTime: DateTime.tryParse(raw['update_time'] as String? ?? ''),
    );
  }

  /// 取 `{"zh-CN": "…"}` 或裸字符串形式的本地化文本。
  String? _localizedText(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      for (final key in const ['zh-CN', 'zh', 'en']) {
        final candidate = value[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }
    return null;
  }

  /// `global_label` 的 `zh-CN` 是一个数组，第 2 项通常是规范短名。
  String? _shortLabel(Object? globalLabel) {
    if (globalLabel is! Map) return null;
    final list = globalLabel['zh-CN'];
    if (list is List && list.length > 1 && list[1] is String) {
      final text = (list[1] as String).trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  /// 从 `custom_properties.preview` 取按 Slide 序号排序的页面图，首张即封面。
  List<String> _coverUrls(Object? customProperties) {
    if (customProperties is! Map) return const [];
    final preview = customProperties['preview'];
    if (preview is! Map) return const [];

    final entries = <(int, String)>[];
    preview.forEach((key, value) {
      if (key is! String || value is! String || value.isEmpty) return;
      final match = RegExp(r'(\d+)').firstMatch(key);
      entries.add((match == null ? 1 << 20 : int.parse(match.group(1)!), value));
    });
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    return entries.map((e) => e.$2).toList();
  }

  // —— 磁盘缓存 ——

  Future<CatalogIndex?> _readCache(int? expectedVersion) async {
    final payload = await _cache.readCatalog();
    if (payload == null) return null;
    if (payload['schema'] != _cacheSchemaVersion) return null;
    // expectedVersion 为 null 表示版本探测失败（多半是断网）：
    // 此时应当信任磁盘上的缓存，让离线阅读可用，而不是整库重下。
    if (expectedVersion != null &&
        (payload['version'] as num?)?.toInt() != expectedVersion) {
      return null;
    }

    try {
      final rootJson = payload['tree'];
      if (rootJson is! List) return null;
      final root = _decodeNode(rootJson);
      root.linkChildren();

      final booksJson = payload['books'];
      if (booksJson is! List) return null;
      final books = booksJson
          .whereType<Map>()
          .map((b) => Textbook.fromJson(b.cast<String, dynamic>()))
          .toList();

      return buildCatalogIndex(
        root: root,
        books: books,
        version: (payload['version'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      // 缓存结构对不上就当没有，让上层重新下载。
      return null;
    }
  }

  Future<void> _writeCache(CatalogIndex index) async {
    await _cache.writeCatalog({
      'schema': _cacheSchemaVersion,
      'version': index.version,
      'saved_at': DateTime.now().toIso8601String(),
      'tree': _encodeNode(index.root),
      'books': index.books.map((b) => b.toJson()).toList(),
    });
  }

  /// 紧凑的树编码：`[id, name, dimensionId, [children]]`。
  List<dynamic> _encodeNode(CategoryNode node) => [
        node.id,
        node.name,
        node.dimensionId,
        node.children.map(_encodeNode).toList(),
      ];

  CategoryNode _decodeNode(List<dynamic> raw) {
    final node = CategoryNode(
      id: raw[0] as String,
      name: raw[1] as String,
      dimensionId: raw[2] as String?,
      isSynthetic: (raw[2] as String?) == null,
    );
    for (final child in (raw[3] as List)) {
      node.children.add(_decodeNode(child as List));
    }
    return node;
  }

  // —— 详情 ——

  /// 解析教材详情，得到下载直链、版别、章节目录。
  Future<TextbookDetail> fetchDetail(
    String contentId, {
    bool isTchMaterialPage = true,
    bool withChapters = true,
  }) async {
    final url = isTchMaterialPage
        ? PlatformEndpoints.materialDetail(contentId)
        : PlatformEndpoints.specialEduDetail(contentId);
    final data = await _fetchDetailJson(contentId, url, isTchMaterialPage);

    final rootTitle = _localizedText(data['global_title']) ??
        (data['title'] as String?)?.trim() ??
        '（未命名资源）';
    final edition = editionOf(data);
    final dirSegments = relativeDirOf(data);

    final files = <ResourceFile>[];
    final primary = _extractPrimaryFile(data, rootTitle, edition, dirSegments);
    if (primary == null) {
      throw ApiException(
        '未能从该资源中解析出可下载文件。若这是课程/备课资源，'
        '平台可能只提供了在线预览。',
        url: url,
      );
    }
    files.add(primary);

    // 教材常带配套音频（英语听力等），失败不影响正文。
    try {
      final audioJson =
          await _api.getJson(PlatformEndpoints.relationAudios(contentId));
      if (audioJson is List) {
        for (final raw in audioJson) {
          if (raw is! Map) continue;
          final audio =
              _extractAudioFile(raw.cast<String, dynamic>(), rootTitle);
          if (audio != null) files.add(audio);
        }
      }
    } catch (_) {
      // 配套音频不是必需的。
    }

    var chapters = const <Chapter>[];
    var fromTree = false;
    var frontPage = 0;
    if (withChapters && primary.isPdf) {
      final parsed = await _parseChapters(data);
      chapters = parsed.chapters;
      fromTree = parsed.fromTree;
      frontPage = parsed.frontPage;
    }

    return TextbookDetail(
      textbookId: contentId,
      title: rootTitle,
      files: files,
      chapters: chapters,
      chaptersFromTree: fromTree,
      frontPage: frontPage,
    );
  }

  /// 取详情 JSON，主端点失败时按类型换端点重试。
  ///
  /// 平台的资源分散在几套接口下：普通电子教材走 `ndrv2/resources/tch_material`，
  /// 而课程包、专题课（如部分体育教师用书）走 `ndrs/special_edu`。只打一个端点
  /// 会把后者的 403/404 当成失败，但其实换个端点就能拿到。
  Future<Map<String, dynamic>> _fetchDetailJson(
    String contentId,
    String primaryUrl,
    bool isTchMaterialPage,
  ) async {
    // LinkedHashSet 去重并保留顺序：避免三个端点里出现重复 URL 时白跑一遍。
    final candidates = <String>{
      primaryUrl,
      if (isTchMaterialPage) PlatformEndpoints.specialEduDetail(contentId),
      if (isTchMaterialPage) PlatformEndpoints.qualityCourseDetail(contentId),
    }.toList();

    ApiException? lastError;
    for (final url in candidates) {
      try {
        final json = await _api.getJson(url);
        if (json is Map) return json.cast<String, dynamic>();
        lastError = ApiException('详情接口返回了非预期结构。', url: url);
      } on ApiException catch (error) {
        lastError = error;
        // 只有「换个端点可能有救」的情况才继续尝试；网络/超时错误直接抛出，
        // 否则会把一次断网放大成三次请求。
        final status = error.statusCode;
        if (status != 403 && status != 404) rethrow;
      }
    }
    throw lastError ??
        ApiException('无法从平台获取该资源的详情。', url: primaryUrl);
  }

  /// 从 `ti_items` 里挑出正文文件。
  ///
  /// 参考实现分两轮：先找 `ti_is_source_file`，找不到再按 `ti_file_flag`
  /// 白名单兜底 —— 平台有些老资源这两个字段并不一致。
  ResourceFile? _extractPrimaryFile(
    Map<String, dynamic> data,
    String title,
    String? edition,
    List<String> dirSegments,
  ) {
    final items = data['ti_items'];
    if (items is! List) return null;

    ResourceFile? build(Map item, bool isPrimary) {
      final format = (item['ti_format'] as String?)?.trim().toLowerCase();
      if (format == null || format.isEmpty || format == 'folder') return null;
      final url = _resolveItemUrl(item);
      if (url == null) return null;
      return ResourceFile(
        url: url,
        format: format,
        title: title,
        sizeBytes: (item['ti_size'] as num?)?.toInt(),
        isPrimary: isPrimary,
        edition: edition,
        dirSegments: dirSegments,
      );
    }

    for (final raw in items) {
      if (raw is! Map) continue;
      if (raw['ti_is_source_file'] != true) continue;
      final file = build(raw, true);
      if (file != null) return file;
    }

    const fallbackFlags = {'source', 'pdf', 'ppt', 'pptx', 'doc', 'docx'};
    for (final raw in items) {
      if (raw is! Map) continue;
      final flag = raw['ti_file_flag'];
      if (flag is! String || !fallbackFlags.contains(flag)) continue;
      final file = build(raw, true);
      if (file != null) return file;
    }
    return null;
  }

  ResourceFile? _extractAudioFile(Map<String, dynamic> data, String rootTitle) {
    final title = _localizedText(data['global_title']) ?? rootTitle;
    final items = data['ti_items'];
    if (items is! List) return null;

    for (final raw in items) {
      if (raw is! Map) continue;
      final flag = raw['ti_file_flag'];
      final format = (raw['ti_format'] as String?)?.trim().toLowerCase();
      if (format == null || !const {'href', 'source'}.contains(flag)) continue;
      if (!const {'mp3', 'm4a', 'wav'}.contains(format)) continue;
      final url = _resolveItemUrl(raw);
      if (url == null) continue;
      return ResourceFile(
        url: url,
        format: format,
        title: title,
        sizeBytes: (raw['ti_size'] as num?)?.toInt(),
        isPrimary: false,
      );
    }
    return null;
  }

  /// `ti_storage` 是 `cs_path:${ref-path}/…` 形式，需要换成实际 CDN 域名；
  /// 部分条目只有 `ti_storages` 数组，取第一个非空值。
  String? _resolveItemUrl(Map item) {
    final storage = item['ti_storage'];
    if (storage is String && storage.isNotEmpty) {
      return storage.replaceFirst('cs_path:\${ref-path}', kPrivateAssetPrefix);
    }
    final storages = item['ti_storages'];
    if (storages is List) {
      for (final candidate in storages) {
        if (candidate is String && candidate.isNotEmpty) return candidate;
      }
    }
    return null;
  }

  /// 通过 `ebook_mapping` + `trees` 两个接口合并出章节目录。
  ///
  /// mapping 给「node_id → 页码」，tree 给「node_id → 标题与层级」，
  /// 两者 id 对齐后才能得到可跳转的目录。
  Future<({List<Chapter> chapters, bool fromTree, int frontPage})>
      _parseChapters(Map<String, dynamic> data) async {
    const empty = (chapters: <Chapter>[], fromTree: false, frontPage: 0);
    try {
      final items = data['ti_items'];
      if (items is! List) return empty;

      String? mappingUrl;
      for (final raw in items) {
        if (raw is Map && raw['ti_file_flag'] == 'ebook_mapping') {
          mappingUrl = _resolveItemUrl(raw);
          if (mappingUrl != null) break;
        }
      }
      if (mappingUrl == null) return empty;

      // mapping 位于 ndr-private，必须带真实签名。
      final mappingRaw = await _api.getText(mappingUrl, sign: true);
      final mappingJson = jsonDecode(mappingRaw);
      if (mappingJson is! Map) return empty;

      final ebookId = mappingJson['ebook_id'];
      // 前置页数：印刷页码 + frontPage = PDF 页码。
      // 目录展示要用它换算出「书上印的页码」，否则用户对着书看会觉得页码不对。
      final frontPage = (mappingJson['front_page'] as num?)?.toInt() ?? 0;
      final pageOfNode = <String, int>{};
      final mappings = mappingJson['mappings'];
      if (mappings is List) {
        for (final entry in mappings) {
          if (entry is! Map) continue;
          final nodeId = entry['node_id'];
          if (nodeId is String) {
            pageOfNode[nodeId] = (entry['page_number'] as num?)?.toInt() ?? 1;
          }
        }
      }

      if (ebookId is String && ebookId.isNotEmpty) {
        // 章节树在公开主机上，不需要签名。
        final treeJson =
            await _api.getJson(PlatformEndpoints.ebookTree(ebookId));
        final nodes = treeJson is List
            ? treeJson
            : (treeJson is Map ? treeJson['child_nodes'] : null);
        if (nodes is List && nodes.isNotEmpty) {
          final chapters = _buildChapters(nodes, pageOfNode);
          if (chapters.isNotEmpty) {
            return (chapters: chapters, fromTree: true, frontPage: frontPage);
          }
        }
      }

      // 兜底：拿不到树时，仅用页码生成平铺索引。
      if (pageOfNode.isEmpty) return empty;
      final pages = pageOfNode.values.toList()..sort();
      return (
        chapters: [
          for (var i = 0; i < pages.length; i++)
            Chapter(title: '第 ${i + 1} 节 (P${pages[i]})', pageIndex: pages[i]),
        ],
        fromTree: false,
        frontPage: frontPage,
      );
    } catch (_) {
      // 目录只是锦上添花，失败时静默降级。
      return empty;
    }
  }

  List<Chapter> _buildChapters(
    List<dynamic> nodes,
    Map<String, int> pageOfNode,
  ) {
    final result = <Chapter>[];
    for (final raw in nodes) {
      if (raw is! Map) continue;
      final title = (raw['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      final id = raw['id'] as String?;
      final children = raw['child_nodes'];
      result.add(Chapter(
        title: title,
        pageIndex: id == null ? null : pageOfNode[id],
        children: children is List ? _buildChapters(children, pageOfNode) : const [],
      ));
    }
    return result;
  }

  /// 下载文件到本地缓存目录，返回落盘文件。
  ///
  /// [onProgress] 的字节数来自 `Content-Length`，平台未给时会传 null。
  Future<File> download({
    required String url,
    required String fileName,
    String? subdir,
    void Function(int received, int? total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final target = File(
      [
        _cache.booksDir.path,
        if (subdir != null && subdir.isNotEmpty) _sanitizeSegment(subdir),
        _sanitizeSegment(fileName),
      ].join('/'),
    );
    await target.parent.create(recursive: true);

    final response = await _api.sendGet(url);

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw ApiException(
        '下载失败（HTTP ${response.statusCode}）。若为 400/403，'
        '通常是登录凭据失效，请在设置中重新粘贴 Cookie。',
        statusCode: response.statusCode,
        url: url,
      );
    }

    final totalHeader = response.headers['content-length'];
    final total = totalHeader == null ? null : int.tryParse(totalHeader);
    var received = 0;

    // 先写临时文件，成功后改名 —— 中断时不会留下半个 PDF 被当成已下载。
    final temp = File('${target.path}.part');
    final sink = temp.openWrite();
    try {
      await for (final chunk in response.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw const DownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }

    if (target.existsSync()) await target.delete();
    return temp.rename(target.path);
  }

  /// 已下载的本地文件（若存在）。
  File? localFileFor(String fileName, {String? subdir}) {
    final path = [
      _cache.booksDir.path,
      if (subdir != null && subdir.isNotEmpty) _sanitizeSegment(subdir),
      _sanitizeSegment(fileName),
    ].join('/');
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  CacheStore get cache => _cache;

  String _sanitizeSegment(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    // Windows 上以点结尾的文件名不合法；同时避免超长路径。
    final trimmed = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
    final safe = trimmed.isEmpty ? 'unnamed' : trimmed;
    return safe.length <= 120 ? safe : safe.substring(0, 120);
  }
}

/// 取消下载。
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => '下载已取消';
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
