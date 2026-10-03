/// 脚本声明：写在脚本**头部注释**里，由纯 Dart 静态解析（不执行代码）。
///
/// 写法（单行）：
///   // @script kind=source name="本地测试书源" capabilities=search,detail,download
///
/// 写法（多行续写，后面的行只写 key=value）：
///   // @script kind=clean
///   // name="TXT 清洗转 EPUB"
///   // capabilities=clean
///
/// `kind` 决定它出现在哪个入口，避免被错用：
///   - source：书源（搜索 / 详情 / 下载）
///   - clean ：清洗（TXT → EPUB）
///   - tool  ：其它工具脚本（默认值；不在书源页出现）
class ScriptMeta {
  const ScriptMeta({
    this.kind = ScriptKind.tool,
    this.name,
    this.capabilities = const <String>{},
    this.description,
    this.raw = const <String, String>{},
  });

  final ScriptKind kind;
  final String? name;
  final Set<String> capabilities;
  final String? description;
  final Map<String, String> raw;

  /// 解析头部声明；没有声明时按 tool 处理（最保守，不会被当成书源误用）。
  static ScriptMeta parse(String source) {
    final marker = RegExp(r'^\s*//\s*@script\b(.*)$', caseSensitive: false);
    final continuation = RegExp(
      r'^\s*//\s*([A-Za-z_][\w-]*)\s*[=:]\s*(.+?)\s*$',
    );
    final fields = <String, String>{};
    var started = false;

    final lines = source.split('\n');
    for (var i = 0; i < lines.length && i < 200; i++) {
      final line = lines[i];
      final match = marker.firstMatch(line);
      if (match != null) {
        started = true;
        _absorb(fields, match.group(1) ?? '');
        continue;
      }
      if (!started) continue;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('//')) break;
      final cont = continuation.firstMatch(trimmed);
      if (cont == null) break;
      final key = cont.group(1);
      final value = cont.group(2);
      if (key != null && value != null) {
        fields[key.toLowerCase()] = _unquote(value.trim());
      }
    }

    if (fields.isEmpty) return const ScriptMeta();
    return ScriptMeta(
      kind: ScriptKind.parse(fields['kind']),
      name: fields['name'],
      capabilities: (fields['capabilities'] ?? fields['capability'] ?? '')
          .split(RegExp(r'[,/|]'))
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet(),
      description: fields['description'],
      raw: Map.unmodifiable(fields),
    );
  }

  static void _absorb(Map<String, String> fields, String body) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      if (char == '"' || char == "'") {
        quoted = !quoted;
        continue;
      }
      if (!quoted && (char == ' ' || char == '\t')) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final eq = token.indexOf('=');
      final colon = eq < 0 ? token.indexOf(':') : eq;
      if (colon < 0) continue;
      final key = token.substring(0, colon).trim().toLowerCase();
      final value = token.substring(colon + 1).trim();
      if (key.isEmpty) continue;
      if (value.isNotEmpty) {
        fields[key] = _unquote(value);
      } else if (i + 1 < tokens.length) {
        fields[key] = _unquote(tokens[++i]);
      }
    }
  }

  static String _unquote(String value) =>
      value.replaceAll(RegExp(r'''^["']|["']$'''), '');
}

/// 脚本类型（决定出现在哪个入口）。
enum ScriptKind {
  source,
  clean,
  tool;

  static ScriptKind parse(String? value) => switch (value?.toLowerCase()) {
    'source' || '书源' => ScriptKind.source,
    'clean' || '清洗' => ScriptKind.clean,
    _ => ScriptKind.tool,
  };

  String get label => switch (this) {
    ScriptKind.source => '书源',
    ScriptKind.clean => '清洗',
    ScriptKind.tool => '其他',
  };
}
