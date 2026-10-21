import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:file_selector/file_selector.dart';

import '../services/tts/local_tts_synthesizer.dart';
import '../services/tts/tts_model_store.dart';
import '../services/tts/read_aloud_controller.dart';
import '../state/app_state.dart';

/// 朗读快速设置面板：中文音色、语速、试听。
///
/// 同时用于两处，行为一致：
///   - 阅读器内（`onDark: true`，菜单里的「朗读设置」）
///   - 设置页「朗读」分区（跟随主题）
///
/// 传入 [controller] 时，面板会操作阅读器正在使用的朗读器（改完立即生效，
/// 并通过 [onRestart] 从当前句重读）；不传则自建一个仅用于试听的朗读器。
class ReadAloudSettingsPanel extends StatefulWidget {
  const ReadAloudSettingsPanel({
    super.key,
    this.controller,
    this.onRestart,
    this.onDark = false,
  });

  final ReadAloudController? controller;

  /// 音色/语速变化后，从第 [at] 句重读（仅在传了 [controller] 时使用）。
  final Future<void> Function(int at)? onRestart;

  final bool onDark;

  @override
  State<ReadAloudSettingsPanel> createState() => _ReadAloudSettingsPanelState();
}

class _ReadAloudSettingsPanelState extends State<ReadAloudSettingsPanel> {
  static const _sample = '夜色像一层薄薄的墨，慢慢洇开在窗棂上。';

