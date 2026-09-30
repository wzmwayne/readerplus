import 'dart:convert';

/// 翻页方式。
enum PageMode {
  cover('覆盖'),
  slide('滑动'),
  scroll('滚动'),
  none('无动画');

  const PageMode(this.label);
  final String label;

  static PageMode parse(String? name) =>
      PageMode.values.firstWhere((e) => e.name == name, orElse: () => PageMode.slide);
}

/// 页眉/页脚可选内容。
enum TipMode {
  none('无'),
  bookName('书名'),
  chapterName('章节名'),
  pageIndex('页码'),
  progress('进度'),
  time('时间'),
  battery('电量');

  const TipMode(this.label);
  final String label;

  static TipMode parse(String? name) =>
      TipMode.values.firstWhere((e) => e.name == name, orElse: () => TipMode.none);
}

/// 一套阅读排版样式，数值取自原版预设（微信读书 + 预设1~5）。
class ReadingStyle {
  final String name;
  final String bgColor;
  final String textColor;
  final String bgColorNight;
  final String textColorNight;
  final double textSize;
  final double lineSpacing;
  final double letterSpacing;
  final String paragraphIndent;
  final double paragraphSpacing;
  final double paddingLeft;
  final double paddingRight;
  final double paddingTop;
  final double paddingBottom;
  final double headerPaddingLeft;
  final double headerPaddingRight;
  final double headerPaddingTop;
  final double headerPaddingBottom;
  final double footerPaddingLeft;
  final double footerPaddingRight;
  final double footerPaddingTop;
  final double footerPaddingBottom;
  final bool showHeaderLine;
  final bool showFooterLine;

