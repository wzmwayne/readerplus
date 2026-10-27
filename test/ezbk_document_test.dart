import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/ezbk/ezbk_document.dart';

void main() {
  group('EZBK 解析', () {
    test('三级标题与级别上限', () {
      final doc = EzbkCodec.parse('# 章\n## 节\n### 小节\n#### 四级');
      final h = doc.headings;
      expect(h.length, 4);
      expect([for (final b in h) b.level], [1, 2, 3, 3]);
      expect(h.first.text, '章');
    });

    test('超过 120 字节的标题降级为正文', () {
      final x = 'x' * 130;
      final long = '#$x';
      final doc = EzbkCodec.parse(long);
      expect(doc.headings, isEmpty);
      expect(doc.warnings, isNotEmpty);
    });

    test('空标题降级为正文', () {
      final doc = EzbkCodec.parse('#\n# \n正文');
      expect(doc.headings, isEmpty);
      expect(doc.blocks.length, 3);
    });

    test('单独一行 --- 是换页符（兼容原项目）', () {
      final doc = EzbkCodec.parse('正文甲\n---\n正文乙');
      expect(doc.blocks.length, 3);
      expect(doc.blocks[1].isPageBreak, isTrue);
      expect(doc.toPlainText().contains('---'), isFalse);
    });

    test('@pagebreak 已不再支持（按未知命令告警）', () {
      final doc = EzbkCodec.parse('@pagebreak');
      expect(doc.commands, isEmpty);
      expect(doc.warnings, isNotEmpty);
    });

    test('转义行不参与解析', () {
      final doc = EzbkCodec.parse('\\\\# 不是标题\n\\\\@image 不是命令\n# 真标题');
      expect(doc.headings.length, 1);
      expect(doc.headings.first.text, '真标题');
      expect(doc.commands, isEmpty);
      expect(doc.blocks.first.text, '# 不是标题');
    });

    test('命令行：未知命令忽略并告警', () {
      final doc = EzbkCodec.parse('@unknown a b\n@hr\n正文');
      expect(doc.commands.length, 1);
      expect(doc.commands.first.name, 'hr');
      expect(doc.warnings.length, 1);
    });

    test('命令行：双引号参数与 meta', () {
      final doc = EzbkCodec.parse('@meta title 夜航船\n@image "res/my cover.jpg" 封面');
      expect(doc.meta['title'], '夜航船');
      final img = doc.commands.firstWhere((c) => c.name == 'image');
      expect(img.args[0], 'res/my cover.jpg');
      expect(img.args[1], '封面');
    });

    test('@blob base64 往返', () {
      final bytes = utf8.encode('hello ezbk');
      final b64 = base64Encode(bytes);
      final src = '@blob cover $b64\n@image blob:cover';
      final doc = EzbkCodec.parse(src);
      expect(doc.blobs['cover'], isNotNull);
      expect(utf8.decode(doc.blobs['cover']!), 'hello ezbk');
    });

    test('@blob 非法 base64 忽略并告警', () {
      final doc = EzbkCodec.parse('@blob bad !!!notbase64');
      expect(doc.blobs, isEmpty);
      expect(doc.warnings, isNotEmpty);
    });

    test('CRLF 与 LF 结果一致', () {
      final a = EzbkCodec.parse('# 章\n正文');
      final b = EzbkCodec.parse('# 章\r\n正文');
      expect(a.blocks.length, b.blocks.length);
      expect(a.headings.first.text, b.headings.first.text);
    });

    test('空文件不崩溃', () {
      final doc = EzbkCodec.parse('');
      expect(doc.blocks, isEmpty);
      expect(doc.headings, isEmpty);
    });

    test('序列化可重新解析（往返）', () {
      final doc = EzbkCodec.parse('# 章\n## 节\n正文一\n正文二');
      final again = EzbkCodec.parse(EzbkCodec.serialize(doc));
      expect(again.headings.length, doc.headings.length);
      expect(again.blocks.length, doc.blocks.length);
      expect([for (final b in again.headings) b.level], [1, 2]);
    });
  });
}