  ReadAloudController? _own;
  List<TtsModel>? _models;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadModels());
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// 面板操作的目标朗读器：优先使用阅读器的，否则自建试听用的。
  ReadAloudController get _target => widget.controller ?? (_own ??= ReadAloudController());

  ReadAloudController? get _listenable => widget.controller ?? _own;

  Future<void> _loadModels() async {
    // 注意：不能因为 _loading 为真就提前 return —— 导入流程会先把 _loading 置真，
    // 若在这里短路，导入完成后列表永远不刷新（表现为"必须重启应用才看到模型"）。
    if (mounted) setState(() => _loading = true);
    final models = await LocalTtsSynthesizer.store.load();
    if (!mounted) return;
    setState(() {
      _models = models;
      _loading = false;
    });
  }

  /// 导入一个模型包（zip / tar.bz2 / tar.gz / tar），成功后自动选中。
  Future<void> _importModel() async {
    final state = context.read<AppState>();
    // 不做任何后缀/MIME 筛选：Android 的 file_selector 会把 extensions 映射成 MIME，
    // .tar.bz2 这类双后缀会被判成 application/octet-stream 而置灰不可选（实测只能选 .gz/.zip）。
    // 安全边界放在导入器：它按**内容魔数**识别 zip / tar.bz2 / tar.gz / tar，根本不看扩展名；
    // 认不出来就抛出可读错误，不会写入半个模型。
    // 分平台的选文件提示：Android 的文件选择器对目录/类型可见性不稳定，
    // 桌面端则容易踩到中文路径与权限问题。
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入语音模型'),
        content: Text(
          Platform.isAndroid
              ? '请先把模型包放到「下载 / Download」目录，再从列表中选择它。\n\n'
                    '支持 .zip / .tar.bz2 / .tar.gz / .tar，无需解压。'
              : '请把模型包放在不含中文与空格的英文路径下（例如 ~/Downloads），'
                    '并确认当前用户对该文件有读权限。\n\n'
                    '支持 .zip / .tar.bz2 / .tar.gz / .tar，无需解压。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (go != true) return;

    const anyType = [XTypeGroup(label: '模型包', mimeTypes: ['*/*'])];
    final file = await openFile(acceptedTypeGroups: anyType);
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final model = await LocalTtsSynthesizer.store.importPackage(File(file.path));
      state.readerSettings.ttsVoice = model.id;
      await state.saveReaderSettings();
      await _loadModels();
      _snack('已导入：${model.name}');
    } on TtsModelImportException catch (e) {
      _snack('导入失败：${e.message}');
    } catch (e) {
      _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteModel(TtsModel model) async {
    await LocalTtsSynthesizer.dispose(model.id);
    await LocalTtsSynthesizer.store.delete(model);
    await _loadModels();
    _snack('已删除：${model.name}');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  TtsModel? get _selected {
    final id = context.read<AppState>().readerSettings.ttsVoice;
    final list = _models ?? const <TtsModel>[];
    for (final m in list) {
      if (m.id == id) return m;
    }
    return list.isEmpty ? null : list.first;
  }

  Future<void> _applySettings({required bool restart}) async {
    final state = context.read<AppState>();
    final rs = state.readerSettings;
    await state.saveReaderSettings();
    final target = _target
      ..voice = rs.ttsVoice
      ..rate = rs.ttsRateString;
    if (restart && target.isActive) {
      await target.stop();
      final at = target.index;
      final restart = widget.onRestart;
      if (restart != null) {
        await restart(at);
      } else {
        await target.start(_sample, at: at);
      }
    }
  }

  Future<void> _toggleAudition() async {
    final controller = _target;
    final rs = context.read<AppState>().readerSettings;
    controller
      ..voice = rs.ttsVoice
      ..rate = rs.ttsRateString;
    if (controller.isActive) {
      await controller.stop();
      if (mounted) setState(() {});
      return;
    }
    await controller.start('$_sample');
    if (mounted) setState(() {});
  }

  Color _text(double alpha) => widget.onDark
      ? Colors.white.withValues(alpha: alpha)
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rs = state.readerSettings;
    final listenable = _listenable;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.record_voice_over_outlined, size: 18, color: _text(0.7)),
            const SizedBox(width: 8),
            Text('本地语音模型', style: TextStyle(fontSize: 13, color: _text(0.7))),
            const Spacer(),
            Text(
              _selected?.name ?? '未导入',
              style: TextStyle(fontSize: 12, color: _text(0.55)),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '导入模型包（zip / tar.bz2）',
                icon: Icon(Icons.add, size: 18, color: _text(0.7)),
                onPressed: _importModel,
              ),
          ],
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: (_models ?? const <TtsModel>[]).length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final model = _models![index];
              final selected = model.id == rs.ttsVoice ||
                  (rs.ttsVoice.isEmpty && index == 0);
              return Center(
                // InputChip 才有 onDeleted；ChoiceChip 不支持删除按钮
                child: InputChip(
                  label: Text(model.name, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) async {
                    setState(() => rs.ttsVoice = model.id);
                    await _applySettings(restart: true);
                  },
                  onDeleted: () => _deleteModel(model),
                  deleteButtonTooltipMessage: '删除该模型',
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            Text('语速', style: TextStyle(fontSize: 13, color: _text(0.7))),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove, size: 18, color: _text(0.8)),
              onPressed: () async {
                setState(
                  () => rs.ttsRatePercent = (rs.ttsRatePercent - 10).clamp(-50, 100),
                );
                await _applySettings(restart: true);
              },
            ),
            Expanded(
              child: Slider(
                value: rs.ttsRatePercent.clamp(-50, 100).toDouble(),
                min: -50,
                max: 100,
                divisions: 15,
                label: rs.ttsRatePercent == 0
                    ? '正常'
                    : '${rs.ttsRatePercent > 0 ? '+' : ''}${rs.ttsRatePercent}%',
                onChanged: (v) => setState(() => rs.ttsRatePercent = v.round()),
                onChangeEnd: (_) => _applySettings(restart: true),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.add, size: 18, color: _text(0.8)),
              onPressed: () async {
                setState(
                  () => rs.ttsRatePercent = (rs.ttsRatePercent + 10).clamp(-50, 100),
                );
                await _applySettings(restart: true);
              },
            ),
            SizedBox(
              width: 46,
              child: Text(
                rs.ttsRatePercent == 0
                    ? '正常'
                    : '${rs.ttsRatePercent > 0 ? '+' : ''}${rs.ttsRatePercent}%',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: _text(0.6)),
              ),
            ),
          ],
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => unawaited(_toggleAudition()),
              icon: const Icon(Icons.hearing_outlined, size: 18),
              label: Text(_target.isActive ? '停止试听' : '试听'),
            ),
            const Spacer(),
            if (widget.controller != null)
              Text(
                _target.isActive
                    ? '${_target.index + 1}/${_target.segments.length} 句'
                    : '未在朗读',
                style: TextStyle(fontSize: 12, color: _text(0.6)),
              ),
          ],
        ),
        if (_target.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _target.lastError!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );

    if (listenable == null) return body;
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => body,
    );
  }
}
