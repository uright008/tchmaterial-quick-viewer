// ignore_for_file: avoid_print

/// 用真实平台数据校验分类索引。
///
/// 依赖应用跑过一次后留下的目录缓存；缓存不存在时自动跳过，因此在没有网络、
/// 没有缓存的机器上跑 `flutter test` 也不会失败。
///
/// 这个用例存在的意义：真实分类树里平台**复用 tag_id**（80 个「一年级」节点
/// 共用一个 id），单靠构造出来的小样例很容易漏掉这类问题。这里的父子计数
/// 不变量能在真实数据上把这类错误直接暴露出来。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/data/catalog_index.dart';
import 'package:tchmaterial_quick_viewer/src/models/category.dart';
import 'package:tchmaterial_quick_viewer/src/models/textbook.dart';

/// 应用支持目录下的应用标识（与 pubspec 里的 org / project name 对应）。
const String _appId = 'com.tchviewer.tchmaterial_quick_viewer';
const String _subDir = 'tchmaterial_viewer';

/// 定位目录缓存文件。
///
/// **不能写死绝对路径**：仓库是公开的，写死就只在一台机器上成立。这里按平台
/// 推导出 `getApplicationSupportDirectory()` 的常见落点，另外允许用环境变量
/// `TCHVIEWER_CATALOG` 显式指定（CI 或其他机器上跑集成用例时用得上）。
/// 都找不到就返回 null，调用方跳过用例。
String? _findCatalogCache() {
  final override = Platform.environment['TCHVIEWER_CATALOG'];
  if (override != null && override.isNotEmpty && File(override).existsSync()) {
    return override;
  }

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return null;

  final candidates = <String>[
    if (Platform.isLinux)
      '$home/.local/share/$_appId/$_subDir/catalog_v1.json',
    if (Platform.isMacOS)
      '$home/Library/Application Support/$_appId/$_subDir/catalog_v1.json',
    if (Platform.isWindows)
      '${Platform.environment['APPDATA']}/$_appId/$_subDir/catalog_v1.json',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

CategoryNode _decodeNode(List<dynamic> raw) {
  final node = CategoryNode(
    id: raw[0] as String,
    name: raw[1] as String,
    dimensionId: raw[2] as String?,
  );
  for (final child in raw[3] as List) {
    node.children.add(_decodeNode(child as List));
  }
  return node;
}

void main() {
  final cachePath = _findCatalogCache();
  if (cachePath == null) {
    test('真实目录缓存不存在，跳过', () {},
        skip: '未找到目录缓存；先运行一次应用，或设置 TCHVIEWER_CATALOG');
    return;
  }
  final cacheFile = File(cachePath);

  late CatalogIndex index;

  setUpAll(() {
    final payload =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final root = _decodeNode(payload['tree'] as List);
    root.linkChildren();
    final books = (payload['books'] as List)
        .cast<Map<String, dynamic>>()
        .map(Textbook.fromJson)
        .toList();
    index = buildCatalogIndex(
      root: root,
      books: books,
      version: (payload['version'] as num?)?.toInt() ?? 0,
    );
  });

  test('教材总数与根计数一致', () {
    expect(index.bookCount, greaterThan(3000));
    final rootCount =
        index.root.children.fold<int>(0, (sum, c) => sum + c.totalBookCount);
    // 未分类节点也是 root 的子节点，因此这里应正好等于总数。
    expect(rootCount, index.bookCount);
    print('教材总数：${index.bookCount}，'
        '未分类：${index.uncategorizedCount}');
  });

  test('每个子节点的总数不超过父节点（兄弟分支不串味）', () {
    final violations = <String>[];

    void check(CategoryNode node) {
      for (final child in node.children) {
        if (child.totalBookCount > node.totalBookCount) {
          violations.add(
            '${node.displayPath}(${node.totalBookCount}) → '
            '${child.name}(${child.totalBookCount})',
          );
        }
        check(child);
      }
    }

    check(index.root);
    expect(violations, isEmpty,
        reason: '出现子节点比父节点还多的情况，说明教材被归到了错误的节点：'
            '${violations.take(5).join('; ')}');
  });

  test('节点的直接教材数不超过其总数', () {
    for (final node in index.root.descendants) {
      expect(node.directBookCount, lessThanOrEqualTo(node.totalBookCount),
          reason: node.displayPath);
    }
  });

  test('所有教材都被归入某个节点，没有丢失', () {
    // 每本书至少应能在「未分类」或某个分类节点里被找到。
    final seen = <String>{};
    for (final entry in index.booksByNode.entries) {
      for (final book in entry.value) {
        // 只统计叶子归属，避免把祖先节点的累计值也算进来。
        seen.add(book.id);
      }
    }
    expect(seen.length, index.bookCount);
  });

  test('同名维度节点在不同父节点下各自独立计数', () {
    // 「一年级」在真实树里出现 80 次且共用同一个 tag_id。
    final occurrences = index.root.findAllById('e7bbd296-0590-11ed-9c79-92fc3b3249d5');
    expect(occurrences.length, greaterThan(10),
        reason: '平台的年级维度应在多个版本下重复出现');

    final counts = <String, int>{
      for (final node in occurrences) node.uniqueKey: node.totalBookCount,
    };
    // 每个实例都必须有自己的键，否则计数会被合并成一个。
    expect(counts.length, occurrences.length,
        reason: 'uniqueKey 必须能区分同 id 的不同实例');

    // 至少要有两个实例的计数不同，才算真正按分支分开统计了。
    expect(counts.values.toSet().length, greaterThan(1),
        reason: '所有同名节点计数完全相同，说明仍在按 id 合并');
  });

  test('平台分类树覆盖到 6 个学段', () {
    final stages = index.root.children
        .expand((c) => c.children)
        .where((n) => n.dimensionId == 'zxxxd')
        .map((n) => n.name)
        .toSet();
    print('学段：$stages');
    expect(stages, containsAll([
      '小学',
      '初中',
      '高中',
    ]));
    expect(stages.length, greaterThanOrEqualTo(6));
  });

  test('搜索能命中真实教材', () {
    final results = index.search('数学 一年级');
    expect(results, isNotEmpty);
    for (final book in results.take(10)) {
      expect(book.dimensions['zxxxk'], '数学');
    }
    print('「数学 一年级」命中 ${results.length} 本');
  });

  test('打印各学段教材数，便于人工核对', () {
    for (final top in index.root.children) {
      for (final stage in top.children) {
        print('  ${stage.name}: ${stage.totalBookCount}');
      }
    }
    print('  未分类: ${index.uncategorizedCount}');
  });
}
