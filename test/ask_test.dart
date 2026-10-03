import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/hetu_engine.dart';
import 'package:reader/services/script/script_runner.dart';

/// 脚本提问（ask）：明文/秘密两种模式、.then 接续、无界面与次数上限的兜底。
void main() {
  ScriptRunner runner({
    void Function(String)? log,
    Future<AskReply> Function(AskRequest)? ask,
  }) => ScriptRunner(
    entry: HetuScriptEngine.isolateEntry,
    onLog: log,
    onAsk: ask,
  );

  test('明文询问：问题与回答都进日志，脚本用 .then 拿到答案', () async {
    final logs = <String>[];
    final result = await runner(
      log: logs.add,
      ask: (request) async {
        expect(request.secret, isFalse);
        expect(request.question, '取个名字');
        return const AskReply(ok: true, answer: '夜航船');
      },
    ).run('''
      ask('取个名字').then((reply) {
        var payload = {}
        payload['ok'] = reply['ok']
        payload['answer'] = reply['answer']
        result(payload)
      })
    ''');
    expect(result.ok, isTrue, reason: result.error);
    expect(
      (result.result as Map)['answer'],
      '夜航船',
      reason: '日志：${logs.join(' | ')}',
    );
    expect(logs.join('\n'), contains('询问：取个名字'));
    expect(logs.join('\n'), contains('回答：夜航船'));
  });

  test('秘密询问：输入遮挡由界面负责，回答绝不入日志', () async {
    final logs = <String>[];
    final result = await runner(
      log: logs.add,
      ask: (request) async {
        expect(request.secret, isTrue, reason: 'secret:true 应传给界面');
        expect(request.default_, '上一次的密钥', reason: '默认答案应传给界面用于预填');
        return const AskReply(ok: true, answer: 'sk-TOP-SECRET-123');
      },
    ).run('''
      ask('请输入 API Key', {'secret': true, 'default': '上一次的密钥'}).then((reply) {
        var payload = {}
        payload['ok'] = reply['ok']
        payload['answer'] = reply['answer']
        result(payload)
      })
    ''');
    expect(result.ok, isTrue, reason: result.error);
    expect((result.result as Map)['answer'], 'sk-TOP-SECRET-123');
    final text = logs.join('\n');
    expect(text, isNot(contains('sk-TOP-SECRET-123')), reason: '秘密回答不能进日志');
    expect(text, contains('询问（秘密，回答不入日志）'));
    expect(text, contains('17 字符'), reason: '只记录长度');
  });

  test('用户取消：脚本拿到 ok=false，自己决定怎么办', () async {
    final result = await runner(
      log: (_) {},
      ask: (request) async => const AskReply.cancelled(),
    ).run('''
      ask('要几章？').then((reply) {
        var payload = {}
        payload['ok'] = reply['ok']
        result(payload)
      })
    ''');
    expect(result.ok, isTrue, reason: result.error);
    expect((result.result as Map)['ok'], isFalse);
  });

  test('没有界面时立即返回 ok=false（脚本不会卡住）', () async {
    final logs = <String>[];
    final result = await runner(log: logs.add).run('''
      ask('谁会回答我？').then((reply) {
        var payload = {}
        payload['ok'] = reply['ok']
        result(payload)
      })
    ''');
    expect(result.ok, isTrue, reason: result.error);
    expect((result.result as Map)['ok'], isFalse);
    expect(logs.join('\n'), contains('没有可用的界面来提问'));
  });

  test('次数上限：超过 10 次按取消处理（防脚本狂弹框）', () async {
    var asked = 0;
    final result = await runner(
      log: (_) {},
      ask: (request) async {
        asked++;
        return const AskReply(ok: true, answer: 'x');
      },
    ).run('''
      var i = 0
      fun next() {
        if (i >= 12) {
          result({'asked': i})
        } else {
          i = i + 1
          ask("第 \${i} 次").then((reply) { next() })
        }
      }
      next()
    ''');
    expect(result.ok, isTrue, reason: result.error);
    expect(asked, 10, reason: '宿主最多问 10 次');
    expect((result.result as Map)['asked'], 12, reason: '脚本自己继续跑完');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
