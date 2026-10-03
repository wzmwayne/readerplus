import 'package:flutter/material.dart';

import '../services/script/script_runner.dart';

/// 脚本提问对话框：只有文本问答。
///
/// - `secret: false`（默认，明文）：输入框正常显示；
/// - `secret: true`（秘密）：输入框遮挡（obscureText），且回答不入日志（由宿主保证）；
/// - [abort] 触发时自动关闭并按取消处理 —— 用于「取消」按钮强杀脚本时，
///   避免用户面对一个永远不会返回的输入框。
Future<AskReply> showScriptAskDialog(
  BuildContext context,
  AskRequest request, {
  Listenable? abort,
}) async {
  final reply = await showDialog<AskReply>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AskDialog(request: request, abort: abort),
  );
  return reply ?? const AskReply.cancelled();
}

class _AskDialog extends StatefulWidget {
  const _AskDialog({required this.request, this.abort});

  final AskRequest request;
  final Listenable? abort;

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.request.default_,
  );

  @override
  void initState() {
    super.initState();
    widget.abort?.addListener(_onAbort);
  }

  @override
  void dispose() {
    widget.abort?.removeListener(_onAbort);
    _controller.dispose();
    super.dispose();
  }

  void _onAbort() {
    if (!mounted) return;
    Navigator.of(context).pop(const AskReply.cancelled());
  }

  @override
  Widget build(BuildContext context) {
    final secret = widget.request.secret;
    return AlertDialog(
      icon: Icon(secret ? Icons.lock_outline : Icons.help_outline),
      title: const Text('书源脚本需要你输入'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.request.question),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: secret,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) =>
                Navigator.of(context).pop(AskReply(ok: true, answer: value)),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: secret ? '秘密输入（不会写进日志）' : '回答',
            ),
          ),
          if (secret) ...[
            const SizedBox(height: 6),
            Text(
              '秘密模式：输入内容遮挡显示，且不会出现在日志里。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const AskReply.cancelled()),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(AskReply(ok: true, answer: _controller.text)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
