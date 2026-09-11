/// 教材分类索引：把平台返回的分类树与教材列表合并成可直接浏览的结构。
///
/// 本文件是纯逻辑（不碰网络、不碰文件），因此可以脱离平台单独做单元测试。
///
/// 平台数据有两个坑，索引构建必须处理：
///
/// 1. `tag_paths` 并非总能用。约 18% 的教材（教学指南、配套课件）`tag_list`
///    为空数组、`tag_paths` 也为空，只能落到「未分类」。
/// 2. 路径深度不固定。多数是 7 段（教材/学段/学科/版本/年级/册次），但带
///    `bknd`（年度）维度的是 8 段，教学指南只有 6 段。所以不能按固定下标取
///    维度，必须按 `tag_id` 逐层下钻，能走多深走多深。
library;

import '../models/category.dart';
import '../models/textbook.dart';

/// 无法归入平台分类树时的兜底节点 id。
const String kUncategorizedNodeId = '__uncategorized';

/// 分类树 + 教材列表的合并结果。
class CatalogIndex {
  CatalogIndex._({
    required this.root,
    required this.books,
    required this.booksById,
    required this.booksByNode,
    required this.placementByBookId,
    required this.version,
    required this.failedParts,
    required this.uncategorizedCount,
  });

  /// 合成的总根（「全部教材」），其子节点才是平台的顶层分类（通常只有「电子教材」）。
  final CategoryNode root;

  final List<Textbook> books;
  final Map<String, Textbook> booksById;

  /// 教材 id → 它最终被挂到的分类节点。
  ///
  /// 有了它才能断言「落点必须是 tag_path 落点的后代」，把跨分支跳级这类
  /// 错误挡住（见 `test/real_catalog_test.dart`）。
  final Map<String, CategoryNode> placementByBookId;

  /// 节点唯一键（[CategoryNode.uniqueKey]，即 tag_id 路径）→
  /// 该节点**及其所有后代**下的教材。
  ///
  /// 用路径而不是节点 id 作键：平台在多个父节点下复用同一批 tag_id，
  /// 按 id 归并会让兄弟分支的教材混在一起。
  final Map<String, List<Textbook>> booksByNode;

  /// 平台 `module_version`，用于缓存失效判断。
  final int version;

  /// 本次加载失败的教材分片数（0 表示数据完整）。
  ///
  /// 分片失败意味着少了成百上千本书。这里如实记录，并在有失败时禁止写缓存，
  /// 免得残缺目录以「当前平台版本」落盘后被永久沿用。
  final int failedParts;

  final int uncategorizedCount;

  static const CatalogIndex empty = _EmptyCatalogIndex();

  int get bookCount => books.length;

  /// 某个分类节点下的教材（含其后代，已按分类路径排序）。
  List<Textbook> booksIn(CategoryNode node) =>
      booksByNode[node.uniqueKey] ?? const [];

  Textbook? bookById(String id) => booksById[id];

  /// 这本书最终落在哪个分类节点下。
  CategoryNode? placementOf(String bookId) => placementByBookId[bookId];

