/// 分类树面板：把解析出的「学段 → 学科 → 版本 → 年级 → 册次」层级画出来。
///
/// 平台的分类深度并不统一（教学指南只到学科、部分教材多一层「年度」），所以这里
/// 用可展开的树而不是固定层级的级联选择器 —— 树能如实反映任意深度，级联选择器
/// 遇到不齐整的分支会出现空列。
library;

import 'package:flutter/material.dart';

import '../../data/catalog_index.dart';
import '../../models/category.dart';

/// 一个可见行：节点 + 缩进深度。
typedef _Row = ({CategoryNode node, int depth});

class CategoryTreePanel extends StatefulWidget {
  const CategoryTreePanel({
    super.key,
    required this.index,
    required this.selected,
    required this.onSelect,
  });

  final CatalogIndex index;
  final CategoryNode? selected;
  final ValueChanged<CategoryNode> onSelect;

  @override
  State<CategoryTreePanel> createState() => _CategoryTreePanelState();
}

class _CategoryTreePanelState extends State<CategoryTreePanel> {
  /// 已收起的节点。**必须用 [CategoryNode.uniqueKey] 而不是 id**：
  /// 平台在不同父节点下复用同一批 tag_id（80 个「一年级」节点共用一个 id），
  /// 用 id 当键会让「收起一个一年级」把全树所有的一年级一起收起。
  final Set<String> _collapsed = <String>{};

  /// 首次进入时只展开根节点，避免一次性渲染 1500+ 行。
  @override
  void initState() {
    super.initState();
    for (final child in widget.index.root.children) {
      _collapsed.add(child.uniqueKey);
    }
  }

  @override
  void didUpdateWidget(CategoryTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（搜索、面包屑跳转）改变了选中项时，展开到该节点的路径。
    final selected = widget.selected;
    if (selected != null && selected.id != oldWidget.selected?.id) {
      for (final node in selected.path) {
        _collapsed.remove(node.uniqueKey);
      }
    }
  }

  void _toggle(CategoryNode node) {
    setState(() {
      if (!_collapsed.remove(node.uniqueKey)) {
        _collapsed.add(node.uniqueKey);
      }
    });
  }

  List<_Row> _visibleRows() {
    final rows = <_Row>[];

    void walk(CategoryNode node, int depth) {
      rows.add((node: node, depth: depth));
      if (_collapsed.contains(node.uniqueKey)) return;
      for (final child in node.children) {
        walk(child, depth + 1);
      }
    }

    for (final child in widget.index.root.children) {
      walk(child, 0);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows();
    final total = widget.index.bookCount;
    final uncategorized = widget.index.uncategorizedCount;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('教材分类', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('$total 本',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: rows.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _AllBooksRow(
                  selected: widget.selected == null,
                  count: total,
                  onTap: () => widget.onSelect(widget.index.root),
                );
              }
              if (index == rows.length + 1) {
                if (uncategorized == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '其中 $uncategorized 本未归入平台分类',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final row = rows[index - 1];
              return _CategoryRow(
                node: row.node,
                depth: row.depth,
                selected: widget.selected?.id == row.node.id,
                collapsed: _collapsed.contains(row.node.uniqueKey),
                onToggle: () => _toggle(row.node),
                onSelect: () => widget.onSelect(row.node),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AllBooksRow extends StatelessWidget {
  const _AllBooksRow({
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        leading: const Icon(Icons.apps, size: 18),
        title: const Text('全部教材'),
        trailing: _CountBadge(count: count),
        onTap: onTap,
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.collapsed,
    required this.onToggle,
    required this.onSelect,
  });

  final CategoryNode node;
  final int depth;
  final bool selected;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChildren = node.children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: 8 + depth * 12.0, right: 8, top: 1, bottom: 1),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.only(left: 4, right: 8),
        leading: SizedBox(
          width: 22,
          height: 22,
          child: hasChildren
              ? IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: collapsed ? '展开' : '收起',
                  icon: Icon(collapsed
                      ? Icons.chevron_right
                      : Icons.keyboard_arrow_down),
                  onPressed: onToggle,
                )
              : Icon(
                  Icons.circle,
                  size: 6,
                  color: theme.colorScheme.outlineVariant,
                ),
        ),
        title: Text(
          node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: node.isSynthetic ? FontWeight.w400 : null,
            color: node.isSynthetic ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: depth == 0 && hasChildren
            ? Text(
                _dimensionHint(node),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: _CountBadge(count: node.totalBookCount),
        onTap: onSelect,
      ),
    );
  }

  /// 生成「学段 › 学科 › 版本 › 年级」这样的层级提示。
  ///
  /// 沿第一个有子节点的分支往下走，最多 4 层就停。**不能递归整棵子树** ——
  /// 原来那种写法会在每次构建行时遍历该节点下的全部后代，「电子教材」下面是
  /// 1558 个节点，展开列表时每帧都要白跑一遍。
  String _dimensionHint(CategoryNode node) {
    final dims = <String>[];
    var cursor = node;

    while (dims.length < 4) {
      final next = cursor.children.isEmpty ? null : cursor.children.first;
      if (next == null) break;
      final label = next.dimension.label;
      if (label != '其他' && !dims.contains(label)) dims.add(label);
      cursor = next;
    }
    return dims.join(' › ');
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
