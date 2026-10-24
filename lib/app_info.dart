/// 构建时注入的应用信息。
///
/// CI 通过 `--dart-define=APP_VERSION=... --dart-define=APP_BUILD_NUMBER=...`
/// 注入版本串（形如 `1.1.4+3600001.g09653ab`：语义版本 + versionCode + 提交号）；
/// 本地直接 `flutter run` 时不注入，界面显示为开发版。
const String kAppVersion = String.fromEnvironment('APP_VERSION');
const String kAppBuildNumber = String.fromEnvironment('APP_BUILD_NUMBER');

/// 供界面展示的版本文案。
String get appVersionLabel {
  if (kAppVersion.isEmpty) return '开发版（本地构建未注入版本号）';
  // CI 注入的版本串已含 `+versionCode.g提交号`，再拼一次会重复；
  // 只有「纯语义版本 + 单独 build 号」（如 F-Droid 源码构建）时才补括号。
  if (kAppBuildNumber.isEmpty || kAppVersion.contains('+')) {
    return kAppVersion;
  }
  return '$kAppVersion（$kAppBuildNumber）';
}
