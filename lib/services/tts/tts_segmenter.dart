import 'dart:math' as math;

/// 朗读用的**分句器**：把正文切成适合逐句合成的小段。
///
/// 为什么需要它：把整段（甚至整页）一次性塞进 VITS 模型时，模型看不到句子边界，
/// 会出现"断句/连读很奇怪"的现象。逐句合成 + 预合成若干句，听感与延迟都更好。
///
/// 规则（按优先级）：
///  1. 先按句末标点切（`。！？!?；;…` 以及其后紧跟的引号/括号）；
///  2. 过短的片段（< [minLen] 字）与相邻片段合并，避免一口气蹦一个词；
///  3. 过长片段（> [maxLen] 字）在次级标点（`，,、：:`）处再切，尽量不切破短语；
///  4. 仍过长则按 [maxLen] 硬切，保证单句不会让合成等待过久。
class TtsSegmenter {
  const TtsSegmenter._();

  /// 句末终止符。
  static const _terminators = '。！？!?；;…';

  /// 可跟在终止符后面、应归到本句的收尾符号。
  static const _closers = '”’」』）】》"\'()[]';

  /// 次级停顿符（长句再切分用）。
  static const _softBreaks = '，,、：:—';

  static List<String> split(
    String text, {
    int maxLen = 60,
    int minLen = 6,
  }) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t\u3000]+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];

    final sentences = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final s = buffer.toString().trim();
      buffer.clear();
      if (s.isNotEmpty) sentences.add(s);
    }

    for (var i = 0; i < normalized.length; i++) {
      final ch = normalized[i];
      if (ch == '\n') {
        flush();
        continue;
      }
      buffer.write(ch);
      if (_terminators.contains(ch)) {
        // 把紧跟的收尾引号/括号并进本句
        while (i + 1 < normalized.length && _closers.contains(normalized[i + 1])) {
          i++;
          buffer.write(normalized[i]);
        }
        flush();
      }
    }
    flush();

    // 只合并"没有句末标点"的短残片（换行 / 段落切出来的半句）。
    // 完整短句（"好。""天亮了！"）保持独立：逐句合成时这类句子反而更自然。
    final merged = <String>[];
    for (final s in sentences) {
      final unterminated = !_endsWithTerminator(s);
      if (merged.isNotEmpty && unterminated && _visibleLen(s) < minLen) {
        merged[merged.length - 1] = '${merged.last}$s';
      } else {
        merged.add(s);
      }
    }

    // 切分过长片段
    final result = <String>[];
    for (final s in merged) {
      result.addAll(_splitLong(s, maxLen));
    }
    return result.where((s) => s.trim().isNotEmpty).toList(growable: false);
  }

  /// 是否以句末标点结尾（忽略尾部的收尾引号/括号与空白）。
  static bool _endsWithTerminator(String s) {
    var i = s.length - 1;
    while (i >= 0) {
      final ch = s[i];
      if (_closers.contains(ch) || ch.trim().isEmpty) {
        i--;
        continue;
      }
      return _terminators.contains(ch);
    }
    return false;
  }

  /// 统计可见字符数（忽略空白），用于长度阈值判断。
  static int _visibleLen(String s) => s.replaceAll(RegExp(r'\s'), '').length;

  static List<String> _splitLong(String sentence, int maxLen) {
    if (_visibleLen(sentence) <= maxLen) return [sentence];
    final parts = <String>[];
    var start = 0;
    final chars = sentence.split('');
    while (start < chars.length) {
      if (_visibleLen(chars.sublist(start).join()) <= maxLen) {
        parts.add(chars.sublist(start).join());
        break;
      }
      // 在 [start, start+maxLen] 窗口内找最靠后的次级停顿符
      final windowEnd = math.min(start + maxLen, chars.length - 1);
      var cut = -1;
      for (var i = windowEnd; i > start; i--) {
        if (_softBreaks.contains(chars[i])) {
          cut = i;
          break;
        }
      }
      if (cut < 0) cut = windowEnd;
      parts.add(chars.sublist(start, cut + 1).join());
      start = cut + 1;
    }
    return parts;
  }
}
