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

/// 阅读界面。
///
/// 交互约定：
///   点击左侧 1/3 上一页，右侧 1/3 下一页，中间 1/3 呼出菜单
///   覆盖 / 滑动模式翻页有动画，无动画模式点击与滑动都立即切换
///   阅读进度按「章节 + 屏幕首行行号」保存，与设备分辨率、字号无关
///   横屏时菜单顶栏/底栏显示在左右两侧（可在菜单里关闭）
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with SingleTickerProviderStateMixin {
  List<Chapter> _chapters = const [];
  String _content = '';
  int _chapterIndex = 0;
  List<ReaderPageContent> _pages = const [];
  int _pageIndex = 0;
  bool _loading = true;

  bool _menuVisible = false;
  String? _panel;
  bool _tocVisible = false;

  /// 分页结果的签名：尺寸、字体缩放或排版设置变化时重新分页。
  String _paginateSignature = '';
  Size _viewport = Size.zero;

  /// 待恢复的行号（打开书籍或跳章时设置）。
  int? _pendingLine;

  double _drag = 0;
  late final AnimationController _settle;
  double _settleFrom = 0;
  double _settleTo = 0;
  VoidCallback? _settleThen;

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
      setState(() {
        _drag = _settleFrom + (_settleTo - _settleFrom) * _settle.value;
      });
    });
    _settle.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final then = _settleThen;
      _settleThen = null;
      if (!mounted) return;
      setState(() => _drag = 0);
      then?.call();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _settle.dispose();
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

  /// 页眉/页脚的精确高度，分页与渲染共用，保证不会超出。
  double _tipBarHeight(ReaderSettings rs, {required bool isHeader}) {
    final hasAny = isHeader ? _hasHeader(rs) : _hasFooter(rs);
    if (!hasAny) return 0;
    final textHeight = rs.textSize * 0.68 * 1.25;
    const padding = 12.0; // 上下内边距之和
    final showLine = isHeader ? rs.showHeaderLine : rs.showFooterLine;
    return textHeight + padding + (showLine ? 8 : 0);
  }

  String get _chapterText {
    if (_chapters.isEmpty) return _content;
    final ch = _chapters[_chapterIndex];
    final start = ch.start.clamp(0, _content.length);
    final end = ch.end.clamp(start, _content.length);
    return _content.substring(start, end);
  }

  double get _bookProgress => _chapters.isEmpty
      ? 0
      : ((_chapterIndex + (_pages.isEmpty ? 0 : _pageIndex / _pages.length)) /
                _chapters.length)
            .clamp(0, 1)
            .toDouble();

  double get _scrollLineHeight {
    final rs = _rs;
    return rs.textSize + rs.lineSpacing + rs.paragraphSpacing + 1;
  }

  // ---------------- 分页 ----------------

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
    if (signature == _paginateSignature) return;
    _paginateSignature = signature;

    final headerHeight = _tipBarHeight(rs, isHeader: true);
    final footerHeight = _tipBarHeight(rs, isHeader: false);
    final maxWidth = size.width - rs.paddingLeft - rs.paddingRight;
    final maxHeight =
        size.height - rs.paddingTop - rs.paddingBottom - headerHeight - footerHeight;

    final pages = ChapterPaginator.paginate(
      text: _chapterText,
      style: _textStyle(rs),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      indent: rs.paragraphIndent,
      paragraphSpacing: rs.paragraphSpacing,
      textScaler: scaler,
    );
    _pages = pages;

    final pending = _pendingLine;
    _pendingLine = null;
    if (pending != null) {
      _pageIndex = ChapterPaginator.pageIndexForLine(pages, pending);
    } else {
      _pageIndex = _pageIndex.clamp(0, pages.length - 1);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (rs.pageMode == PageMode.slide && _slideController.hasClients) {
        _slideController.jumpToPage(_pageIndex);
      }
      if (rs.pageMode == PageMode.scroll && _scrollController.hasClients) {
        final target = (pending ?? _pages[_pageIndex].firstLine) * _scrollLineHeight;
        _scrollController.jumpTo(target.clamp(0, _scrollController.position.maxScrollExtent));
      }
    });
  }

  // ---------------- 翻页 ----------------

  void _applyTurn(int delta) {
    final target = _pageIndex + delta;
    if (target < 0) {
      _goChapter(_chapterIndex - 1, toLastPage: true);
      return;
    }
    if (target >= _pages.length) {
      _goChapter(_chapterIndex + 1);
      return;
    }
    setState(() => _pageIndex = target);
    _persistProgress();
  }

  /// 翻页；覆盖 / 滑动模式有动画，无动画模式直接切换。
  void _turnPage(int delta) {
    if (_pages.isEmpty) return;
    switch (_rs.pageMode) {
      case PageMode.cover:
        final width = _viewport.width;
        _animateDragTo(delta > 0 ? -width : width, then: () => _applyTurn(delta));
      case PageMode.slide:
        final target = _pageIndex + delta;
        if (target < 0 || target >= _pages.length) {
          _applyTurn(delta);
          return;
        }
        if (_slideController.hasClients) {
          _slideController.animateToPage(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        } else {
          _applyTurn(delta);
        }
      case PageMode.none:
      case PageMode.scroll:
        _applyTurn(delta);
    }
  }

  void _goChapter(int index, {bool toLastPage = false}) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _pages = const [];
      _paginateSignature = '';
      _pendingLine = toLastPage ? null : 0;
      _menuVisible = false;
      _tocVisible = false;
      _drag = 0;
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
      _turnPage(-1);
    } else if (x > width * 2 / 3) {
      _turnPage(1);
    } else {
      setState(() => _menuVisible = true);
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (_settle.isAnimating) _settle.stop();
    setState(() {
      _drag = (_drag + details.delta.dx).clamp(-width, width);
    });
  }

  void _onDragEnd(DragEndDetails details, double width) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final goNext = _drag < -width * 0.22 || (velocity < -600 && _drag < -20);
    final goPrev = _drag > width * 0.22 || (velocity > 600 && _drag > 20);

    if (_rs.pageMode == PageMode.none) {
      // 无动画模式：滑动即时生效
      setState(() {
        _drag = 0;
        if (goNext) {
          _applyTurn(1);
        } else if (goPrev) {
          _applyTurn(-1);
        }
      });
      return;
    }
    if (goNext) {
      _animateDragTo(-width, then: () => _applyTurn(1));
    } else if (goPrev) {
      _animateDragTo(width, then: () => _applyTurn(-1));
    } else {
      _animateDragTo(0);
    }
  }

  void _animateDragTo(double target, {VoidCallback? then}) {
    _settleFrom = _drag;
    _settleTo = target;
    _settleThen = then;
    _settle.forward(from: 0);
  }

  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final state = context.read<AppState>();
    final line = _pages.isEmpty
        ? 0
        : _pages[_pageIndex.clamp(0, _pages.length - 1)].firstLine;
    final offset = _pages.isEmpty
        ? 0
        : _pages[_pageIndex.clamp(0, _pages.length - 1)].startOffset;
    await state.saveProgress(
      widget.book,
      _chapterIndex,
      line,
      offset,
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
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _paginateIfNeeded(constraints, rs, scaler);
          return Stack(
            children: [
              Positioned.fill(child: _buildContent(constraints, rs, scaler)),
              if (rs.brightness > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: rs.brightness * 0.6),
                    ),
                  ),
                ),
              if (_tocVisible) _buildToc(rs),
              _buildMenu(rs, state, isLandscape: isLandscape),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BoxConstraints constraints,
    ReaderSettings rs,
    TextScaler scaler,
  ) {
    final width = constraints.maxWidth;
    switch (rs.pageMode) {
      case PageMode.slide:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, width),
          child: PageView.builder(
            controller: _slideController,
            itemCount: _pages.length,
            onPageChanged: (i) {
              setState(() => _pageIndex = i);
              _persistProgress();
            },
            itemBuilder: (context, index) => _pageFrame(rs, index, scaler),
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
        final animated = rs.pageMode == PageMode.cover;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, width),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: (d) => _onDragEnd(d, width),
          child: Stack(
            children: [
              if (_drag > 0 && _pageIndex > 0)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(-width + _drag, 0),
                    child: _pageFrame(rs, _pageIndex - 1, scaler),
                  ),
                ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(animated ? _drag : 0, 0),
                  child: _pageFrame(rs, _pageIndex, scaler),
                ),
              ),
              if (animated && _drag < 0 && _pageIndex + 1 < _pages.length)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(width + _drag, 0),
                    child: _pageFrame(rs, _pageIndex + 1, scaler),
                  ),
                ),
            ],
          ),
        );
    }
  }

  List<String> _scrollParagraphs() => _chapterText
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => '${_rs.paragraphIndent}$e')
      .toList();

  Widget _pageFrame(ReaderSettings rs, int index, TextScaler scaler) {
    final page = index >= 0 && index < _pages.length ? _pages[index] : null;
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
            SizedBox(height: headerHeight, child: _tipBar(rs, isHeader: true)),
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (page != null)
                    for (final para in page.paragraphs) ...[
                      Text(para.text, style: _textStyle(rs)),
                      if (para.gapAfter > 0) SizedBox(height: para.gapAfter),
                    ],
                ],
              ),
            ),
          ),
          if (footerHeight > 0)
            SizedBox(height: footerHeight, child: _tipBar(rs, isHeader: false)),
        ],
      ),
    );
  }

  Widget _tipBar(ReaderSettings rs, {required bool isHeader}) {
    final style = TextStyle(
      fontSize: rs.textSize * 0.68,
      color: parseHexColor(rs.textColor, fallback: Colors.black)
          .withValues(alpha: 0.65),
    );
    Widget slot(TipMode mode) => Text(
      _tipText(mode),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Column(
      mainAxisAlignment: isHeader ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (isHeader && rs.showHeaderLine)
          Divider(height: 8, thickness: 0.5, color: style.color),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
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

  String _tipText(TipMode mode) {
    switch (mode) {
      case TipMode.none:
        return '';
      case TipMode.bookName:
        return widget.book.title;
      case TipMode.chapterName:
        return _chapters.isEmpty ? '' : _chapters[_chapterIndex].title;
      case TipMode.pageIndex:
        return '${_pageIndex + 1}/${_pages.length}';
      case TipMode.progress:
        return '${(_bookProgress * 100).toStringAsFixed(1)}%';
      case TipMode.time:
        return DateFormat('HH:mm').format(DateTime.now());
      case TipMode.battery:
        return '';
    }
  }

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

  Widget _buildMenu(ReaderSettings rs, AppState state, {required bool isLandscape}) {
    final sideBars = isLandscape && rs.landscapeSideMenu;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_menuVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _menuVisible ? 1 : 0,
          child: sideBars
              ? Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: _menuTop(state, vertical: true),
                      ),
                    ),
                    Expanded(
                      child: _panel == null
                          ? const SizedBox.shrink()
                          : Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 520),
                                child: _panelBody(rs, state),
                              ),
                            ),
                    ),
                    SizedBox(
                      width: 52,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _menuBottom(rs, state, vertical: true),
                      ),
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

  Widget _menuTop(AppState state, {bool vertical = false}) {
    final bar = Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: vertical ? null : 52,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  await _persistProgress();
                  if (mounted) Navigator.of(context).pop();
                },
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    Text(
                      _chapters.isEmpty ? '' : _chapters[_chapterIndex].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  final rs = _rs;
                  switch (value) {
                    case 'night':
                      setState(() {
                        rs.nightMode = !rs.nightMode;
                        final style = kReadingStyles[
                            rs.styleIndex.clamp(0, kReadingStyles.length - 1)];
                        rs.bgColor =
                            rs.nightMode ? style.bgColorNight : style.bgColor;
                        rs.textColor = rs.nightMode
                            ? style.textColorNight
                            : style.textColor;
                        _paginateSignature = '';
                      });
                      state.saveReaderSettings();
                    case 'sideMenu':
                      setState(() {
                        rs.landscapeSideMenu = !rs.landscapeSideMenu;
                      });
                      state.saveReaderSettings();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'night', child: Text('切换夜间/日间')),
                  CheckedPopupMenuItem(
                    value: 'sideMenu',
                    checked: _rs.landscapeSideMenu,
                    child: const Text('横屏时菜单显示在左右'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return bar;
  }

  Widget _menuBottom(ReaderSettings rs, AppState state, {bool vertical = false}) {
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
                children: [
                  _menuButton(Icons.list, '目录',
                      () => setState(() => _tocVisible = !_tocVisible)),
                  _menuButton(Icons.brightness_6, '亮度', () => _togglePanel('bright')),
                  _menuButton(Icons.color_lens_outlined, '背景', () => _togglePanel('bg')),
                  _menuButton(Icons.text_fields, '字号', () => _togglePanel('font')),
                  _menuButton(Icons.auto_stories_outlined, '翻页', () => _togglePanel('page')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    ),
  );

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
    Widget stepper(String label, double value, VoidCallback dec, VoidCallback inc) =>
        Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                onPressed: dec),
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
                onPressed: inc),
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
            () => update(() => rs.letterSpacing = math.max(0, rs.letterSpacing - 0.5)),
            () => update(() => rs.letterSpacing = math.min(8, rs.letterSpacing + 0.5)),
          ),
          stepper(
            '段距',
            rs.paragraphSpacing,
            () => update(
                () => rs.paragraphSpacing = math.max(0, rs.paragraphSpacing - 2)),
            () => update(
                () => rs.paragraphSpacing = math.min(32, rs.paragraphSpacing + 2)),
          ),
          Row(
            children: [
              const SizedBox(
                width: 64,
                child: Text('加粗',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                            color: rs.styleIndex == i ? Colors.white : Colors.white24,
                            width: rs.styleIndex == i ? 2 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(kReadingStyles[i].name,
                          style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
          Row(
            children: [
              const Text('夜间', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Switch(
                value: rs.nightMode,
                onChanged: (v) {
                  setState(() {
                    rs.nightMode = v;
                    rs.applyStyle(
                      kReadingStyles[rs.styleIndex.clamp(0, kReadingStyles.length - 1)],
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
                _pageIndex = 0;
                _pendingLine = _pages.isEmpty ? 0 : _pages[_pageIndex].firstLine;
                _paginateSignature = '';
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