  const ReadingStyle({
    required this.name,
    required this.bgColor,
    required this.textColor,
    required this.bgColorNight,
    required this.textColorNight,
    this.textSize = 18,
    this.lineSpacing = 10,
    this.letterSpacing = 0,
    this.paragraphIndent = '　　',
    this.paragraphSpacing = 6,
    this.paddingLeft = 22,
    this.paddingRight = 22,
    this.paddingTop = 5,
    this.paddingBottom = 4,
    this.headerPaddingLeft = 19,
    this.headerPaddingRight = 16,
    this.headerPaddingTop = 10,
    this.headerPaddingBottom = 0,
    this.footerPaddingLeft = 13,
    this.footerPaddingRight = 17,
    this.footerPaddingTop = 0,
    this.footerPaddingBottom = 10,
    this.showHeaderLine = true,
    this.showFooterLine = true,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'bgColor': bgColor,
    'textColor': textColor,
    'bgColorNight': bgColorNight,
    'textColorNight': textColorNight,
    'textSize': textSize,
    'lineSpacing': lineSpacing,
    'letterSpacing': letterSpacing,
    'paragraphIndent': paragraphIndent,
    'paragraphSpacing': paragraphSpacing,
    'paddingLeft': paddingLeft,
    'paddingRight': paddingRight,
    'paddingTop': paddingTop,
    'paddingBottom': paddingBottom,
    'headerPaddingLeft': headerPaddingLeft,
    'headerPaddingRight': headerPaddingRight,
    'headerPaddingTop': headerPaddingTop,
    'headerPaddingBottom': headerPaddingBottom,
    'footerPaddingLeft': footerPaddingLeft,
    'footerPaddingRight': footerPaddingRight,
    'footerPaddingTop': footerPaddingTop,
    'footerPaddingBottom': footerPaddingBottom,
    'showHeaderLine': showHeaderLine,
    'showFooterLine': showFooterLine,
  };

  factory ReadingStyle.fromJson(Map<String, dynamic> json) => ReadingStyle(
    name: json['name'] as String? ?? '自定义',
    bgColor: json['bgColor'] as String? ?? '#FFFFFF',
    textColor: json['textColor'] as String? ?? '#000000',
    bgColorNight: json['bgColorNight'] as String? ?? '#000000',
    textColorNight: json['textColorNight'] as String? ?? '#ADADAD',
    textSize: (json['textSize'] as num?)?.toDouble() ?? 18,
    lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 10,
    letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
    paragraphIndent: json['paragraphIndent'] as String? ?? '　　',
    paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 6,
    paddingLeft: (json['paddingLeft'] as num?)?.toDouble() ?? 22,
    paddingRight: (json['paddingRight'] as num?)?.toDouble() ?? 22,
    paddingTop: (json['paddingTop'] as num?)?.toDouble() ?? 5,
    paddingBottom: (json['paddingBottom'] as num?)?.toDouble() ?? 4,
    headerPaddingLeft: (json['headerPaddingLeft'] as num?)?.toDouble() ?? 19,
    headerPaddingRight: (json['headerPaddingRight'] as num?)?.toDouble() ?? 16,
    headerPaddingTop: (json['headerPaddingTop'] as num?)?.toDouble() ?? 10,
    headerPaddingBottom: (json['headerPaddingBottom'] as num?)?.toDouble() ?? 0,
    footerPaddingLeft: (json['footerPaddingLeft'] as num?)?.toDouble() ?? 13,
    footerPaddingRight: (json['footerPaddingRight'] as num?)?.toDouble() ?? 17,
    footerPaddingTop: (json['footerPaddingTop'] as num?)?.toDouble() ?? 0,
    footerPaddingBottom: (json['footerPaddingBottom'] as num?)?.toDouble() ?? 10,
    showHeaderLine: json['showHeaderLine'] as bool? ?? true,
    showFooterLine: json['showFooterLine'] as bool? ?? true,
  );
}

/// 内置排版预设，数值来自原版 readConfig 默认数据。
const List<ReadingStyle> kReadingStyles = [
  ReadingStyle(
    name: '微信读书',
    bgColor: '#C0EDC6',
    textColor: '#0B0B0B',
    bgColorNight: '#000000',
    textColorNight: '#ADADAD',
  ),
  ReadingStyle(
    name: '预设1',
    bgColor: '#FFFFFF',
    textColor: '#000000',
    bgColorNight: '#000000',
    textColorNight: '#FFFFFF',
  ),
  ReadingStyle(
    name: '预设2',
    bgColor: '#DDC090',
    textColor: '#3E3422',
    bgColorNight: '#3C3F43',
    textColorNight: '#DCDFE1',
  ),
  ReadingStyle(
    name: '预设3',
    bgColor: '#C2D8AA',
    textColor: '#596C44',
    bgColorNight: '#3C3F43',
    textColorNight: '#88C16F',
  ),
  ReadingStyle(
    name: '预设4',
    bgColor: '#DBB8E2',
    textColor: '#68516C',
    bgColorNight: '#3C3F43',
    textColorNight: '#F6AEAE',
  ),
  ReadingStyle(
    name: '预设5',
    bgColor: '#ABCEE0',
    textColor: '#3D4C54',
    bgColorNight: '#3C3F43',
    textColorNight: '#90BFF5',
  ),
];

/// 阅读设置：独立于应用主题，跟随书籍阅读界面。
class ReaderSettings {
  int styleIndex;
  double textSize;
  double lineSpacing;
  double letterSpacing;
  double paragraphSpacing;
  String paragraphIndent;
  bool bold;
  double paddingLeft;
  double paddingRight;
  double paddingTop;
  double paddingBottom;
  String bgColor;
  String textColor;
  bool nightMode;
  String fontFamily;
  PageMode pageMode;
  bool keepScreenOn;
  double brightness;
  TipMode headerLeft;
  TipMode headerMiddle;
  TipMode headerRight;
  TipMode footerLeft;
  /// 横屏时是否把顶栏/底栏显示到左右两侧。
  bool landscapeSideMenu;

  /// 朗读音色（Edge TTS 中文音色）与语速。
  String ttsVoice;
  String ttsRate;

  TipMode footerMiddle;
  TipMode footerRight;
  bool showHeaderLine;
  bool showFooterLine;

  ReaderSettings({
    this.styleIndex = 0,
    this.textSize = 18,
    this.lineSpacing = 10,
    this.letterSpacing = 0,
    this.paragraphSpacing = 6,
    this.paragraphIndent = '　　',
    this.bold = false,
    this.paddingLeft = 22,
    this.paddingRight = 22,
    this.paddingTop = 5,
    this.paddingBottom = 4,
    this.bgColor = '#C0EDC6',
    this.textColor = '#0B0B0B',
    this.nightMode = false,
    this.fontFamily = '',
    this.pageMode = PageMode.slide,
    this.keepScreenOn = true,
    this.brightness = 0,
    this.headerLeft = TipMode.none,
    this.headerMiddle = TipMode.chapterName,
    this.headerRight = TipMode.none,
    this.footerLeft = TipMode.progress,
    this.footerMiddle = TipMode.none,
    this.landscapeSideMenu = true,
    this.ttsVoice = 'zh-CN-XiaoxiaoNeural',
    this.ttsRate = '+0%',
    this.footerRight = TipMode.pageIndex,
    this.showHeaderLine = false,
    this.showFooterLine = true,
  });

