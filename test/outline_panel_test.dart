/// 章节目录面板的回归用例。
///
/// 这里守着的是一个实际发生过的 bug：面板原来只在宽度 ≥ 1000 时渲染，窄屏下
/// 「目录」按钮照样在切换状态却什么都不发生 —— 手机上等于完全打不开；而且列表
/// 是一次性摊平的，没有展开/收起。下面这些用例把「能展开」这件事钉住。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchmaterial_quick_viewer/src/models/textbook.dart';
import 'package:tchmaterial_quick_viewer/src/ui/pages/reader_page.dart';

/// 两章，每章两个小节，另有一个无子节点的独立小节。
const _chapters = [
  Chapter(
    title: '第一单元 我是小学生啦',
    pageIndex: 6,
    children: [
      Chapter(title: '第1课 开开心心上学去', pageIndex: 7),
      Chapter(title: '第2课 拉拉手，交朋友', pageIndex: 11),
    ],
  ),
  Chapter(
    title: '第二单元 过好校园生活',
    pageIndex: 22,
    children: [
      Chapter(title: '第5课 老师，您好', pageIndex: 23),
    ],
  ),
  Chapter(title: '附录', pageIndex: 63),
];

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('印刷页码换算（front_page）', () {
    // 实测数据：某教材 front_page=5，目录写「第一单元 / 1」，平台映射给 6。
    test('印刷页码 = PDF 页码 - front_page', () {
      const ch = Chapter(title: '第一单元', pageIndex: 6);
      expect(ch.printedPage(5), 1);
      expect(const Chapter(title: '第16课', pageIndex: 63).printedPage(5), 58);
    });

    test('前置页本身没有印刷页码', () {
      // PDF 第 1..5 页是封面/目录，印刷页码不存在。
      expect(const Chapter(title: '封面', pageIndex: 1).printedPage(5), isNull);
      expect(const Chapter(title: '目录', pageIndex: 5).printedPage(5), isNull);
    });

    test('front_page 未知时返回 null，调用方回退到 PDF 页码', () {
      expect(const Chapter(title: 'x', pageIndex: 10).printedPage(0), isNull);
    });

    test('没有页码的节点返回 null', () {
      expect(const Chapter(title: 'x').printedPage(5), isNull);
    });
  });

  group('OutlinePanel', () {
    testWidgets('顶层章节默认可见，子节点默认收起', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));

      expect(find.text('第一单元 我是小学生啦'), findsOneWidget);
      expect(find.text('第二单元 过好校园生活'), findsOneWidget);
      expect(find.text('附录'), findsOneWidget);
      // 子节点在展开之前不应出现。
      expect(find.text('第1课 开开心心上学去'), findsNothing);
      expect(find.text('第5课 老师，您好'), findsNothing);
    });

    testWidgets('点子节点的展开箭头能展开下一层', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));

      // 两个带子节点的章节 => 两个展开箭头。
      final arrows = find.byTooltip('展开');
      expect(arrows, findsNWidgets(2));

      await tester.tap(arrows.first);
      await tester.pumpAndSettle();

      expect(find.text('第1课 开开心心上学去'), findsOneWidget);
      expect(find.text('第2课 拉拉手，交朋友'), findsOneWidget);
      // 另一个章节仍保持收起。
      expect(find.text('第5课 老师，您好'), findsNothing);
    });

    testWidgets('再点一次可以收起', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));

      await tester.tap(find.byTooltip('展开').first);
      await tester.pumpAndSettle();
      expect(find.text('第1课 开开心心上学去'), findsOneWidget);

      await tester.tap(find.byTooltip('收起').first);
      await tester.pumpAndSettle();
      expect(find.text('第1课 开开心心上学去'), findsNothing);
    });

    testWidgets('「全部收起」只在展开过之后出现，且不递归', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));

      // 初始没有展开任何节点，就不该有这个按钮。
      expect(find.byTooltip('全部收起'), findsNothing);

      await tester.tap(find.byTooltip('展开').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('全部收起'), findsOneWidget);

      await tester.tap(find.byTooltip('全部收起'));
      await tester.pumpAndSettle();
      expect(find.text('第1课 开开心心上学去'), findsNothing);
      expect(find.byTooltip('全部收起'), findsNothing);
    });

    testWidgets('深层目录默认也只显示第一级（不递归展开）', (tester) async {
      const deep = [
        Chapter(
          title: 'L1',
          pageIndex: 1,
          children: [
            Chapter(
              title: 'L2',
              pageIndex: 2,
              children: [
                Chapter(
                  title: 'L3',
                  pageIndex: 3,
                  children: [Chapter(title: 'L4', pageIndex: 4)],
                ),
              ],
            ),
          ],
        ),
      ];

      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: deep,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));

      expect(find.text('L1'), findsOneWidget);
      expect(find.text('L2'), findsNothing, reason: '第二级默认必须是收起的');
      expect(find.text('L3'), findsNothing);
      expect(find.text('L4'), findsNothing);
    });

    testWidgets('不存在「全部展开」入口', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));
      await tester.tap(find.byTooltip('展开').first);
      await tester.pumpAndSettle();
      // 目录的用途是定位，一次性摊开整棵树反而更难找。
      expect(find.text('全部展开'), findsNothing);
    });

    testWidgets('点标题会把对应章节回调出去', (tester) async {
      final jumped = <int>[];
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (chapter) => jumped.add(chapter.pageIndex!),
        ),
      ));

      await tester.tap(find.text('附录'));
      await tester.pumpAndSettle();
      expect(jumped, [63]);

      // 点带子节点的标题应当只跳页，不该顺手把树展开。
      await tester.tap(find.text('第一单元 我是小学生啦'));
      await tester.pumpAndSettle();
      expect(jumped, [63, 6]);
      expect(find.text('第1课 开开心心上学去'), findsNothing);
    });

    testWidgets('没有目录时给出可读的空状态', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: const [],
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));
      expect(find.textContaining('没有目录'), findsOneWidget);
    });

    testWidgets('有 front_page 时行尾显示书上印刷的页码', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          frontPage: 5,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));
      // _chapters 里第一单元 pageIndex=6 → 印刷页码 1
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('P6'), findsNothing, reason: '不该显示绝对 PDF 页号');
      expect(find.text('印刷页码'), findsOneWidget);
    });

    testWidgets('没有 front_page 时回退到 PDF 页码', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));
      expect(find.text('P6'), findsOneWidget);
    });

    testWidgets('数据源会标注是平台目录还是 PDF 书签', (tester) async {
      await tester.pumpWidget(host(
        OutlinePanel(
          chapters: _chapters,
          loading: false,
          currentPage: 1,
          onJump: (_) {},
        ),
      ));
      expect(find.text('平台目录'), findsOneWidget);
    });
  });
}