  /// 按关键词做多词 AND 搜索，覆盖书名与全部维度名。
  List<Textbook> search(String query, {int limit = 300}) {
    final keywords =
        query.toLowerCase().split(RegExp(r'\s+')).where((k) => k.isNotEmpty);
    if (keywords.isEmpty) return const [];
    final result = <Textbook>[];
    for (final book in books) {
      if (keywords.every(book.searchHaystack.contains)) {
        result.add(book);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  /// 从根开始的分类树路径。
  List<CategoryNode> get stageRoots => root.children;
}

class _EmptyCatalogIndex implements CatalogIndex {
  const _EmptyCatalogIndex();

  @override
  CategoryNode get root => CategoryNode(
        id: kCatalogRootNodeId,
        name: '全部教材',
        dimensionId: null,
        isSynthetic: true,
      );
  @override
  List<Textbook> get books => const [];
  @override
  Map<String, Textbook> get booksById => const {};
  @override
  Map<String, List<Textbook>> get booksByNode => const {};
  @override
  Map<String, CategoryNode> get placementByBookId => const {};
  @override
  CategoryNode? placementOf(String bookId) => null;
  @override
  int get version => 0;
  @override
  int get failedParts => 0;
  @override
  int get uncategorizedCount => 0;
  @override
  int get bookCount => 0;
  @override
  List<Textbook> booksIn(CategoryNode node) => const [];
  @override
  Textbook? bookById(String id) => null;
  @override
  List<Textbook> search(String query, {int limit = 300}) => const [];
  @override
  List<CategoryNode> get stageRoots => const [];
}

/// 把平台 `tch_material_tag.json` 的 `hierarchies` 解析成分类树。
///
/// 平台结构是「列表套一层 children」反复嵌套：
/// `hierarchies: [ {children: [ {tag_id, tag_name, hierarchies: [...]} ]} ]`。
CategoryNode parseTagHierarchy(List<dynamic> hierarchies) {
  final root = CategoryNode(
    id: kCatalogRootNodeId,
    name: '全部教材',
    dimensionId: null,
    isSynthetic: true,
  );
  root.children.addAll(_parseLevel(hierarchies));
  root.linkChildren();
  return root;
}

List<CategoryNode> _parseLevel(List<dynamic>? hierarchies) {
  final nodes = <CategoryNode>[];
  if (hierarchies == null) return nodes;

  for (final container in hierarchies) {
    if (container is! Map) continue;
    final children = container['children'];
    if (children is! List) continue;

    for (final raw in children) {
      if (raw is! Map) continue;
      final id = raw['tag_id'];
      if (id is! String || id.isEmpty) continue;

      final node = CategoryNode(
        id: id,
        name: (raw['tag_name'] as String?)?.trim() ?? '(未命名分类)',
        dimensionId: raw['tag_dimension_id'] as String?,
      );
      node.children.addAll(_parseLevel(raw['hierarchies'] as List?));
      nodes.add(node);
    }
  }
  return nodes;
}

/// 合并分类树与教材列表，产出可浏览的索引。
CatalogIndex buildCatalogIndex({
  required CategoryNode root,
  required List<Textbook> books,
  int version = 0,
  int failedParts = 0,
}) {
  final booksByNode = <String, List<Textbook>>{};
  final placementByBookId = <String, CategoryNode>{};
  final booksById = <String, Textbook>{};

  var uncategorized = 0;

  for (final book in books) {
    booksById[book.id] = book;

    var target = _resolveByTagPath(root, book.tagIds);

    // tag_paths 走不通（或只走了一半）时，用 tag_list 的维度名继续下钻，
    // 取能到达更深的那一个。
    if (target == null || target == root || target.children.isNotEmpty) {
      // 关键：以 tag_path 的落点为基准下钻，而不是从 root 重新开始。
      // 这样维度细化只可能落在同一分支的更深处，不会跳到兄弟分支去。
      final base = (target == null || target == root) ? root : target;
      final byDims = _resolveByDimensions(base, book);
      if (byDims != null && byDims.depth > (target?.depth ?? -1)) {
        target = byDims;
      }
    }

    if (target == null || target == root) {
      target = _uncategorizedNodeOf(root);
      uncategorized++;
    }

    // 挂到目标节点及其所有祖先上，这样任意层级都能列出其下全部教材。
    for (final node in target.path) {
      if (node == root) continue;
      (booksByNode[node.uniqueKey] ??= <Textbook>[]).add(book);
    }
    placementByBookId[book.id] = target;
    target.directBookCount++;
  }

  // 统计各节点总量，并给每个节点下的教材排序。
  for (final node in root.descendants) {
    final list = booksByNode[node.uniqueKey];
    node.totalBookCount = list?.length ?? 0;
    if (list != null) list.sort(compareTextbooks);
  }

  // 累计教材时跳过了根节点（它不在 booksByNode 里），这里补上，
  // 否则「全部教材」会显示成 0 本。
  root.totalBookCount = books.length;

  return CatalogIndex._(
    root: root,
    books: books,
    booksById: booksById,
    booksByNode: booksByNode,
    placementByBookId: placementByBookId,
    version: version,
    failedParts: failedParts,
    uncategorizedCount: uncategorized,
  );
}

/// 排序：学段 → 学科 → 版本 → 年级 → 册次 → 书名。
///
/// 用固定的年级/册次顺序表，避免「一年级 / 二年级 / … / 九年级」被按拼音排乱。
int compareTextbooks(Textbook a, Textbook b) {
  for (final getter in <String? Function(Textbook)>[
    (t) => t.stage,
    (t) => t.subject,
    (t) => t.edition,
    (t) => t.grade,
    (t) => t.volume,
  ]) {
    final av = getter(a);
    final bv = getter(b);
    final cmp = _compareNames(av, bv);
    if (cmp != 0) return cmp;
  }
  return a.title.compareTo(b.title);
}

const List<String> _gradeOrder = [
  '一年级', '二年级', '三年级', '四年级', '五年级', '六年级',
  '七年级', '八年级', '九年级',
  '高一', '高二', '高三',
  '高中一年级', '高中二年级', '高中三年级',
];

const List<String> _volumeOrder = [
  '上册', '下册', '全一册', '一册', '第一册', '第二册', '第三册', '第四册',
];

int _indexOr(List<String> order, String? value, int fallback) {
  if (value == null) return fallback;
  final idx = order.indexOf(value);
  return idx < 0 ? fallback : idx;
}

int _compareNames(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;

  final ai = _indexOr(_gradeOrder, a, -1);
  final bi = _indexOr(_gradeOrder, b, -1);
  if (ai >= 0 && bi >= 0 && ai != bi) return ai - bi;

  final av = _indexOr(_volumeOrder, a, -1);
  final bv = _indexOr(_volumeOrder, b, -1);
  if (av >= 0 && bv >= 0 && av != bv) return av - bv;

  return a.compareTo(b);
}

/// 按 `tag_paths` 的 tag_id 逐层下钻，返回能到达的最深节点。
///
/// `tag_paths[0]` 是平台顶层的容器 UUID（分类树里没有对应节点），因此从下标 1
/// 开始走。
CategoryNode? _resolveByTagPath(CategoryNode root, List<String> tagIds) {
  if (tagIds.length < 2) return null;

  CategoryNode? cursor;
  for (var i = 1; i < tagIds.length; i++) {
    final parent = cursor ?? root;
    CategoryNode? next;
    for (final child in parent.children) {
      if (child.id == tagIds[i]) {
        next = child;
        break;
      }
    }
    if (next == null) break;
    cursor = next;
  }
  return cursor;
}

/// 从 [start] 出发，用 `tag_list` 的维度名**沿树的实际层级**逐层下钻。
///
/// 两个约束缺一不可，它们都是踩过坑才定下来的：
///
/// 1. **只看直接子节点**，不在整棵子树里捞同名节点。
/// 2. **某一维找不到就地停下**（`break`），绝不跳过它继续用更下层的名字匹配。
///
/// 违规的后果是真实发生过的：某本《物理九年级全一册》的版别是
/// 「北师大版（主编：闫金铎）」，而树里该学科下只有「北师大版（主编：郭玉英）」。
/// 旧实现遇到版别匹配不上就 `continue`，接着拿「九年级」从根重新搜 —— 于是这本书
/// 被挂进了**另一个版别**的分支，该分支计数被多算，用户也在错误的分类里看到它。
///
/// [start] 必须是 `tag_path` 已经确定的落点（而不是 root）：这样维度下钻只会在
/// 平台给出的分支内部做细化，永远不会跨分支。
CategoryNode? _resolveByDimensions(CategoryNode start, Textbook book) {
  // 已经在路径上的维度不再重复匹配：`tag_path` 可能已经走到了「版本」，
  // 这时要从「年级」接着往下看，而不是又从「学段」开始找。
  final satisfied = <String>{
    for (final node in start.path)
      if (node.dimensionId != null && node.dimensionId!.isNotEmpty)
        node.dimensionId!,
  };

  var cursor = start;
  CategoryNode? deepest;

  for (final dim in CategoryDimension.fallbackOrder) {
    if (satisfied.contains(dim)) continue;

    final name = book.dimensions[dim];
    if (name == null || name.isEmpty) continue;

    final hit = _directChild(cursor, dim, name);
    if (hit == null) break;
    cursor = hit;
    deepest = hit;
  }
  return deepest;
}

/// 在 [parent] 的**直接子节点**里找指定维度同名的节点。
///
/// 「电子教材」这类容器层（dimension 为 [CategoryDimension.root]）是透明的：
/// 合成根下面只有它，真正的学段/学科都挂在它下面，穿透它才能开始下钻。
CategoryNode? _directChild(
  CategoryNode parent,
  String dimensionId,
  String name,
) {
  for (final child in parent.children) {
    if (child.dimension == CategoryDimension.root) {
      final inside = _directChild(child, dimensionId, name);
      if (inside != null) return inside;
      continue;
    }
    if (child.dimensionId == dimensionId && child.name == name) return child;
  }
  return null;
}

/// 取（必要时创建）「未分类」节点。
CategoryNode _uncategorizedNodeOf(CategoryNode root) {
  for (final child in root.children) {
    if (child.id == kUncategorizedNodeId) return child;
  }
  final node = CategoryNode(
    id: kUncategorizedNodeId,
    name: '未分类',
    dimensionId: null,
    isSynthetic: true,
  );
  node.parent = root;
  root.children.add(node);
  return node;
}

/// 从详情页 `tag_list` 提取「学段/学科/版本」三段目录，供下载分类存放。
List<String> relativeDirOf(Map<String, dynamic> resourceData) {
  final found = <String, String>{};
  final tags = resourceData['tag_list'];
  if (tags is List) {
    for (final tag in tags) {
      if (tag is! Map) continue;
      final dim = tag['tag_dimension_id'];
      final name = tag['tag_name'];
      if (dim is String && name is String && name.isNotEmpty) {
        found.putIfAbsent(dim, () => name);
      }
    }
  }
  return [
    for (final dim in const ['zxxxd', 'zxxxk', 'zxxbb'])
      if (found[dim] != null) found[dim]!,
  ];
}

/// 取教材版别（人教版、北师大版…）。
String? editionOf(Map<String, dynamic> resourceData) {
  final tags = resourceData['tag_list'];
  if (tags is! List) return null;
  for (final tag in tags) {
    if (tag is Map && tag['tag_dimension_id'] == 'zxxbb') {
      final name = tag['tag_name'];
      if (name is String && name.isNotEmpty) return name;
    }
  }
  return null;
}
