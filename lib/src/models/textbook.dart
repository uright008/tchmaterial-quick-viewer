/// 教材与资源模型。
library;

import 'category.dart';

/// 列表接口返回的一本教材（不含下载直链，直链需要另取详情）。
class Textbook {
  Textbook({
    required this.id,
    required this.title,
    this.shortTitle,
    this.tagIds = const [],
    this.dimensions = const {},
    this.coverUrl,
    this.coverUrls = const [],
    this.resourceTypeCode,
    this.updateTime,
  });

  final String id;
  final String title;

  /// 平台 `global_label` 里的规范短名，例如「义务教育教科书 道德与法治 一年级上册」。
  final String? shortTitle;

  /// `tag_paths` 首个路径拆出的 tag_id 序列，用于在分类树上定位。
  final List<String> tagIds;

  /// `tag_dimension_id` → `tag_name`。
  final Map<String, String> dimensions;

  /// 首页缩略图（`custom_properties.preview.Slide1`），公有 CDN，可直接加载。
  final String? coverUrl;
  final List<String> coverUrls;

  final String? resourceTypeCode;
  final DateTime? updateTime;

  // —— 分类维度便捷访问 ——

  String? _dim(String key) => dimensions[key];

  String? get stage => _dim('zxxxd');
  String? get subject => _dim('zxxxk');
  String? get edition => _dim('zxxbb');
  String? get grade => _dim('zxxnj');
  String? get volume => _dim('zxxcc');

  /// 「小学 · 语文 · 统编版 · 一年级 · 上册」
  String get classificationLabel => CategoryDimension.fallbackOrder
      .map((k) => dimensions[k])
      .whereType<String>()
      .join(' · ');

  /// 搜索用的小写索引串。
  late final String searchHaystack = [
    title,
    shortTitle ?? '',
    ...dimensions.values,
  ].join(' ').toLowerCase();

  bool get hasCover => (coverUrl ?? '').isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (shortTitle != null) 'short_title': shortTitle,
        'tag_ids': tagIds,
        'dims': dimensions,
        if (coverUrl != null) 'cover': coverUrl,
        if (coverUrls.length > 1) 'covers': coverUrls,
        if (resourceTypeCode != null) 'type': resourceTypeCode,
        if (updateTime != null) 'updated': updateTime!.toIso8601String(),
      };

  factory Textbook.fromJson(Map<String, dynamic> json) {
    final rawDims = json['dims'];
    final dims = <String, String>{};
    if (rawDims is Map) {
      rawDims.forEach((key, value) {
        if (value is String && value.isNotEmpty) dims['$key'] = value;
      });
    }
    final covers = (json['covers'] as List?)?.whereType<String>().toList() ??
        const <String>[];

    return Textbook(
      id: json['id'] as String,
      title: json['title'] as String? ?? '（未命名教材）',
      shortTitle: json['short_title'] as String?,
      tagIds:
          (json['tag_ids'] as List?)?.whereType<String>().toList() ?? const [],
      dimensions: dims,
      coverUrl: json['cover'] as String?,
      coverUrls: covers,
      resourceTypeCode: json['type'] as String?,
      updateTime: DateTime.tryParse(json['updated'] as String? ?? ''),
    );
  }

  @override
  String toString() => 'Textbook($title)';
}

/// 教材详情里的一个可下载文件（正文 PDF、配套音频等）。
class ResourceFile {
  const ResourceFile({
    required this.url,
    required this.format,
    required this.title,
    this.sizeBytes,
    this.isPrimary = true,
    this.edition,
    this.dirSegments = const [],
  });

  final String url;

  /// `pdf` / `mp3` / `pptx` …
  final String format;
  final String title;
  final int? sizeBytes;

  /// 正文（source 文件）还是配套资源（如英语听力）。
  final bool isPrimary;

  final String? edition;

  /// 按分类层级存放时使用的目录段（学段/学科/版本）。
  final List<String> dirSegments;

  bool get isPdf => format.toLowerCase() == 'pdf';
  bool get isAudio => const ['mp3', 'm4a', 'wav'].contains(format.toLowerCase());

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  /// 建议的本地文件名（保留平台原始扩展名）。
  String get suggestedFileName {
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
    final base = safe.isEmpty ? 'textbook' : safe;
    return '$base.${format.toLowerCase()}';
  }
}

