/// 「用系统程序打开」与「分享」的统一入口。
///
/// 各平台的机制不一样，这里把它们收敛成一个 API，调用方不需要关心平台差异：
///
/// * **Android** —— `file://` 从 API 24 起不允许跨应用传递，必须换成
///   FileProvider 提供的 `content://` URI。这件事只能在原生侧做，所以走
///   MethodChannel（见 `MainActivity.kt`）。分享交给 `share_plus`（它会把文件
///   复制进自己的 share cache，并且不申请任何多余权限）。
/// * **iOS / macOS / Windows / Linux** —— 直接把路径交给系统即可：
///   桌面端用 `url_launcher` 打开，iOS 用 `share_plus` 的分享面板。
///
/// 注意：Android 上分享**不需要**复制文件，`share_plus` 自己处理；
/// 而「打开」走的是我们自己的 FileProvider，读的是原文件、不产生副本。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 与 `MainActivity.kt` 里的 channel 名保持一致。
const String _androidChannel = 'tchmaterial_quick_viewer/file_actions';

/// 操作结果，便于 UI 给出准确提示而不是笼统的「失败」。
enum FileActionResult {
  /// 已交给系统处理。
  ok,

  /// 当前平台不支持该操作。
  unsupported,

  /// 文件不存在（多半是还没下载完成）。
  fileMissing,

  /// 系统里没有能处理它的应用。
  noHandler,

  /// 其它失败。
  failed,
}

extension FileActionResultMessage on FileActionResult {
  String get message => switch (this) {
        FileActionResult.ok => '已交给系统处理',
        FileActionResult.unsupported => '当前平台不支持该操作',
        FileActionResult.fileMissing => '文件不存在，请先下载',
        FileActionResult.noHandler => '没有找到可以打开它的应用',
        FileActionResult.failed => '操作失败',
      };
}

String _mimeTypeOf(File file) {
  final name = file.path.toLowerCase();
  if (name.endsWith('.pdf')) return 'application/pdf';
  if (name.endsWith('.mp3')) return 'audio/mpeg';
  if (name.endsWith('.m4a')) return 'audio/mp4';
  if (name.endsWith('.wav')) return 'audio/wav';
  return 'application/octet-stream';
}

/// 当前平台是否支持把文件交给外部程序打开。
bool get supportsExternalFileOpen {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    // Android 走我们自己实现的 FileProvider + ACTION_VIEW。
    TargetPlatform.android ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows =>
      true,
    _ => false,
  };
}

/// 当前平台是否支持分享文件。
bool get supportsSharing {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows =>
      true,
    _ => false,
  };
}

/// 用系统里的其它程序打开 [file]。
Future<FileActionResult> openFileExternally(File file) async {
  if (!file.existsSync()) return FileActionResult.fileMissing;
  if (!supportsExternalFileOpen) return FileActionResult.unsupported;

  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final handled = await _androidChannel_().invokeMethod<bool>(
        'openWith',
        {'path': file.path, 'mimeType': _mimeTypeOf(file)},
      );
      return handled == true
          ? FileActionResult.ok
          : FileActionResult.noHandler;
    }

    // 桌面端：url_launcher 能把 file:// 交给系统默认程序。
    final launched = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    return launched ? FileActionResult.ok : FileActionResult.noHandler;
  } on PlatformException catch (error) {
    debugPrint('openFileExternally 失败: $error');
    return FileActionResult.failed;
  } catch (error) {
    debugPrint('openFileExternally 失败: $error');
    return FileActionResult.failed;
  }
}

MethodChannel _androidChannel_() =>
    const MethodChannel(_androidChannel);

/// 调起系统分享面板把 [file] 分享出去。
///
/// `share_plus` 在 Android 上会把文件复制进它自己的 share cache —— 因为它的
/// FileProvider 只开放了那一个目录。教材动辄 20 MB，所以这里如实告知调用方
/// 可能会有一次复制，别在 UI 上表现得像瞬时完成。
Future<FileActionResult> shareFile(File file, {String? subject}) async {
  if (!file.existsSync()) return FileActionResult.fileMissing;
  if (!supportsSharing) return FileActionResult.unsupported;

  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: _mimeTypeOf(file))],
        subject: subject,
      ),
    );
    // 用户取消不算失败。
    return result.status == ShareResultStatus.unavailable
        ? FileActionResult.noHandler
        : FileActionResult.ok;
  } catch (error) {
    debugPrint('shareFile 失败: $error');
    return FileActionResult.failed;
  }
}
