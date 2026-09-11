/// 教材目录浏览状态：加载、分类选择、搜索、排序。
library;

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../data/catalog_index.dart';
import '../data/catalog_repository.dart';
import '../models/category.dart';
import '../models/textbook.dart';
import 'settings_controller.dart';

class CatalogController extends ChangeNotifier {
  CatalogController(this._repository);

  final CatalogRepository _repository;

  bool _disposed = false;

  /// 释放后不再发通知。
  ///
  /// 目录加载与下载都是异步的，窗口关闭 / 热重启时它们可能还在飞。回调里即使
  /// 有 `mounted` 守卫也拦不住控制器本身 —— change notifier 一旦释放，
  /// 再 notifyListeners() 会在 debug 下直接断言失败。
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  CatalogIndex _index = CatalogIndex.empty;
  bool _loading = false;
  String? _error;
  CatalogProgress? _progress;

  CategoryNode? _selected;
  String _query = '';
  SortOrder _sortOrder = SortOrder.classification;

  CatalogIndex get index => _index;
  bool get isLoading => _loading;
  String? get error => _error;
  CatalogProgress? get progress => _progress;
  CategoryNode? get selected => _selected;
  String get query => _query;
  SortOrder get sortOrder => _sortOrder;

  bool get hasData => _index.bookCount > 0;
  bool get isSearching => _query.trim().isNotEmpty;

  /// 当前标题（用于顶栏）。
  String get currentTitle =>
      isSearching ? '搜索「${_query.trim()}」' : (_selected?.name ?? '全部教材');

  /// 当前要展示的教材列表。
  List<Textbook> get visibleBooks {
    if (isSearching) {
      final results = _index.search(_query);
      return _applySort(results);
    }
    final node = _selected;
    if (node == null) return _applySort(_index.books);
    return _applySort(_index.booksIn(node));
  }

  List<Textbook> _applySort(List<Textbook> books) {
    switch (_sortOrder) {
      case SortOrder.classification:
        // 索引里已按分类顺序排好，直接复用。
        return books;
      case SortOrder.title:
        return [...books]..sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.recentlyUpdated:
        return [...books]..sort((a, b) {
            final at = a.updateTime;
            final bt = b.updateTime;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
    }
  }

  /// 面包屑：从根到当前选中节点。
  List<CategoryNode> get breadcrumbs => _selected?.path ?? const [];

  Future<void> load({bool forceRefresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _safeNotify();

    try {
      // 先用缓存快速出首屏，再在后台检查平台版本，避免每次启动都等 40 MB 下载。
      final index = await _repository.load(
        forceRefresh: forceRefresh,
        onProgress: (progress) {
          _progress = progress;
          _safeNotify();
        },
      );
      // 重新拉取后整棵树是**新建的对象**，旧的 _selected 指向已废弃的节点。
      // 按 uniqueKey 在新树里找回同一个位置，避免选中态凭空丢失或错位。
      final previousKey = _selected?.uniqueKey;
      _index = index;
      if (previousKey != null) {
        _selected = _findByUniqueKey(index.root, previousKey);
      }
      _error = null;
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = '加载教材目录失败：$error';
    } finally {
      _loading = false;
      _progress = null;
      _safeNotify();
    }
  }

  void select(CategoryNode? node) {
    _selected = node;
    _query = '';
    _safeNotify();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _safeNotify();
  }

  void setSortOrder(SortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    _safeNotify();
  }

  CategoryNode? nodeById(String id) => _index.root.findById(id);

  /// 按 uniqueKey 在新树里找回节点（刷新后重新定位选中项用）。
  CategoryNode? _findByUniqueKey(CategoryNode root, String key) {
    for (final node in root.descendants) {
      if (node.uniqueKey == key) return node;
    }
    return null;
  }
}
