/// 分类树面板的回归用例。
///
/// 守住一个真实踩过的坑：平台在不同父节点下**复用同一批 `tag_id`**（实测 80 个
/// 「一年级」节点共用一个 id）。收起状态如果拿 `node.id` 当键，收起一个「一年级」
/// 会把全树所有「一年级」一起收起 —— 用户看到的就是「点哪儿都乱动」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/data/catalog_index.dart';
import 'package:tchmaterial_quick_viewer/src/models/textbook.dart';
import 'package:tchmaterial_quick_viewer/src/ui/widgets/category_tree_panel.dart';

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

/// 两个不同版本下各有一个「一年级」，**共用同一个 tag_id**。
List<dynamic> sharedIdHierarchies() => wrap([
      node('elec', '电子教材', '5036342742', kids: [
        node('primary', '小学', 'zxxxd', kids: [
          node('yuwen', '语文', 'zxxxk', kids: [
            node('tyb', '统编版', 'zxxbb', kids: [
              node('shared_g1', '一年级', 'zxxnj', kids: [
                node('up_a', '上册', 'zxxcc'),
              ]),
            ]),
          ]),
          node('shuxue', '数学', 'zxxxk', kids: [
            node('rj', '人教版', 'zxxbb', kids: [
              node('shared_g1', '一年级', 'zxxnj', kids: [
                node('up_b', '上册', 'zxxcc'),
              ]),
            ]),
          ]),
        ]),
      ]),
    ]);

CatalogIndex buildIndex() => buildCatalogIndex(
      root: parseTagHierarchy(sharedIdHierarchies()),
      books: [
        Textbook(
          id: 'b1',
          title: '统编版语文一年级上册',
          tagIds: const ['c', 'elec', 'primary', 'yuwen', 'tyb', 'shared_g1', 'up_a'],
        ),
        Textbook(
          id: 'b2',
          title: '人教版数学一年级上册',
          tagIds: const ['c', 'elec', 'primary', 'shuxue', 'rj', 'shared_g1', 'up_b'],
        ),
      ],
    );

/// 展开某一层里所有可展开的节点（面板只暴露「展开」tooltip，靠数量推进）。
Future<void> expandAllVisible(WidgetTester tester) async {
  var guard = 0;
  while (guard++ < 12) {
    final arrows = find.byTooltip('展开');
    if (arrows.evaluate().isEmpty) return;
    await tester.tap(arrows.first);
    await tester.pumpAndSettle();
  }
}

Widget host(CatalogIndex index) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 900,
          child: CategoryTreePanel(
            index: index,
            selected: null,
            onSelect: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('默认可视层级只到顶层，不递归展开', (tester) async {
    await tester.pumpWidget(host(buildIndex()));

    expect(find.text('全部教材'), findsOneWidget);
    expect(find.text('电子教材'), findsOneWidget);
    // 根的子节点默认是收起的。
    expect(find.text('小学'), findsNothing);
  });

  testWidgets('共享 tag_id 的两个「一年级」可以独立收起', (tester) async {
    await tester.pumpWidget(host(buildIndex()));

    // 一路展开到两个「一年级」都出现。
    await expandAllVisible(tester);

    expect(find.text('一年级'), findsNWidgets(2),
        reason: '两个版本下应各有一个「一年级」');

    // 此时两个「一年级」的子树都展开着，各有一个「上册」。
    expect(find.text('上册'), findsNWidgets(2));

    // 收起其中一个「一年级」。
    // 每行是一个 ListTile，箭头就在同一行的 leading 里。
    final yearTiles = find.ancestor(
      of: find.text('一年级'),
      matching: find.byType(ListTile),
    );
    expect(yearTiles, findsNWidgets(2), reason: '两个「一年级」应各占一行');

    final arrowInFirst = find.descendant(
      of: yearTiles.first,
      matching: find.byTooltip('收起'),
    );
    expect(arrowInFirst, findsOneWidget, reason: '「一年级」行内应有收起箭头');
    await tester.tap(arrowInFirst);
    await tester.pumpAndSettle();

    // 关键断言：只应收起被点的那一个，另一个必须保持展开。
    expect(find.text('一年级'), findsNWidgets(2));
    expect(find.text('上册'), findsOneWidget,
        reason: '收起一个「一年级」不该把另一个的子树也收掉 —— '
            '这正说明收起状态是按 id 而不是按节点路径记录的');
  });
}
