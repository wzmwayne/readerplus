import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/js/js_interpreter.dart';
import 'package:reader/services/script/js/js_lexer.dart';
import 'package:reader/services/script/js/js_parser.dart';
import 'package:reader/services/script/js/js_runtime.dart';

String run(String source, {Map<String, Object?>? globals}) {
  final interp = Interpreter(globals: globals);
  return toStringJs(interp.run(source));
}

void main() {
  test('词法：数字/字符串/标识符/注释', () {
    final tokens = Lexer('var a = 1 // 注释\n"x" + \'y\'').tokenize();
    expect(tokens.first.text, 'var');
    expect(tokens.where((t) => t.kind == TokKind.number).length, 1);
    expect(tokens.where((t) => t.kind == TokKind.string).length, 2);
  });

  test('语法：缺少右括号报错并带行列', () {
    expect(() => JsParser.parse('if (a { }').parseProgram(),
        throwsA(isA<JsSyntaxError>()));
  });

  test('表达式与控制流', () {
    expect(run('1 + 2 * 3'), '7');
    expect(run('var a = 1; if (a > 0) { a = 5 } else { a = 6 } a'), '5');
    expect(run('var s = 0; for (var i = 1; i <= 4; i++) { s += i } s'), '10');
    expect(run('var s = 0; var i = 0; while (i < 3) { s += i; i++ } s'), '3');
    expect(run('var n = 0; for (var x of [1,2,3]) { n += x } n'), '6');
    expect(run('var t = 0; for (var k in {a:1,b:2}) { t++ } t'), '2');
  });

  test('函数：声明、递归、闭包', () {
    expect(run('function add(a, b) { return a + b } add(2, 3)'), '5');
    expect(run('function f(n) { if (n <= 1) { return 1 } return n * f(n - 1) } f(5)'), '120');
    expect(run('function mk() { var c = 0; return function () { c += 1; return c } } var g = mk(); g(); g()'), '2');
  });

  test('字符串与数组方法', () {
    expect(run('"a,b,c".split(",").length'), '3');
    expect(run('" x ".trim()'), 'x');
    expect(run('[1,2,3].join("-")'), '1-2-3');
    expect(run('var a = []; a.push(1); a.push(2); a.length'), '2');
  });

  test('JSON / Math / Object.keys', () {
    expect(run('JSON.parse(\'{"a":1}\').a'), '1');
    expect(run('JSON.stringify({a:1})'), '{"a":1}');
    expect(run('Math.floor(3.7)'), '3');
    expect(run('Object.keys({a:1,b:2}).length'), '2');
  });

  test('try/catch 捕获运行时错误', () {
    expect(run('var r = ""; try { undefinedFn() } catch (e) { r = "caught" } r'), 'caught');
  });

  test('宿主函数可注入', () {
    expect(
      run('log("hi") + store.get("k")', globals: {
        'log': JsFunction(const [], null, Scope(null),
            name: 'log', native: (args) => 'logged'),
        'store': <String, Object?>{
          'get': JsFunction(const [], null, Scope(null),
              name: 'get', native: (args) => 'v:${args.first}'),
        },
      }),
      'loggedv:k',
    );
  });

  test('不支持语法明确报错（class / import）', () {
    expect(() => JsParser.parse('class A {}').parseProgram(),
        throwsA(isA<JsSyntaxError>()));
    expect(() => JsParser.parse('import x from "y"').parseProgram(),
        throwsA(anyOf(isA<JsSyntaxError>(), isA<TypeError>())));
  });
}