/// 脚本支持理解确认题：题库 + 抽题 + 判定。
///
/// 纯 Dart（不依赖 Flutter），便于单元测试。
///
/// 题库分两半：`kScriptQuizCorrect` 是应当被勾选的陈述，
/// `kScriptQuizWrong` 是"半对型"陈述（前半句真实，后半句结论跑偏）。
/// 每次抽 5 条：1 条正确 + 1 条错误 + 3 条来自其余 68 条，最后打乱顺序。
/// 因此一道题里可能出现 1~4 条正确项（多选判定天然兼容，不重抽）。
library;

import 'dart:math';

/// 一条候选陈述。
class ScriptQuizItem {
  const ScriptQuizItem({required this.text, required this.isCorrect});

  /// 陈述原文。
  final String text;

  /// 是否为"应当勾选"的陈述。
  final bool isCorrect;
}

/// 每次呈现的选项数量。
const int kScriptQuizOptionCount = 5;

/// 正确陈述（20 条）。
const List<String> kScriptQuizCorrect = [
  '我自行导入的脚本来自第三方，未经 F-Droid 或本应用开发者审查，可能访问网络或读取数据。',
  '启用脚本扩展后，我导入的脚本可能利用本应用的网络权限访问互联网。',
  '脚本是否安全取决于脚本内容和来源，能运行不代表安全。',
  '沙箱能降低风险，但安全仍取决于脚本行为与来源。',
  '朋友发给我的脚本也可能包含恶意代码，仍需判断来源。',
  '用 AI 检查脚本可作辅助，但不能替代审查与自行判断。',
  '本应用不附带脚本；我自行导入的脚本来自第三方，风险由我承担。',
  '我可以在设置中随时关闭脚本支持，关闭后脚本相关功能将不可用。',
  '拒绝启用脚本不会阻止我使用应用的核心功能。',
  '导入脚本前，我应该确认自己信任该脚本的来源。',
  '脚本可能读取本应用有权访问的数据，具体行为取决于脚本内容。',
  '脚本联网行为受本应用网络权限影响，但脚本内容仍可能发起网络请求。',
  '答错理解确认题时，不应启用脚本支持。',
  '脚本扩展是可选功能，不是使用应用核心功能的强制前提。',
  '我导入的脚本未经 F-Droid 打包者逐行审查，不能假定 F-Droid 已保证其安全。',
  '脚本能执行哪些操作，取决于脚本引擎开放的能力和脚本本身的代码。',
  '即使脚本在沙箱中运行，也不应随意运行来源不明的脚本。',
  '启用脚本后，联网行为来自我导入的脚本，而不是本应用自带的联网功能。',
  '启用脚本支持意味着我愿意承担运行第三方脚本带来的潜在风险。',
  '我可以自己编写脚本，但仍需对自己编写的脚本行为负责。',
];

