/// 浏览页：分类树 + 教材网格 + 搜索。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog_repository.dart';
import '../../models/category.dart';
import '../../models/textbook.dart';
import '../../state/catalog_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/book_card.dart';
import '../widgets/category_tree_panel.dart';
import 'book_detail_page.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  late final TextEditingController _searchController;
  bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: context.read<CatalogController>().query,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final showSidebar = _showSidebar && !narrow;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('教材查看器'),
        leading: narrow
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: '分类',
                  onPressed: () => _openTreeSheet(context),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '重新拉取平台目录',
            onPressed: catalog.isLoading
                ? null
                : () => catalog.load(forceRefresh: true),
            icon: catalog.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            onChanged: catalog.setQuery,
            showSidebarToggle: !narrow,
            sidebarVisible: _showSidebar,
            onToggleSidebar: () =>
                setState(() => _showSidebar = !_showSidebar),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                if (showSidebar) ...[
                  SizedBox(
                    width: 296,
                    child: CategoryTreePanel(
                      index: catalog.index,
                      selected: catalog.selected,
                      onSelect: (node) {
                        catalog.select(node.id == kCatalogRootNodeId
                            ? null
                            : node);
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: _Body(catalog: catalog)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openTreeSheet(BuildContext context) {
    final catalog = context.read<CatalogController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: CategoryTreePanel(
          index: catalog.index,
          selected: catalog.selected,
          onSelect: (node) {
            catalog.select(node.id == kCatalogRootNodeId ? null : node);
            Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.showSidebarToggle,
    required this.sidebarVisible,
    required this.onToggleSidebar,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool showSidebarToggle;
  final bool sidebarVisible;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          if (showSidebarToggle)
            IconButton(
              tooltip: sidebarVisible ? '隐藏分类树' : '显示分类树',
              onPressed: onToggleSidebar,
              icon: Icon(sidebarVisible
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索教材名称、学科、版本、年级…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: catalog.isSearching
                    ? IconButton(
                        tooltip: '清除',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _SortButton(),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();

    return PopupMenuButton<SortOrder>(
      tooltip: '排序方式',
      initialValue: catalog.sortOrder,
      onSelected: catalog.setSortOrder,
      itemBuilder: (context) => [
        for (final order in SortOrder.values)
          PopupMenuItem(
            value: order,
            child: Row(
              children: [
                Icon(order.icon, size: 18),
                const SizedBox(width: 10),
                Text(order.label),
                if (order == catalog.sortOrder) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 16),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(catalog.sortOrder.icon, size: 18),
            const SizedBox(width: 8),
            Text(catalog.sortOrder.label),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.catalog});

  final CatalogController catalog;

  @override
  Widget build(BuildContext context) {
    if (catalog.isLoading && !catalog.hasData) {
      return _LoadingView(progress: catalog.progress);
    }
    if (catalog.error != null && !catalog.hasData) {
      return _ErrorView(
        message: catalog.error!,
        onRetry: () => catalog.load(forceRefresh: true),
      );
    }
    if (!catalog.hasData) {
      return const Center(child: Text('暂无数据'));
    }

    final books = catalog.visibleBooks;

    return Column(
      children: [
        _BreadcrumbBar(catalog: catalog, count: books.length),
        const Divider(height: 1),
        Expanded(
          child: books.isEmpty
              ? const _EmptyView()
              : _BookGrid(books: books),
        ),
      ],
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.catalog, required this.count});

  final CatalogController catalog;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crumbs = catalog.breadcrumbs
        .where((n) => n.name != '全部教材')
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (catalog.isSearching)
                    Text(
                      '搜索结果',
                      style: theme.textTheme.titleSmall,
                    )
                  else
                    for (var i = 0; i < crumbs.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => catalog.select(
                          crumbs[i].id == kCatalogRootNodeId ? null : crumbs[i],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            crumbs[i].name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: i == crumbs.length - 1
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count 本',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.books});

  final List<Textbook> books;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = switch (width) {
          < 560 => 2,
          < 800 => 3,
          < 1080 => 4,
          < 1400 => 5,
          < 1750 => 6,
          _ => 7,
        };

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            // 封面接近 A4（1:1.414）再加上底部两行文字。
            childAspectRatio: 0.60,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            // 用 Selector 只订阅「这本是否已下载」这一个布尔值。
            // 直接 watch LibraryController 的话，下载过程中每来一块数据都会
            // notifyListeners()，整屏书卡跟着重建 —— 一本 20 MB 的教材能有
            // 几百次通知，滚动时就会明显掉帧。
            return Selector<LibraryController, bool>(
              selector: (_, library) => library.isDownloaded(book.id),
              builder: (context, downloaded, _) => BookCard(
                textbook: book,
                downloaded: downloaded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BookDetailPage(textbook: book),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.progress});

  final CatalogProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            progress?.message ?? '正在加载教材目录…',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (progress?.fraction != null)
            SizedBox(
              width: 280,
              child: LinearProgressIndicator(value: progress!.fraction),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('目录加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('该分类下没有教材', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
