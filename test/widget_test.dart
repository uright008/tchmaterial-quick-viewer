/// Widget 冒烟测试：分类树面板与教材卡片的渲染。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/data/catalog_index.dart';
import 'package:tchmaterial_quick_viewer/src/ui/widgets/book_card.dart';
import 'package:tchmaterial_quick_viewer/src/ui/widgets/category_tree_panel.dart';

import 'catalog_index_test.dart' show platformHierarchies, book;

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late CatalogIndex index;

  setUp(() {
    final root = parseTagHierarchy(platformHierarchies());
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
        book(id: 'g1', title: '信息科技教学指南'),
      ],
    );
  });

  testWidgets('分类树面板渲染出「全部教材」与顶层分类', (tester) async {
    await tester.pumpWidget(host(
      CategoryTreePanel(index: index, selected: null, onSelect: (_) {}),
    ));

    expect(find.text('教材分类'), findsOneWidget);
    expect(find.text('全部教材'), findsOneWidget);
    // setUp 默认收起根节点，所以顶层分类可见、更深层不可见。
    expect(find.text('电子教材'), findsOneWidget);
    expect(find.text('小学'), findsNothing);
  });

  testWidgets('点开分类后能看到下级节点与计数', (tester) async {
    await tester.pumpWidget(host(
      CategoryTreePanel(index: index, selected: null, onSelect: (_) {}),
    ));

    await tester.tap(find.byTooltip('展开').first);
    await tester.pumpAndSettle();

    expect(find.text('小学'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('点击分类节点会回调选中项', (tester) async {
    String? capturedId;
    await tester.pumpWidget(host(
      CategoryTreePanel(
        index: index,
        selected: null,
        onSelect: (node) => capturedId = node.id,
      ),
    ));

    await tester.tap(find.text('全部教材'));
    await tester.pumpAndSettle();

    expect(capturedId, '__root');
  });

  testWidgets('教材卡片展示书名与分类标签', (tester) async {
    final textbook = index.bookById('b1')!;
    await tester.pumpWidget(host(
      SizedBox(
        width: 220,
        height: 360,
        child: BookCard(textbook: textbook, onTap: () {}),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('语文一年级上册'), findsOneWidget);
    expect(find.textContaining('小学'), findsOneWidget);
  });

  testWidgets('已下载的教材显示下载完成角标', (tester) async {
    final textbook = index.bookById('b1')!;
    await tester.pumpWidget(host(
      SizedBox(
        width: 220,
        height: 360,
        child: BookCard(textbook: textbook, onTap: () {}, downloaded: true),
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.download_done), findsOneWidget);
  });

  testWidgets('未分类教材仍能构造出卡片（无封面时走占位图）', (tester) async {
    final textbook = index.bookById('g1')!;
    await tester.pumpWidget(host(
      SizedBox(
        width: 220,
        height: 360,
        child: BookCard(textbook: textbook, onTap: () {}),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('信息科技教学指南'), findsOneWidget);
    expect(textbook.hasCover, isFalse);
  });
}
