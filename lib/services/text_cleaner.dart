/// 文本清理规则：用于 TXT 导入时自动做格式清理（规则形式与来源参考 Legado 的替换净化）。
class CleanRule {
  CleanRule({
    required this.name,
    required this.pattern,
    this.replacement = '',
    this.enabled = true,
    this.builtin = false,
    this.note = '',
  });

  /// 规则名（展示用）。
  final String name;

  /// 正则表达式，按多行模式匹配。
  final String pattern;

  /// 替换内容，支持 `$1` 这样的分组引用。
  final String replacement;

  /// 是否默认启用。
  bool enabled;

  /// 是否为内置规则（内置规则不能删除，只能停用）。
  final bool builtin;

  /// 规则说明。
  final String note;

  RegExp get regex => RegExp(pattern, multiLine: true);

  Map<String, dynamic> toJson() => {
    'name': name,
    'pattern': pattern,
    'replacement': replacement,
    'enabled': enabled,
    'builtin': builtin,
    'note': note,
  };

  factory CleanRule.fromJson(Map<String, dynamic> json) => CleanRule(
    name: json['name'] as String? ?? '未命名规则',
    pattern: json['pattern'] as String? ?? '',
    replacement: json['replacement'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    builtin: json['builtin'] as bool? ?? false,
    note: json['note'] as String? ?? '',
  );
}

/// TXT 自动格式清理。
///
/// 规则按顺序应用；内置规则参考 Legado 的替换净化常见条目，
/// 略激进的“段落合并”默认关闭，避免误合并列表或诗句。
class TextCleaner {
  const TextCleaner._();

  static final List<CleanRule> builtinRules = [
    CleanRule(
      name: '去除 BOM 与零宽字符',
      pattern: r'[\uFEFF\u200B-\u200D]',
      builtin: true,
      note: '去掉文件头的 BOM 以及排版里混入的零宽字符',
    ),
    CleanRule(
      name: '去除行首空白',
      pattern: r'^[ \t\u3000]+',
      builtin: true,
      note: '缩进由阅读器统一处理，正文行首空白会影响排版',
    ),
    CleanRule(
      name: '去除行尾空白',
      pattern: r'[ \t\u3000]+$',
      builtin: true,
    ),
    CleanRule(
      name: '合并连续空行',
      pattern: r'\n{3,}',
      replacement: '\n\n',
      builtin: true,
      note: '多个空行合并为一个',
    ),
    CleanRule(
      name: '统一下半角省略号',
      pattern: r'\.{3,}',
      replacement: '……',
      builtin: true,
    ),
    CleanRule(
      name: '去除常见广告行',
      pattern: r'^.*(https?://|www\.|最新章节|请收藏|手机阅读|txt下载|一秒记住).*$',
      builtin: true,
      note: '移除含网址或常见推广语的整行',
    ),
    CleanRule(
      name: '去除替换乱码字符',
      pattern: r'\uFFFD',
      builtin: true,
    ),
    CleanRule(
      name: '段落合并（拆行修复）',
      pattern: r'([^。！？…；：”」』）])\n(?=[^ \t\n])',
      replacement: r'$1',
      enabled: false,
      builtin: true,
      note: '把被硬换行拆开的段落接回；可能误合并列表与诗句，默认关闭',
    ),
  ];

  /// 内置规则的深拷贝，用于首次初始化或重置。
  static List<CleanRule> defaultRules() =>
      builtinRules.map((r) => CleanRule.fromJson(r.toJson())).toList();

  /// 按顺序应用启用的规则，返回清理后的文本。
  ///
  /// 注意：Dart 的 `String.replaceAll` 不会展开 `$1` 这类分组引用，
  /// 因此替换串里带 `$` 时改用 `replaceAllMapped` 自行展开。
  static String apply(String text, List<CleanRule> rules) {
    var result = text;
    for (final rule in rules) {
      if (!rule.enabled || rule.pattern.isEmpty) continue;
      try {
        final regex = rule.regex;
        if (rule.replacement.contains(r'$')) {
          result = result.replaceAllMapped(
            regex,
            (match) => expandReplacement(rule.replacement, match),
          );
        } else {
          result = result.replaceAll(regex, rule.replacement);
        }
      } on FormatException {
        // 规则写错时跳过，不影响导入
        continue;
      }
    }
    return result;
  }

  /// 展开替换串里的 `$0`~`$9` 与 `$$`（转义为字面 `$`）。
  static String expandReplacement(String replacement, Match match) {
    if (!replacement.contains(r'$')) return replacement;
    final buffer = StringBuffer();
    for (var i = 0; i < replacement.length; i++) {
      final ch = replacement[i];
      if (ch == r'$' && i + 1 < replacement.length) {
        final next = replacement[i + 1];
        if (next == r'$') {
          buffer.write(r'$');
          i++;
          continue;
        }
        final index = int.tryParse(next);
        if (index != null && index <= match.groupCount) {
          buffer.write(match.group(index) ?? '');
          i++;
          continue;
        }
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  /// 统计单条规则命中的次数，便于设置页展示效果。
  static int matchCount(String text, CleanRule rule) {
    if (rule.pattern.isEmpty) return 0;
    try {
      return rule.regex.allMatches(text).length;
    } on FormatException {
      return 0;
    }
  }
}
