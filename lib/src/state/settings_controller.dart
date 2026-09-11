/// 界面偏好与登录凭据的状态。
library;

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../models/credentials.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._store) {
    _credentials = _store.readCredentials();
    _themeMode = _parseThemeMode(_store.readThemeMode());
    _sortOrder = SortOrder.fromId(_store.readSortOrder());
    _autoOpenNative = _store.readAutoOpenNative();
  }

  final SettingsStore _store;

  bool _disposed = false;

  /// 释放后不再发通知：写偏好是异步的，窗口关闭时可能还在飞。
  void _safeNotify() {
    if (_disposed) return;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late Credentials _credentials;
  late ThemeMode _themeMode;
  late SortOrder _sortOrder;
  late bool _autoOpenNative;

  Credentials get credentials => _credentials;
  ThemeMode get themeMode => _themeMode;
  SortOrder get sortOrder => _sortOrder;

  /// 用系统默认程序打开 PDF，而不是内置阅读器。
  bool get autoOpenNative => _autoOpenNative;

  bool get hasCredentials => !_credentials.isEmpty;
  bool get canSignRequests => _credentials.canSign;

  bool get credentialsExpired => _credentials.isExpired;

  /// 保存新凭据；传入空串表示退出登录。
  Future<void> saveCredentials(String rawInput) async {
    final parsed = parseCredentials(rawInput);
    _credentials = parsed;
    await _store.writeCredentials(parsed);
    _safeNotify();
  }

  Future<void> clearCredentials() async {
    _credentials = Credentials.empty;
    await _store.writeCredentials(Credentials.empty);
    _safeNotify();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _store.writeThemeMode(_themeModeId(mode));
    _safeNotify();
  }

  Future<void> setSortOrder(SortOrder order) async {
    _sortOrder = order;
    await _store.writeSortOrder(order.id);
    _safeNotify();
  }

  Future<void> setAutoOpenNative(bool value) async {
    _autoOpenNative = value;
    await _store.writeAutoOpenNative(value);
    _safeNotify();
  }

  static String _themeModeId(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _parseThemeMode(String id) => switch (id) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// 教材列表排序方式。
enum SortOrder {
  /// 按「学段 → 学科 → 版本 → 年级 → 册次」的天然分类顺序。
  classification('default', '分类顺序', Icons.account_tree_outlined),

  /// 按书名。
  title('title', '按书名', Icons.sort_by_alpha),

  /// 按平台更新时间倒序。
  recentlyUpdated('updated', '最近更新', Icons.update);

  const SortOrder(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static SortOrder fromId(String id) =>
      SortOrder.values.firstWhere((o) => o.id == id, orElse: () => classification);
}
