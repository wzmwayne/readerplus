import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/js/js_async_interpreter.dart';
import 'package:reader/services/script/js/js_interpreter.dart';
import 'package:reader/services/script/js/js_runtime.dart';

JsFunction fn(Object? Function(List<Object?> args) body) =>
    JsFunction(const [], null, Scope(null), native: body);

Future<String> runAsync(String source, [Map<String, Object?>? globals]) async {
  final interp = AsyncInterpreter(globals: globals);
  return toStringJs(await interp.run(source));
}

void main() {
  test('同步逻辑与同步求值器结果一致', () async {
    expect(await runAsync('1 + 2 * 3'), '7');
    expect(await runAsync('function f(n) { if (n <= 1) { return 1 } return n * f(n-1) } f(5)'),
        '120');
    expect(await runAsync('var s = 0; for (var i = 0; i < 4; i++) { s += i } s'), '6');
  });

  test('宿主 Future 被透明等待（脚本写法不变）', () async {
    final out = await runAsync(
      'var r = fetch("u"); r.body',
      {
        'fetch': fn((args) => Future.value({'body': 'got ${toStringJs(args.first)}'})),
      },
    );
    expect(out, 'got u');
  });

  test('循环里多次 await 宿主调用', () async {
    final out = await runAsync(
      'var total = ""; for (var i = 0; i < 3; i++) { total += fetch(i) } total',
      {
        'fetch': fn((args) => Future.value('<${toStringJs(args.first)}>')),
      },
    );
    expect(out, '<0><1><2>');
  });

  test('try/catch 能捕获宿主 Future 的异常', () async {
    final out = await runAsync(
      'var r = ""; try { boom() } catch (e) { r = "caught" } r',
      {
        'boom': fn((_) => Future.error(const JsRuntimeError('网络失败'))),
      },
    );
    expect(out, 'caught');
  });
}