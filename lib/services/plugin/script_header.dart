/// 脚本声明：从脚本**头部注释**里静态解析（不执行代码、不启动 Python）。
///
/// 单行写法（推荐）：
///   # @readerplus kind=source id=example name="示例书源" version=1.0 capabilities=search,detail,download
///
/// 多行写法（同一条声明拆成多行注释，后面的行只写 key=value）：
///   # @readerplus kind=clean
///   # id=txt-cleaner
///   # name="TXT 清洗转 EPUB"
///   # capabilities=clean
///
/// `kind`：clean（清洗转 EPUB）/ source（书源）；`capabilities` 用逗号或斜杠分隔。
class ScriptHeader {
  const ScriptHeader({
    this.kind,
    this.id,
    this.name,
    this.version,
    this.capabilities = const <String>{},
    this.raw = const <String, String>{},
  });

  final String? kind;
  final String? id;
  final String? name;
  final String? version;
  final Set<String> capabilities;

  /// 全部键值（便于将来扩展，无需改解析器）。
  final Map<String, String> raw;

  bool get isSource => kind == 'source';
  bool get isClean => kind == 'clean';

  static final RegExp _marker = RegExp(
    r'^\s*#\s*@readerplus\b(.*)$',
    caseSensitive: false,
  );
  static final RegExp _continuation = RegExp(r'^\s*#\s*([A-Za-z_][\w-]*)\s*[=:]\s*(.+?)\s*$');

  /// 解析头部注释；没有任何声明时返回 null。
  static ScriptHeader? parse(String source) {
    final lines = source.split('\n');
    var started = false;
    final fields = <String, String>{};

    for (var i = 0; i < lines.length && i < 200; i++) {
      final line = lines[i];
      final match = _marker.firstMatch(line);
      if (match != null) {
        started = true;
        _absorb(fields, match.group(1) ?? '');
        continue;
      }
      if (!started) continue;
      // 声明开始后，允许紧跟若干行 "# key=value" 续写
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('#')) break;
      final cont = _continuation.firstMatch(trimmed);
      if (cont == null) break;
      final key = cont.group(1);
      final value = cont.group(2);
      if (key != null && value != null) {
        fields[key.toLowerCase()] = _unquote(value.trim());
      }
    }

    if (fields.isEmpty) return null;
    return ScriptHeader(
      kind: fields['kind']?.toLowerCase(),
      id: fields['id'],
      name: fields['name'],
      version: fields['version'],
      capabilities: _splitList(
        fields['capabilities'] ?? fields['capability'] ?? '',
      ),
      raw: Map.unmodifiable(fields),
    );
  }

  /// 把 `kind=source id=x name="A B" caps=a,b` 解析进 map（支持引号）。
  static void _absorb(Map<String, String> fields, String body) {
    var token = StringBuffer();
    var quoted = false;
    final tokens = <String>[];
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      if (char == '"' || char == "'") {
        quoted = !quoted;
        continue;
      }
      if (!quoted && (char == ' ' || char == '\t')) {
        if (token.isNotEmpty) {
          tokens.add(token.toString());
          token = StringBuffer();
        }
        continue;
      }
      token.write(char);
    }
    if (token.isNotEmpty) tokens.add(token.toString());

    for (var i = 0; i < tokens.length; i++) {
      final entry = tokens[i];
      final index = entry.indexOf('=');
      final index2 = index < 0 ? entry.indexOf(':') : index;

      if (index2 >= 0) {
        final key = entry.substring(0, index2).trim().toLowerCase();
        final value = entry.substring(index2 + 1).trim();
        if (key.isEmpty) continue;
        if (value.isNotEmpty) {
          fields[key] = _unquote(value);
        } else if (i + 1 < tokens.length) {
          // 形如 "kind: source"：值在下一个 token
          fields[key] = _unquote(tokens[++i]);
        }
        continue;
      }
    }
  }

  static String _unquote(String value) =>
      value.replaceAll(RegExp(r'''^["']|["']$'''), '');

  static Set<String> _splitList(String value) => value
      .split(RegExp(r'[,/|]'))
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet();
}
