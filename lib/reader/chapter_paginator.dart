import 'package:flutter/material.dart';

/// 页面中的一段正文。段落在跨页时会被拆成多个分片，
/// [paragraphStart] 标记该分片是否为段首（段首已包含缩进字符）。
class PageParagraph {
  PageParagraph({
    required this.text,
    required this.paragraphStart,
    this.gapAfter = 0,
  });

  final String text;
  final bool paragraphStart;
  double gapAfter;
}

/// 一页正文。
///
/// 行号用于记录阅读进度：`firstLine` / `lastLine` 是本页在**整章行序**中的下标，
/// 与设备分辨率、字号无关地表达「屏幕顶部停在哪一行」。
class ReaderPageContent {
  ReaderPageContent({
    required this.paragraphs,
    required this.firstLine,
    required this.lastLine,
    required this.startOffset,
    required this.endOffset,
  });

  final List<PageParagraph> paragraphs;
  final int firstLine;
  final int lastLine;

  /// 本页正文在整章文本中的字符区间。
  final int startOffset;
  final int endOffset;

  bool containsLine(int line) => line >= firstLine && line <= lastLine;
}

/// 将章节正文按可用宽高切分为多页。
///
/// 关键点：
/// 1. 用与渲染**完全相同**的宽度、样式与 [textScaler] 测量，避免系统字体缩放导致
///    测量结果小于实际渲染而溢出；
/// 2. 逐行累计高度，超出可用高度即分页，因此每页高度不超过可用高度；
/// 3. 记录每页首/末行号，供按「章节 + 行号」保存与恢复阅读进度。
class ChapterPaginator {
  const ChapterPaginator._();

  static List<ReaderPageContent> paginate({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required String indent,
    double paragraphSpacing = 0,
    bool applyIndent = true,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (text.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return [
        ReaderPageContent(
          paragraphs: const [],
          firstLine: 0,
          lastLine: 0,
          startOffset: 0,
          endOffset: 0,
        ),
      ];
    }

    final paragraphs = text.split('\n');
    final pages = <ReaderPageContent>[];
    var current = <PageParagraph>[];
    var used = 0.0;
    var pageFirstLine = 0;
    int? pageFirstOffset;
    var nextLine = 0;
    var paragraphOffset = 0;

    void flush() {
      if (current.isEmpty) return;
      pages.add(
        ReaderPageContent(
          paragraphs: current,
          firstLine: pageFirstLine,
          lastLine: nextLine > pageFirstLine ? nextLine - 1 : pageFirstLine,
          startOffset: pageFirstOffset ?? paragraphOffset,
          endOffset: paragraphOffset,
        ),
      );
      current = <PageParagraph>[];
      used = 0;
      pageFirstLine = nextLine;
      pageFirstOffset = null;
    }

    for (var p = 0; p < paragraphs.length; p++) {
      final raw = paragraphs[p];
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        // 空行只在页面内留出段距；放不下就换页。
        if (current.isNotEmpty) {
          if (used + paragraphSpacing <= maxHeight) {
            current.last.gapAfter = paragraphSpacing;
            used += paragraphSpacing;
          } else {
            flush();
          }
        }
        paragraphOffset += raw.length + 1;
        continue;
      }
      final content = applyIndent ? '$indent$trimmed' : trimmed;

      final painter = TextPainter(
        text: TextSpan(text: content, style: style),
        textDirection: TextDirection.ltr,
        maxLines: null,
        textScaler: textScaler,
      )..layout(maxWidth: maxWidth);

      final metrics = painter.computeLineMetrics();
      final ranges = <TextRange>[];
      var offset = 0;
      while (offset < content.length) {
        final range = painter.getLineBoundary(TextPosition(offset: offset));
        if (range.end <= range.start) break;
        ranges.add(range);
        offset = range.end;
      }
      final lineCount =
          metrics.length < ranges.length ? metrics.length : ranges.length;
      if (lineCount == 0) {
        painter.dispose();
        paragraphOffset += raw.length + 1;
        continue;
      }

      var i = 0;
      while (i < lineCount) {
        final chunkRanges = <TextRange>[];
        var chunkHeight = 0.0;
        while (i < lineCount) {
          final h = metrics[i].height;
          final wouldOverflow = used + chunkHeight + h > maxHeight;
          if (wouldOverflow && (chunkRanges.isNotEmpty || current.isNotEmpty)) {
            break;
          }
          chunkRanges.add(ranges[i]);
          chunkHeight += h;
          i++;
        }
        if (chunkRanges.isEmpty) {
          // 走到这里只可能是「本页已经放满」（current 非空）。
          // 必须先换页再放这一行，否则会多塞一行导致超出可用高度。
          if (current.isNotEmpty) {
            flush();
            continue;
          }
          // 页面为空且单行本身高于可用高度（极端小窗）：仍放一行，避免死循环。
          chunkRanges.add(ranges[i]);
          chunkHeight += metrics[i].height;
          i++;
        }
        pageFirstOffset ??= paragraphOffset + chunkRanges.first.start;
        current.add(
          PageParagraph(
            text: content.substring(
              chunkRanges.first.start,
              chunkRanges.last.end,
            ),
            paragraphStart: chunkRanges.first.start == 0,
          ),
        );
        used += chunkHeight;
        nextLine += chunkRanges.length;
        if (i < lineCount) flush();
      }
      painter.dispose();

      final moreParagraphs =
          paragraphs.skip(p + 1).any((e) => e.trim().isNotEmpty);
      if (moreParagraphs && paragraphSpacing > 0) {
        if (used + paragraphSpacing > maxHeight) {
          flush();
        } else if (current.isNotEmpty) {
          current.last.gapAfter = paragraphSpacing;
          used += paragraphSpacing;
        }
      }
      paragraphOffset += raw.length + 1;
    }

    if (current.isNotEmpty) flush();
    if (pages.isEmpty) {
      pages.add(
        ReaderPageContent(
          paragraphs: const [],
          firstLine: 0,
          lastLine: 0,
          startOffset: 0,
          endOffset: 0,
        ),
      );
    }
    return pages;
  }

  /// 找到包含指定行号的页；找不到时返回最接近的一页。
  static int pageIndexForLine(List<ReaderPageContent> pages, int line) {
    if (pages.isEmpty) return 0;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].containsLine(line)) return i;
    }
    for (var i = pages.length - 1; i >= 0; i--) {
      if (pages[i].firstLine <= line) return i;
    }
    return 0;
  }
}