/// "半对型"陈述（50 条，均不应勾选）。
const List<String> kScriptQuizWrong = [
  '沙箱能限制脚本可访问的资源，因此导入脚本后通常不用再关注来源。',
  'F-Droid 会审查应用主体代码，因此我导入的第三方脚本也可以按同样标准信任。',
  '朋友发来的脚本一般没有恶意，所以来源判断可以主要看关系。',
  'AI 能发现常见问题，所以 AI 检查过的脚本通常可以跳过自行判断。',
  '本应用提供了脚本运行能力，因此我导入的脚本出问题也可以找开发者处理。',
  '脚本只是文本文件，通常不会直接联网，所以导入来源的影响有限。',
  '脚本通过应用开放的接口运行，因此扩展行为不会超出应用原有范围。',
  '脚本支持可以在设置里关闭，所以启用时不必太在意后续风险。',
  '拒绝启用脚本后，脚本相关功能会不可用，因此核心功能通常也会受影响。',
  '脚本若经过数字签名，通常说明内容可靠，因此可以优先信任签名脚本。',
  '普通用户也可以导入脚本，所以脚本内容一般已经过某种筛选。',
  '脚本可以从本地导入，因此其行为通常只影响当前设备，隐私风险较低。',
  '脚本运行受应用权限限制，因此脚本能做的事情通常不会超出应用本身。',
  '脚本通过应用的网络权限联网，所以把该权限收紧后联网风险通常也可以一并消除。',
  '理解题用于确认阅读，答错后一般也可以直接启用，只要之后再留意。',
  '选项随机排序能减少死记硬背，因此题目本身通常不需要太认真作答。',
  '脚本运行在应用权限范围内，因此它对其他应用数据的访问通常可以忽略。',
  '开源脚本便于检查，因此来源开源的脚本一般可以视为低风险。',
  'F-Droid 会关注应用安全，因此第三方脚本的安全问题通常也会被覆盖。',
  '脚本在应用内运行，因此它读取的数据通常不会超出应用已获得的数据范围，隐私风险有限。',
  '脚本不容易直接读取应用无权访问的数据，所以导入脚本的隐私风险通常较低。',
  '脚本主要本地运行，因此网络请求通常需要额外配置，来源风险可以稍后再说。',
  '可以把脚本分享给他人，但一般注明来源即可，不必提醒运行风险。',
  '脚本内容比扩展名重要，因此扩展名正确的脚本通常可以优先运行。',
  '运行脚本前应用会提示，因此默认开启脚本支持也能让用户知情。',
  '拒绝启用脚本只是少一个扩展功能，因此应用可以限制部分核心功能来引导用户启用。',
  '启用脚本不会修改系统分区，因此它通常不会带来系统级风险。',
  '脚本可以手动触发，因此自动执行的风险通常不用考虑。',
  '脚本来自应用商店或可信站点时通常经过扫描，因此本地导入脚本也可以沿用这种信任。',
  '脚本解释执行，因此它通常难以直接窃取数据。',
  '脚本调用系统 API 会受到限制，因此它一般不会影响隐私。',
  '脚本在设备上持久化需要额外条件，因此来源不明的脚本通常可以先用后删。',
  '隐私风险主要与安装包有关，因此脚本内容通常只影响功能不影响隐私。',
  '脚本可由 AI 生成，因此人工审查脚本的负担通常可以降低。',
  '脚本联网需要网络权限，因此断网测试后通常可以判断脚本长期安全。',
  '沙箱能隔离部分行为，因此阅读脚本内容的重要性通常可以降低。',
  '脚本来源会影响风险，因此只要功能能运行，来源问题可以后续处理。',
  '脚本可自由导入，因此应用通常会自动信任用户选择的脚本。',
  '应用会记录用户同意，因此导入脚本后的行为通常由用户自行承担，应用不必再单独提示。',
  '脚本可以请求网络，因此应用声明网络权限后，脚本行为通常已受到系统约束。',
  '脚本运行在应用进程中，因此它一般会受到应用权限限制，通常无需额外告知。',
  '脚本可以扩展功能，因此启用脚本后核心功能通常也依赖脚本才能完整使用。',
  '脚本可以静默执行部分操作，因此用户同意一次后通常不必再逐项区分具体脚本。',
  '脚本可以读取应用数据，因此只要应用数据不敏感，脚本来源通常不重要。',
  '脚本可以修改应用内设置，因此系统设置通常也会受到同等影响。',
  '脚本可以绕过部分检查，因此 F-Droid 的审查通常对脚本功能不适用。',
  'AI 审查能覆盖常见漏洞，因此经过 AI 审查的脚本通常可以替代开发者检查。',
  '脚本不请求网络权限时通常不会联网，因此导入脚本时网络风险可以暂不考虑。',
  '导入脚本后开发者会提供支持，因此脚本行为的责任通常可以由开发者分担。',
  '理解题只是启用前的一步，因此答对后通常不必再回看风险说明。',
];

/// 题库全量：20 条正确 + 50 条错误。
final List<ScriptQuizItem> kScriptQuizBank = List.unmodifiable([
  for (final text in kScriptQuizCorrect)
    ScriptQuizItem(text: text, isCorrect: true),
  for (final text in kScriptQuizWrong)
    ScriptQuizItem(text: text, isCorrect: false),
]);

/// 抽到的一道题：5 条已打乱顺序的选项。
class ScriptQuizQuestion {
  ScriptQuizQuestion(List<ScriptQuizItem> options)
      : options = List.unmodifiable(options);

  /// 按呈现顺序排列的选项。
  final List<ScriptQuizItem> options;

  /// 正确项在 [options] 中的下标集合。
  Set<int> get correctIndices => <int>{
        for (var i = 0; i < options.length; i++)
          if (options[i].isCorrect) i,
      };

  /// 判定：选中的下标集合与正确下标集合**恰好相同**才通过。
  ///
  /// 少选一条或多勾一条都不通过（多选按集合比较，顺序无关）。
  bool isAnswerCorrect(Set<int> picked) {
    final correct = correctIndices;
    if (picked.length != correct.length) return false;
    return picked.containsAll(correct);
  }
}

/// 抽一道题：1 条正确 + 1 条错误 + 3 条来自其余 68 条，最后打乱顺序。
///
/// [random] 可注入固定种子，便于测试复现。
ScriptQuizQuestion drawScriptQuiz([Random? random]) {
  final rng = random ?? Random();
  final correct = List<int>.generate(kScriptQuizCorrect.length, (i) => i)
    ..shuffle(rng);
  final wrong = List<int>.generate(kScriptQuizWrong.length, (i) => i)
    ..shuffle(rng);

  final options = <ScriptQuizItem>[
    // 保底各抽一条：正确项与错误项都会出现在题中
    ScriptQuizItem(text: kScriptQuizCorrect[correct.first], isCorrect: true),
    ScriptQuizItem(text: kScriptQuizWrong[wrong.first], isCorrect: false),
  ];

  // 其余选项来自剩余 68 条（19 条正确 + 49 条错误），因此一道题可能出现
  // 2~4 条正确项 —— 多选判定天然兼容，不因此重抽。
  final rest = <ScriptQuizItem>[
    for (final i in correct.skip(1))
      ScriptQuizItem(text: kScriptQuizCorrect[i], isCorrect: true),
    for (final i in wrong.skip(1))
      ScriptQuizItem(text: kScriptQuizWrong[i], isCorrect: false),
  ]..shuffle(rng);
  options.addAll(rest.take(kScriptQuizOptionCount - options.length));
  options.shuffle(rng);
  return ScriptQuizQuestion(options);
}
