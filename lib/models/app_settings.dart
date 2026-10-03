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
  });

  Map<String, dynamic> toJson() => {
    'themeIndex': themeIndex,
    'gridLayout': gridLayout,
    'gridColumnsPortrait': gridColumnsPortrait,
    'gridColumnsLandscape': gridColumnsLandscape,
    'sortMode': sortMode,
    'tocRulePattern': tocRulePattern,
    'portraitLabels': portraitLabels,
    'landscapeExpanded': landscapeExpanded,
      'scriptSandboxAudit': scriptSandboxAudit,
  };

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
  );
}

/// 网格列数合法范围。
const int kShelfColumnsMin = 1;
const int kShelfColumnsMax = 10;

int _clampColumns(int value) =>
    value.clamp(kShelfColumnsMin, kShelfColumnsMax);
