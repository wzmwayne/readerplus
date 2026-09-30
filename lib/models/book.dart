import 'dart:math';

/// 书架中的一本书。书籍正文与目录分别存放在 `books/<id>/` 下。
class Book {
  final String id;
  String title;
  String author;
  String intro;
  String? coverPath;
  String group;
  bool finished;
  int charCount;
  int chapterCount;
  String? originalPath;
  int lastChapter;
  int lastOffset;

  /// 阅读进度锚点：屏幕顶部所在的行号（章内整体行序，与分辨率无关）。
  int lastLine;
  double progress;
  DateTime addedAt;
  DateTime? lastReadAt;

  Book({
    required this.id,
    required this.title,
    this.author = '',
    this.intro = '',
    this.coverPath,
    this.group = '全部',
    this.finished = false,
    this.charCount = 0,
    this.chapterCount = 0,
    this.originalPath,
    this.lastChapter = 0,
    this.lastOffset = 0,
    this.lastLine = 0,
    this.progress = 0,
    DateTime? addedAt,
    this.lastReadAt,
  }) : addedAt = addedAt ?? DateTime.now();

  static final Random _random = Random();

  /// 生成不依赖第三方库的本地唯一 id。
  static String newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = _random.nextInt(1 << 32).toRadixString(36);
    return '$ts$rnd';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'intro': intro,
    'coverPath': coverPath,
    'group': group,
    'finished': finished,
    'charCount': charCount,
    'chapterCount': chapterCount,
    'originalPath': originalPath,
    'lastChapter': lastChapter,
    'lastOffset': lastOffset,
    'lastLine': lastLine,
    'progress': progress,
    'addedAt': addedAt.toIso8601String(),
    'lastReadAt': lastReadAt?.toIso8601String(),
  };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名',
    author: json['author'] as String? ?? '',
    intro: json['intro'] as String? ?? '',
    coverPath: json['coverPath'] as String?,
    group: json['group'] as String? ?? '全部',
    finished: json['finished'] as bool? ?? false,
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    originalPath: json['originalPath'] as String?,
    lastChapter: (json['lastChapter'] as num?)?.toInt() ?? 0,
    lastOffset: (json['lastOffset'] as num?)?.toInt() ?? 0,
    lastLine: (json['lastLine'] as num?)?.toInt() ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    lastReadAt: DateTime.tryParse(json['lastReadAt'] as String? ?? ''),
  );
}

/// 章节目录项，[start] / [end] 是正文字符串中的下标区间。
class Chapter {
  final int index;
  final String title;
  final int start;
  final int end;

  const Chapter({
    required this.index,
    required this.title,
    required this.start,
    required this.end,
  });

  int get length => end - start;

  Map<String, dynamic> toJson() => {
    'index': index,
    'title': title,
    'start': start,
    'end': end,
  };

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    index: (json['index'] as num).toInt(),
    title: json['title'] as String,
    start: (json['start'] as num).toInt(),
    end: (json['end'] as num).toInt(),
  );
}
