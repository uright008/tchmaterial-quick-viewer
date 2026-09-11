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
    notifyListeners();

    try {
      // 先用缓存快速出首屏，再在后台检查平台版本，避免每次启动都等 40 MB 下载。
      final index = await _repository.load(
        forceRefresh: forceRefresh,
        onProgress: (progress) {
          _progress = progress;
          notifyListeners();
        },
      );
      _index = index;
      _error = null;
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = '加载教材目录失败：$error';
    } finally {
      _loading = false;
      _progress = null;
      notifyListeners();
    }
  }

  void select(CategoryNode? node) {
    _selected = node;
    _query = '';
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void clearQuery() {
    if (_query.isEmpty) return;
    _query = '';
    notifyListeners();
  }

  void setSortOrder(SortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    notifyListeners();
  }

  CategoryNode? nodeById(String id) => _index.root.findById(id);
}