/// PDF 显式目标（PDF 32000-1:2008, 12.3.2.2）。
///
/// 这里只存原始数值，不直接引用 pdfrx 的 `PdfDest`，免得模型层依赖渲染库；
/// 阅读器跳转时再还原成 `PdfDest` 交给 `goToDest`。
///
/// 为什么需要它：`PdfDest` 除了页码还带 `command` + `params`，其中就包含**页内
/// 纵向位置**（`xyz` 是 `[left, top, zoom]`，`fitH`/`fitBH` 是 `[top]`）。
/// 只取页码而丢掉 `top`，本来该落在标题处的跳转就只能落在页顶。
class PdfDestination {
  const PdfDestination({
    required this.pageNumber,
    required this.command,
    this.params = const [],
  });

  /// 1 起的页码（pdfrx 已做 `pageIndex + 1`，与 `goToPage` 的语义一致）。
  final int pageNumber;

  /// `xyz` / `fit` / `fitH` / `fitV` / `fitR` / `fitB` / `fitBH` / `fitBV`
  final String command;

  /// 位置参数，坐标系是 PDF 用户空间（原点在左下角，Y 轴向上）。
  final List<double?> params;
}

/// 章节目录节点（来自 `ebook_mapping` + `trees` 接口的合并结果）。
class Chapter {
  const Chapter({
    required this.title,
    this.pageIndex,
    this.destination,
    this.children = const [],
  });

  final String title;

  /// 1 起的 **PDF** 页码；为 null 表示平台未给出映射。
  final int? pageIndex;

  /// PDF 自带书签里的精确目标位置（含页内偏移）。平台目录没有这个信息。
  final PdfDestination? destination;

  final List<Chapter> children;

  bool get hasPage => pageIndex != null && pageIndex! > 0;

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] as String? ?? '',
        pageIndex: (json['page_index'] as num?)?.toInt(),
        children: (json['children'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Chapter.fromJson)
                .toList() ??
            const [],
      );

  /// 换算成书上印刷的页码。
  ///
  /// 平台的 `page_number` 是**绝对 PDF 页索引**，而书上印的是正文页码，
  /// 两者相差 `front_page`（前置页数，封面/目录等）。实测某本教材前置 5 页：
  /// 目录里写「第一单元 / 1」，映射给的却是 6，差值恒为 `front_page`。
  /// 展示时用印刷页码，用户才能和手里的书对上。
  int? printedPage(int frontPage) {
    final page = pageIndex;
    if (page == null || frontPage <= 0 || page <= frontPage) return null;
    return page - frontPage;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (pageIndex != null) 'page_index': pageIndex,
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
      };

  // 刻意不提供 `flatten()` 之类的「递归展平」工具。
  //
  // 目录树一旦被整棵摊平，UI 就会在打开瞬间铺出上百条记录：既难定位，也把
  // 「逐级展开」这件事变得没有意义。需要遍历时请在具体 UI 里做**有界的**下钻
  // （见 `OutlinePanel._visibleRows`：只走用户展开过的分支）。
}

/// 教材详情的解析结果。
class TextbookDetail {
  const TextbookDetail({
    required this.textbookId,
    required this.title,
    required this.files,
    this.chapters = const [],
    this.chaptersFromTree = false,
    this.frontPage = 0,
  });

  final String textbookId;
  final String title;
  final List<ResourceFile> files;

  /// 目录；为空表示平台没有为该教材提供 `ebook_mapping`。
  final List<Chapter> chapters;

  /// true = 带层级结构的真目录；false = 只有页码的兜底索引。
  final bool chaptersFromTree;

  /// 教材前置页数（封面、目录等），来自平台 `ebook_mapping.front_page`。
  ///
  /// 「印刷页码 + frontPage = PDF 页码」。为 0 表示未知（例如目录来自 PDF
  /// 自带书签时）。
  final int frontPage;

  /// 正文文件（优先 PDF）。
  ResourceFile? get primaryFile {
    for (final f in files) {
      if (f.isPrimary && f.isPdf) return f;
    }
    for (final f in files) {
      if (f.isPrimary) return f;
    }
    return files.isEmpty ? null : files.first;
  }

  List<ResourceFile> get attachments =>
      files.where((f) => f != primaryFile).toList();

  bool get hasChapters => chapters.isNotEmpty;
}
