import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/script_header.dart';

void main() {
  group('头部注释声明解析', () {
    test('单行写法，含引号与逗号能力列表', () {
      final header = ScriptHeader.parse('''
"""示例书源。"""
# @readerplus kind=source id=example name="示例 书源" version=1.2 capabilities=search,detail,download

import os
''');
      expect(header, isNotNull);
      expect(header!.kind, 'source');
      expect(header.isSource, isTrue);
      expect(header.id, 'example');
      expect(header.name, '示例 书源');
      expect(header.version, '1.2');
      expect(header.capabilities, {'search', 'detail', 'download'});
    });

    test('多行续写写法', () {
      final header = ScriptHeader.parse('''
# @readerplus kind=clean
# id=txt-cleaner
# name="TXT 清洗转 EPUB"
# capabilities=clean
print("hi")
''');
      expect(header, isNotNull);
      expect(header!.isClean, isTrue);
      expect(header.id, 'txt-cleaner');
      expect(header.name, 'TXT 清洗转 EPUB');
      expect(header.capabilities, {'clean'});
    });

    test('允许大小写与冒号分隔', () {
      final header = ScriptHeader.parse('# @ReaderPlus Kind: source Capabilities: detail/dowNload');
      expect(header!.kind, 'source');
      expect(header.capabilities, {'detail', 'download'});
    });

    test('没有声明时返回 null', () {
      expect(ScriptHeader.parse('print("no declaration")'), isNull);
      expect(ScriptHeader.parse('# 普通注释\nprint(1)'), isNull);
    });

    test('解析不依赖执行代码：语法错误的脚本也能解析', () {
      final header = ScriptHeader.parse('# @readerplus kind=source\n!!! this is not python !!!');
      expect(header!.kind, 'source');
    });
  });
}
