/// 平台能力判定。
library;

import 'package:flutter/foundation.dart';

/// 是否支持「用系统默认程序打开本地文件」。
///
/// 桌面端 `url_launcher` 能直接把 `file://` 交给系统处理；Android 从 API 24 起
/// 会抛 `FileUriExposedException`（`file://` 不允许跨应用传递），必须自己配
/// FileProvider 换成 `content://`。本应用内置了 PDF 阅读器，移动端并不缺这个
/// 能力，所以直接不暴露入口，而不是给用户留一个点了必报错的按钮。
bool get supportsExternalFileOpen {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows =>
      true,
    _ => false,
  };
}
