/// 分类解析与索引构建测试。
///
/// 用例刻意复刻平台真实数据的三种形态：
///   * 标准 7 段 `tag_paths`（教材/学段/学科/版本/年级/册次）
///   * 8 段（多一层 `bknd` 年度维度）
///   * `tag_list` 为空的「教学指南」类资源，必须落到「未分类」
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/data/catalog_index.dart';
import 'package:tchmaterial_quick_viewer/src/models/category.dart';
import 'package:tchmaterial_quick_viewer/src/models/textbook.dart';

/// `hierarchies` 是「列表套 children」的容器结构。
List<dynamic> wrap(List<dynamic> children) => [
      {'children': children}
    ];

Map<String, dynamic> node(
  String id,
  String name,
  String dimension, {
  List<dynamic>? kids,
}) =>
    {
      'tag_id': id,
      'tag_name': name,
      'tag_dimension_id': dimension,
      'hierarchies': kids == null ? <dynamic>[] : wrap(kids),
    };

/// 平台分类树：电子教材 → 学段 → 学科 → 版本 → 年级 → 册次。
List<dynamic> platformHierarchies() => wrap([
      node('elec', '电子教材', '5036342742', kids: [
        node('primary', '小学', 'zxxxd', kids: [
          node('yuwen', '语文', 'zxxxk', kids: [
            node('tyb', '统编版', 'zxxbb', kids: [
              node('g1', '一年级', 'zxxnj', kids: [
                node('up1', '上册', 'zxxcc'),
                node('down1', '下册', 'zxxcc'),
              ]),
              node('g2', '二年级', 'zxxnj', kids: [
                node('up2', '上册', 'zxxcc'),
              ]),
            ]),
          ]),
          node('shuxue', '数学', 'zxxxk', kids: [
            node('rj', '人教版', 'zxxbb', kids: [
              node('g1b', '一年级', 'zxxnj', kids: [
                node('up_rj1', '上册', 'zxxcc'),
              ]),
            ]),
          ]),
        ]),
        node('junior', '初中', 'zxxxd', kids: [
          node('yuwen_j', '语文', 'zxxxk', kids: [
            node('tyb_j', '统编版', 'zxxbb', kids: [
              node('g7', '七年级', 'zxxnj', kids: [
                node('up7', '上册', 'zxxcc'),
              ]),
            ]),
          ]),
        ]),
      ]),
    ]);

/// 教材 id 的前缀固定是平台顶层容器 UUID，分类树里没有对应节点。
const String _rootContainer = 'f5261ccc-b7a5-42f4-b015-610dcec58c60';

Textbook book({
  required String id,
  required String title,
  List<String> path = const [],
  Map<String, String> dims = const {},
}) =>
    Textbook(
      id: id,
      title: title,
      tagIds: path.isEmpty ? const [] : [_rootContainer, ...path],
      dimensions: dims,
    );

/// 测试用按 id 取教材。测试树里 id 唯一；真实平台分类树会复用 id，因此
/// 生产代码的 `booksIn` 收的是节点对象而不是 id。
List<Textbook> booksIn(CatalogIndex index, String id) {
  final node = index.root.findById(id);
  return node == null ? const [] : index.booksIn(node);
}

