import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tts/edge_tts_client.dart';
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
  List<TtsVoice>? _voices;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _voices = EdgeTtsClient.cachedVoices ?? EdgeTtsClient.builtinVoices;
    unawaited(_loadVoices());
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// 面板操作的目标朗读器：优先使用阅读器的，否则自建试听用的。
  ReadAloudController get _target => widget.controller ?? (_own ??= ReadAloudController());

  ReadAloudController? get _listenable => widget.controller ?? _own;

  Future<void> _loadVoices({bool force = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final voices = await EdgeTtsClient.loadChineseVoices(forceRefresh: force);
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _loading = false;
    });
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
    await controller.start('${TtsVoice.labelOf(rs.ttsVoice)}。$_sample');
    if (mounted) setState(() {});
  }

  Color _text(double alpha) => widget.onDark
      ? Colors.white.withValues(alpha: alpha)
      : Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rs = state.readerSettings;
    final voices = _voices ?? EdgeTtsClient.builtinVoices;
    final listenable = _listenable;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.record_voice_over_outlined, size: 18, color: _text(0.7)),
            const SizedBox(width: 8),
            Text('中文音色', style: TextStyle(fontSize: 13, color: _text(0.7))),
            const Spacer(),
            Text(
              TtsVoice.labelOf(rs.ttsVoice),
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
                tooltip: '刷新音色列表',
                icon: Icon(Icons.refresh, size: 18, color: _text(0.7)),
                onPressed: () => _loadVoices(force: true),
              ),
          ],
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: voices.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final voice = voices[index];
              final selected = voice.shortName == rs.ttsVoice;
              return Center(
                child: ChoiceChip(
                  label: Text(
                    TtsVoice.labelOf(voice.shortName),
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: selected,
                  onSelected: (_) async {
                    setState(() => rs.ttsVoice = voice.shortName);
                    await _applySettings(restart: true);
                  },
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
