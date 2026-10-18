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

  /// 已读章节下标集合（进入该章即记一次；随 library.json 持久化，删书一并清除）。
  final Set<int> readChapters;

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
    Set<int>? readChapters,
  }) : addedAt = addedAt ?? DateTime.now(),
       readChapters = readChapters ?? <int>{};

  /// 该章是否已读。
  bool isChapterRead(int index) => readChapters.contains(index);

  /// 标记已读；返回 true 表示状态真的变了（调用方据此决定是否落盘）。
  bool markChapterRead(int index) => readChapters.add(index);

  /// 切换已读/未读；返回切换后的状态。
  bool toggleChapterRead(int index) =>
      readChapters.remove(index) ? false : readChapters.add(index);

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
    // 已读章节：排好序再写，便于人工查看 diff；空集合也写（保持字段稳定）
    'readChapters': (readChapters.toList()..sort()),
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
    // 兼容旧数据：缺字段 ⇔ 空集合
    readChapters: {
      for (final value in (json['readChapters'] as List?) ?? const [])
        if (value is num) value.toInt(),
    },
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
