/// 应用级设置：整体配色、书架布局、导入规则。
class AppSettings {
  /// 对应 kAppThemes 下标。
  int themeIndex;
  bool gridLayout;
  int gridColumns;
  String sortMode;
  String tocRulePattern;
  bool autoBackup;

  /// 竖屏底部标签是否显示文字（默认只显示图标）。
  bool portraitLabels;

  /// 横屏左侧标签栏是否展开为图标 + 文字（默认只显示图标）。
  bool landscapeExpanded;

  AppSettings({
    this.themeIndex = 0,
    this.gridLayout = true,
    this.gridColumns = 3,
    this.sortMode = 'recent',
    this.tocRulePattern = '',
    this.autoBackup = true,
    this.portraitLabels = false,
    this.landscapeExpanded = false,
  });

  Map<String, dynamic> toJson() => {
    'themeIndex': themeIndex,
    'gridLayout': gridLayout,
    'gridColumns': gridColumns,
    'sortMode': sortMode,
    'tocRulePattern': tocRulePattern,
    'autoBackup': autoBackup,
    'portraitLabels': portraitLabels,
    'landscapeExpanded': landscapeExpanded,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeIndex: (json['themeIndex'] as num?)?.toInt() ?? 0,
    gridLayout: json['gridLayout'] as bool? ?? true,
    gridColumns: (json['gridColumns'] as num?)?.toInt() ?? 3,
    sortMode: json['sortMode'] as String? ?? 'recent',
    tocRulePattern: json['tocRulePattern'] as String? ?? '',
    autoBackup: json['autoBackup'] as bool? ?? true,
    portraitLabels: json['portraitLabels'] as bool? ?? false,
    landscapeExpanded: json['landscapeExpanded'] as bool? ?? false,
  );
}

/// WebDAV 同步配置。
class WebDavConfig {
  String url;
  String username;
  String password;
  String remoteDir;
  bool enabled;

  WebDavConfig({
    this.url = '',
    this.username = '',
    this.password = '',
    this.remoteDir = 'reader-sync',
    this.enabled = false,
  });

  bool get configured => url.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
    'remoteDir': remoteDir,
    'enabled': enabled,
  };

  factory WebDavConfig.fromJson(Map<String, dynamic> json) => WebDavConfig(
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    remoteDir: json['remoteDir'] as String? ?? 'reader-sync',
    enabled: json['enabled'] as bool? ?? false,
  );
}
