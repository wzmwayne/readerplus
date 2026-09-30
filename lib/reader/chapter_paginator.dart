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
class ReaderPageContent {
  ReaderPageContent({required this.paragraphs, required this.startOffset, required this.endOffset});

  final List<PageParagraph> paragraphs;
  final int startOffset;
  final int endOffset;
}

/// 将章节正文按可用宽高切分为多页。
///
/// 采用先测量后切分的方式：段落用 [TextPainter] 按同一宽度布局，
/// 逐行累计高度，超出页面高度即分页，因此分页结果与最终渲染一致。
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
  }) {
    if (text.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return [ReaderPageContent(paragraphs: const [], startOffset: 0, endOffset: 0)];
    }

    final paragraphs = text.split('\n');
    final pages = <ReaderPageContent>[];
    var current = <PageParagraph>[];
    var used = 0.0;
    var paragraphOffset = 0;

    void flush() {
      if (current.isEmpty) return;
      pages.add(
        ReaderPageContent(
          paragraphs: current,
          startOffset: current.first.paragraphStart
              ? paragraphOffset
              : paragraphOffset,
          endOffset: paragraphOffset,
        ),
      );
      current = <PageParagraph>[];
      used = 0;
    }

    for (var p = 0; p < paragraphs.length; p++) {
      final raw = paragraphs[p];
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        // 空行仅在页面内留出段距，不单独占页。
        if (current.isNotEmpty && used + paragraphSpacing <= maxHeight) {
          current.last.gapAfter = paragraphSpacing;
          used += paragraphSpacing;
        }
        continue;
      }
      final content = applyIndent ? '$indent$trimmed' : trimmed;

      final painter = TextPainter(
        text: TextSpan(text: content, style: style),
        textDirection: TextDirection.ltr,
        maxLines: null,
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
      final lineCount = metrics.length < ranges.length ? metrics.length : ranges.length;
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
          if (used + chunkHeight + h > maxHeight && chunkRanges.isNotEmpty) break;
          if (used + chunkHeight + h > maxHeight && current.isNotEmpty) break;
          chunkRanges.add(ranges[i]);
          chunkHeight += h;
          i++;
        }
        if (chunkRanges.isEmpty) {
          chunkRanges.add(ranges[i]);
          chunkHeight += metrics[i].height;
          i++;
        }
        current.add(
          PageParagraph(
            text: content.substring(chunkRanges.first.start, chunkRanges.last.end),
            paragraphStart: chunkRanges.first.start == 0,
          ),
        );
        used += chunkHeight;
        if (i < lineCount) {
          flush();
        }
      }
      painter.dispose();

      // 段落间距：留给本段最后一片，若放不下则换页。
      final moreParagraphs = paragraphs.skip(p + 1).any((e) => e.trim().isNotEmpty);
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
      pages.add(ReaderPageContent(paragraphs: const [], startOffset: 0, endOffset: 0));
    }
    return pages;
  }
}
