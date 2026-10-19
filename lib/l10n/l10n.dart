import '../models/app_settings.dart';

/// 极轻量的运行时文案表：`L10n.of(settings)` 之后取 getter。
///
/// 不走 `gen-l10n`/ARB 的原因：本项目文案集中且量不大，手写 getter 类型安全、
/// 改文案不必跑代码生成；新增语言只需在 [_texts] 里补一列。
class L10n {
  const L10n(this.lang);

  /// `'zh'` 或 `'en'`。
  final String lang;

  bool get isZh => lang != 'en';

  /// 语言解析统一由 [AppSettings.resolvedLang] 负责（system/zh/en 三态）。
  static L10n of(AppSettings settings) => L10n(settings.resolvedLang);

  String _t(String key) => _texts[key]?[lang] ?? _texts[key]?['zh'] ?? key;

  // ---------------- 通用 ----------------

  String get appTitle => _t('app.title');
  String get ok => _t('common.ok');
  String get cancel => _t('common.cancel');
  String get retry => _t('common.retry');
  String get close => _t('common.close');
  String get delete => _t('common.delete');
  String get edit => _t('common.edit');
  String get refresh => _t('common.refresh');
  String get add => _t('common.add');
  String get import => _t('common.import');

  // ---------------- 底部标签 ----------------

  String get tabShelf => _t('tab.shelf');
  String get tabSearch => _t('tab.search');
  String get tabPlugins => _t('tab.plugins');
  String get tabSettings => _t('tab.settings');

  // ---------------- 设置：语言 ----------------

  String get language => _t('settings.language');
  String get languageSystem => _t('settings.language.system');
  String get languageZh => _t('settings.language.zh');
  String get languageEn => _t('settings.language.en');

  // ---------------- 设置：脚本 ----------------

  String get sectionScript => _t('settings.script.section');
  String get enableScripts => _t('settings.script.enable');
  String get scriptsUndecided => _t('settings.script.undecided');
  String get scriptsOff => _t('settings.script.off');
  String get scriptsOn => _t('settings.script.on');
  String get downloadLimit => _t('settings.script.downloadLimit');
  String get downloadLimitUnlimited => _t('settings.script.downloadLimit.unlimited');

  // ---------------- 脚本闸门 ----------------

  String get consentTitle => _t('consent.title');
  String get consentTitleQuiz => _t('consent.titleQuiz');
  String get consentIntro => _t('consent.intro');
  List<String> get consentPoints => [
    _t('consent.point1'),
    _t('consent.point2'),
    _t('consent.point3'),
    _t('consent.point4'),
    _t('consent.point5'),
    _t('consent.point6'),
  ];
  String get consentDisclaimer => _t('consent.disclaimer');
  String get consentQuizPrompt => _t('consent.quizPrompt');
  String get consentSubmit => _t('consent.submit');
  String get consentSkip => _t('consent.skip');
  String get consentDecline => _t('consent.decline');
  String get consentEnable => _t('consent.enable');
  String get consentWrong => _t('consent.wrong');

  // ---------------- 关闭态引导 ----------------

  String get scriptsOffTitle => _t('off.title');
  String get scriptsOffBody => _t('off.body');
  String get goEnable => _t('off.goEnable');
  String get searchNeedsScripts => _t('off.searchHint');

  // ---------------- 文案表 ----------------
  //
  // 规则：`zh` 是基准，`en` 必须逐条对照功能，不写空话、不承诺未实现的能力。

