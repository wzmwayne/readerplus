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

  // ---------------- 搜索 ----------------
  String get searchCancelled => _t('search.cancelled');
  String searchForcedStop(int n) =>
      _t('search.forcedStop').replaceAll('{n}', '$n');
  String get searchUserCancel => _t('search.userCancel');
  String searchAnswered(int n) => _t('search.answered').replaceAll('{n}', '$n');
  String get searchAskCancelled => _t('search.askCancelled');
  String get searchAnonymous => _t('search.anonymous');
  String searchMeta(String author, String cover) =>
      _t('search.meta').replaceAll('{author}', author).replaceAll('{cover}', cover);
  String get searchNoCover => _t('search.noCover');
  String searchCoverBytes(int n) =>
      _t('search.coverBytes').replaceAll('{n}', '$n');
  String searchEpubDone(String path, int n) =>
      _t('search.epubDone').replaceAll('{path}', path).replaceAll('{n}', '$n');
  String get searchImportFailed => _t('search.importFailed');
  String searchImported(String title, String author) =>
      _t('search.imported').replaceAll('{title}', title).replaceAll('{author}', author);
  String searchActionCancelled(String action) =>
      _t('search.actionCancelled').replaceAll('{action}', action);
  String searchActionTimeout(String action) =>
      _t('search.actionTimeout').replaceAll('{action}', action);
  String searchActionCrashed(String action, String detail) =>
      _t('search.actionCrashed').replaceAll('{action}', action).replaceAll('{detail}', detail);
  String get searchCancelTooltip => _t('search.cancelTooltip');
  String get searchManageSources => _t('search.manageSources');
  String get searchOffTitle => _t('search.offTitle');
  String get searchOffBody => _t('search.offBody');
  String searchSourcesTitle(int sel, int total) =>
      _t('search.sourcesTitle').replaceAll('{sel}', '$sel').replaceAll('{total}', '$total');
  String get searchSourcesHint => _t('search.sourcesHint');
  String get searchGroupedHint => _t('search.groupedHint');
  String get searchSourceGone => _t('search.sourceGone');

  // ---------------- 脚本页 ----------------
  String get scriptRejectImport => _t('scriptPage.rejectImport');
  String get scriptKindHint => _t('scriptPage.kindHint');
  String get scriptOffTitle => _t('scriptPage.offTitle');
  String get scriptOffBody => _t('scriptPage.offBody');
  String get scriptEmptyTitle => _t('scriptPage.emptyTitle');
  String get scriptEmptySubtitle => _t('scriptPage.emptySubtitle');

  // ---------------- 书架 ----------------
  String shelfTxtDone(int n) => _t('shelf.txtDone').replaceAll('{n}', '$n');
  String shelfImported(String title) =>
      _t('shelf.imported').replaceAll('{title}', title);
  String get shelfImportFailed => _t('shelf.importFailed');
  String get shelfFormatsHint => _t('shelf.formatsHint');
  String get shelfEmptyHint => _t('shelf.emptyHint');

  // ---------------- 开发者 / 崩溃 ----------------
  String get devNoLog => _t('dev.noLog');
  String get devAppSection => _t('dev.appSection');
  String get devLogSection => _t('dev.logSection');
  String get crashTitle => _t('crash.title');

  // ---------------- 阅读器 ----------------
  String get readerEmptyBook => _t('reader.emptyBook');
  String get readerLandscapeHint => _t('reader.landscapeHint');

  // ---------------- 朗读面板 ----------------
  String get ttsImportTitle => _t('tts.importTitle');
  String get ttsImportHint => _t('tts.importHint');
  String get ttsPickFile => _t('tts.pickFile');
  String get ttsLocalModel => _t('tts.localModel');
  String get ttsNotImported => _t('tts.notImported');
  String get ttsImportTooltip => _t('tts.importTooltip');
  String get ttsDeleteTooltip => _t('tts.deleteTooltip');
  String ttsImported(String name) => _t('tts.imported').replaceAll('{name}', name);
  String ttsImportFailed(String msg) => _t('tts.importFailed').replaceAll('{msg}', msg);
  String ttsDeleted(String name) => _t('tts.deleted').replaceAll('{name}', name);
  String get ttsRate => _t('tts.rate');
  String get ttsRateNormal => _t('tts.rateNormal');

  // ---------------- 设置页其余 ----------------
  String get settingsSectionUi => _t('settings.ui.section');
  String get settingsSectionAbout => _t('settings.about.section');
  String get settingsLegadoNotice => _t('settings.about.legado');
  String get settingsLicense => _t('settings.about.license');

  String get settingsPortraitOnly => _t('settings.portraitOnly');
  String get settingsAppDescription => _t('settings.appDescription');
  String get settingsCustomJson => _t('settings.customJson');
  String get settingsCredits => _t('settings.credits');
  String get scriptsOnDetail => _t('settings.script.onDetail');
  String get scriptsOffDetail => _t('settings.script.offDetail');
  String get scriptsUndecidedDetail => _t('settings.script.undecidedDetail');
  String get settingsScriptTurnedOff => _t('settings.script.turnedOff');
  String settingsLangSwitched(String mode) =>
      _t('settings.langSwitched').replaceAll('{mode}', mode);
  String settingsDownloadLimitSet(int seconds) => seconds == 0
      ? _t('settings.downloadLimitSetUnlimited')
      : _t('settings.downloadLimitSet').replaceAll('{n}', '$seconds');
  String get settingsSectionShelf => _t('settings.shelf.section');
  String get settingsPortraitLabels => _t('settings.portraitLabels');

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

    'search.cancelled': {'zh': '已取消', 'en': 'Cancelled'},
    'search.forcedStop': {
      'zh': '已强制停止：保留已完成的 {n} 条',
      'en': 'Force-stopped: kept {n} completed result(s)',
    },
    'search.userCancel': {'zh': '用户取消：强制停止所有运行中的脚本', 'en': 'User cancelled: all running scripts force-stopped'},
    'search.answered': {'zh': '已回答（{n} 字符）', 'en': 'Answered ({n} chars)'},
    'search.askCancelled': {'zh': '询问被取消', 'en': 'Prompt cancelled'},
    'search.anonymous': {'zh': '佚名', 'en': 'Unknown'},
    'search.meta': {'zh': '元数据：作者={author}，封面={cover}', 'en': 'Metadata: author={author}, cover={cover}'},
    'search.noCover': {'zh': '无（用默认）', 'en': 'none (default)'},
    'search.coverBytes': {'zh': '{n} 字节', 'en': '{n} bytes'},
    'search.epubDone': {'zh': '已生成 EPUB：{path}（{n} 字节）', 'en': 'EPUB created: {path} ({n} bytes)'},
    'search.importFailed': {'zh': '入库失败', 'en': 'Failed to add to library'},
    'search.imported': {'zh': '已入库：{title}（作者 {author}）', 'en': 'Added: {title} (by {author})'},
    'search.actionCancelled': {'zh': '{action}被取消：脚本已被强制停止', 'en': '{action} cancelled: script force-stopped'},
    'search.actionTimeout': {'zh': '{action}超时：脚本已被强制停止', 'en': '{action} timed out: script force-stopped'},
    'search.actionCrashed': {'zh': '{action}：脚本异常退出（{detail}）', 'en': '{action}: script crashed ({detail})'},
    'search.cancelTooltip': {'zh': '取消：强制停止所有运行中的脚本', 'en': 'Cancel: force-stop all running scripts'},
    'search.manageSources': {'zh': '管理脚本与书源', 'en': 'Manage scripts and sources'},
    'search.offTitle': {'zh': '脚本支持未启用', 'en': 'Script support is off'},
    'search.offBody': {
      'zh': '未启用时不列出任何书源，也不能发起搜索。可在「设置 → 脚本 → 启用脚本支持」开启（需先通过理解确认题）；未启用不影响书架与阅读。',
      'en': 'No sources are listed and search is disabled. Enable it in Settings → Scripts → Enable script support (an understanding check is required first). The shelf and reader are unaffected.',
    },
    'search.sourcesTitle': {'zh': '书源（已选 {sel}/{total}）', 'en': 'Sources ({sel}/{total} selected)'},
    'search.sourcesHint': {'zh': '勾选参与搜索的书源；管理请点右上角', 'en': 'Tick sources to include; manage via the top-right button'},
    'search.groupedHint': {'zh': '按脚本分组：详情已在搜索时带回，点击直接查看', 'en': 'Grouped by script: details come from the search, tap to open'},
    'search.sourceGone': {'zh': '该脚本已不可用', 'en': 'This script is no longer available'},

    'scriptPage.rejectImport': {'zh': '拒绝导入：插件页只接受 .ht 脚本与 .json 规则', 'en': 'Import rejected: only .ht scripts and .json rules are accepted here'},
    'scriptPage.kindHint': {'zh': '类型由头部 // @script kind=source|clean|tool 决定', 'en': 'Type is set by the header // @script kind=source|clean|tool'},
    'scriptPage.offTitle': {'zh': '脚本支持未启用', 'en': 'Script support is off'},
    'scriptPage.offBody': {'zh': '书架与阅读等功能不受影响。', 'en': 'The shelf, reader and other features are unaffected.'},
    'scriptPage.emptyTitle': {'zh': '还没有脚本', 'en': 'No scripts yet'},
    'scriptPage.emptySubtitle': {'zh': '用右上角按钮导入 .ht 或从模板新建', 'en': 'Import a .ht file or create one from a template'},

    'shelf.txtDone': {'zh': 'TXT 已转为 EPUB（{n} 字节）', 'en': 'TXT converted to EPUB ({n} bytes)'},
    'shelf.imported': {'zh': '已导入：{title}', 'en': 'Imported: {title}'},
    'shelf.importFailed': {'zh': '导入失败，详见开发者页日志', 'en': 'Import failed; see the developer log'},
    'shelf.formatsHint': {'zh': '支持 TXT（UTF-8 / GBK）与 EPUB 2 / 3', 'en': 'Supports TXT (UTF-8 / GBK) and EPUB 2 / 3'},
    'shelf.emptyHint': {'zh': '点击右上角 + 导入本地 TXT / EPUB 文件', 'en': 'Tap + to import a local TXT / EPUB file'},

    'dev.noLog': {'zh': '（还没有日志文件）', 'en': '(no log file yet)'},
    'dev.appSection': {'zh': '应用与环境', 'en': 'App and environment'},
    'dev.logSection': {'zh': '日志文件（单个、永远追加）', 'en': 'Log file (single, append-only)'},
    'crash.title': {'zh': '应用遇到问题，信息已写入日志文件', 'en': 'Something went wrong; details were written to the log'},

    'reader.emptyBook': {'zh': '这本书还没有正文', 'en': 'This book has no text yet'},
    'reader.landscapeHint': {'zh': '横屏时菜单显示在左右', 'en': 'In landscape the menu is shown on the sides'},

    'tts.importTitle': {'zh': '导入语音模型', 'en': 'Import a voice model'},
    'tts.importHint': {
      'zh': '① Android：请先把模型包放到「下载 / Download」目录，再从列表里选择它。\n'
          '② Linux / 桌面：请把模型包放在不含中文与空格的英文路径下（例如 ~/Downloads），'
          '并确认当前用户对该文件有读权限。\n\n'
          '支持 .zip / .tar.bz2 / .tar.gz / .tar，无需解压。',
      'en': '1) Android: put the model package in your Download folder first, then pick it from the list.\n'
          '2) Linux / desktop: keep the path ASCII without spaces (e.g. ~/Downloads) and make sure the app can read the file.\n\n'
          'Supports .zip / .tar.bz2 / .tar.gz / .tar; no need to extract.',
    },
    'tts.pickFile': {'zh': '选择文件', 'en': 'Choose file'},
    'tts.localModel': {'zh': '本地语音模型', 'en': 'Local voice model'},
    'tts.notImported': {'zh': '未导入', 'en': 'Not imported'},
    'tts.importTooltip': {'zh': '导入模型包（zip / tar.bz2）', 'en': 'Import a model package (zip / tar.bz2)'},
    'tts.deleteTooltip': {'zh': '删除该模型', 'en': 'Delete this model'},
    'tts.imported': {'zh': '已导入：{name}', 'en': 'Imported: {name}'},
    'tts.importFailed': {'zh': '导入失败：{msg}', 'en': 'Import failed: {msg}'},
    'tts.deleted': {'zh': '已删除：{name}', 'en': 'Deleted: {name}'},
    'tts.rate': {'zh': '语速', 'en': 'Speed'},
    'tts.rateNormal': {'zh': '正常', 'en': 'Normal'},

    'settings.ui.section': {'zh': '界面', 'en': 'Interface'},
    'settings.about.section': {'zh': '关于', 'en': 'About'},
    'settings.about.legado': {
      'zh': '部分界面设计与交互逻辑借鉴自开源项目 Legado（GPL-3.0）；本项目未包含其源代码。',
      'en': 'Parts of the UI design and interaction logic are inspired by the open-source project Legado (GPL-3.0); this project contains none of its source code.',
    },
    'settings.about.license': {'zh': 'GPL-3.0-or-later，详见仓库 LICENSE', 'en': 'GPL-3.0-or-later; see LICENSE in the repository'},

    'settings.portraitOnly': {'zh': '仅竖屏生效；横屏用左侧标签栏的展开按钮', 'en': 'Portrait only; in landscape use the rail expand button'},
    'settings.appDescription': {'zh': '多平台小说阅读器：Android 与 Linux 桌面共用一套自适应界面', 'en': 'A multi-platform reader: one adaptive UI for Android and Linux desktop'},
    'settings.customJson': {'zh': '自定义 JSON（library / settings / reader_settings / sources），保存在应用私有目录', 'en': 'Custom JSON (library / settings / reader_settings / sources) stored in the app private directory'},
    'settings.credits': {'zh': '来源与致谢', 'en': 'Credits'},
    'settings.script.onDetail': {'zh': '已启用：可导入并运行脚本。关闭后脚本相关功能不可用，', 'en': 'Enabled: scripts can be imported and run. When off, '},
    'settings.script.offDetail': {'zh': '已关闭：脚本相关功能不可用（搜索页不列书源、插件页不可管理）。', 'en': 'Disabled: script features are unavailable (no sources in search, no management on the plugins page).'},
    'settings.script.undecidedDetail': {'zh': '尚未确认：脚本相关功能当前不可用。开启需先阅读说明并通过理解确认题', 'en': 'Undecided: script features are unavailable. Enabling requires reading the notice and passing the understanding check.'},
    'settings.script.turnedOff': {'zh': '用户在设置里关闭脚本支持', 'en': 'User disabled script support in settings'},
    'settings.langSwitched': {'zh': '界面语言已切换为 {mode}', 'en': 'Language switched to {mode}'},
    'settings.downloadLimitSet': {'zh': '下载脚本运行上限已设为 {n} 秒', 'en': 'Script download timeout set to {n} s'},
    'settings.downloadLimitSetUnlimited': {'zh': '下载脚本运行上限已设为 不限制', 'en': 'Script download timeout set to unlimited'},

    'settings.shelf.section': {'zh': '书架', 'en': 'Shelf'},
    'settings.portraitLabels': {'zh': '底部标签显示文字', 'en': 'Show labels on bottom tabs'},
  };
}
