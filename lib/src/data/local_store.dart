/// 本地持久化：登录凭据、界面偏好，以及教材目录缓存。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/credentials.dart';

/// 应用偏好（用 `shared_preferences` 保存）。
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  static const _kCredentials = 'credentials_v1';
  static const _kThemeMode = 'theme_mode';
  static const _kSortOrder = 'sort_order';
  static const _kAutoOpenNative = 'auto_open_native';

  Credentials readCredentials() {
    final raw = _prefs.getString(_kCredentials);
    if (raw == null || raw.isEmpty) return Credentials.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Credentials.fromJson(decoded);
    } on FormatException {
      // 旧版本写坏的数据直接忽略，等同未登录。
    }
    return Credentials.empty;
  }

  Future<void> writeCredentials(Credentials credentials) async {
    if (credentials.isEmpty) {
      await _prefs.remove(_kCredentials);
      return;
    }
    await _prefs.setString(_kCredentials, jsonEncode(credentials.toJson()));
  }

  /// `system` / `light` / `dark`
  String readThemeMode() => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> writeThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

  /// `default` / `title` / `updated`
  String readSortOrder() => _prefs.getString(_kSortOrder) ?? 'default';
  Future<void> writeSortOrder(String order) =>
      _prefs.setString(_kSortOrder, order);

  bool readAutoOpenNative() => _prefs.getBool(_kAutoOpenNative) ?? false;
  Future<void> writeAutoOpenNative(bool value) =>
      _prefs.setBool(_kAutoOpenNative, value);
}

/// 磁盘缓存与下载目录。
///
/// 两类数据分开存放：
///
/// * **目录缓存**（约 24 MB 的 JSON）是纯内部数据，放在应用支持目录；
/// * **下载的教材**尽量放到系统的「下载」目录下，而不是埋在
///   `~/.local/share/<app-id>/` 这种没人找得到的地方。
///
/// 实际落点按平台不同（**这一点必须和各平台的文件共享配置对齐**，
/// 详见 `android/app/src/main/res/xml/tch_file_paths.xml`）：
///
/// | 平台 | 落点 | 用户可见性 |
/// |---|---|---|
/// | Linux / macOS / Windows | `~/Downloads/tchMaterial/` | 可见 |
/// | Android | `<externalFilesDir>/Download/tchMaterial/`，即 `Android/data/<pkg>/files/Download/tchMaterial/` | 应用专属；Android 11+ 分区存储下文件管理器通常进不去，只能靠系统分享导出 |
/// | iOS | 沙盒内的 `Downloads/` | 沙盒内，需经分享或「文件」App 导出 |
///
/// 注意 Android **不是**返回 null：`getDownloadsPath()` 实际返回
/// `getExternalFilesDirs(DIRECTORY_DOWNLOADS)`；只有设备没有外部存储时才回退到
/// 应用内部支持目录。两条分支都要能被 FileProvider 覆盖。
class CacheStore {
  CacheStore._(this.root, this.booksDir, this._legacyBooksDir);

  /// 应用私有目录，存放目录缓存等内部数据。
  final Directory root;

  /// 教材文件落盘位置（对用户可见）。
  final Directory booksDir;

  /// 旧版本的下载目录，仅用于一次性迁移。
  final Directory? _legacyBooksDir;

  static const String folderName = 'tchMaterial';

  static Future<CacheStore> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/tchmaterial_viewer');
    if (!root.existsSync()) root.createSync(recursive: true);

    final legacy = Directory('${root.path}/books');

    Directory books;
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null && downloads.path.isNotEmpty) {
        books = Directory('${downloads.path}/$folderName');
      } else {
        books = legacy;
      }
    } catch (_) {
      // 平台不支持共享下载目录，退回应用私有目录。
      books = legacy;
    }
    if (!books.existsSync()) books.createSync(recursive: true);

    final store = CacheStore._(root, books, legacy);
    await store._migrateLegacyDownloads();
    return store;
  }

  /// 仅供测试：用指定目录构造，绕过 `path_provider`。
  ///
  /// 控制器层要能被测到就必须能造出 repository，而 `open()` 依赖平台插件。
  @visibleForTesting
  static CacheStore inDirectory(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final books = Directory('${dir.path}/books');
    if (!books.existsSync()) books.createSync(recursive: true);
    return CacheStore._(dir, books, null);
  }

  /// 把老版本留在应用私有目录里的教材搬到新位置，避免用户以为要重下。
  Future<void> _migrateLegacyDownloads() async {
    final legacy = _legacyBooksDir;
    if (legacy == null || identical(legacy.path, booksDir.path)) return;
    if (!legacy.existsSync()) return;

    try {
      for (final entity in legacy.listSync()) {
        if (entity is! File) continue;
        final target = File('${booksDir.path}/${entity.uri.pathSegments.last}');
        if (target.existsSync()) continue;
        await entity.rename(target.path);
      }
      // 搬空之后把旧目录删掉；还有残留就留着。
      if (legacy.listSync().isEmpty) legacy.deleteSync();
    } catch (_) {
      // 迁移失败不影响使用，下次启动再试。
    }
  }

  File get _catalogFile => File('${root.path}/catalog_v1.json');

  Future<void> writeCatalog(Map<String, dynamic> payload) async {
    await _catalogFile.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<Map<String, dynamic>?> readCatalog() async {
    if (!_catalogFile.existsSync()) return null;
    try {
      final decoded = jsonDecode(await _catalogFile.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 缓存损坏时静默重下，不影响使用。
    }
    return null;
  }

  Future<void> clearCatalog() async {
    if (_catalogFile.existsSync()) await _catalogFile.delete();
  }

  /// 已下载教材占用的字节数。
  int downloadedBytes() {
    if (!booksDir.existsSync()) return 0;
    var total = 0;
    for (final entity in booksDir.listSync(recursive: true)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  List<File> downloadedBooks() {
    if (!booksDir.existsSync()) return const [];
    return booksDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }
}
