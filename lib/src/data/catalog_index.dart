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
    required this.version,
    required this.uncategorizedCount,
  });

  /// 合成的总根（「全部教材」），其子节点才是平台的顶层分类（通常只有「电子教材」）。
  final CategoryNode root;

  final List<Textbook> books;
  final Map<String, Textbook> booksById;

  /// 节点唯一键（[CategoryNode.uniqueKey]，即 tag_id 路径）→
  /// 该节点**及其所有后代**下的教材。
  ///
  /// 用路径而不是节点 id 作键：平台在多个父节点下复用同一批 tag_id，
  /// 按 id 归并会让兄弟分支的教材混在一起。
  final Map<String, List<Textbook>> booksByNode;

  /// 平台 `module_version`，用于缓存失效判断。
  final int version;

  final int uncategorizedCount;

  static const CatalogIndex empty = _EmptyCatalogIndex();

  int get bookCount => books.length;

  /// 某个分类节点下的教材（含其后代，已按分类路径排序）。
  List<Textbook> booksIn(CategoryNode node) =>
      booksByNode[node.uniqueKey] ?? const [];

  Textbook? bookById(String id) => booksById[id];

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
  int get version => 0;
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
}) {
  final booksByNode = <String, List<Textbook>>{};
  final booksById = <String, Textbook>{};
  final lookup = dimensionNameLookup(root);

  var uncategorized = 0;

  for (final book in books) {
    booksById[book.id] = book;

    var target = _resolveByTagPath(root, book.tagIds);

    // tag_paths 走不通（或只走了一半）时，用 tag_list 的维度名继续下钻，
    // 取能到达更深的那一个。
    if (target == null || target == root || target.children.isNotEmpty) {
      final byDims = _resolveByDimensions(root, book, lookup);
      if (byDims != null &&
          (target == null || byDims.depth > target.depth)) {
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
    version: version,
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

/// 建 `维度|名称` → 节点 的查找表。
///
/// 同一维度下同名节点在树里会重复出现（「一年级」挂在几十个版本节点下），
/// 因此值是一个候选列表，由调用方按父子关系挑出正确的那一个。
Map<String, List<CategoryNode>> dimensionNameLookup(CategoryNode root) {
  final map = <String, List<CategoryNode>>{};
  for (final node in root.descendants) {
    final dim = node.dimensionId;
    if (dim == null || dim.isEmpty) continue;
    (map['$dim|${node.name}'] ??= <CategoryNode>[]).add(node);
  }
  return map;
}

/// 用 `tag_list` 的维度名从根逐层下钻，返回最深命中节点。
///
/// 每层都限定在上一层已命中节点的子树内，避免把「人教版 · 一年级」匹配到另一个
/// 学科下的同名节点。
CategoryNode? _resolveByDimensions(
  CategoryNode root,
  Textbook book,
  Map<String, List<CategoryNode>> lookup,
) {
  CategoryNode cursor = root;
  CategoryNode? deepest;

  for (final dim in CategoryDimension.fallbackOrder) {
    final name = book.dimensions[dim];
    if (name == null || name.isEmpty) continue;

    final hit = _pickDescendant(lookup['$dim|$name'], cursor);
    if (hit == null) continue;
    cursor = hit;
    deepest = hit;
  }
  return deepest;
}

/// 从候选里挑出位于 [ancestor] 子树中的节点（含自身）。
///
/// 用父链上溯判断归属，复杂度 O(深度) —— 直接遍历子树在根节点上会是
/// O(1500)，乘上几千本教材后开销明显。
CategoryNode? _pickDescendant(
  List<CategoryNode>? candidates,
  CategoryNode ancestor,
) {
  if (candidates == null || candidates.isEmpty) return null;
  for (final candidate in candidates) {
    for (CategoryNode? node = candidate; node != null; node = node.parent) {
      if (identical(node, ancestor)) return candidate;
    }
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
