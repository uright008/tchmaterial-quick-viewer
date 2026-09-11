/// 下载与本地书架状态。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/catalog_repository.dart';
import '../models/textbook.dart';

enum DownloadStatus { queued, running, done, failed, cancelled }

/// 一次教材下载的进度。
class DownloadTask {
  DownloadTask({required this.textbook, required this.file});

  final Textbook textbook;
  final ResourceFile file;

  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int? total;
  File? localFile;
  String? error;

  final CancelToken _cancelToken = CancelToken();

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.running;

  /// 0..1，平台未返回 `Content-Length` 时为 null（UI 改用不确定进度条）。
  double? get progress {
    final totalBytes = total;
    if (totalBytes == null || totalBytes <= 0) return null;
    return (received / totalBytes).clamp(0.0, 1.0);
  }

  String get progressLabel {
    final totalBytes = total;
    if (totalBytes == null || totalBytes <= 0) {
      return received > 0 ? _formatBytes(received) : '准备中…';
    }
    return '${_formatBytes(received)} / ${_formatBytes(totalBytes)}';
  }

  void cancel() => _cancelToken.cancel();

  CancelToken get cancelToken => _cancelToken;

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

class LibraryController extends ChangeNotifier {
  LibraryController(this._repository);

  final CatalogRepository _repository;

  bool _disposed = false;

  /// 释放后不再发通知（见 CatalogController 里同样的说明）。
  void _safeNotify() {
    if (_disposed) return;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  final Map<String, DownloadTask> _tasks = {};

  /// 已解析过的详情（内存缓存，避免来回翻页重复请求）。
  final Map<String, TextbookDetail> _details = {};

  /// 已经**尝试过带章节**加载的教材。
  ///
  /// 平台约 18% 的教材本来就没有章节目录。只判断 `chapters.isEmpty` 的话，
  /// 这类书每次打开详情/阅读页都会重新发一轮请求（含 ebook_mapping 下载与
  /// tree 查询），白等一次往返。
  final Set<String> _chaptersAttempted = {};

  CatalogRepository get repository => _repository;

  List<DownloadTask> get tasks => _tasks.values.toList();

  List<DownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isActive).toList();

  DownloadTask? taskFor(String textbookId) => _tasks[textbookId];

  bool isDownloaded(String textbookId) {
    final task = _tasks[textbookId];
    return task?.status == DownloadStatus.done && task?.localFile != null;
  }

  /// 解析教材详情，带内存缓存。
  Future<TextbookDetail> resolveDetail(
    Textbook textbook, {
    bool withChapters = true,
  }) async {
    final cached = _details[textbook.id];
    if (cached != null) {
      if (!withChapters) return cached;
      // 有目录，或已经试过且确实没有目录 —— 都直接复用。
      if (cached.chapters.isNotEmpty ||
          _chaptersAttempted.contains(textbook.id)) {
        return cached;
      }
    }
    final detail = await _repository.fetchDetail(
      textbook.id,
      withChapters: withChapters,
    );
    _details[textbook.id] = detail;
    if (withChapters) _chaptersAttempted.add(textbook.id);
    _safeNotify();
    return detail;
  }

  /// 确保教材正文已落盘，返回本地文件。
  ///
  /// 已有本地文件时直接复用，不会重复下载。
  Future<File> ensureLocal(
    Textbook textbook,
    ResourceFile file, {
    void Function(DownloadTask task)? onUpdate,
  }) async {
    final existing = _repository.localFileFor(file.suggestedFileName);
    if (existing != null) {
      final task = _tasks[textbook.id] ??
          DownloadTask(textbook: textbook, file: file);
      task.status = DownloadStatus.done;
      task.localFile = existing;
      task.total = existing.lengthSync();
      task.received = task.total!;
      _invalidateDiskCache();
      _tasks[textbook.id] = task;
      _safeNotify();
      onUpdate?.call(task);
      return existing;
    }
    return download(textbook, file, onUpdate: onUpdate);
  }

