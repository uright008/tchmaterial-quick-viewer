/// 书架页：下载进度与本地已缓存教材。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../core/file_actions.dart';
import '../../state/library_controller.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final tasks = library.tasks;
    final files = library.offlineFiles;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          if (tasks.any((t) => !t.isActive))
            TextButton.icon(
              onPressed: library.clearFinished,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('清除已结束'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (tasks.isNotEmpty) ...[
            Text('下载任务', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TaskCard(task: task),
              ),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Text('已缓存教材', style: theme.textTheme.titleMedium),
              const SizedBox(width: 10),
              Text(
                '${files.length} 个文件 · ${_formatBytes(library.cacheSizeBytes)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (supportsExternalFileOpen)
                TextButton.icon(
                  onPressed: () =>
                      launchUrl(Uri.file(library.downloadFolderPath)),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('打开文件夹'),
                ),
            ],
          ),
          // 把落盘位置明写出来：教材是放在用户可见的下载目录里的，
          // 方便直接用第三方阅读器打开，而不是埋在应用私有目录。
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              library.downloadFolderPath,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (files.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '还没有下载任何教材',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '在「浏览」里打开一本教材即可在线阅读或下载',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            for (final file in files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OfflineFileCard(file: file),
              ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (task.status) {
      DownloadStatus.queued => '排队中',
      DownloadStatus.running => '下载中',
      DownloadStatus.done => '已完成',
      DownloadStatus.failed => '失败',
      DownloadStatus.cancelled => '已取消',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.textbook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(status: status, task: task),
                if (task.isActive) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '取消',
                    iconSize: 18,
                    onPressed: task.cancel,
                    icon: const Icon(Icons.close),
                  ),
                ] else if (task.status != DownloadStatus.done) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '移除',
                    iconSize: 18,
                    onPressed: () =>
                        context.read<LibraryController>().dismiss(task.textbook.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            if (task.isActive) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: task.progress),
              const SizedBox(height: 6),
              Text(
                task.progressLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 8),
              Text(
                task.error!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.task});

  final String status;
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = task.status == DownloadStatus.failed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isError
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _OfflineFileCard extends StatelessWidget {
  const _OfflineFileCard({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = file.uri.pathSegments.last;
    final modified = file.lastModifiedSync();
    final size = _formatBytes(file.lengthSync());

    return Card(
      child: ListTile(
        leading: Icon(
          name.toLowerCase().endsWith('.pdf')
              ? Icons.picture_as_pdf
              : Icons.audiotrack,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          name.replaceAll(RegExp(r'\.(pdf|mp3|m4a)$'), ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$size · ${modified.year}-${_pad(modified.month)}-${_pad(modified.day)}',
          style: theme.textTheme.labelSmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (supportsExternalFileOpen)
              IconButton(
                tooltip: '用系统程序打开',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _run(context, openFileExternally(file)),
              ),
            if (supportsSharing)
              IconButton(
                tooltip: '分享',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _run(context, shareFile(file)),
              ),
            IconButton(
              tooltip: '删除本地文件',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  context.read<LibraryController>().deleteLocal(file),
            ),
          ],
        ),
      ),
    );
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  /// 把结果统一反馈给用户：成功就闭嘴，失败说明原因。
  static Future<void> _run(
    BuildContext context,
    Future<FileActionResult> action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await action;
    if (result == FileActionResult.ok) return;
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
