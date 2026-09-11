/// 教材分类模型。
///
/// 平台的分类是一棵「教材 → 学段 → 学科 → 版本 → 年级 → 册次」的树
/// （`tch_material_tag.json` 的 `hierarchies`），每层节点都带 `tag_dimension_id`
/// 标明它属于哪个维度。本文件把维度元数据集中在一处，避免 UI 里散落魔法字符串。
library;

/// 合成根节点（「全部教材」）的 id。
///
/// 平台返回的分类树顶层没有统一根，本应用在 `parseTagHierarchy` 里补了一个
/// 合成根；各处判断「是否根节点」都应引用这个常量，不要散落字面量。
const String kCatalogRootNodeId = '__root';

/// 分类维度。`id` 来自平台的 `tag_dimension_id`。
enum CategoryDimension {  root('5036342742', '教材'),
  stage('zxxxd', '学段'),
  subject('zxxxk', '学科'),
  edition('zxxbb', '版本'),
  grade('zxxnj', '年级'),
  volume('zxxcc', '册次'),
  category('zxxlb', '类别'),
  year('bknd', '年度'),
  view('tagView', '视图'),
  unknown('', '其他');

  const CategoryDimension(this.id, this.label);

  final String id;
  final String label;

  static CategoryDimension fromId(String? id) {
    if (id == null || id.isEmpty) return CategoryDimension.unknown;
    for (final d in CategoryDimension.values) {
      if (d.id == id) return d;
    }
    return CategoryDimension.unknown;
  }

  /// 通过 `tag_paths` 无法定位时的兜底排序：学段→学科→版本→年级→册次。
  static const List<String> fallbackOrder = [
    'zxxxd',
    'zxxxk',
    'zxxbb',
    'zxxnj',
    'zxxcc',
  ];
}

/// 分类树上的一个节点。
class CategoryNode {
  CategoryNode({
    required this.id,
    required this.name,
    required this.dimensionId,
    List<CategoryNode>? children,
    this.isSynthetic = false,
  }) : children = children ?? <CategoryNode>[];

  /// `tag_id`；合成节点使用 `__` 前缀。
  final String id;
  final String name;
  final String? dimensionId;

  /// 按平台返回顺序排列的子节点。
  final List<CategoryNode> children;

  /// 平台分类树里不存在的兜底节点（如「未分类」）。
  final bool isSynthetic;

  CategoryNode? parent;

  /// 恰好挂在本节点下的教材数。构建索引时写入。
  int directBookCount = 0;

  /// 本节点及其所有后代下的教材数。构建索引时写入。
  int totalBookCount = 0;

  CategoryDimension get dimension => CategoryDimension.fromId(dimensionId);

  bool get isLeaf => children.isEmpty;

  /// 从根到本节点的路径（含自身）。
  List<CategoryNode> get path {
    final result = <CategoryNode>[];
    CategoryNode? node = this;
    while (node != null) {
      result.insert(0, node);
      node = node.parent;
    }
    return result;
  }

  /// `学段/学科/版本/年级/册次` 形式的可读路径。
  ///
  /// 跳过「教材」维度层与合成根 —— 前者的 `dimensionId` 是平台容器 id，后者
  /// 的 `dimensionId` 为 null，两者都不该出现在路径文案里。
  String get displayPath => path
      .where((n) =>
          n.id != kCatalogRootNodeId && n.dimension != CategoryDimension.root)
      .map((n) => n.name)
      .join(' · ');

  int get depth {
    var d = 0;
    var node = parent;
    while (node != null) {
      d++;
      node = node.parent;
    }
    return d;
  }

  /// 深度优先遍历自身与所有后代。
  Iterable<CategoryNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  void linkChildren() {
    for (final child in children) {
      child.parent = this;
      child.linkChildren();
    }
  }

  /// 全树唯一的键：从根到本节点的 tag_id 路径。
  ///
  /// **不能只用 [id]**。平台在不同父节点下复用了同一批 `tag_id`：实测分类树里有
  /// 101 组重复 id，全部 80 个「一年级」节点共用同一个 tag_id（`44bec67a-…`），
  /// 56 个版本节点、「道德与法治」等 28 个学科节点也同样共用。若按 id 归并教材，
  /// 兄弟分支会被错误合并 —— 表现为「一年级 150 本」挂在本该只有 104 本的
  /// 「统编版」下面。
  String get uniqueKey {
    final buffer = StringBuffer();
    for (final node in path) {
      if (buffer.isNotEmpty) buffer.write('/');
      buffer.write(node.id);
    }
    return buffer.toString();
  }

  /// 返回第一个匹配的节点。真实数据里 id 会重复，需要拿到全部时用 [findAllById]。
  CategoryNode? findById(String nodeId) {
    if (id == nodeId) return this;
    for (final child in children) {
      final hit = child.findById(nodeId);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 返回所有 id 匹配的节点（真实树里会命中多个兄弟分支上的同名维度节点）。
  List<CategoryNode> findAllById(String nodeId) =>
      descendants.where((node) => node.id == nodeId).toList();

  @override
  String toString() => 'CategoryNode($name, ${children.length} children)';
}
