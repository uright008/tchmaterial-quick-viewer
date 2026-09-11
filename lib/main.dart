/// 国家中小学智慧教育平台 · 电子课本查看器
///
/// 数据与签名规则参考开源项目 happycola233/tchMaterial-parser。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/data/local_store.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 打开持久化存储后再渲染首帧，避免界面先闪一下空状态。
    final settingsStore = await SettingsStore.open();
    final cacheStore = await CacheStore.open();

    runApp(
      TchMaterialApp(settingsStore: settingsStore, cacheStore: cacheStore),
    );
  } catch (error, stackTrace) {
    // 没有这层兜底的话，存储初始化失败（Web 无 path_provider 实现、目录不可写、
    // 插件缺失等）会直接把启动异常抛在 runApp 之前 —— 用户看到的是一片纯白，
    // 连「出了什么事」都不知道。这里至少把原因和平台讲清楚。
    debugPrint('启动失败: $error\n$stackTrace');
    runApp(_StartupFailureApp(error: error));
  }
}

/// 存储初始化失败时的兜底界面。
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 44),
                  const SizedBox(height: 16),
                  const Text(
                    '无法启动',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isWeb
                        ? 'Web 平台不受支持：本应用依赖本地文件系统来缓存教材，'
                            '而浏览器环境没有对应的存储实现。\n\n'
                            '请改用桌面端（Windows / macOS / Linux）'
                            '或 Android 构建。'
                        : '初始化本地存储失败，可能是应用目录不可写或插件缺失。',
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '$error',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
