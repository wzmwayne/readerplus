/// 构建时注入的应用信息。
///
/// CI 通过 `--dart-define=APP_VERSION=... --dart-define=APP_BUILD_NUMBER=...`
/// 把自动版本号（yymmddhhmmss 与 versionCode）带进应用；
/// 本地直接 `flutter run` 时不注入，界面显示为开发版。
const String kAppVersion = String.fromEnvironment('APP_VERSION');
const String kAppBuildNumber = String.fromEnvironment('APP_BUILD_NUMBER');

/// 供界面展示的版本文案。
String get appVersionLabel {
  if (kAppVersion.isEmpty) return '开发版（本地构建未注入版本号）';
  if (kAppBuildNumber.isEmpty) return kAppVersion;
  return '$kAppVersion（$kAppBuildNumber）';
}
