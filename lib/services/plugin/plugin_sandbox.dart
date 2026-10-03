import 'dart:async';
import 'dart:convert';

import '../app_log.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// 脚本任务类型。
enum PluginTask {
  /// 清洗 TXT（读 input/ 的文本，产出 EPUB 3 到 output/）。
  clean('clean', '清洗并转 EPUB'),

  /// 下载/抓取书源（产出 EPUB 3 到 output/）。
  source('source', '书源下载');

  const PluginTask(this.id, this.label);

  final String id;
  final String label;

  static PluginTask fromId(String? id) => PluginTask.values.firstWhere(
    (task) => task.id == id,
    orElse: () => PluginTask.clean,
  );
}

/// 一个用户脚本。
class PluginScript {
  PluginScript({
    required this.id,
    required this.name,
    required this.source,
    this.description = '',
    this.task = PluginTask.clean,
    this.enabled = true,
    this.params = const {},
    this.builtin = false,
  });

  final String id;
  String name;
  String description;
  PluginTask task;
  bool enabled;
  bool builtin;
  String source;

  /// 脚本内 SCRIPT 声明里的标识与版本（describe 后填充）。
  String? declaredId;
  String? version;

  /// 能力列表：clean / search / detail / download（由声明决定）。
  Set<String> capabilities = {};

  /// 运行参数（写进 params.json，脚本自行容错）。
  Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'task': task.id,
    'enabled': enabled,
    'builtin': builtin,
    'params': params,
    'declaredId': declaredId,
    'version': version,
    'capabilities': capabilities.toList(),
  };

  static PluginScript fromJson(Map<String, dynamic> json, String source) {
    final id = json['id'] as String;
    return PluginScript(
        id: id,
        name: json['name'] as String? ?? id,
        description: json['description'] as String? ?? '',
        task: PluginTask.fromId(json['task'] as String?),
        enabled: json['enabled'] as bool? ?? true,
        builtin: json['builtin'] as bool? ?? false,
        params: (json['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        source: source,
      )
        ..declaredId = json['declaredId'] as String?
        ..version = json['version'] as String?
        ..capabilities =
            ((json['capabilities'] as List?)?.cast<String>() ?? const [])
                .toSet();
  }
}

/// 一次脚本执行的结果。
class PluginRunResult {
  const PluginRunResult({
    required this.ok,
    required this.outputs,
    required this.traceback,
    required this.sandboxPath,
    required this.log,
  });

  final bool ok;
  final List<File> outputs;
  final String traceback;
  final String sandboxPath;
  final String log;

  String get summary => ok
      ? '完成：${outputs.map((f) => f.uri.pathSegments.last).join('、')}'
      : '失败：$traceback';
}

/// 脚本运行环境（真实实现走 serious_python；测试可注入假实现）。
abstract class PluginRuntime {
  /// 带 SANDBOX_ROOT 运行沙盒入口；返回程序最终输出（日志另见 log.txt）。
  Future<void> runSandbox(String sandboxPath, {required bool audit});

  /// 取消当前执行。
  void cancel();
}

/// 沙盒：一次执行独立目录，输入输出全部通过文件交换。
class PluginSandbox {
  PluginSandbox._(this.root);

  final Directory root;

  Directory get input => Directory('${root.path}/input');
  Directory get output => Directory('${root.path}/output');
  Directory get work => Directory('${root.path}/work');
  File get paramsFile => File('${root.path}/params.json');
  File get scriptFile => File('${root.path}/user_script.py');
  /// 结果清单：写在 `output/manifest.json`（根目录仅作旧运行兜底）。
  File get manifestFile {
    final inOutput = File('${output.path}/manifest.json');
    return inOutput.existsSync() ? inOutput : File('${root.path}/manifest.json');
  }
  /// 运行日志：写在 `output/log.txt`（根目录仅作旧运行兜底）。
  File get logFile {
    final inOutput = File('${output.path}/log.txt');
    return inOutput.existsSync() ? inOutput : File('${root.path}/log.txt');
  }

  static Future<PluginSandbox> create(Directory parent) async {
    final id = List.generate(
      12,
      (_) => Random().nextInt(16).toRadixString(16),
    ).join();
    final root = Directory('${parent.path}/$id');
    final sandbox = PluginSandbox._(root);
    await sandbox.input.create(recursive: true);
    await sandbox.output.create(recursive: true);
    await sandbox.work.create(recursive: true);
    return sandbox;
  }

  /// 写入运行参数（脚本应自行对缺失字段做默认值）。
  Future<void> writeParams(Map<String, dynamic> params) =>
      paramsFile.writeAsString(jsonEncode(params), flush: true);

  Future<void> writeScript(String source) =>
      scriptFile.writeAsString(source, flush: true);

  /// 把输入文件放进 input/。
  Future<File> addInput(String fileName, List<int> bytes) async {
    final file = File('${input.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 读取日志文件（前台显示用）。
  Future<String> readLog() async =>
      logFile.existsSync() ? logFile.readAsString() : '';

  /// 解析 manifest.json；缺失或损坏时按失败处理。
  Future<
    ({bool ok, String traceback, List<String> outputs, Map<String, dynamic>? script})
  >
  readManifest() async {
    if (!manifestFile.existsSync()) {
      final inOutput = File('${output.path}/manifest.json');
      final atRoot = File('${root.path}/manifest.json');
      AppLog.error(
        'plugin',
        '未找到结果清单：${inOutput.path}（存在=${inOutput.existsSync()}）、'
        '${atRoot.path}（存在=${atRoot.existsSync()}）',
      );
      return (
        ok: false,
        traceback: '脚本未写出 manifest.json',
        outputs: const <String>[],
        script: null,
      );
    }
    final raw = await manifestFile.readAsString();
    AppLog.info(
      'plugin',
      '读到结果清单：${manifestFile.path}（${raw.length} 字节）',
    );
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'error';
      final outputs =
          (decoded['outputs'] as List?)?.cast<String>() ?? const <String>[];
      return (
        ok: status == 'ok',
        traceback: decoded['traceback'] as String? ?? '',
        outputs: outputs,
        script: (decoded['script'] as Map?)?.cast<String, dynamic>(),
      );
    } catch (error) {
      AppLog.error(
        'plugin',
        'manifest.json 解析失败：$error；内容前 200 字符：'
        '${raw.length > 200 ? raw.substring(0, 200) : raw}',
      );
      return (
        ok: false,
        traceback: 'manifest.json 解析失败：$error',
        outputs: const <String>[],
        script: null,
      );
    }
  }

  /// 书源脚本的 search / detail 结果（output/result.json）。
  Future<Map<String, dynamic>?> readResultJson() async {
    final file = File('${output.path}/result.json');
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 脚本产物（不含宿主的 log.txt / manifest.json）。
  /// 脚本产物：`output/` 下的文件（递归），不含宿主的 log.txt / manifest.json。
  List<File> listOutputs() {
    if (!output.existsSync()) return const [];
    const bookkeeping = {'log.txt', 'manifest.json'};
    return output
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => !bookkeeping.contains(file.uri.pathSegments.last))
        .toList();
  }

  Future<void> dispose({bool keepForDebug = false}) async {
    if (keepForDebug) return;
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } catch (error) {
      debugPrint('[plugin] 清理沙盒失败：$error');
    }
  }
}
