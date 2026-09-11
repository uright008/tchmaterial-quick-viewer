/// 国家中小学智慧教育平台 · 电子课本查看器
///
/// 数据与签名规则参考开源项目 happycola233/tchMaterial-parser。
library;

import 'package:flutter/material.dart';

import 'src/data/local_store.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 打开持久化存储后再渲染首帧，避免界面先闪一下空状态。
  final settingsStore = await SettingsStore.open();
  final cacheStore = await CacheStore.open();

  runApp(
    TchMaterialApp(settingsStore: settingsStore, cacheStore: cacheStore),
  );
}