  Future<File> download(
    Textbook textbook,
    ResourceFile file, {
    void Function(DownloadTask task)? onUpdate,
  }) async {
    final existingTask = _tasks[textbook.id];
    if (existingTask != null && existingTask.isActive) {
      // 同一个教材已在下载中，等待既有任务而不是叠加第二个请求。
      //
      // 必须区分终态：原实现只判断 localFile == null 就往下走新建任务，
      // 于是用户点了「取消」，200 ms 后立刻又自动开下一个 —— 取消形同虚设；
      // 失败时也会静默重试一次，请求数凭空翻倍。这里改成如实上报。
      var waited = Duration.zero;
      const tick = Duration(milliseconds: 200);
      const maxWait = Duration(minutes: 30);
      while (existingTask.isActive && waited < maxWait) {
        await Future<void>.delayed(tick);
        waited += tick;
      }

      final file = existingTask.localFile;
      if (file != null) return file;
      if (existingTask.status == DownloadStatus.cancelled) {
        throw const DownloadCancelled();
      }
      if (existingTask.status == DownloadStatus.failed) {
        throw ApiException(existingTask.error ?? '下载失败');
      }
      throw ApiException('等待既有下载任务超时。');
    }

    final task = DownloadTask(textbook: textbook, file: file);
    _tasks[textbook.id] = task;
    task.status = DownloadStatus.running;
    _safeNotify();
    onUpdate?.call(task);

    // 进度通知节流：平台按块推送数据，20 MB 的教材会产生几百次回调。
    // 每次都 notifyListeners() 会让订阅方（书架页、阅读页）高频重建，
    // 限到 ~10 Hz 对肉眼已经完全够用。
    var lastNotifiedAt = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      final local = await _repository.download(
        url: file.url,
        fileName: file.suggestedFileName,
        cancelToken: task.cancelToken,
        onProgress: (received, total) {
          task.received = received;
          task.total = total ?? task.total;
          final now = DateTime.now();
          if (now.difference(lastNotifiedAt).inMilliseconds < 100) return;
          lastNotifiedAt = now;
          _safeNotify();
          onUpdate?.call(task);
        },
      );
      task.localFile = local;
      task.status = DownloadStatus.done;
      _invalidateDiskCache();
      _safeNotify();
      onUpdate?.call(task);
      return local;
    } on DownloadCancelled {
      task.status = DownloadStatus.cancelled;
      _safeNotify();
      onUpdate?.call(task);
      rethrow;
    } on ApiException catch (error) {
      task.status = DownloadStatus.failed;
      task.error = error.message;
      _safeNotify();
      onUpdate?.call(task);
      rethrow;
    } catch (error) {
      task.status = DownloadStatus.failed;
      task.error = '下载失败：$error';
      _safeNotify();
      onUpdate?.call(task);
      rethrow;
    }
  }

  void dismiss(String textbookId) {
    final task = _tasks[textbookId];
    if (task != null && !task.isActive) {
      _tasks.remove(textbookId);
      _safeNotify();
    }
  }

  void clearFinished() {
    _tasks.removeWhere((_, task) => !task.isActive);
    _safeNotify();
  }

  /// 本地已下载的 PDF。
  List<File> get offlineFiles =>
      _offlineFilesCache ??= _repository.cache.downloadedBooks();

  int get cacheSizeBytes =>
      _cacheSizeCache ??= _repository.cache.downloadedBytes();

  /// 教材文件的落盘目录（用户可见，可直接交给第三方阅读器打开）。
  String get downloadFolderPath => _repository.cache.booksDir.path;

  // 磁盘扫描结果做缓存。
  //
  // 书架页与设置页都常驻（IndexedStack），又都 watch 本控制器；而下载进度
  // 会以约 10 Hz 通知。若每次都同步递归扫一遍下载目录，下载时就是每秒几十次
  // 目录遍历 —— 正是「下载的时候界面发卡」的来源。
  List<File>? _offlineFilesCache;
  int? _cacheSizeCache;

  void _invalidateDiskCache() {
    _offlineFilesCache = null;
    _cacheSizeCache = null;
  }

  Future<void> deleteLocal(File file) async {
    if (file.existsSync()) await file.delete();
    _invalidateDiskCache();
    final fileName = file.uri.pathSegments.last;
    _tasks.removeWhere(
      (_, task) => task.localFile?.uri.pathSegments.last == fileName,
    );
    _safeNotify();
  }

  Future<void> clearCatalogCache() => _repository.cache.clearCatalog();
}
