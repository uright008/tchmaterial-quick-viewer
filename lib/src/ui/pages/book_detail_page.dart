/// 教材详情页：封面、分类信息、文件列表与章节目录。
library;


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/platform_support.dart';
import '../../models/category.dart';
import '../../models/textbook.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import 'reader_page.dart';

class BookDetailPage extends StatefulWidget {
  const BookDetailPage({super.key, required this.textbook});

  final Textbook textbook;

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  TextbookDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _withChapters = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = context.read<LibraryController>();
      final detail = await library.resolveDetail(
        widget.textbook,
        withChapters: _withChapters,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('教材详情'),
        actions: [
          IconButton(
            tooltip: '在平台上查看',
            onPressed: _openOnPlatform,
            icon: const Icon(Icons.open_in_new),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(textbook: widget.textbook),
                const SizedBox(height: 24),
                if (_loading)
                  const _LoadingCard()
                else if (_error != null)
                  _ErrorCard(message: _error!, onRetry: _load)
                else if (_detail != null) ...[
                  _FilesSection(
                    detail: _detail!,
                    textbook: widget.textbook,
                    onRead: _openReader,
                    onDownload: _download,
                    onOpenExternal: _openExternally,
                  ),
                  const SizedBox(height: 20),
                  _ChaptersSection(
                    detail: _detail!,
                    onToggleLoad: _toggleChapters,
                    onJump: _openReaderAtPage,
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  '教材编号：${widget.textbook.id}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleChapters() async {
    setState(() => _withChapters = !_withChapters);
    if (_withChapters && (_detail?.chapters.isEmpty ?? true)) {
      await _load();
    }
  }

  Future<void> _openOnPlatform() async {
    final uri =
        Uri.parse(PlatformEndpoints.materialPage(widget.textbook.id));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      _toast('无法打开浏览器');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openReader(ResourceFile file, {int? page}) async {
    final settings = context.read<SettingsController>();

    if (settings.autoOpenNative && supportsExternalFileOpen) {
      final local = context
          .read<LibraryController>()
          .repository
          .localFileFor(file.suggestedFileName);
      if (local != null) {
        if (await launchUrl(Uri.file(local.path),
            mode: LaunchMode.externalApplication)) {
          return;
        }
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          textbook: widget.textbook,
          file: file,
          detail: _detail,
          initialPage: page,
        ),
      ),
    );
  }

  Future<void> _openReaderAtPage(int page) async {
    final file = _detail?.primaryFile;
    if (file == null) return;
    await _openReader(file, page: page);
  }

  Future<void> _download(ResourceFile file) async {
    final library = context.read<LibraryController>();
    _toast('开始下载：${file.title}');
    try {
      await library.download(widget.textbook, file);
      if (!mounted) return;
      _toast('已下载：${file.title}');
    } catch (error) {
      if (!mounted) return;
      _toast('$error');
    }
  }

  Future<void> _openExternally(ResourceFile file) async {
    final library = context.read<LibraryController>();
    try {
      final local = await library.ensureLocal(widget.textbook, file);
      await launchUrl(Uri.file(local.path),
          mode: LaunchMode.externalApplication);
    } catch (error) {
      if (!mounted) return;
      _toast('$error');
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.textbook});

  final Textbook textbook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = textbook.coverUrl;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 156,
            height: 214,
            color: theme.colorScheme.surfaceContainerHighest,
            child: cover == null || cover.isEmpty
                ? Icon(Icons.menu_book_outlined,
                    size: 44, color: theme.colorScheme.onSurfaceVariant)
                : Image.network(
                    cover,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.menu_book_outlined,
                      size: 44,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(textbook.title, style: theme.textTheme.headlineSmall),
              if (textbook.shortTitle != null &&
                  textbook.shortTitle != textbook.title) ...[
                const SizedBox(height: 6),
                Text(
                  textbook.shortTitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final dimension in CategoryDimension.fallbackOrder)
                    if (textbook.dimensions[dimension] != null)
                      _DimensionChip(
                        label: CategoryDimension.fromId(dimension).label,
                        value: textbook.dimensions[dimension]!,
                      ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DimensionChip extends StatelessWidget {
  const _DimensionChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesSection extends StatelessWidget {
  const _FilesSection({
    required this.detail,
    required this.textbook,
    required this.onRead,
    required this.onDownload,
    required this.onOpenExternal,
  });

  final TextbookDetail detail;
  final Textbook textbook;
  final void Function(ResourceFile file) onRead;
  final Future<void> Function(ResourceFile file) onDownload;
  final Future<void> Function(ResourceFile file) onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryController>();
    final task = library.taskFor(textbook.id);
    final primary = detail.primaryFile;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('资源文件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 14),
            if (primary != null)
              _FileRow(
                file: primary,
                isPrimary: true,
                task: task,
                onRead: () => onRead(primary),
                onDownload: () => onDownload(primary),
                onOpenExternal: () => onOpenExternal(primary),
              ),
            for (final file in detail.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _FileRow(
                  file: file,
                  isPrimary: false,
                  task: null,
                  onRead: null,
                  onDownload: () => onDownload(file),
                  onOpenExternal: () => onOpenExternal(file),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.isPrimary,
    required this.task,
    required this.onRead,
    required this.onDownload,
    required this.onOpenExternal,
  });

  final ResourceFile file;
  final bool isPrimary;
  final dynamic task;
  final VoidCallback? onRead;
  final Future<void> Function() onDownload;
  final Future<void> Function()? onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = task != null && task.isActive;
    final isDone = task != null && task.status == DownloadStatus.done;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                file.isAudio ? Icons.audiotrack : Icons.picture_as_pdf,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPrimary ? '正文（${file.format.toUpperCase()}）' : file.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (file.sizeLabel.isNotEmpty)
                Text(
                  file.sizeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (isRunning || (task != null && task.status == DownloadStatus.failed)) ...[
            const SizedBox(height: 12),
            if (isRunning) ...[
              LinearProgressIndicator(value: task.progress),
              const SizedBox(height: 6),
              Text(
                task.progressLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else
              Text(
                task.error ?? '下载失败',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (onRead != null)
                FilledButton.icon(
                  onPressed: onRead,
                  icon: const Icon(Icons.auto_stories_outlined, size: 18),
                  label: const Text('在线阅读'),
                ),
              OutlinedButton.icon(
                onPressed: isRunning ? null : onDownload,
                icon: Icon(
                  isDone ? Icons.download_done : Icons.download_outlined,
                  size: 18,
                ),
                label: Text(isDone ? '重新下载' : '下载'),
              ),
              // Android/iOS 上 file:// 会被系统拒绝，且内置阅读器已够用，
              // 因此只在外层支持时才显示这个入口。详见 platform_support.dart。
              if (onOpenExternal != null && supportsExternalFileOpen)
                TextButton.icon(
                  onPressed: onOpenExternal,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('用系统程序打开'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChaptersSection extends StatelessWidget {
  const _ChaptersSection({
    required this.detail,
    required this.onToggleLoad,
    required this.onJump,
  });

  final TextbookDetail detail;
  final Future<void> Function() onToggleLoad;
  final void Function(int page) onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (detail.chapters.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.toc_outlined),
          title: const Text('加载章节目录'),
          subtitle: const Text('平台未在默认加载中返回目录，可尝试单独拉取'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onToggleLoad,
        ),
      );
    }

    // **只列第一级**，不递归摊平。
    //
    // 原来这里是 `chapters.expand((c) => c.flatten())`，会把整棵树一次性铺开；
    // 教材目录动辄上百条，详情页会被拉得很长，反而找不到东西。完整的分级目录
    // 在阅读器的目录面板里（那里可逐级展开）。
    final topLevel = detail.chapters;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('章节目录', style: theme.textTheme.titleMedium),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    detail.chaptersFromTree
                        ? '${topLevel.length} 个单元 · 在阅读器中可逐级展开'
                        : '仅页码索引',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final chapter in topLevel)
              InkWell(
                onTap: chapter.hasPage
                    ? () => onJump(chapter.pageIndex!)
                    : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (chapter.children.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${chapter.children.length} 节',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (chapter.hasPage)
                        Text(
                          'P${chapter.pageIndex}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Text('解析失败', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            Text(message, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
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