  ReaderSettings clone() => ReaderSettings.fromJson(toJson());

  void applyStyle(ReadingStyle style, {required bool night}) {
    textSize = style.textSize;
    lineSpacing = style.lineSpacing;
    letterSpacing = style.letterSpacing;
    paragraphSpacing = style.paragraphSpacing;
    paragraphIndent = style.paragraphIndent;
    paddingLeft = style.paddingLeft;
    paddingRight = style.paddingRight;
    paddingTop = style.paddingTop;
    paddingBottom = style.paddingBottom;
    showHeaderLine = style.showHeaderLine;
    showFooterLine = style.showFooterLine;
    bgColor = night ? style.bgColorNight : style.bgColor;
    textColor = night ? style.textColorNight : style.textColor;
  }

  Map<String, dynamic> toJson() => {
    'styleIndex': styleIndex,
    'textSize': textSize,
    'lineSpacing': lineSpacing,
    'letterSpacing': letterSpacing,
    'paragraphSpacing': paragraphSpacing,
    'paragraphIndent': paragraphIndent,
    'bold': bold,
    'paddingLeft': paddingLeft,
    'paddingRight': paddingRight,
    'paddingTop': paddingTop,
    'paddingBottom': paddingBottom,
    'bgColor': bgColor,
    'textColor': textColor,
    'nightMode': nightMode,
    'fontFamily': fontFamily,
    'pageMode': pageMode.name,
    'keepScreenOn': keepScreenOn,
    'brightness': brightness,
    'headerLeft': headerLeft.name,
    'headerMiddle': headerMiddle.name,
    'headerRight': headerRight.name,
    'footerLeft': footerLeft.name,
    'footerMiddle': footerMiddle.name,
    'landscapeSideMenu': landscapeSideMenu,
      'ttsVoice': ttsVoice,
      'ttsRate': ttsRate,
    'footerRight': footerRight.name,
    'showHeaderLine': showHeaderLine,
    'showFooterLine': showFooterLine,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    styleIndex: (json['styleIndex'] as num?)?.toInt() ?? 0,
    textSize: (json['textSize'] as num?)?.toDouble() ?? 18,
    lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 10,
    letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0,
    paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 6,
    paragraphIndent: json['paragraphIndent'] as String? ?? '　　',
    bold: json['bold'] as bool? ?? false,
    paddingLeft: (json['paddingLeft'] as num?)?.toDouble() ?? 22,
    paddingRight: (json['paddingRight'] as num?)?.toDouble() ?? 22,
    paddingTop: (json['paddingTop'] as num?)?.toDouble() ?? 5,
    paddingBottom: (json['paddingBottom'] as num?)?.toDouble() ?? 4,
    bgColor: json['bgColor'] as String? ?? '#C0EDC6',
    textColor: json['textColor'] as String? ?? '#0B0B0B',
    nightMode: json['nightMode'] as bool? ?? false,
    fontFamily: json['fontFamily'] as String? ?? '',
    pageMode: PageMode.parse(json['pageMode'] as String?),
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
    headerLeft: TipMode.parse(json['headerLeft'] as String?),
    headerMiddle: TipMode.parse(json['headerMiddle'] as String?),
    headerRight: TipMode.parse(json['headerRight'] as String?),
    footerLeft: TipMode.parse(json['footerLeft'] as String?),
    footerMiddle: TipMode.parse(json['footerMiddle'] as String?),
    landscapeSideMenu: json['landscapeSideMenu'] as bool? ?? true,
      ttsVoice: json['ttsVoice'] as String? ?? 'zh-CN-XiaoxiaoNeural',
      ttsRate: json['ttsRate'] as String? ?? '+0%',
    footerRight: TipMode.parse(json['footerRight'] as String?),
    showHeaderLine: json['showHeaderLine'] as bool? ?? false,
    showFooterLine: json['showFooterLine'] as bool? ?? true,
  );

  String encode() => jsonEncode(toJson());
}
