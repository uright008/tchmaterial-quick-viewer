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

  final Map<String, DownloadTask> _tasks = {};

  /// 已解析过的详情（内存缓存，避免来回翻页重复请求）。
  final Map<String, TextbookDetail> _details = {};

  CatalogRepository get repository => _repository;

  List<DownloadTask> get tasks => _tasks.values.toList();

  List<DownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isActive).toList();

  DownloadTask? taskFor(String textbookId) => _tasks[textbookId];

  bool isDownloaded(String textbookId) {
    final task = _tasks[textbookId];
    return task?.status == DownloadStatus.done && task?.localFile != null;
  }

  /// 已缓存的详情（含章节目录）。
  TextbookDetail? cachedDetail(String textbookId) => _details[textbookId];

  /// 解析教材详情，带内存缓存。
  Future<TextbookDetail> resolveDetail(
    Textbook textbook, {
    bool withChapters = true,
  }) async {
    final cached = _details[textbook.id];
    if (cached != null && (!withChapters || cached.chapters.isNotEmpty)) {
      return cached;
    }
    final detail = await _repository.fetchDetail(
      textbook.id,
      withChapters: withChapters,
    );
    _details[textbook.id] = detail;
    notifyListeners();
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
      _tasks[textbook.id] = task;
      notifyListeners();
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
      while (existingTask.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final file = existingTask.localFile;
      if (file != null) return file;
    }

    final task = DownloadTask(textbook: textbook, file: file);
    _tasks[textbook.id] = task;
    task.status = DownloadStatus.running;
    notifyListeners();
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
          notifyListeners();
          onUpdate?.call(task);
        },
      );
      task.localFile = local;
      task.status = DownloadStatus.done;
      notifyListeners();
      onUpdate?.call(task);
      return local;
    } on DownloadCancelled {
      task.status = DownloadStatus.cancelled;
      notifyListeners();
      onUpdate?.call(task);
      rethrow;
    } on ApiException catch (error) {
      task.status = DownloadStatus.failed;
      task.error = error.message;
      notifyListeners();
      onUpdate?.call(task);
      rethrow;
    } catch (error) {
      task.status = DownloadStatus.failed;
      task.error = '下载失败：$error';
      notifyListeners();
      onUpdate?.call(task);
      rethrow;
    }
  }

  void dismiss(String textbookId) {
    final task = _tasks[textbookId];
    if (task != null && !task.isActive) {
      _tasks.remove(textbookId);
      notifyListeners();
    }
  }

  void clearFinished() {
    _tasks.removeWhere((_, task) => !task.isActive);
    notifyListeners();
  }

  /// 本地已下载的 PDF。
  List<File> get offlineFiles => _repository.cache.downloadedBooks();

  int get cacheSizeBytes => _repository.cache.downloadedBytes();

  /// 教材文件的落盘目录（用户可见，可直接交给第三方阅读器打开）。
  String get downloadFolderPath => _repository.cache.booksDir.path;

  Future<void> deleteLocal(File file) async {
    if (file.existsSync()) await file.delete();
    final fileName = file.uri.pathSegments.last;
    _tasks.removeWhere(
      (_, task) => task.localFile?.uri.pathSegments.last == fileName,
    );
    notifyListeners();
  }

  Future<void> clearCatalogCache() => _repository.cache.clearCatalog();
}
