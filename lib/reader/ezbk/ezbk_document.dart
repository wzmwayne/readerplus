import 'dart:convert';
import 'dart:typed_data';

/// EZBK v1.1 文档模型与解析 / 序列化。
///
/// 规范：docs/ezbk-format-v1.1.md。判定顺序为
/// 转义行 -> 标题 -> 命令 -> 正文；未知命令只记 warning，不中断解析。
const String ezbkMagic = 'EZBK0001';
const int ezbkMaxHeadingLevel = 3;
const int ezbkMaxHeadingBytes = 120;
const int ezbkMaxInlineBlobBytes = 256 * 1024;

enum EzbkBlockKind { heading, paragraph }

class EzbkBlock {
  const EzbkBlock(this.kind, this.text, {this.level = 1});

  final EzbkBlockKind kind;
  final String text;
  final int level;

  bool get isHeading => kind == EzbkBlockKind.heading;

  /// 规范文本形式（标题带前导 #）。
  String get source =>
      isHeading ? '${String.fromCharCodes(List.filled(level, 0x23))} $text' : text;
}

class EzbkCommand {
  const EzbkCommand(this.name, this.args);

  final String name;
  final List<String> args;

  String? arg(int index) => index >= 0 && index < args.length ? args[index] : null;
}

class EzbkDocument {
  EzbkDocument({
    required this.blocks,
    required this.commands,
    required this.meta,
    required this.blobs,
    required this.warnings,
  });

  final List<EzbkBlock> blocks;
  final List<EzbkCommand> commands;
  final Map<String, String> meta;
  final Map<String, Uint8List> blobs;
  final List<String> warnings;

  List<EzbkBlock> get headings {
    final out = <EzbkBlock>[];
    for (final b in blocks) {
      if (b.isHeading) out.add(b);
    }
    return out;
  }

  String get title {
    final fromMeta = meta['title'];
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    final h = headings;
    return h.isEmpty ? '' : h.first.text;
  }

  /// 纯文本渲染（丢弃命令、解引用不了的资源）。
  String toPlainText() {
    final buffer = StringBuffer();
    for (final b in blocks) {
      buffer.writeln(b.text);
    }
    return buffer.toString();
  }
}

/// EZBK 解析与序列化。
class EzbkCodec {
  const EzbkCodec._();

  static EzbkDocument parse(String source) {
    final blocks = <EzbkBlock>[];
    final commands = <EzbkCommand>[];
    final meta = <String, String>{};
    final blobs = <String, Uint8List>{};
    final warnings = <String>[];

    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    var start = 0;
    if (lines.isNotEmpty && lines.first.trim() == ezbkMagic) start = 1;

    for (var i = start; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      // 1) 转义行：行首两个反斜杠，去掉后按字面输出
      if (raw.startsWith('\\\\')) {
        blocks.add(EzbkBlock(EzbkBlockKind.paragraph, raw.substring(2)));
        continue;
      }

      // 2) 标题行
      if (raw.startsWith('#')) {
        var level = 0;
        while (level < raw.length && raw.codeUnitAt(level) == 0x23) {
          level++;
        }
        final text = raw.substring(level).trim();
        final tooLong = utf8.encode(raw).length >= ezbkMaxHeadingBytes;
        if (text.isEmpty || tooLong) {
          if (tooLong) warnings.add('第 ${i + 1} 行标题超过 $ezbkMaxHeadingBytes 字节，已降级为正文');
          blocks.add(EzbkBlock(EzbkBlockKind.paragraph, raw));
          continue;
        }
        final capped = level > ezbkMaxHeadingLevel ? ezbkMaxHeadingLevel : level;
        blocks.add(EzbkBlock(EzbkBlockKind.heading, text, level: capped));
        continue;
      }

      // 3) 命令行
      if (raw.startsWith('@')) {
        final body = raw.substring(1).trim();
        if (body.isEmpty) {
          warnings.add('第 ${i + 1} 行是空的命令行，已忽略');
          continue;
        }
        final parts = splitCommandArgs(body);
        final name = parts.isEmpty ? '' : parts.first;
        final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
        if (name.isEmpty) {
          warnings.add('第 ${i + 1} 行缺少命令名，已忽略');
          continue;
        }
        final command = EzbkCommand(name, args);
        switch (name) {
          case 'meta':
            if (args.length >= 2) {
              meta[args[0]] = args.sublist(1).join(' ');
              commands.add(command);
            } else {
              warnings.add('第 ${i + 1} 行 @meta 缺少键或值，已忽略');
            }
          case 'blob':
            if (args.length >= 2) {
              final decoded = _tryBase64(args[1]);
              if (decoded == null) {
                warnings.add('第 ${i + 1} 行 @blob base64 解码失败，已忽略');
              } else {
                blobs[args[0]] = decoded;
                commands.add(command);
                if (decoded.length > ezbkMaxInlineBlobBytes) {
                  warnings.add('第 ${i + 1} 行 @blob 超过建议上限 256KB');
                }
              }
            } else {
              warnings.add('第 ${i + 1} 行 @blob 缺少名称或数据，已忽略');
            }
          case 'image':
          case 'hr':
          case 'toc':
          case 'pagebreak':
            commands.add(command);
          default:
            warnings.add('第 ${i + 1} 行未知命令 @$name，已忽略');
        }
        continue;
      }

      // 4) 正文
      blocks.add(EzbkBlock(EzbkBlockKind.paragraph, raw));
    }

    return EzbkDocument(
      blocks: blocks,
      commands: commands,
      meta: meta,
      blobs: blobs,
      warnings: warnings,
    );
  }

  /// 规范化输出：魔数 + 块 + 命令（保持原始相对顺序有限：此处按块在前、命令在后）。
  static String serialize(EzbkDocument doc) {
    final buffer = StringBuffer();
    buffer.writeln(ezbkMagic);
    for (final entry in doc.meta.entries) {
      buffer.writeln('@meta ${entry.key} ${entry.value}');
    }
    for (final entry in doc.blobs.entries) {
      buffer.writeln('@blob ${entry.key} ${base64Encode(entry.value)}');
    }
    for (final c in doc.commands) {
      if (c.name == 'meta' || c.name == 'blob') continue;
      final args = c.args.isEmpty ? '' : ' ${c.args.join(' ')}';
      buffer.writeln('@${c.name}$args');
    }
    for (final b in doc.blocks) {
      buffer.writeln(b.source);
    }
    return buffer.toString();
  }

  /// 按空格切分命令参数，支持双引号包裹的含空格参数。
  static List<String> splitCommandArgs(String body) {
    final out = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == '"') {
        quoted = !quoted;
        continue;
      }
      if (!quoted && (ch == ' ' || ch == '\t')) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(ch);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out;
  }

  static Uint8List? _tryBase64(String text) {
    try {
      return base64Decode(text);
    } catch (_) {
      return null;
    }
  }
}