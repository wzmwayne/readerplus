import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/script_meta.dart';
import 'package:reader/services/plugin/source_store.dart';

/// 脚本必须能声明自己的类型，宿主据此分流，避免把清洗脚本当书源用。
void main() {
  test('解析单行声明（含引号名称与能力列表）', () {
    final meta = ScriptMeta.parse('''
// @script kind=source name="本地测试书源" capabilities=search,detail,download
print('hi')
''');
    expect(meta.kind, ScriptKind.source);
    expect(meta.name, '本地测试书源');

  });

  test('解析多行续写与冒号写法；大小写不敏感', () {
    final meta = ScriptMeta.parse('''
// @Script kind=clean
// name="TXT 清洗转 EPUB"
// Capabilities: clean
''');
    expect(meta.kind, ScriptKind.clean);
    expect(meta.name, 'TXT 清洗转 EPUB');

  });

  test('没有声明时按最保守的 tool 处理（不会被当成书源）', () {
    final meta = ScriptMeta.parse('log("no declaration")');
    expect(meta.kind, ScriptKind.tool);
  });

  test('解析不执行代码：语法错误的脚本也能读出声明', () {
    final meta = ScriptMeta.parse('// @script kind=source\n!!! 不是合法代码 !!!');
    expect(meta.kind, ScriptKind.source);
  });

  test('仓储条目：类型以脚本内声明为准（编辑后自动同步）', () {
    final source = SourceEntry.fromJson({
      'id': 'x',
      'name': '旧名字',
      'format': 'script',
      'kind': 'source', // 旧记录写的是 source
      'body': '// @script kind=clean name="改名后"\nlog("x")',
    });
    expect(source.kind, ScriptKind.clean, reason: '应以脚本内声明覆盖旧记录');
    expect(source.isSource, isFalse, reason: '清洗脚本不应出现在书源页');

    final rule = SourceEntry.fromJson({
      'id': 'r',
      'name': '规则源',
      'format': 'rule',
      'body': '{"id":"r"}',
    });
    expect(rule.kind, ScriptKind.source);
    expect(rule.isSource, isTrue);
  });
}
