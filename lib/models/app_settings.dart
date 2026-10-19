import 'dart:ui' show PlatformDispatcher;

/// 界面语言模式。
enum AppLangMode { system, zh, en }

/// 应用级设置：整体配色、书架布局、导入规则。
class AppSettings {
  /// 对应 kAppThemes 下标。
  int themeIndex;
  bool gridLayout;
  /// 网格视图每行本数（竖屏默认 3，横屏默认 6，范围 1-10）。
  int gridColumnsPortrait;
  int gridColumnsLandscape;
  String sortMode;
  String tocRulePattern;

  /// 竖屏底部标签是否显示文字（默认只显示图标）。
  bool portraitLabels;

  /// 横屏左侧标签栏是否展开为图标 + 文字（默认只显示图标）。
  bool landscapeExpanded;

  /// 脚本沙盒审计钩子（默认开启：禁止脚本访问沙盒外的文件）。
  bool scriptSandboxAudit;

  /// 下载脚本的运行上限（秒）。**0 = 不限制**（默认）。
  /// 搜索保持短上限，避免卡住界面；下载大书允许长时间跑，
  /// 需要时可在设置里收紧，或随时用搜索页的「取消」强制停止。
  int downloadTimeoutSeconds;

  /// 脚本支持的三态同意状态（JSON 里按"键是否存在"判定）：
  ///   - `null` = 从未决定（首启，或旧版本升级后缺该键）⇒ 脚本关闭 + 弹理解确认闸门；
  ///   - `true` = 用户已通过理解确认题，启用脚本；
  ///   - `false` = 用户明确选择不启用（含答错后放弃）。
  ///
  /// 有效开关一律用 `scriptsEnabled == true` 判断：`null` 与 `false` 都是关闭态，
  /// 区别只在"是否需要自动弹闸门"。
  bool? scriptsEnabled;

  /// 界面语言：默认跟随系统（首次启动时读取系统语言），用户可显式改为中文/英文。
  AppLangMode langMode;

  /// 实际生效的语言代码（`zh` / `en`）。
  String get resolvedLang {
    switch (langMode) {
      case AppLangMode.zh:
        return 'zh';
      case AppLangMode.en:
        return 'en';
      case AppLangMode.system:
        final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
        return code == 'zh' ? 'zh' : 'en';
    }
  }

  AppSettings({
    this.themeIndex = 0,
    this.gridLayout = true,
    this.gridColumnsPortrait = 3,
    this.gridColumnsLandscape = 6,
    this.sortMode = 'recent',
    this.tocRulePattern = '',
    this.portraitLabels = false,
    this.landscapeExpanded = false,
    this.scriptSandboxAudit = true,
    this.downloadTimeoutSeconds = 0,
    this.scriptsEnabled,
    this.langMode = AppLangMode.system,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'themeIndex': themeIndex,
      'gridLayout': gridLayout,
      'gridColumnsPortrait': gridColumnsPortrait,
      'gridColumnsLandscape': gridColumnsLandscape,
      'sortMode': sortMode,
      'tocRulePattern': tocRulePattern,
      'portraitLabels': portraitLabels,
      'landscapeExpanded': landscapeExpanded,
      'scriptSandboxAudit': scriptSandboxAudit,
      'downloadTimeoutSeconds': downloadTimeoutSeconds,
    };
    // 只在已决定时写键：缺键 = 从未决定（首启 / 升级前的老配置）
    if (scriptsEnabled != null) json['scriptsEnabled'] = scriptsEnabled;
    json['langMode'] = langMode.name;
    return json;
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeIndex: (json['themeIndex'] as num?)?.toInt() ?? 0,
    gridLayout: json['gridLayout'] as bool? ?? true,
    // 归一化到 1..10：历史配置里可能出现超范围值（旧版迁移曾把它翻倍），
    // 直接交给 Slider 会触发断言崩溃
    gridColumnsPortrait: _clampColumns(
      (json['gridColumnsPortrait'] as num?)?.toInt() ??
          (json['gridColumns'] as num?)?.toInt() ??
          3,
    ),
    gridColumnsLandscape: _clampColumns(
      (json['gridColumnsLandscape'] as num?)?.toInt() ??
          (json['gridColumns'] as num?)?.toInt() ??
          6,
    ),
    sortMode: json['sortMode'] as String? ?? 'recent',
    tocRulePattern: json['tocRulePattern'] as String? ?? '',
    portraitLabels: json['portraitLabels'] as bool? ?? false,
    landscapeExpanded: json['landscapeExpanded'] as bool? ?? false,
      scriptSandboxAudit: json['scriptSandboxAudit'] as bool? ?? true,
    downloadTimeoutSeconds:
        (json['downloadTimeoutSeconds'] as num?)?.toInt() ?? 0,
    // 用 containsKey 区分"缺键"（null，从未决定 ⇒ 弹闸门）与"显式 false"
    // （用户已明确拒绝，不再自动打扰）
    scriptsEnabled: json.containsKey('scriptsEnabled')
        ? json['scriptsEnabled'] as bool?
        : null,
    langMode: AppLangMode.values.firstWhere(
      (mode) => mode.name == '${json['langMode'] ?? ''}',
      orElse: () => AppLangMode.system,
    ),
  );
}

/// 网格列数合法范围。
const int kShelfColumnsMin = 1;
const int kShelfColumnsMax = 10;

int _clampColumns(int value) =>
    value.clamp(kShelfColumnsMin, kShelfColumnsMax);
