import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_log.dart';
import '../services/plugin/script_quiz.dart';
import '../state/app_state.dart';

/// 脚本支持的理解确认闸门（整页路由，不能用返回键跳过）。
///
/// 两段式：① 提示 + 免责声明，底部两个同色同宽按钮；② 同一页切到答题区
/// （5 条陈述多选 + 提交）。判定见 [ScriptQuizQuestion.isAnswerCorrect]：
/// 选中集合必须与正确项集合恰好相同。答错可「重试」（重新抽题）或「直接开始」。
///
/// 文案全部走 [L10n]，中英各一份；**不得宣称"内置脚本"之类已不存在的能力**。
class ScriptConsentPage extends StatefulWidget {
  const ScriptConsentPage({super.key, this.random});

  /// 抽题随机源（测试可注入固定种子）。
  final Random? random;

  /// 打开闸门页，返回值 = 用户最终是否启用脚本支持。
  ///
  /// 落盘只在这里做一处：通过 ⇒ true；暂不启用/直接开始 ⇒ false。
  static Future<bool> show(BuildContext context) async {
    final state = context.read<AppState>();
    final decided = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const ScriptConsentPage(),
        fullscreenDialog: true,
      ),
    );
    final enabled = decided == true;
    state.settings.scriptsEnabled = enabled;
    await state.saveSettings();
    AppLog.info(
      'script',
      enabled ? '脚本支持已启用（通过理解确认题）' : '脚本支持未启用（用户选择暂不启用）',
    );
    return enabled;
  }

  @override
  State<ScriptConsentPage> createState() => _ScriptConsentPageState();
}

class _ScriptConsentPageState extends State<ScriptConsentPage> {
  ScriptQuizQuestion? _quiz;
  final Set<int> _picked = {};
  bool _wrong = false;

  bool get _inQuiz => _quiz != null;

  L10n get _l => L10n.of(context.read<AppState>().settings);

  void _startQuiz() {
    setState(() {
      _quiz = drawScriptQuiz(widget.random);
      _picked.clear();
      _wrong = false;
    });
  }

  void _submit() {
    final quiz = _quiz;
    if (quiz == null) return;
    if (quiz.isAnswerCorrect(_picked)) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _wrong = true);
    AppLog.info('script', '理解确认题未通过：可以重试，或直接开始（不启用脚本）');
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_inQuiz ? l.consentTitleQuiz : l.consentTitle),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _inQuiz ? _quizBody(theme, l) : _noticeBody(theme, l)),
              _actions(l),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noticeBody(ThemeData theme, L10n l) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        children: [
          Text(l.consentIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          for (final point in l.consentPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  Expanded(
                    child: Text(point, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              l.consentDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );

  Widget _quizBody(ThemeData theme, L10n l) {
    final quiz = _quiz!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      children: [
        Text(l.consentQuizPrompt, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < quiz.options.length; i++)
          CheckboxListTile(
            value: _picked.contains(i),
            onChanged: (value) => setState(() {
              if (value == true) {
                _picked.add(i);
              } else {
                _picked.remove(i);
              }
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(quiz.options[i].text),
          ),
        if (_wrong)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.consentWrong,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// 底部按钮：同一按钮类型 + Expanded ⇒ 同色、同宽、同高。
  Widget _actions(L10n l) {
    final actions = _inQuiz
        ? (_wrong
            ? <({String label, VoidCallback onPressed})>[
                (label: l.retry, onPressed: _startQuiz),
                (label: l.consentSkip, onPressed: () => Navigator.of(context).pop(false)),
              ]
            : <({String label, VoidCallback onPressed})>[
                (label: l.consentSubmit, onPressed: _submit),
              ])
        : <({String label, VoidCallback onPressed})>[
            (label: l.consentDecline, onPressed: () => Navigator.of(context).pop(false)),
            (label: l.consentEnable, onPressed: _startQuiz),
          ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: actions[i].onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(actions[i].label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