  static const Map<String, Map<String, String>> _texts = {
    'app.title': {'zh': '阅读', 'en': 'Reader'},

    'common.ok': {'zh': '确定', 'en': 'OK'},
    'common.cancel': {'zh': '取消', 'en': 'Cancel'},
    'common.retry': {'zh': '重试', 'en': 'Try again'},
    'common.close': {'zh': '关闭', 'en': 'Close'},
    'common.delete': {'zh': '删除', 'en': 'Delete'},
    'common.edit': {'zh': '编辑', 'en': 'Edit'},
    'common.refresh': {'zh': '刷新', 'en': 'Refresh'},
    'common.add': {'zh': '添加', 'en': 'Add'},
    'common.import': {'zh': '导入', 'en': 'Import'},

    'tab.shelf': {'zh': '书架', 'en': 'Shelf'},
    'tab.search': {'zh': '搜索', 'en': 'Search'},
    'tab.plugins': {'zh': '插件', 'en': 'Plugins'},
    'tab.settings': {'zh': '设置', 'en': 'Settings'},

    'settings.language': {'zh': '界面语言', 'en': 'Language'},
    'settings.language.system': {'zh': '跟随系统', 'en': 'System default'},
    'settings.language.zh': {'zh': '中文', 'en': '中文'},
    'settings.language.en': {'zh': 'English', 'en': 'English'},

    'settings.script.section': {'zh': '脚本', 'en': 'Scripts'},
    'settings.script.enable': {'zh': '启用脚本支持', 'en': 'Enable scripts'},
    'settings.script.undecided': {
      'zh': '尚未选择：脚本相关功能当前不可用',
      'en': 'Not decided yet: script features are unavailable',
    },
    'settings.script.off': {
      'zh': '已关闭：搜索页与插件页不可用，书架与阅读不受影响',
      'en': 'Off: Search and Plugins are unavailable; Shelf and Reader keep working',
    },
    'settings.script.on': {
      'zh': '已启用：可导入并运行脚本；关闭后脚本功能不可用，重新开启需再次确认',
      'en': 'On: scripts can be imported and run; turning it off disables script '
          'features and re-enabling asks for confirmation again',
    },
    'settings.script.downloadLimit': {
      'zh': '下载脚本运行上限',
      'en': 'Download script time limit',
    },
    'settings.script.downloadLimit.unlimited': {
      'zh': '不限制（默认）',
      'en': 'No limit (default)',
    },

    'consent.title': {'zh': '启用脚本支持', 'en': 'Enable scripts'},
    'consent.titleQuiz': {'zh': '理解确认', 'en': 'Read and confirm'},
    'consent.intro': {
      'zh': '脚本扩展是可选功能。启用后你可以导入并运行第三方脚本（书源、清洗等），'
          '它们为应用增加能力，也因此带来风险。',
      'en': 'Scripts are optional. Once enabled you can import and run third-party '
          'scripts (book sources, text cleaning and so on). They add capability to '
          'the app, and that is exactly where the risk comes from.',
    },
    'consent.point1': {
      'zh': '你自行导入的脚本来自第三方，未经 F-Droid 或本应用开发者审查。',
      'en': 'Scripts you import come from third parties and are not reviewed by '
          'F-Droid or by the app developer.',
    },
    'consent.point2': {
      'zh': '脚本可以利用本应用的网络权限访问互联网，也可能读取本应用有权访问的数据。',
      'en': 'A script can use the app network permission to reach the internet, and '
          'can read the data the app itself is allowed to read.',
    },
    'consent.point3': {
      'zh': '脚本是否安全取决于脚本内容与来源；沙箱能降低风险，"能运行"不等于"安全"。',
      'en': 'Safety depends on what the script does and where it came from. The '
          'sandbox reduces risk; "it runs" does not mean "it is safe".',
    },
    'consent.point4': {
      'zh': '本应用默认关闭脚本支持，也不附带任何脚本；你导入的脚本一律由你自行承担风险。',
      'en': 'Script support is off by default and the app ships no scripts. Any '
          'script you import is your own responsibility.',
    },
    'consent.point5': {
      'zh': '不启用脚本支持时，书架、阅读、导入 TXT/EPUB 等核心功能照常可用；'
          '搜索页与插件页不可用。',
      'en': 'With scripts disabled the core features still work: shelf, reading and '
          'importing TXT/EPUB. Search and Plugins stay unavailable.',
    },
    'consent.point6': {
      'zh': '你可以在「设置 → 脚本」随时关闭脚本支持，关闭后脚本相关功能不可用，'
          '重新开启需再次通过本题。',
      'en': 'You can turn script support off at any time in Settings → Scripts. Script '
          'features then stop working, and re-enabling asks you to pass this check again.',
    },
    'consent.disclaimer': {
      'zh': '免责声明：脚本由你自行导入，其行为与后果由你自行承担。'
          '本应用不对第三方脚本的安全性作出保证，也不对其造成的损失负责。',
      'en': 'Disclaimer: you import scripts yourself and you are responsible for what '
          'they do. The app makes no guarantee about the safety of third-party scripts '
          'and is not liable for any damage they cause.',
    },
    'consent.quizPrompt': {
      'zh': '下面 5 条陈述中有 1~4 条是正确的。请勾选你认为正确的陈述（可多选），'
          '然后点「提交」。',
      'en': 'Between 1 and 4 of the 5 statements below are correct. Tick every '
          'statement you believe is true (multiple choices allowed), then press Submit.',
    },
    'consent.submit': {'zh': '提交', 'en': 'Submit'},
    'consent.skip': {'zh': '直接开始', 'en': 'Start without scripts'},
    'consent.decline': {'zh': '暂不启用', 'en': 'Not now'},
    'consent.enable': {'zh': '启用脚本', 'en': 'Continue'},
    'consent.wrong': {
      'zh': '未通过：需要恰好勾选全部正确项，漏选或多选都不行。'
          '可以重试（重新抽题），或直接开始（不启用脚本）。',
      'en': 'Not passed: you must tick exactly the correct statements — no more, no '
          'less. You can try again with a new set, or start without scripts.',
    },

    'off.title': {
      'zh': '脚本支持未启用',
      'en': 'Script support is off',
    },
    'off.body': {
      'zh': '脚本是可选的扩展能力。启用后你可以导入书源与清洗脚本；'
          '不启用时书架、阅读与 TXT/EPUB 导入照常可用。',
      'en': 'Scripts are optional extensions. Enabling lets you import book sources '
          'and cleaning scripts; without them the shelf, reader and TXT/EPUB import '
          'keep working.',
    },
    'off.goEnable': {'zh': '去开启', 'en': 'Enable'},
    'off.searchHint': {
      'zh': '脚本支持未启用：搜索需要书源脚本。可在设置 → 脚本中开启。',
      'en': 'Script support is off: search needs a book source script. '
          'Enable it in Settings → Scripts.',
    },
  };
}
