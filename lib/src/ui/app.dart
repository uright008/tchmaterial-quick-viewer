/// 应用入口与依赖装配。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/catalog_repository.dart';
import '../data/local_store.dart';
import '../state/catalog_controller.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import 'home_page.dart';
import 'theme.dart';

class TchMaterialApp extends StatefulWidget {
  const TchMaterialApp({
    super.key,
    required this.settingsStore,
    required this.cacheStore,
  });

  final SettingsStore settingsStore;
  final CacheStore cacheStore;

  @override
  State<TchMaterialApp> createState() => _TchMaterialAppState();
}

class _TchMaterialAppState extends State<TchMaterialApp> {
  late final SettingsController _settings;
  late final PlatformApi _api;
  late final CatalogRepository _repository;
  late final CatalogController _catalog;
  late final LibraryController _library;

  @override
  void initState() {
    super.initState();
    _settings = SettingsController(widget.settingsStore);

    // 每次请求都现读凭据，用户改完设置后立即生效，无需重建 API 客户端。
    _api = PlatformApi(credentials: () => _settings.credentials);

    _repository = CatalogRepository(api: _api, cache: widget.cacheStore);
    _catalog = CatalogController(_repository);
    _library = LibraryController(_repository);

    // 把持久化的排序偏好灌进目录控制器。
    // 原来这个值只存在 SettingsController 里，启动时没人同步过去，于是设置里
    // 选好的「按书名」重启后自动变回「分类顺序」。
    _catalog.setSortOrder(_settings.sortOrder);
  }

  @override
  void dispose() {
    _api.close();
    _catalog.dispose();
    _library.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _catalog),
        ChangeNotifierProvider.value(value: _library),
        Provider<PlatformApi>.value(value: _api),
        Provider<CatalogRepository>.value(value: _repository),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) => MaterialApp(
          title: '国家中小学智慧教育平台 · 教材查看器',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: settings.themeMode,
          home: const HomePage(),
        ),
      ),
    );
  }
}
