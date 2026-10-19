import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

/// 一个可用的本地语音模型（用户自行导入，应用不内置、不联网下载）。
class TtsModel {
  const TtsModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.language,
    required this.dirPath,
    required this.onnxFile,
    required this.hasEspeakData,
    required this.sizeBytes,
    required this.importedAt,
  });

  final String id;
  final String name;

  /// `piper`（自带 espeak-ng-data）或 `vits`（需 lexicon/fst）。
  final String kind;

  /// `zh` / `en` / `unknown`（由包内文件与文件名推断，仅供展示）。
  final String language;

  final String dirPath;
  final String onnxFile;
  final bool hasEspeakData;
  final int sizeBytes;
  final DateTime importedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'language': language,
    'dirPath': dirPath,
    'onnxFile': onnxFile,
    'hasEspeakData': hasEspeakData,
    'sizeBytes': sizeBytes,
    'importedAt': importedAt.toIso8601String(),
  };

  static TtsModel fromJson(Map<String, dynamic> json) => TtsModel(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    kind: '${json['kind'] ?? 'piper'}',
    language: '${json['language'] ?? 'unknown'}',
    dirPath: '${json['dirPath'] ?? ''}',
    onnxFile: '${json['onnxFile'] ?? ''}',
    hasEspeakData: json['hasEspeakData'] == true,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    importedAt:
        DateTime.tryParse('${json['importedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// 导入失败：`message` 直接面向用户，说明缺什么、该怎么补。
class TtsModelImportException implements Exception {
  const TtsModelImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 模型仓储：**zip 导入 → 解压 → 校验 → 落库**。
///
/// 目录结构（应用私有目录，用户不可直接改）：
///   `<root>/<modelId>/…`   模型文件
///   `<root>/models.json`   已导入模型清单
///
/// 校验规则（缺一不可，失败时给出能照做的提示）：
///   - 恰好一个 `.onnx`（体积 ≥ 1 MB，防止下成 HTML 错误页）；
///   - `tokens.txt` 存在且非空；
///   - `espeak-ng-data/` 内至少 20 个文件（Piper），或 `lexicon.txt` 非空（VITS 类）。
class TtsModelStore {
  TtsModelStore({Future<Directory> Function()? root})
    : _rootProvider = root ?? _defaultRoot;

  final Future<Directory> Function() _rootProvider;

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/tts_models');
  }

  Future<Directory> _root() async {
    final dir = await _rootProvider();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<TtsModel>> load() async {
    final root = await _root();
    final file = File('${root.path}/models.json');
    if (!file.existsSync()) return const [];
    try {
      final raw = jsonDecode(file.readAsStringSync());
      final list = (raw is Map ? raw['models'] : raw) as List?;
      if (list == null) return const [];
      return list
          .whereType<Map>()
          .map((e) => TtsModel.fromJson(e.cast<String, dynamic>()))
          .where((m) => File(m.onnxFile).existsSync())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<TtsModel> models) async {
    final root = await _root();
    File('${root.path}/models.json').writeAsStringSync(
      jsonEncode({'models': models.map((m) => m.toJson()).toList()}),
      flush: true,
    );
  }

  Future<void> delete(TtsModel model) async {
    final models = await load();
    final rest = models.where((m) => m.id != model.id).toList();
    await _save(rest);
    final dir = Directory(model.dirPath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// 导入一个模型包并校验可用性。
  ///
  /// 支持 `.zip`、`.tar.bz2`、`.tar.gz`、`.tar`（**按内容魔数识别，不看扩展名**）：
  /// sherpa 官方发布的是 `.tar.bz2`，用户也可能自己压成 zip。
  Future<TtsModel> importPackage(File file, {String? displayName}) async {
    if (!file.existsSync()) {
      throw const TtsModelImportException('文件不存在');
    }
    final files = await _decodeEntries(await file.readAsBytes());
    if (files.isEmpty) {
      throw const TtsModelImportException('包里没有文件');
    }
    for (final f in files) {
      final name = f.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.split('/').contains('..')) {
        throw TtsModelImportException('包内含越界路径，已拒绝：${f.name}');
      }
    }

    final onnx = files.where((f) => f.name.toLowerCase().endsWith('.onnx')).toList();
    if (onnx.isEmpty) {
      throw const TtsModelImportException(
        '包里没有 .onnx 模型文件（请确认下载的是语音模型，不是示例音频；'
        '支持 zip / tar.bz2 / tar.gz / tar）',
      );
    }
    if (onnx.length > 1) {
      throw TtsModelImportException(
        '包里有多份 .onnx（${onnx.length} 个），无法确定用哪个；请一个 zip 只放一个模型',
      );
    }
    final tokens = files.where((f) => f.name.endsWith('tokens.txt')).toList();
    if (tokens.isEmpty || tokens.first.size == 0) {
      throw const TtsModelImportException('缺少 tokens.txt（或内容为空），模型无法解码');
    }
    final espeakFiles = files.where((f) => f.name.contains('espeak-ng-data/')).toList();
    final lexicon = files.where((f) => f.name.endsWith('lexicon.txt')).toList();
    final hasEspeak = espeakFiles.length >= 20;
    if (!hasEspeak && (lexicon.isEmpty || lexicon.first.size == 0)) {
      throw const TtsModelImportException(
        '缺少 espeak-ng-data/（Piper 模型）或 lexicon.txt（VITS 模型），无法把文字转成音素',
      );
    }
    if (onnx.first.size < 1024 * 1024) {
      throw TtsModelImportException(
        '模型文件只有 ${(onnx.first.size / 1024).toStringAsFixed(0)} KB，不像完整模型（常见 20–300 MB）',
      );
    }

    // 解压到临时目录，再整体搬到最终位置（避免半成品残留）
    final root = await _root();
    final id = 'model_${DateTime.now().millisecondsSinceEpoch}';
    final tmp = Directory('${root.path}/.import_$id');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      for (final f in files) {
        final out = File('${tmp.path}/${f.name.replaceAll('\\', '/')}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(f.bytes, flush: true);
      }
      final finalDir = Directory('${root.path}/$id');
      tmp.renameSync(finalDir.path);

      final onnxInFinal = File('${finalDir.path}/${onnx.first.name.replaceAll('\\', '/')}');
      final name = (displayName ?? _guessName(onnx.first.name)).trim();
      final model = TtsModel(
        id: id,
        name: name.isEmpty ? id : name,
        kind: hasEspeak ? 'piper' : 'vits',
        language: _guessLanguage(onnx.first.name, name),
        dirPath: finalDir.path,
        onnxFile: onnxInFinal.path,
        hasEspeakData: hasEspeak,
        sizeBytes: _dirSize(finalDir),
        importedAt: DateTime.now(),
      );
      await _save([...await load(), model]);
      return model;
    } catch (e) {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      if (e is TtsModelImportException) rethrow;
      throw TtsModelImportException('解压失败：$e');
    }
  }

  /// 按魔数识别容器格式并展开为文件列表（zip / gzip+tar / bzip2+tar / tar）。
  static Future<List<({String name, int size, List<int> bytes})>> _decodeEntries(
    List<int> raw,
  ) async {
    if (raw.length < 4) {
      throw const TtsModelImportException('文件太小，不是有效的模型包');
    }
    final b = raw;
    final isZip = b[0] == 0x50 && b[1] == 0x4B; // PK
    final isGzip = b[0] == 0x1F && b[1] == 0x8B;
    final isBzip2 = b[0] == 0x42 && b[1] == 0x5A && b[2] == 0x68; // BZh
    try {
      Archive archive;
      if (isZip) {
        archive = ZipDecoder().decodeBytes(b);
      } else if (isGzip) {
        archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(b));
      } else if (isBzip2) {
        archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(b));
      } else {
        // 未压缩 tar：直接尝试
        archive = TarDecoder().decodeBytes(b);
      }
      return archive.files
          .where((f) => f.isFile)
          .map((f) => (
                name: f.name,
                size: f.size,
                bytes: f.content as List<int>,
              ))
          .toList();
    } catch (e) {
      throw TtsModelImportException(
        '无法识别或解包该文件（支持 zip / tar.bz2 / tar.gz / tar）：$e',
      );
    }
  }

  static String _guessName(String onnxName) {
    final base = onnxName.split('/').last;
    return base.endsWith('.onnx') ? base.substring(0, base.length - 5) : base;
  }

  static String _guessLanguage(String onnxName, String displayName) {
    final s = '$onnxName $displayName'.toLowerCase();
    if (s.contains('zh') || s.contains('cmn') || s.contains('chinese') || s.contains('中文')) {
      return 'zh';
    }
    if (s.contains('en_') || s.contains('english') || s.contains('英文')) return 'en';
    return 'unknown';
  }

  static int _dirSize(Directory dir) {
    var total = 0;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }
}
