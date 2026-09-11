/// 阅读页：内置 PDF 阅读器 + 平台章节目录。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../../core/file_actions.dart';
import '../../models/textbook.dart';
import '../../state/library_controller.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.textbook,
    required this.file,
    this.detail,
    this.initialPage,
  });

  final Textbook textbook;
  final ResourceFile file;

  /// 已解析的详情（含章节目录）；为 null 时会自行拉取。
  final TextbookDetail? detail;

  final int? initialPage;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final PdfViewerController _controller = PdfViewerController();

  File? _localFile;
  String? _error;
  DownloadTaskSnapshot? _download;

  TextbookDetail? _detail;

  /// PDF 自带书签。平台并非每本教材都提供 `ebook_mapping`，这时用阅读器内核
  /// 解析出的书签兜底，目录面板才不至于空着。
  List<Chapter> _pdfOutline = const [];
  bool _usingPdfOutline = false;

  bool _showOutline = true;
  bool _outlineLoading = false;
  int _currentPage = 1;
  int _pageCount = 0;

  /// 目录状态版本号。
  ///
  /// 窄屏时目录是 `showModalBottomSheet` 打开的 —— 那是一条独立路由，builder
  /// 只在打开时跑一次，父页面后续的 setState 不会重建它。如果打开时章节还在
  /// 加载，弹层就会永远停在转圈上。用一个 ValueNotifier 让弹层能跟着刷新。
  final ValueNotifier<int> _outlineRevision = ValueNotifier<int>(0);

  void _bumpOutline() => _outlineRevision.value++;

  @override
  void dispose() {
    _outlineRevision.dispose();
    super.dispose();
  }

  /// 目录数据源：优先用平台目录，没有再退回 PDF 自带书签。
  List<Chapter> get _outlineChapters {
    final platform = _detail?.chapters ?? const <Chapter>[];
    return platform.isNotEmpty ? platform : _pdfOutline;
  }

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final library = context.read<LibraryController>();
    try {
      final file = await library.ensureLocal(
        widget.textbook,
        widget.file,
        onUpdate: (task) {
          if (!mounted) return;
          setState(() {
            _download = DownloadTaskSnapshot(
              received: task.received,
              total: task.total,
            );
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _localFile = file;
        _download = null;
      });
      await _loadOutline(library);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _download = null;
      });
    }
  }

  Future<void> _loadOutline(LibraryController library) async {
    if (_detail != null && _detail!.hasChapters) return;
    setState(() => _outlineLoading = true);
    _bumpOutline();
    try {
      final detail = await library.resolveDetail(widget.textbook);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _outlineLoading = false;
      });
      _bumpOutline();
    } catch (_) {
      // 目录取不到不影响阅读。
      if (!mounted) return;
      setState(() => _outlineLoading = false);
      _bumpOutline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = _outlineChapters;
    // 侧栏只在够宽时占位。**窄屏走底部弹层** —— 之前的写法是
    // `showOutline = _showOutline && wide`，窄屏下按钮仍然在切换状态、却什么都不
    // 会发生，手机上（宽度必然 < 1000）目录等于完全没法打开。
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final showSidePanel = _showOutline && wide;
    final canShowOutline = _localFile != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          widget.textbook.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pageCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '$_currentPage / $_pageCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: wide
                ? (showSidePanel ? '隐藏目录' : '显示目录')
                : '打开目录',
            onPressed: canShowOutline
                ? (wide
                    ? () => setState(() => _showOutline = !_showOutline)
                    : () => _openOutlineSheet(context))
                : null,
            icon: Icon(showSidePanel ? Icons.toc : Icons.toc_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '视图',
            onSelected: _onViewAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'fit-width', child: Text('适应宽度')),
              const PopupMenuItem(value: 'fit-page', child: Text('适应整页')),
              const PopupMenuItem(value: 'zoom-in', child: Text('放大')),
              const PopupMenuItem(value: 'zoom-out', child: Text('缩小')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'first', child: Text('回到首页')),
              if (supportsExternalFileOpen)
                const PopupMenuItem(
                  value: 'external',
                  child: Text('用系统程序打开'),
                ),
              if (supportsSharing)
                const PopupMenuItem(value: 'share', child: Text('分享这本教材')),
            ],
          ),
        ],
      ),
      body: _buildBody(context, chapters, showSidePanel),
    );
  }

  /// 窄屏：把目录放进底部弹层，保证任何宽度下都能打开。
  Future<void> _openOutlineSheet(BuildContext context) async {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.75;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // 弹层是独立路由，必须自己订阅目录状态，否则打开后就再也不更新。
      builder: (_) => SizedBox(
        height: sheetHeight,
        child: ValueListenableBuilder<int>(
          valueListenable: _outlineRevision,
          builder: (context, _, _) => OutlinePanel(
            chapters: _outlineChapters,
            loading: _outlineLoading,
            usingPdfOutline: _usingPdfOutline,
            frontPage: _detail?.frontPage ?? 0,
            currentPage: _currentPage,
            onJump: (chapter) {
              _jumpTo(chapter);
              Navigator.of(context).maybePop();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Chapter> chapters,
    bool showOutline,
  ) {
    if (_error != null) {
      return _ReaderMessage(
        icon: Icons.error_outline,
        title: '无法打开教材',
        message: _error!,
        action: FilledButton.icon(
          onPressed: () {
            setState(() => _error = null);
            _prepare();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重试'),
        ),
      );
    }

    final file = _localFile;
    if (file == null) {
      final download = _download;
      final total = download?.total;
      final ratio = (total ?? 0) > 0 ? download!.received / total! : null;
      return _ReaderMessage(
        icon: Icons.downloading,
        title: '正在准备教材…',
        message: download == null
            ? '正在检查本地缓存'
            : '${_formatBytes(download.received)}'
                '${total == null ? '' : ' / ${_formatBytes(total)}'}',
        progress: ratio,
      );
    }

    final viewer = PdfViewer.file(
      file.path,
      controller: _controller,
      initialPageNumber: widget.initialPage ?? 1,
      // 增量加载：先出前几页，边读边在后台解析剩余部分。
      useProgressiveLoading: true,
      params: PdfViewerParams(
        margin: 12,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,

        // ── 渲染性能 ────────────────────────────────────────────────
        //
        // 先讲清楚边界：pdfium 只有 CPU 光栅化后端，**没有 GPU 路径** —— 把某
        // 一页画成位图这一步永远在 CPU 上跑。GPU(Impeller) 负责的是后半程：
        // 把已经光栅化好的页位图合成到屏幕上，命中缓存时滚动/缩放是满帧的。
        //
        // 所以「卡」几乎总是来自两件事，而不是「没开 GPU」：
        //   1. 每帧在做多余的活；
        //   2. 频繁触发重新光栅化（缩放超出已渲染尺度、缓存被挤掉）。
        // 下面这些参数就是围绕这两点定的。
        sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
          // 原来放到 8：再放大就会按更高 DPI 重画整页，对阅读收益很小。
          maxScale: 6,
          minScale: 0.5,
        ),
        behaviorControlParams: const PdfViewerBehaviorControlParams(
          // 先铺一张低分辨率整页再补全清晰版，翻页不会出现空白等待。
          enableLowResolutionPagePreview: true,
          // 只测量真正可见的页。默认 false 会在打开时遍历整份文档
          // （loadPagesProgressively），170 页扫描件首屏会明显变慢。
          loadPageDimensionsOnDemand: true,
        ),
        // 视口上下左右各预渲染半屏而不是各一整屏，少画一半的页。
        verticalCacheExtent: 0.5,
        horizontalCacheExtent: 0.5,

        // ── 必须关闭文本选择层 ──────────────────────────────────────
        //
        // pdfrx 默认开启文本选择，会在绘制每页时调用
        // `PdfPageTextRange.enumerateFragmentBoundingRects()`。教材基本是扫描
        // 件，文本片段下标容易越界，于是 `_paintPagesCustom` 每帧抛一次
        // `RangeError: Invalid value: Not in inclusive range 0..24: -1`，
        // 日志被刷屏、帧率也被拖垮。
        //
        // pdfrx 在那处的守卫是
        //   `final text = isTextSelectionEnabled
        //        ? _getCachedTextOrDelayLoadText(page.pageNumber) : null;`
        // 关掉之后 text 恒为 null，整块绘制逻辑都不会进入。阅读器本来也不需要
        // 选中文字，顺带还省掉了「为缓存范围内每一页解析内容流」的开销。
        textSelectionParams: const PdfTextSelectionParams(enabled: false),

        // 不加 pageDropShadow：那是每帧为每页多画一次的装饰，对扫描件阅读没
        // 有任何帮助。
        onViewerReady: (document, controller) {
          if (!mounted) return;
          setState(() => _pageCount = document.pages.length);
          _loadPdfOutline(document);
        },
        onPageChanged: (pageNumber) {
          if (!mounted || pageNumber == null) return;
          setState(() => _currentPage = pageNumber);
        },
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
          final ratio =
              (totalBytes ?? 0) > 0 ? bytesDownloaded / totalBytes! : null;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  totalBytes == null
                      ? '正在载入 ${_formatBytes(bytesDownloaded)}'
                      : '正在载入 ${_formatBytes(bytesDownloaded)}'
                          ' / ${_formatBytes(totalBytes)}',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(value: ratio),
                ),
              ],
            ),
          );
        },
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            _ReaderMessage(
          icon: Icons.broken_image_outlined,
          title: 'PDF 渲染失败',
          message: '$error',
        ),
      ),
    );

    if (!showOutline) return viewer;

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: OutlinePanel(
            chapters: chapters,
            loading: _outlineLoading,
            usingPdfOutline: _usingPdfOutline,
            frontPage: _detail?.frontPage ?? 0,
            currentPage: _currentPage,
            onJump: _jumpTo,
            onClose: () => setState(() => _showOutline = false),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: viewer),
      ],
    );
  }

  /// 读取 PDF 自带书签作为兜底目录。
  ///
  /// 平台只在部分教材上提供 `ebook_mapping`，没有的那些原本目录面板是空白的。
  /// pdfium 能解析 PDF 自身的 `/Outlines`，直接拿来用。
  Future<void> _loadPdfOutline(PdfDocument document) async {
    // 平台目录优先，已经有就不必再解析。
    if (_detail?.hasChapters ?? false) return;
    try {
      final nodes = await document.loadOutline();
      if (!mounted || nodes.isEmpty) return;
      // 期间可能已经拉到平台目录了，再确认一次。
      if (_detail?.hasChapters ?? false) return;
      setState(() {
        _pdfOutline = nodes.map(_toChapter).toList();
        _usingPdfOutline = _pdfOutline.isNotEmpty;
      });
      _bumpOutline();
    } catch (_) {
      // 书签不是必需品，解析失败就当没有。
    }
  }

  Chapter _toChapter(PdfOutlineNode node) {
    final dest = node.dest;
    return Chapter(
      title: node.title,
      pageIndex: dest?.pageNumber,
      // 连页内位置一起带上。PDF 的显式目标里 `xyz` 是 [left, top, zoom]，
      // `fitH`/`fitBH` 是 [top] —— 只取页码就会丢掉这个纵向偏移，
      // 本该落在标题处的跳转只能落到页顶。
      destination: dest == null
          ? null
          : PdfDestination(
              pageNumber: dest.pageNumber,
              command: dest.command.name,
              params: dest.params ?? const [],
            ),
      children: node.children.map(_toChapter).toList(),
    );
  }

  /// 跳转到目录项。
  ///
  /// 有 PDF 自带书签（含页内偏移）就用 `goToDest`，让 pdfrx 按 PDF 规范换算；
  /// 平台目录只给了页码，那就跳页顶。
  Future<void> _jumpTo(Chapter chapter) async {
    final dest = chapter.destination;
    if (dest != null) {
      final handled = await _controller.goToDest(
        PdfDest(dest.pageNumber, PdfDestCommand.parse(dest.command), dest.params),
      );
      if (handled) return;
    }
    final page = chapter.pageIndex;
    if (page != null && page > 0) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  Future<void> _onViewAction(String action) async {
    switch (action) {
      case 'fit-width':
        await _controller.setZoom(_controller.centerPosition, 1.0);
      case 'fit-page':
        await _controller.setZoom(_controller.centerPosition, 0.8);
      case 'zoom-in':
        await _controller.setZoom(
          _controller.centerPosition,
          (_controller.currentZoom * 1.25).clamp(0.2, 6.0),
        );
      case 'zoom-out':
        await _controller.setZoom(
          _controller.centerPosition,
          (_controller.currentZoom * 0.8).clamp(0.2, 6.0),
        );
      case 'first':
        await _controller.goToPage(pageNumber: 1);
      case 'external':
      case 'share':
        final file = _localFile;
        if (file == null) return;
        final result = action == 'share'
            ? await shareFile(file, subject: widget.textbook.title)
            : await openFileExternally(file);
        if (!mounted || result == FileActionResult.ok) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

/// 下载进度快照（避免直接持有 ChangeNotifier 里的可变对象）。
class DownloadTaskSnapshot {
  const DownloadTaskSnapshot({required this.received, this.total});
  final int received;
  final int? total;
}

/// 章节目录面板：可逐级展开/收起的树。
///
/// 之前的实现是把所有层级 `expand()` 摊平成一个列表，既没有展开箭头、层级也只
/// 靠缩进区分；加上外层 `showOutline && wide` 的宽度门限，窄屏下点了按钮毫无反
/// 应。现在改成真正的树：带箭头、可收起、任何宽度都能打开（窄屏走底部弹层）。
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    super.key,
    required this.chapters,
    required this.loading,
    required this.currentPage,
    required this.onJump,
    this.onClose,
    this.usingPdfOutline = false,
    this.frontPage = 0,
  });

  final List<Chapter> chapters;
  final bool loading;
  final int currentPage;
  final ValueChanged<Chapter> onJump;
  final VoidCallback? onClose;

  /// 目录来自 PDF 自带书签（而非平台接口）。
  final bool usingPdfOutline;

  /// 平台给出的前置页数，用于把 PDF 页码换算成书上印刷的页码。
  final int frontPage;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

/// 一行：节点 + 深度 + 稳定 key（用于记住收起状态）。
typedef _OutlineRow = ({Chapter chapter, int depth, String key});

class _OutlinePanelState extends State<OutlinePanel> {
  /// 记录**已展开**的节点，而不是已收起的。
  ///
  /// 初始为空 = 只有第一级可见。反过来用「已收起」集合很容易写错：空集合意味着
  /// 「什么都没收起」，也就是递归全展开 —— 打开目录瞬间铺满整棵树，既难找也卡。
  final Set<String> _expanded = <String>{};

  /// 摊平成当前可见的行，跳过被收起的子树。
  List<_OutlineRow> _visibleRows() {
    final rows = <_OutlineRow>[];

    void walk(List<Chapter> nodes, int depth, String prefix) {
      for (var i = 0; i < nodes.length; i++) {
        final chapter = nodes[i];
        final key = prefix.isEmpty ? '$i' : '$prefix/$i';
        rows.add((chapter: chapter, depth: depth, key: key));
        // 只有用户明确展开过才往下走。
        if (chapter.children.isNotEmpty && _expanded.contains(key)) {
          walk(chapter.children, depth + 1, key);
        }
      }
    }

    walk(widget.chapters, 0, '');
    return rows;
  }

  void _toggle(String key) => setState(() {
        if (!_expanded.remove(key)) _expanded.add(key);
      });

  /// 只做「收起」，且不递归 —— 清空展开集合即可回到「只有第一级」的初始状态。
  /// 刻意不提供「全部展开」：目录的用途是定位，一次性摊开整棵树反而更难找。
  void _collapseAll() => setState(_expanded.clear);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _visibleRows();
    final hasTree = widget.chapters.any((c) => c.children.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.toc, size: 18),
              const SizedBox(width: 8),
              Text('目录', style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              Flexible(
                child: Tooltip(
                  // 面板只有 300px，长标签会被截断，完整说明放 tooltip。
                  message: widget.usingPdfOutline
                      ? '目录来自 PDF 自带书签（平台未提供章节目录）'
                      : (widget.frontPage > 0
                          ? '行尾显示的是**书上印刷的页码**（PDF 页码 = 印刷页码 + '
                              '${widget.frontPage} 页前置页）'
                          : '目录来自平台，行尾为 PDF 页码'),
                  child: Text(
                    widget.usingPdfOutline
                        ? 'PDF 书签'
                        : (widget.frontPage > 0 ? '印刷页码' : '平台目录'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (hasTree && _expanded.isNotEmpty)
                IconButton(
                  tooltip: '全部收起',
                  iconSize: 18,
                  onPressed: _collapseAll,
                  icon: const Icon(Icons.unfold_less),
                ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: '收起',
                  iconSize: 18,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildList(theme, rows)),
      ],
    );
  }

  Widget _buildList(ThemeData theme, List<_OutlineRow> rows) {
    if (widget.loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '这本教材没有目录：平台未提供章节信息，PDF 自身也没有书签。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final chapter = row.chapter;
        final hasChildren = chapter.children.isNotEmpty;
        final expanded = _expanded.contains(row.key);
        final isCurrent = chapter.hasPage &&
            _isCurrentSection(chapter.pageIndex!, rows, index);

        return InkWell(
          // 点标题只跳页；展开/收起交给左侧箭头，避免想翻页却把树展开了。
          onTap: chapter.hasPage ? () => widget.onJump(chapter) : null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(6 + row.depth * 14.0, 2, 10, 2),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          tooltip: expanded ? '收起' : '展开',
                          onPressed: () => _toggle(row.key),
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.chevron_right,
                          ),
                        )
                      : Icon(
                          Icons.circle,
                          size: 5,
                          color: theme.colorScheme.outlineVariant,
                        ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : (row.depth == 0 ? FontWeight.w600 : null),
                        color: isCurrent ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                ),
                if (chapter.hasPage)
                  Text(
                    // 有前置页信息时显示**书上印的页码** —— 用户是拿着书对照的，
                    // 显示绝对 PDF 页号（比印刷页大 frontPage）会被认为「不准」。
                    'P${chapter.printedPage(widget.frontPage) ?? chapter.pageIndex}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 当前页落在哪一条目录：取下一条有页码的目录作为上界。
  bool _isCurrentSection(
    int page,
    List<_OutlineRow> rows,
    int index,
  ) {
    if (page < (rows[index].chapter.pageIndex ?? 0)) return false;
    for (var i = index + 1; i < rows.length; i++) {
      final next = rows[i].chapter.pageIndex;
      if (next != null) return page < next;
    }
    return true;
  }
}

class _ReaderMessage extends StatelessWidget {
  const _ReaderMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 260,
                child: LinearProgressIndicator(value: progress),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
