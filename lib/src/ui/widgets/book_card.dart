/// 教材卡片：封面 + 书名 + 分类标签。
library;

import 'package:flutter/material.dart';

import '../../models/textbook.dart';

class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.textbook,
    required this.onTap,
    this.downloaded = false,
    this.selected = false,
  });

  final Textbook textbook;
  final VoidCallback onTap;
  final bool downloaded;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Cover(textbook: textbook, downloaded: downloaded)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    textbook.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    textbook.classificationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.textbook, required this.downloaded});

  final Textbook textbook;
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = textbook.coverUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: url == null || url.isEmpty
              ? _placeholder(theme)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  // 封面是整页扫描图，按显示尺寸解码可以省下大量内存。
                  cacheWidth: 420,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => _placeholder(theme),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _placeholder(theme, showSpinner: true);
                  },
                ),
        ),
        if (downloaded)
          Positioned(
            top: 6,
            right: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.download_done,
                  size: 13,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(ThemeData theme, {bool showSpinner = false}) {
    return Center(
      child: showSpinner
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 34,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    textbook.subject ?? '教材',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