void main() {
  late CategoryNode root;

  setUp(() {
    root = parseTagHierarchy(platformHierarchies());
  });

  group('parseTagHierarchy', () {
    test('顶层是平台的顶层分类', () {
      expect(root.children, hasLength(1));
      expect(root.children.first.name, '电子教材');
      expect(root.children.first.dimensionId, '5036342742');
    });

    test('逐层展开出完整路径', () {
      final leaf = root
          .findById('up1');
      expect(leaf, isNotNull);
      expect(
        leaf!.path.map((n) => n.name).toList(),
        ['全部教材', '电子教材', '小学', '语文', '统编版', '一年级', '上册'],
      );
    });

    test('子节点的 parent 反向指针被连好', () {
      final yuwen = root.findById('yuwen')!;
      expect(yuwen.parent?.name, '小学');
      expect(yuwen.parent?.parent?.name, '电子教材');
      expect(yuwen.depth, 3);
    });

    test('displayPath 跳过「全部教材」与「电子教材」两层容器', () {
      // 「电子教材」是平台的顶层容器（dimensionId = 5036342742），每本书都挂在
      // 它下面，路径文案里重复出现没有意义，因此和合成根一起被过滤掉。
      expect(
        root.findById('up1')!.displayPath,
        '小学 · 语文 · 统编版 · 一年级 · 上册',
      );
    });

    test('统计出的节点总数与维度分布正确', () {
      final all = root.descendants.toList();
      expect(all.where((n) => n.dimensionId == 'zxxxd').length, 2);
      expect(all.where((n) => n.dimensionId == 'zxxxk').length, 3);
      expect(all.where((n) => n.dimensionId == 'zxxcc').length, 5);
    });

    test('空输入不抛异常', () {
      expect(parseTagHierarchy(const []).children, isEmpty);
    });
  });

  group('buildCatalogIndex 分类归属', () {
    test('标准 7 段路径落到册次节点', () {
      final index = buildCatalogIndex(
        root: root,
        books: [
          book(
            id: 'b1',
            title: '义务教育教科书·语文一年级上册',
            path: const [
              'elec', 'primary', 'yuwen', 'tyb', 'g1', 'up1',
            ],
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '语文',
              'zxxbb': '统编版',
              'zxxnj': '一年级',
              'zxxcc': '上册',
            },
          ),
        ],
      );

      expect(index.bookCount, 1);
      expect(booksIn(index, 'up1'), hasLength(1));
      // 祖先节点也应能看到这本教材。
      expect(booksIn(index, 'g1'), hasLength(1));
      expect(booksIn(index, 'yuwen'), hasLength(1));
      expect(booksIn(index, 'primary'), hasLength(1));
      expect(booksIn(index, 'elec'), hasLength(1));
      // 兄弟分支不受影响。
      expect(booksIn(index, 'down1'), isEmpty);
      expect(booksIn(index, 'shuxue'), isEmpty);
    });

    test('8 段路径（多一层年度维度）仍能落到底', () {
      // 「年度」节点不在分类树里，下钻应停在能到达的最深节点。
      final index = buildCatalogIndex(
        root: root,
        books: [
          book(
            id: 'b2',
            title: '英语三年级下册',
            path: const [
              'elec', 'primary', 'yuwen', 'tyb', '2024', 'g1', 'up1',
            ],
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '语文',
              'zxxbb': '统编版',
              'zxxnj': '一年级',
              'zxxcc': '上册',
            },
          ),
        ],
      );

      // 走到 tyb 后 '2024' 找不到，改用维度名继续下钻，比停在 tyb 更深。
      final placed = booksIn(index, 'up1');
      expect(placed, hasLength(1));
      expect(placed.first.id, 'b2');
    });

    test('tag_paths 为空但 tag_list 完整时用维度名归类', () {
      final index = buildCatalogIndex(
        root: root,
        books: [
          book(
            id: 'b3',
            title: '数学一年级上册',
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '数学',
              'zxxbb': '人教版',
              'zxxnj': '一年级',
              'zxxcc': '上册',
            },
          ),
        ],
      );

      final placed = booksIn(index, 'up_rj1');
      expect(placed, hasLength(1));
      expect(placed.first.id, 'b3');
      // 不能串到语文分支下的同名「一年级/上册」。
      expect(booksIn(index, 'up1'), isEmpty);
    });

    test('维度完全为空的教学指南落到「未分类」', () {
      final index = buildCatalogIndex(
        root: root,
        books: [
          book(id: 'g1', title: '义务教育信息科技课程教学指南 在线学习与生活'),
          book(id: 'g2', title: '第1课 寻找信息科技'),
        ],
      );

      expect(index.uncategorizedCount, 2);
      final bucket = root.findById(kUncategorizedNodeId);
      expect(bucket, isNotNull);
      expect(bucket!.name, '未分类');
      expect(booksIn(index, kUncategorizedNodeId), hasLength(2));
    });

    test('全部无法分类时也只创建一个「未分类」节点', () {
      buildCatalogIndex(
        root: root,
        books: [
          book(id: 'g1', title: 'A'),
          book(id: 'g2', title: 'B'),
          book(id: 'g3', title: 'C'),
        ],
      );
      expect(
        root.children.where((c) => c.id == kUncategorizedNodeId).length,
        1,
      );
    });

    test('同名年级不会跨学科误匹配', () {
      final index = buildCatalogIndex(
        root: root,
        books: [
          book(
            id: 'c1',
            title: '初中语文七年级上册',
            dims: const {
              'zxxxd': '初中',
              'zxxxk': '语文',
              'zxxbb': '统编版',
              'zxxnj': '七年级',
              'zxxcc': '上册',
            },
          ),
        ],
      );
      expect(booksIn(index, 'up7'), hasLength(1));
      expect(booksIn(index, 'up1'), isEmpty);
    });
  });

  group('平台复用 tag_id 的回归用例', () {
    /// 真实分类树里「一年级」等节点在不同版本下复用同一个 tag_id
    /// （实测 80 个「一年级」节点共用一个 id），因此教材归并必须按节点路径
    /// 而不是按节点 id，否则兄弟分支的教材会互相污染。
    List<dynamic> sharedIdTree() => wrap([
          node('elec', '电子教材', '5036342742', kids: [
            node('primary', '小学', 'zxxxd', kids: [
              node('yuwen', '语文', 'zxxxk', kids: [
                node('tyb', '统编版', 'zxxbb', kids: [
                  // 与下面「人教版」下的年级共用同一个 tag_id
                  node('shared_g1', '一年级', 'zxxnj', kids: [
                    node('shared_up', '上册', 'zxxcc'),
                  ]),
                ]),
                node('rj', '人教版', 'zxxbb', kids: [
                  node('shared_g1', '一年级', 'zxxnj', kids: [
                    node('shared_up', '上册', 'zxxcc'),
                  ]),
                ]),
              ]),
            ]),
          ]),
        ]);

    test('同一 tag_id 下的同名节点不再共用教材集合', () {
      final tree = parseTagHierarchy(sharedIdTree());
      final index = buildCatalogIndex(
        root: tree,
        books: [
          book(
            id: 'tyb1',
            title: '统编版语文一年级上册',
            path: const [
              'elec', 'primary', 'yuwen', 'tyb', 'shared_g1', 'shared_up',
            ],
          ),
        ],
      );

      final occurrences = tree.findAllById('shared_up');
      expect(occurrences, hasLength(2), reason: '树里应有两个重名「上册」节点');

      final tybNode = tree.findById('tyb')!;
      final rjNode = tree.findById('rj')!;
      final tybUp = index.booksIn(tybNode.children.single.children.single);
      final rjUp = index.booksIn(rjNode.children.single.children.single);

      expect(tybUp.map((b) => b.id), ['tyb1']);
      expect(rjUp, isEmpty, reason: '人教版分支不应看到统编版的教材');

      // 祖先计数不受影响。
      expect(index.booksIn(tybNode), hasLength(1));
      expect(index.booksIn(rjNode), isEmpty);
    });

    test('uniqueKey 用完整路径区分同名节点', () {
      final tree = parseTagHierarchy(sharedIdTree());
      final occurrences = tree.findAllById('shared_up');
      expect(occurrences, hasLength(2));
      expect(occurrences[0].uniqueKey, isNot(occurrences[1].uniqueKey));
      expect(occurrences[0].id, occurrences[1].id);
    });
  });

  group('索引统计与检索', () {
    late CatalogIndex index;

    setUp(() {
      index = buildCatalogIndex(
        root: root,
        books: [
          book(
            id: 'b1',
            title: '义务教育教科书·语文一年级上册',
            path: const ['elec', 'primary', 'yuwen', 'tyb', 'g1', 'up1'],
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '语文',
              'zxxbb': '统编版',
              'zxxnj': '一年级',
              'zxxcc': '上册',
            },
          ),
          book(
            id: 'b2',
            title: '义务教育教科书·语文一年级下册',
            path: const ['elec', 'primary', 'yuwen', 'tyb', 'g1', 'down1'],
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '语文',
              'zxxbb': '统编版',
              'zxxnj': '一年级',
              'zxxcc': '下册',
            },
          ),
          book(
            id: 'b3',
            title: '义务教育教科书·数学一年级上册',
            path: const ['elec', 'primary', 'shuxue', 'rj', 'g1b', 'up_rj1'],
            dims: const {
              'zxxxd': '小学',
              'zxxxk': '数学',
              'zxxbb': '人教版',
              'zxxnj': '一年级',
              'zxxcc': '上册',
            },
          ),
        ],
      );
    });

    test('节点总量自上而下累计', () {
      expect(root.findById('primary')!.totalBookCount, 3);
      expect(root.findById('yuwen')!.totalBookCount, 2);
      expect(root.findById('shuxue')!.totalBookCount, 1);
      expect(root.findById('up1')!.totalBookCount, 1);
      expect(root.findById('up1')!.directBookCount, 1);
    });

    test('按书名检索', () {
      expect(index.search('数学').map((b) => b.id), ['b3']);
    });

    test('多关键词按 AND 组合，跨字段匹配', () {
      expect(index.search('语文 下册').map((b) => b.id), ['b2']);
      expect(index.search('语文 人教版'), isEmpty);
      expect(index.search('一年级 数学').map((b) => b.id), ['b3']);
    });

    test('同节点内按册次（上/下册）排序而非字典序', () {
      final ordered = booksIn(index, 'g1').map((b) => b.volume).toList();
      expect(ordered, ['上册', '下册']);
    });

    test('bookById 命中', () {
      expect(index.bookById('b2')?.title, contains('下册'));
      expect(index.bookById('nope'), isNull);
    });

    test('未知节点返回空列表而不是 null', () {
      expect(index.booksIn(CategoryNode(id: 'x', name: 'x', dimensionId: null)), isEmpty);
    });
  });

  group('详情页字段提取', () {
    test('relativeDirOf 取学段/学科/版本三段', () {
      final dir = relativeDirOf({
        'tag_list': [
          {'tag_dimension_id': 'zxxnj', 'tag_name': '一年级'},
          {'tag_dimension_id': 'zxxxd', 'tag_name': '小学'},
          {'tag_dimension_id': 'zxxxk', 'tag_name': '语文'},
          {'tag_dimension_id': 'zxxbb', 'tag_name': '统编版'},
        ],
      });
      expect(dir, ['小学', '语文', '统编版']);
    });

    test('relativeDirOf 在 tag_list 缺失时返回空', () {
      expect(relativeDirOf({}), isEmpty);
    });

    test('editionOf 取版别', () {
      expect(
        editionOf({
          'tag_list': [
            {'tag_dimension_id': 'zxxxk', 'tag_name': '语文'},
            {'tag_dimension_id': 'zxxbb', 'tag_name': '人教版'},
          ],
        }),
        '人教版',
      );
      expect(editionOf({}), isNull);
    });
  });

  group('CategoryDimension', () {
    test('维度 id 映射到中文标签', () {
      expect(CategoryDimension.fromId('zxxxd').label, '学段');
      expect(CategoryDimension.fromId('zxxxk').label, '学科');
      expect(CategoryDimension.fromId('zxxbb').label, '版本');
      expect(CategoryDimension.fromId('zxxnj').label, '年级');
      expect(CategoryDimension.fromId('zxxcc').label, '册次');
    });

    test('未知维度落到 unknown 而不是抛异常', () {
      expect(CategoryDimension.fromId('whatever'), CategoryDimension.unknown);
      expect(CategoryDimension.fromId(null), CategoryDimension.unknown);
    });
  });
}
