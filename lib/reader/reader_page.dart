import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../models/reader_settings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'chapter_paginator.dart';

/// 扁平化后的一页：属于哪一章、章内第几页、页内容。
class _FlatPage {
  const _FlatPage({
    required this.chapter,
    required this.pageInChapter,
    required this.page,
  });

  final int chapter;
  final int pageInChapter;
  final ReaderPageContent page;

  int get firstLine => page.firstLine;
  int get lastLine => page.lastLine;
}

/// 阅读界面。
///
/// 分页模型：维护「上一章 + 当前章 + 下一章」三章的页缓存，并拼接成一个扁平分页列表。
/// 点击翻页与滑动翻页走同一套逻辑（同一个 [_turnBy]），因此章节交界处行为一致：
/// 章节末继续翻进入下一章首页，章节首页回翻进入上一章最后一页。
///
/// 阅读进度按「章节 + 屏幕首行行号」保存（与设备分辨率、字号无关）。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin {
  List<Chapter> _chapters = const [];
  String _content = '';
  int _chapterIndex = 0;
  bool _loading = true;

  /// 三章窗口拼接出的扁平页列表。
  final List<_FlatPage> _flat = [];
  int _flatIndex = 0;

  /// 按章缓存分页结果，避免每次跨章都重算。
  final Map<int, List<ReaderPageContent>> _pageCache = {};
  String _paginateSignature = '';
  int _windowChapter = -1;
  Size _viewport = Size.zero;
  int? _pendingLine;

  bool _menuVisible = false;
  String? _panel;
  bool _tocVisible = false;

  /// 拖动/动画位移（用 ValueNotifier 驱动，避免动画期间整页重建）。
  final ValueNotifier<double> _drag = ValueNotifier<double>(0);
  late final AnimationController _settle;
  double _dragFrom = 0;
  double _dragTo = 0;
  VoidCallback? _afterSettle;

  final PageController _slideController = PageController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _settle.addListener(() {
      _drag.value = _dragFrom + (_dragTo - _dragFrom) * _settle.value;
    });
    _settle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final after = _afterSettle;
      _afterSettle = null;
      _drag.value = 0;
      after?.call();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _settle.dispose();
    _drag.dispose();
    _slideController.dispose();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _persistProgress();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final chapters = await state.library.chaptersOf(widget.book.id);
    final content = await state.library.contentOf(widget.book.id);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _content = content;
      _chapterIndex = widget.book.lastChapter.clamp(
        0,
        math.max(0, chapters.length - 1),
      );
      _pendingLine = widget.book.lastLine;
      _loading = false;
      _paginateSignature = '';
    });
  }

  ReaderSettings get _rs => context.read<AppState>().readerSettings;

  _FlatPage? get _current =>
      _flat.isEmpty || _flatIndex >= _flat.length ? null : _flat[_flatIndex];

  TextStyle _textStyle(ReaderSettings rs) => TextStyle(
    fontSize: rs.textSize,
    height: (rs.textSize + rs.lineSpacing) / rs.textSize,
    letterSpacing: rs.letterSpacing,
    fontWeight: rs.bold ? FontWeight.w600 : FontWeight.normal,
    color: parseHexColor(rs.textColor, fallback: Colors.black),
    fontFamily: rs.fontFamily.isEmpty ? null : rs.fontFamily,
  );

  bool _hasHeader(ReaderSettings rs) =>
      rs.headerLeft != TipMode.none ||
      rs.headerMiddle != TipMode.none ||
      rs.headerRight != TipMode.none;

  bool _hasFooter(ReaderSettings rs) =>
      rs.footerLeft != TipMode.none ||
      rs.footerMiddle != TipMode.none ||
      rs.footerRight != TipMode.none;

  double _tipBarHeight(ReaderSettings rs, {required bool isHeader}) {
    final hasAny = isHeader ? _hasHeader(rs) : _hasFooter(rs);
    if (!hasAny) return 0;
    final textHeight = rs.textSize * 0.68 * 1.25;
    const padding = 12.0;
    final showLine = isHeader ? rs.showHeaderLine : rs.showFooterLine;
    return textHeight + padding + (showLine ? 8 : 0);
  }

  String _chapterTextOf(int index) {
    if (index < 0 || index >= _chapters.length) return '';
    final ch = _chapters[index];
    final start = ch.start.clamp(0, _content.length);
    final end = ch.end.clamp(start, _content.length);
    return _content.substring(start, end);
  }

  double get _bookProgress {
    final f = _current;
    if (f == null || _chapters.isEmpty) return 0;
    final total = _pagesOfChapter(f.chapter).length;
    final inChapter = total == 0 ? 0 : (f.pageInChapter + 1) / total;
    return ((f.chapter + inChapter) / _chapters.length).clamp(0, 1).toDouble();
  }

  double get _scrollLineHeight {
    final rs = _rs;
    return rs.textSize + rs.lineSpacing + rs.paragraphSpacing + 1;
  }

  // ---------------- 分页（三章窗口 + 缓存） ----------------

  List<ReaderPageContent> _pagesOfChapter(
    int index, {
    ReaderSettings? rs,
    TextScaler? scaler,
  }) {
    final cached = _pageCache[index];
    if (cached != null) return cached;
    if (_viewport.isEmpty) return const [];
    final settings = rs ?? _rs;
    final textScaler = scaler ?? TextScaler.noScaling;
    final headerHeight = _tipBarHeight(settings, isHeader: true);
    final footerHeight = _tipBarHeight(settings, isHeader: false);
    final maxWidth =
        _viewport.width - settings.paddingLeft - settings.paddingRight;
    final maxHeight = _viewport.height -
        settings.paddingTop -
        settings.paddingBottom -
        headerHeight -
        footerHeight;
    final pages = ChapterPaginator.paginate(
      text: _chapterTextOf(index),
      style: _textStyle(settings),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      indent: settings.paragraphIndent,
      paragraphSpacing: settings.paragraphSpacing,
      textScaler: textScaler,
    );
    _pageCache[index] = pages;
    return pages;
  }

  /// 以 (chapter, line) 为锚点重建三章窗口。
  void _rebuildWindow(int anchorChapter, int anchorLine) {
    final flat = <_FlatPage>[];
    for (final chapter in [
      anchorChapter - 1,
      anchorChapter,
      anchorChapter + 1,
    ]) {
      if (chapter < 0 || chapter >= _chapters.length) continue;
      final pages = _pagesOfChapter(chapter);
      for (var i = 0; i < pages.length; i++) {
        flat.add(_FlatPage(chapter: chapter, pageInChapter: i, page: pages[i]));
      }
    }
    _flat
      ..clear()
      ..addAll(flat);
    _flatIndex = _indexFor(anchorChapter, anchorLine);
    _windowChapter = anchorChapter;
  }

  int _indexFor(int chapter, int line) {
    var fallback = 0;
    for (var i = 0; i < _flat.length; i++) {
      final f = _flat[i];
      if (f.chapter != chapter) continue;
      if (line >= f.firstLine && line <= f.lastLine) return i;
      if (f.firstLine <= line) fallback = i;
    }
    return fallback;
  }

  void _paginateIfNeeded(
    BoxConstraints constraints,
    ReaderSettings rs,
    TextScaler scaler,
  ) {
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    if (size.isEmpty) return;
    _viewport = size;
    final signature = [
      size.width.toStringAsFixed(1),
      size.height.toStringAsFixed(1),
      scaler.scale(1).toStringAsFixed(3),
      rs.textSize,
      rs.lineSpacing,
      rs.letterSpacing,
      rs.paragraphSpacing,
      rs.paddingLeft,
      rs.paddingRight,
      rs.paddingTop,
      rs.paddingBottom,
      rs.paragraphIndent,
      rs.fontFamily,
      rs.bold,
      rs.headerLeft.name,
      rs.headerMiddle.name,
      rs.headerRight.name,
      rs.footerLeft.name,
      rs.footerMiddle.name,
      rs.footerRight.name,
      rs.showHeaderLine,
      rs.showFooterLine,
    ].join('|');

    final sameLayout = signature == _paginateSignature;
    if (sameLayout && _windowChapter == _chapterIndex && _flat.isNotEmpty) {
      return;
    }
    if (!sameLayout) _pageCache.clear();
    _paginateSignature = signature;

    final anchorLine = _pendingLine ?? (_current?.firstLine ?? 0);
    _pendingLine = null;
    _pagesOfChapter(_chapterIndex, rs: rs, scaler: scaler);
    _rebuildWindow(_chapterIndex, anchorLine);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (rs.pageMode == PageMode.slide && _slideController.hasClients) {
        _slideController.jumpToPage(_flatIndex);
      }
      if (rs.pageMode == PageMode.scroll && _scrollController.hasClients) {
        final offset = anchorLine * _scrollLineHeight;
        _scrollController.jumpTo(
          offset.clamp(0, _scrollController.position.maxScrollExtent),
        );
      }
    });
  }

  // ---------------- 翻页（点击与滑动共用） ----------------

  void _applyTurn(int delta) {
    final target = _flatIndex + delta;
    if (target < 0 || target >= _flat.length) return;
    setState(() {
      _flatIndex = target;
      final chapter = _flat[target].chapter;
      if (chapter != _chapterIndex) {
        _chapterIndex = chapter;
        // 进入新章后把窗口挪到它附近（页缓存命中，代价很小）
        _paginateSignature = '';
      }
    });
    _persistProgress();
  }

  /// 统一的翻页入口：点击与滑动都走这里，只有动画方式不同。
  void _turnBy(int delta, {required bool animated}) {
    if (delta == 0 || _flat.isEmpty) return;
    final target = _flatIndex + delta;
    if (target < 0 || target >= _flat.length) return;
    final rs = _rs;
    if (!animated || _viewport.width <= 0) {
      _applyTurn(delta);
      return;
    }
    switch (rs.pageMode) {
      case PageMode.slide:
        if (_slideController.hasClients) {
          _slideController.animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        } else {
          _applyTurn(delta);
        }
      case PageMode.cover:
        _settleTo(
          delta > 0 ? -_viewport.width : _viewport.width,
          then: () => _applyTurn(delta),
        );
      case PageMode.none:
      case PageMode.scroll:
        _applyTurn(delta);
    }
  }

  /// 停在 [target] 位移处；结束后执行 [then]。
  void _settleTo(double target, {VoidCallback? then}) {
    _dragFrom = _drag.value;
    _dragTo = target;
    _afterSettle = then;
    if ((_dragTo - _dragFrom).abs() < 0.5) {
      _drag.value = 0;
      _afterSettle = null;
      then?.call();
      return;
    }
    _settle.forward(from: 0);
  }

  void _goChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _pendingLine = 0;
      _paginateSignature = '';
      _menuVisible = false;
      _tocVisible = false;
      _drag.value = 0;
    });
    _persistProgress();
  }

  void _handleTap(TapUpDetails details, double width) {
    if (_menuVisible) {
      setState(() {
        _menuVisible = false;
        _panel = null;
        _tocVisible = false;
      });
      return;
    }
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _turnBy(-1, animated: true);
    } else if (x > width * 2 / 3) {
      _turnBy(1, animated: true);
    } else {
      setState(() => _menuVisible = true);
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (_settle.isAnimating) _settle.stop();
    _drag.value = (_drag.value + details.delta.dx).clamp(-width, width);
  }

  void _onDragEnd(DragEndDetails details, double width) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final drag = _drag.value;
    final goNext = drag < -width * 0.22 || (velocity < -600 && drag < -20);
    final goPrev = drag > width * 0.22 || (velocity > 600 && drag > 20);

    // 无动画模式：松手立即切换，不做过渡
    if (_rs.pageMode == PageMode.none) {
      _drag.value = 0;
      if (goNext) {
        _applyTurn(1);
      } else if (goPrev) {
        _applyTurn(-1);
      }
      return;
    }
    if (goNext) {
      _turnBy(1, animated: true);
    } else if (goPrev) {
      _turnBy(-1, animated: true);
    } else {
      _settleTo(0);
    }
  }

  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final f = _current;
    await context.read<AppState>().saveProgress(
      widget.book,
      f?.chapter ?? _chapterIndex,
      f?.firstLine ?? 0,
      f?.page.startOffset ?? 0,
      _bookProgress,
    );
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rs = state.readerSettings;
    final bg = parseHexColor(rs.bgColor, fallback: Colors.white);

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_chapters.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(),
        body: const Center(child: Text('这本书还没有正文')),
      );
    }

    final scaler = MediaQuery.textScalerOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _paginateIfNeeded(constraints, rs, scaler);
          return Stack(
            children: [
              Positioned.fill(child: _buildContent(constraints, rs)),
              if (rs.brightness > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: rs.brightness * 0.6),
                    ),
                  ),
                ),
              _buildMenu(rs, state, isLandscape: isLandscape),
              if (_tocVisible) _buildToc(rs),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(BoxConstraints constraints, ReaderSettings rs) {
    final width = constraints.maxWidth;
    switch (rs.pageMode) {
      case PageMode.slide:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, width),
          child: PageView.builder(
            controller: _slideController,
            itemCount: _flat.length,
            onPageChanged: (i) {
              setState(() {
                _flatIndex = i;
                final chapter = _flat[i].chapter;
                if (chapter != _chapterIndex) {
                  _chapterIndex = chapter;
                  _paginateSignature = '';
                }
              });
              _persistProgress();
            },
            itemBuilder: (context, index) =>
                RepaintBoundary(child: _pageFrame(rs, index)),
          ),
        );
      case PageMode.scroll:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, width),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification) _persistProgress();
              return false;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.only(
                left: rs.paddingLeft,
                right: rs.paddingRight,
                top: rs.paddingTop,
                bottom: rs.paddingBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final para in _scrollParagraphs())
                    Padding(
                      padding: EdgeInsets.only(bottom: rs.paragraphSpacing),
                      child: Text(para, style: _textStyle(rs)),
                    ),
                ],
              ),
            ),
          ),
        );
      case PageMode.cover:
      case PageMode.none:
        // 三页预构建（上一页 / 当前页 / 下一页）；动画只更新 Transform，
        // 不重建页面内容，因此不会卡顿。
        final hasPrev = _flatIndex > 0;
        final hasNext = _flatIndex + 1 < _flat.length;
        final prevPage = hasPrev
            ? RepaintBoundary(child: _pageFrame(rs, _flatIndex - 1))
            : null;
        final currentPage = RepaintBoundary(child: _pageFrame(rs, _flatIndex));
        final nextPage = hasNext
            ? RepaintBoundary(child: _pageFrame(rs, _flatIndex + 1))
            : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, width),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: (d) => _onDragEnd(d, width),
          child: ValueListenableBuilder<double>(
            valueListenable: _drag,
            builder: (context, drag, _) => Stack(
              children: [
                if (prevPage != null && drag > 0)
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(-width + drag, 0),
                      child: prevPage,
                    ),
                  ),
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(drag, 0),
                    child: currentPage,
                  ),
                ),
                if (nextPage != null && drag < 0)
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(width + drag, 0),
                      child: nextPage,
                    ),
                  ),
              ],
            ),
          ),
        );
    }
  }

  List<String> _scrollParagraphs() => _chapterTextOf(_chapterIndex)
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => '${_rs.paragraphIndent}$e')
      .toList();

  Widget _pageFrame(ReaderSettings rs, int flatIndex) {
    final flat =
        flatIndex >= 0 && flatIndex < _flat.length ? _flat[flatIndex] : null;
    final headerHeight = _tipBarHeight(rs, isHeader: true);
    final footerHeight = _tipBarHeight(rs, isHeader: false);
    return Container(
      padding: EdgeInsets.only(
        left: rs.paddingLeft,
        right: rs.paddingRight,
        top: rs.paddingTop,
        bottom: rs.paddingBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerHeight > 0)
            SizedBox(
              height: headerHeight,
              child: _tipBar(rs, isHeader: true, flat: flat),
            ),
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (flat != null)
                    for (final para in flat.page.paragraphs) ...[
                      Text(para.text, style: _textStyle(rs)),
                      if (para.gapAfter > 0) SizedBox(height: para.gapAfter),
                    ],
                ],
              ),
            ),
          ),
          if (footerHeight > 0)
            SizedBox(
              height: footerHeight,
              child: _tipBar(rs, isHeader: false, flat: flat),
            ),
        ],
      ),
    );
  }

  Widget _tipBar(ReaderSettings rs, {required bool isHeader, _FlatPage? flat}) {
    final style = TextStyle(
      fontSize: rs.textSize * 0.68,
      color: parseHexColor(rs.textColor, fallback: Colors.black)
          .withValues(alpha: 0.65),
    );
    Widget slot(TipMode mode) => Text(
      _tipText(mode, flat),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Column(
      mainAxisAlignment:
          isHeader ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (isHeader && rs.showHeaderLine)
          Divider(height: 8, thickness: 0.5, color: style.color),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: slot(isHeader ? rs.headerLeft : rs.footerLeft),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: slot(isHeader ? rs.headerMiddle : rs.footerMiddle),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: slot(isHeader ? rs.headerRight : rs.footerRight),
                ),
              ),
            ],
          ),
        ),
        if (!isHeader && rs.showFooterLine)
          Divider(height: 8, thickness: 0.5, color: style.color),
      ],
    );
  }

  String _tipText(TipMode mode, _FlatPage? flat) {
    final chapter = flat?.chapter ?? _chapterIndex;
    switch (mode) {
      case TipMode.none:
        return '';
      case TipMode.bookName:
        return widget.book.title;
      case TipMode.chapterName:
        return _chapters.isEmpty ? '' : _chapters[chapter].title;
      case TipMode.pageIndex:
        final total = _pagesOfChapter(chapter).length;
        return '${(flat?.pageInChapter ?? 0) + 1}/$total';
      case TipMode.progress:
        return '${(_bookProgress * 100).toStringAsFixed(1)}%';
      case TipMode.time:
        return DateFormat('HH:mm').format(DateTime.now());
      case TipMode.battery:
        return '';
    }
  }

  /// 目录抽屉：z 序在左右侧栏之上，因此贴左显示并覆盖侧栏即可。
  Widget _buildToc(ReaderSettings rs) {
    final bg = parseHexColor(rs.bgColor, fallback: Colors.white);
    final fg = parseHexColor(rs.textColor, fallback: Colors.black);
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: math.min(320, MediaQuery.of(context).size.width * 0.78),
      child: Material(
        color: bg,
        elevation: 8,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text('目录', style: TextStyle(color: fg, fontSize: 16)),
                trailing: IconButton(
                  icon: Icon(Icons.close, color: fg),
                  onPressed: () => setState(() => _tocVisible = false),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _chapters.length,
                  itemBuilder: (context, i) {
                    final selected = i == _chapterIndex;
                    return ListTile(
                      dense: true,
                      title: Text(
                        _chapters[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : fg,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => _goChapter(i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 菜单 ----------------

  Widget _buildMenu(
    ReaderSettings rs,
    AppState state, {
    required bool isLandscape,
  }) {
    final sideBars = isLandscape && rs.landscapeSideMenu;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_menuVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _menuVisible ? 1 : 0,
          child: sideBars
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sidePanel(
                      width: _sideWidth,
                      child: _menuTop(state, side: true),
                    ),
                    Expanded(
                      child: _panel == null
                          ? const SizedBox.shrink()
                          : Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: _panelBody(rs, state),
                              ),
                            ),
                    ),
                    _sidePanel(
                      width: _sideWidth,
                      child: _menuBottom(rs, state, side: true),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _menuTop(state),
                    const Spacer(),
                    if (_panel != null) _panelBody(rs, state),
                    _menuBottom(rs, state),
                  ],
                ),
        ),
      ),
    );
  }

  double get _sideWidth => (_viewport.width * 0.22).clamp(132.0, 208.0);

  Widget _sidePanel({required double width, required Widget child}) => SizedBox(
    width: width,
    child: Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(child: child),
    ),
  );

  /// 竖向章节进度条：直接上下拖动跳章（不使用旋转）。
  Widget _verticalChapterProgress() => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      if (height <= 0) return const SizedBox.shrink();
      final maxIndex = math.max(1, _chapters.length - 1);
      final ratio = (_chapterIndex / maxIndex).clamp(0.0, 1.0);
      void seek(double dy) {
        final t = (dy / height).clamp(0.0, 1.0);
        _goChapter((t * maxIndex).round());
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seek(d.localPosition.dy),
        onVerticalDragUpdate: (d) => seek(d.localPosition.dy),
        child: SizedBox(
          width: 32,
          height: height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Center(
                child: Container(
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                top: ((height - 18) * ratio)
                    .clamp(0.0, math.max(0.0, height - 18)),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _menuTop(AppState state, {bool side = false}) {
    final title = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.book.title,
          maxLines: side ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        Text(
          _chapters.isEmpty ? '' : _chapters[_chapterIndex].title,
          maxLines: side ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
    final backButton = IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      tooltip: '返回',
      onPressed: () async {
        await _persistProgress();
        if (mounted) Navigator.of(context).pop();
      },
    );
    final moreButton = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: _onMenuAction,
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'night', child: Text('切换夜间/日间')),
        CheckedPopupMenuItem(
          value: 'sideMenu',
          checked: _rs.landscapeSideMenu,
          child: const Text('横屏时菜单显示在左右'),
        ),
      ],
    );

    if (side) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [backButton, const Spacer(), moreButton]),
            const SizedBox(height: 8),
            title,
          ],
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [backButton, Expanded(child: title), moreButton],
          ),
        ),
      ),
    );
  }

  void _onMenuAction(String value) {
    final state = context.read<AppState>();
    final rs = _rs;
    switch (value) {
      case 'night':
        setState(() {
          rs.nightMode = !rs.nightMode;
          final style =
              kReadingStyles[rs.styleIndex.clamp(0, kReadingStyles.length - 1)];
          rs.bgColor = rs.nightMode ? style.bgColorNight : style.bgColor;
          rs.textColor = rs.nightMode ? style.textColorNight : style.textColor;
          _paginateSignature = '';
        });
        state.saveReaderSettings();
      case 'sideMenu':
        setState(() => rs.landscapeSideMenu = !rs.landscapeSideMenu);
        state.saveReaderSettings();
    }
  }

  Widget _menuBottom(ReaderSettings rs, AppState state, {bool side = false}) {
    final buttons = <Widget>[
      _menuButton(
        Icons.list,
        '目录',
        () => setState(() => _tocVisible = !_tocVisible),
        side: side,
      ),
      _menuButton(
        Icons.brightness_6,
        '亮度',
        () => _togglePanel('bright'),
        side: side,
      ),
      _menuButton(
        Icons.color_lens_outlined,
        '背景',
        () => _togglePanel('bg'),
        side: side,
      ),
      _menuButton(
        Icons.text_fields,
        '字号',
        () => _togglePanel('font'),
        side: side,
      ),
      _menuButton(
        Icons.auto_stories_outlined,
        '翻页',
        () => _togglePanel('page'),
        side: side,
      ),
    ];

    if (side) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${(_bookProgress * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(child: Center(child: _verticalChapterProgress())),
            const SizedBox(height: 8),
            Text(
              '${_chapterIndex + 1}/${_chapters.length} 章',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const Divider(color: Colors.white24, height: 20),
            for (final button in buttons) button,
          ],
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${_chapterIndex + 1}/${_chapters.length}章',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: _chapterIndex.toDouble(),
                      min: 0,
                      max: math.max(1, _chapters.length - 1).toDouble(),
                      divisions: math.max(1, _chapters.length - 1),
                      onChanged: (v) => _goChapter(v.round()),
                    ),
                  ),
                  Text(
                    '${(_bookProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buttons,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool side = false,
  }) {
    if (side) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _togglePanel(String name) {
    setState(() => _panel = _panel == name ? null : name);
  }

  Widget _panelBody(ReaderSettings rs, AppState state) {
    switch (_panel) {
      case 'font':
        return _fontPanel(rs, state);
      case 'bg':
        return _bgPanel(rs, state);
      case 'page':
        return _pagePanel(rs, state);
      case 'bright':
        return _brightPanel(rs, state);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _panelMaterial({required Widget child}) => Material(
    color: Colors.black.withValues(alpha: 0.72),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: child,
    ),
  );

  Widget _fontPanel(ReaderSettings rs, AppState state) {
    Widget stepper(
      String label,
      double value,
      VoidCallback dec,
      VoidCallback inc,
    ) => Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
          onPressed: dec,
        ),
        SizedBox(
          width: 48,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          onPressed: inc,
        ),
      ],
    );
    void update(VoidCallback change) {
      setState(() {
        change();
        _paginateSignature = '';
      });
      state.saveReaderSettings();
    }

    return _panelMaterial(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          stepper(
            '字号',
            rs.textSize,
            () => update(() => rs.textSize = math.max(12, rs.textSize - 1)),
            () => update(() => rs.textSize = math.min(40, rs.textSize + 1)),
          ),
          stepper(
            '行距',
            rs.lineSpacing,
            () => update(() => rs.lineSpacing = math.max(0, rs.lineSpacing - 2)),
            () => update(() => rs.lineSpacing = math.min(40, rs.lineSpacing + 2)),
          ),
          stepper(
            '字距',
            rs.letterSpacing,
            () =>
                update(() => rs.letterSpacing = math.max(0, rs.letterSpacing - 0.5)),
            () =>
                update(() => rs.letterSpacing = math.min(8, rs.letterSpacing + 0.5)),
          ),
          stepper(
            '段距',
            rs.paragraphSpacing,
            () => update(
              () => rs.paragraphSpacing = math.max(0, rs.paragraphSpacing - 2),
            ),
            () => update(
              () => rs.paragraphSpacing = math.min(32, rs.paragraphSpacing + 2),
            ),
          ),
          Row(
            children: [
              const SizedBox(
                width: 64,
                child: Text(
                  '加粗',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              Switch(value: rs.bold, onChanged: (v) => update(() => rs.bold = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bgPanel(ReaderSettings rs, AppState state) {
    void pick(int index) {
      setState(() {
        rs.styleIndex = index;
        rs.applyStyle(kReadingStyles[index], night: rs.nightMode);
        _paginateSignature = '';
      });
      state.saveReaderSettings();
    }

    return _panelMaterial(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kReadingStyles.length; i++)
                GestureDetector(
                  onTap: () => pick(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: parseHexColor(
                            rs.nightMode
                                ? kReadingStyles[i].bgColorNight
                                : kReadingStyles[i].bgColor,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: rs.styleIndex == i
                                ? Colors.white
                                : Colors.white24,
                            width: rs.styleIndex == i ? 2 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kReadingStyles[i].name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Row(
            children: [
              const Text(
                '夜间',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Switch(
                value: rs.nightMode,
                onChanged: (v) {
                  setState(() {
                    rs.nightMode = v;
                    rs.applyStyle(
                      kReadingStyles[
                          rs.styleIndex.clamp(0, kReadingStyles.length - 1)],
                      night: v,
                    );
                    _paginateSignature = '';
                  });
                  state.saveReaderSettings();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pagePanel(ReaderSettings rs, AppState state) => _panelMaterial(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final mode in PageMode.values)
          ChoiceChip(
            label: Text(mode.label),
            selected: rs.pageMode == mode,
            onSelected: (_) {
              setState(() {
                rs.pageMode = mode;
                _drag.value = 0;
              });
              state.saveReaderSettings();
            },
          ),
      ],
    ),
  );

  Widget _brightPanel(ReaderSettings rs, AppState state) => _panelMaterial(
    child: Row(
      children: [
        const Icon(Icons.brightness_low, color: Colors.white70, size: 18),
        Expanded(
          child: Slider(
            value: rs.brightness.clamp(0, 0.9),
            min: 0,
            max: 0.9,
            onChanged: (v) => setState(() => rs.brightness = v),
            onChangeEnd: (_) => state.saveReaderSettings(),
          ),
        ),
        const Icon(Icons.brightness_high, color: Colors.white70, size: 18),
      ],
    ),
  );
}
