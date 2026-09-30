import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/text_cleaner.dart';
import 'package:reader/services/txt_importer.dart';

void main() {
  group('清理规则', () {
    test('内置规则默认状态符合预期', () {
      final rules = TextCleaner.defaultRules();
      expect(rules, isNotEmpty);
      expect(
        rules.firstWhere((r) => r.name.contains('段落合并')).enabled,
        isFalse,
        reason: '略激进的规则应默认关闭',
      );
      expect(rules.firstWhere((r) => r.name.contains('广告')).enabled, isTrue);
    });

    test('去除行首行尾空白与连续空行', () {
      const input = '　　第一章 起点  \n\n\n\n正文一　\n正文二\t\n';
      final out = TextCleaner.apply(input, TextCleaner.defaultRules());
      expect(out, isNot(contains('　　')));
      expect(out, isNot(contains('  \n')));
      expect(out, isNot(contains('\n\n\n')));
      expect(out, contains('第一章 起点\n'));
      expect(out, contains('正文一\n'));
      expect(out, contains('正文二\n'));
    });

    test('去除广告行与零宽字符', () {
      const input = '正文\n请收藏本站 www.example.com 最新章节\n更多内容\u200B在此';
      final out = TextCleaner.apply(input, TextCleaner.defaultRules());
      expect(out, isNot(contains('请收藏')));
      expect(out, isNot(contains('www.example.com')));
      expect(out, isNot(contains('\u200B')));
      expect(out, contains('更多内容在此'));
    });

    test('省略号统一', () {
      expect(TextCleaner.apply('他说...然后走了', TextCleaner.defaultRules()), '他说……然后走了');
    });

    test('停用的规则不生效', () {
      final rules = [
        CleanRule(name: '测试', pattern: '去掉', enabled: false),
      ];
      expect(TextCleaner.apply('去掉我', rules), '去掉我');
    });

    test('支持分组引用', () {
      final rules = [
        CleanRule(name: '包裹', pattern: r'^(.+)$', replacement: r'【$1】'),
      ];
      expect(TextCleaner.apply('标题', rules), '【标题】');
    });

    test('非法正则不影响导入', () {
      final rules = [CleanRule(name: '坏规则', pattern: '(')];
      expect(TextCleaner.apply('正文', rules), '正文');
      expect(TextCleaner.matchCount('正文', rules.first), 0);
    });

    test('命中次数统计', () {
      expect(
        TextCleaner.matchCount('a\n\nb\n\nc', CleanRule(name: '空行', pattern: r'\n\n')),
        2,
      );
    });
  });

  group('导入时应用清理', () {
    test('parseBytes 先清理再切分章节', () {
      const raw = '\uFEFF　　第一章 起点  \n\n\n正文甲\n\n\n第二章 终点\n正文乙\n';
      final parsed = TxtImporter.parseBytes(
        utf8.encode(raw),
        cleanRules: TextCleaner.defaultRules(),
      );
      expect(parsed.chapters.length, 2);
      expect(parsed.chapters[0].title, contains('第一章'));
      expect(parsed.content, isNot(contains('　　')));
      expect(parsed.content, isNot(contains('\n\n\n')));
    });

    test('不传规则时保持原样', () {
      const raw = '　　第一章 起点  \n\n\n正文甲\n';
      final parsed = TxtImporter.parseBytes(utf8.encode(raw));
      expect(parsed.content, raw);
    });
  });
}
