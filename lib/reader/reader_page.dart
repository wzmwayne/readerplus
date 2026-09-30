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

/// 阅读界面：贴近原版的排版与交互。
///
/// 交互约定（与原版一致）：
///   点击左侧 1/3 上一页，右侧 1/3 下一页，中间 1/3 呼出菜单
///   翻页方式支持 覆盖 / 滑动 / 滚动 / 无动画
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
  int _pageIndex = 0;
  List<ReaderPageContent> _pages = const [];
  Size _paginatedSize = Size.zero;

  bool _menuVisible = false;
  String? _panel;
  bool _tocVisible = false;
  bool _loading = true;

  double _dragOffset = 0;
  late final AnimationController _settle;

  final PageController _slideController = PageController();

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => setState(() {}));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _load();
  }

  @override
  void dispose() {
    _settle.dispose();
    _slideController.dispose();
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
      _loading = false;
      _paginatedSize = Size.zero;
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

  double get _tipBarHeight {
    final rs = _rs;
    // 文本高度 + 上下留白，与 _tipBar 的 padding 保持一致
    return rs.textSize * 0.72 + 12;
  }

  bool _hasHeader(ReaderSettings rs) =>
      rs.headerLeft != TipMode.none || rs.headerMiddle != TipMode.none || rs.headerRight != TipMode.none;

  bool _hasFooter(ReaderSettings rs) =>
      rs.footerLeft != TipMode.none || rs.footerMiddle != TipMode.none || rs.footerRight != TipMode.none;

  String get _chapterText {
    if (_chapters.isEmpty) return _content;
    final ch = _chapters[_chapterIndex];
    final start = ch.start.clamp(0, _content.length);
    final end = ch.end.clamp(start, _content.length);
    return _content.substring(start, end);
  }

  void _paginateIfNeeded(BoxConstraints constraints, ReaderSettings rs) {
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    if (size == _paginatedSize || size.isEmpty) return;
    final style = _textStyle(rs);
    final headerHeight = _hasHeader(rs) ? _tipBarHeight : 0.0;
    final footerHeight = _hasFooter(rs) ? _tipBarHeight : 0.0;
    final maxWidth = size.width - rs.paddingLeft - rs.paddingRight;
    final maxHeight = size.height -
        rs.paddingTop -
        rs.paddingBottom -
        headerHeight -
        footerHeight;
    final pages = ChapterPaginator.paginate(
      text: _chapterText,
      style: style,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      indent: rs.paragraphIndent,
      paragraphSpacing: rs.paragraphSpacing,
    );
    _paginatedSize = size;
    _pages = pages;
    _pageIndex = _pageIndex.clamp(0, pages.length - 1);
    if (rs.pageMode == PageMode.slide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _slideController.hasClients) {
          _slideController.jumpToPage(_pageIndex);
        }
      });
    }
  }

  double get _bookProgress => _chapters.isEmpty
      ? 0
      : ((_chapterIndex + (_pages.isEmpty ? 0 : _pageIndex / _pages.length)) /
                _chapters.length)
            .clamp(0, 1)
            .toDouble();

  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final state = context.read<AppState>();
    await state.saveProgress(
      widget.book,
      _chapterIndex,
      _pages.isEmpty ? 0 : _pages[_pageIndex].startOffset,
      _bookProgress,
    );
  }

  void _turnPage(int delta) {
    if (_pages.isEmpty) return;
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
    if (_rs.pageMode == PageMode.slide && _slideController.hasClients) {
      _slideController.jumpToPage(target);
    }
    _persistProgress();
  }

  void _goChapter(int index, {bool toLastPage = false}) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _pageIndex = 0;
      _paginatedSize = Size.zero;
      _pages = const [];
      _menuVisible = false;
      _tocVisible = false;
    });
    _persistProgress();
    if (toLastPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.isNotEmpty) {
          setState(() => _pageIndex = _pages.length - 1);
        }
      });
    }
  }

  void _handleTap(TapUpDetails details, double width) {
    final x = details.localPosition.dx;
    if (x < width / 3) {
      if (!_menuVisible) _turnPage(-1);
    } else if (x > width * 2 / 3) {
      if (!_menuVisible) _turnPage(1);
    } else {
      setState(() {
        _menuVisible = !_menuVisible;
        if (!_menuVisible) {
          _panel = null;
          _tocVisible = false;
        }
      });
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double width) {
    _stopSettle();
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(-width, width);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double width) {
    final threshold = width * 0.22;
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_dragOffset < -threshold || (velocity < -600 && _dragOffset < -20)) {
      _animateDragTo(-width, thenNext: true);
    } else if (_dragOffset > threshold || (velocity > 600 && _dragOffset > 20)) {
      _animateDragTo(width, thenPrev: true);
    } else {
      _animateDragTo(0);
    }
  }

  void _stopSettle() {
    if (_settle.isAnimating) _settle.stop();
  }

  void _animateDragTo(double target, {bool thenNext = false, bool thenPrev = false}) {
    final start = _dragOffset;
    _settle.duration = const Duration(milliseconds: 200);
    _settle.reset();
    void listener() {
      setState(() => _dragOffset = start + (target - start) * _settle.value);
    }

    _settle.addListener(listener);
    _settle.forward().whenComplete(() {
      _settle.removeListener(listener);
      if (!mounted) return;
      setState(() {
        _dragOffset = 0;
        if (thenNext) {
          if (_pageIndex + 1 < _pages.length) {
            _pageIndex++;
          } else {
            _chapterIndex = math.min(_chapterIndex + 1, _chapters.length - 1);
            _pageIndex = 0;
          }
        } else if (thenPrev) {
          if (_pageIndex > 0) {
            _pageIndex--;
          } else if (_chapterIndex > 0) {
            _chapterIndex--;
            _pageIndex = 0;
          }
        }
        _paginatedSize = Size.zero;
      });
      _persistProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rs = state.readerSettings;
    final bg = parseHexColor(rs.bgColor, fallback: Colors.white);

    if (_loading) {
      return Scaffold(backgroundColor: bg, body: const Center(child: CircularProgressIndicator()));
    }
    if (_chapters.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(),
        body: const Center(child: Text('这本书还没有正文')),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _paginateIfNeeded(constraints, rs);
          return Stack(
            children: [
              Positioned.fill(child: _buildContent(constraints, rs)),
              if (rs.brightness > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(color: Colors.black.withValues(alpha: rs.brightness * 0.6)),
                  ),
                ),
              if (_tocVisible) _buildToc(rs),
              _buildMenu(rs, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(BoxConstraints constraints, ReaderSettings rs) {
    switch (rs.pageMode) {
      case PageMode.slide:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, constraints.maxWidth),
          child: PageView.builder(
            controller: _slideController,
            itemCount: _pages.length,
            onPageChanged: (i) {
              setState(() => _pageIndex = i);
              _persistProgress();
            },
            itemBuilder: (context, index) => _pageFrame(rs, index),
          ),
        );
      case PageMode.scroll:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, constraints.maxWidth),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: rs.paddingLeft,
              right: rs.paddingRight,
              top: rs.paddingTop,
              bottom: rs.paddingBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final para in _splitForScroll())
                  Padding(
                    padding: EdgeInsets.only(bottom: rs.paragraphSpacing),
                    child: Text(
                      para,
                      style: _textStyle(rs),
                    ),
                  ),
              ],
            ),
          ),
        );
      case PageMode.cover:
      case PageMode.none:
        final animated = rs.pageMode == PageMode.cover;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, constraints.maxWidth),
          onHorizontalDragUpdate: animated
              ? (d) => _onHorizontalDragUpdate(d, constraints.maxWidth)
              : null,
          onHorizontalDragEnd: animated ? (d) => _onHorizontalDragEnd(d, constraints.maxWidth) : null,
          onHorizontalDragStart: animated
              ? (_) {}
              : null,
          child: Stack(
            children: [
              if (_dragOffset > 0 && _pageIndex > 0)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(-constraints.maxWidth + _dragOffset, 0),
                    child: _pageFrame(rs, _pageIndex - 1),
                  ),
                ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(_dragOffset.clamp(animated ? -constraints.maxWidth : 0, constraints.maxWidth), 0),
                  child: _pageFrame(rs, _pageIndex),
                ),
              ),
              if (animated && _dragOffset < 0 && _pageIndex + 1 < _pages.length)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(constraints.maxWidth + _dragOffset, 0),
                    child: _pageFrame(rs, _pageIndex + 1),
                  ),
                ),
            ],
          ),
        );
    }
  }

  List<String> _splitForScroll() {
    final text = _chapterText;
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Widget _pageFrame(ReaderSettings rs, int index) {
    final page = index >= 0 && index < _pages.length ? _pages[index] : null;
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
          if (_hasHeader(rs)) _tipBar(rs, isHeader: true),
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
          if (_hasFooter(rs)) _tipBar(rs, isHeader: false),
        ],
      ),
    );
  }

  Widget _tipBar(ReaderSettings rs, {required bool isHeader}) {
    final style = TextStyle(
      fontSize: rs.textSize * 0.68,
      color: parseHexColor(rs.textColor, fallback: Colors.black).withValues(alpha: 0.65),
    );
    Widget slot(TipMode mode) => Text(_tipText(mode), style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Column(
      children: [
        if (!isHeader && rs.showFooterLine)
          Divider(height: 8, thickness: 0.5, color: style.color),
        Padding(
          padding: EdgeInsets.only(
            top: isHeader ? 8 : 4,
            bottom: isHeader ? 4 : 8,
          ),
          child: Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: slot(isHeader ? rs.headerLeft : rs.footerLeft))),
              Expanded(child: Align(alignment: Alignment.center, child: slot(isHeader ? rs.headerMiddle : rs.footerMiddle))),
              Expanded(child: Align(alignment: Alignment.centerRight, child: slot(isHeader ? rs.headerRight : rs.footerRight))),
            ],
          ),
        ),
        if (isHeader && rs.showHeaderLine)
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
                          color: selected ? Theme.of(context).colorScheme.primary : fg,
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

  Widget _buildMenu(ReaderSettings rs, AppState state) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_menuVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _menuVisible ? 1 : 0,
          child: Column(
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

  Widget _menuTop(AppState state) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
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
                  switch (value) {
                    case 'night':
                      setState(() {
                        _rs.nightMode = !_rs.nightMode;
                        final style = kReadingStyles[_rs.styleIndex.clamp(0, kReadingStyles.length - 1)];
                        _rs.bgColor = _rs.nightMode ? style.bgColorNight : style.bgColor;
                        _rs.textColor = _rs.nightMode ? style.textColorNight : style.textColor;
                        _paginatedSize = Size.zero;
                      });
                      state.saveReaderSettings();
                    case 'sync':
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const _PlaceholderSyncPage()),
                      );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'night', child: Text('切换夜间/日间')),
                  PopupMenuItem(value: 'sync', child: Text('同步与备份')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBottom(ReaderSettings rs, AppState state) {
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
                      value: _chapters.length <= 1 ? 0 : _chapterIndex.toDouble(),
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
                  _menuButton(Icons.list, '目录', () => setState(() => _tocVisible = !_tocVisible)),
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

  Widget _menuButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
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
    Widget stepper(String label, double value, VoidCallback dec, VoidCallback inc) => Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.white), onPressed: dec),
        SizedBox(
          width: 48,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.white), onPressed: inc),
      ],
    );
    void update(VoidCallback change) {
      setState(() {
        change();
        _paginatedSize = Size.zero;
      });
      state.saveReaderSettings();
    }

    return _panelMaterial(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          stepper('字号', rs.textSize, () => update(() => rs.textSize = math.max(12, rs.textSize - 1)),
              () => update(() => rs.textSize = math.min(40, rs.textSize + 1))),
          stepper('行距', rs.lineSpacing, () => update(() => rs.lineSpacing = math.max(0, rs.lineSpacing - 2)),
              () => update(() => rs.lineSpacing = math.min(40, rs.lineSpacing + 2))),
          stepper('字距', rs.letterSpacing, () => update(() => rs.letterSpacing = math.max(0, rs.letterSpacing - 0.5)),
              () => update(() => rs.letterSpacing = math.min(8, rs.letterSpacing + 0.5))),
          stepper('段距', rs.paragraphSpacing, () => update(() => rs.paragraphSpacing = math.max(0, rs.paragraphSpacing - 2)),
              () => update(() => rs.paragraphSpacing = math.min(32, rs.paragraphSpacing + 2))),
          Row(
            children: [
              const SizedBox(width: 64, child: Text('加粗', style: TextStyle(color: Colors.white70, fontSize: 13))),
              Switch(
                value: rs.bold,
                onChanged: (v) => update(() => rs.bold = v),
              ),
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
        _paginatedSize = Size.zero;
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
                            rs.nightMode ? kReadingStyles[i].bgColorNight : kReadingStyles[i].bgColor,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: rs.styleIndex == i ? Colors.white : Colors.white24,
                            width: rs.styleIndex == i ? 2 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kReadingStyles[i].name,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
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
                    rs.applyStyle(kReadingStyles[rs.styleIndex.clamp(0, kReadingStyles.length - 1)], night: v);
                    _paginatedSize = Size.zero;
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
                _paginatedSize = Size.zero;
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

class _PlaceholderSyncPage extends StatelessWidget {
  const _PlaceholderSyncPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('同步与备份')),
    body: const Center(child: Text('请在书架页的“设置”中使用同步与备份')),
  );
}
