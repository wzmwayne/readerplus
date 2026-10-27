import 'dart:async';

import 'js_interpreter.dart';
import 'js_parser.dart';
import 'js_runtime.dart';

/// 异步求值器：与同步版语义一致，但宿主函数可返回 Future，
/// 解释器**透明等待**（脚本里仍写 `var r = http.get(url)`）。
///
/// 存在意义：网络（http）与询问（ask）本质是 Future；同步求值器无法表达。
class AsyncInterpreter {
  AsyncInterpreter({Map<String, Object?>? globals}) {
    _globals = Scope(null);
    installBuiltins(_globals);
    globals?.forEach((key, value) => _globals.declare(key, value));
  }

  late final Scope _globals;

  Scope get globals => _globals;

  Future<Object?> run(String source) async {
    final program = JsParser.parse(source).parseProgram();
    return execBlock(program, _globals);
  }

  Future<Object?> execBlock(List<JsStmt> body, Scope scope) async {
    Object? last = JsUndefined.instance;
    for (final stmt in body) {
      last = await exec(stmt, scope);
    }
    return last;
  }

  Future<Object?> exec(JsStmt stmt, Scope scope) async {
    if (stmt is Block) return execBlock(stmt.body, Scope(scope));
    if (stmt is EmptyStmt) return JsUndefined.instance;
    if (stmt is VarDecl) {
      final value =
          stmt.init == null ? JsUndefined.instance : await eval(stmt.init!, scope);
      scope.declare(stmt.name, value);
      return value;
    }
    if (stmt is FuncDecl) {
      final fn = _AsyncFunction(stmt.params, stmt.body, scope, name: stmt.name);
      scope.declare(stmt.name, fn);
      return fn;
    }
    if (stmt is ExprStmt) return eval(stmt.expr, scope);
    if (stmt is IfStmt) {
      if (truthy(await eval(stmt.test, scope))) {
        return exec(stmt.consequent, scope);
      }
      final alternate = stmt.alternate;
      if (alternate != null) return exec(alternate, scope);
      return JsUndefined.instance;
    }
    if (stmt is WhileStmt) {
      Object? last = JsUndefined.instance;
      while (truthy(await eval(stmt.test, scope))) {
        try {
          last = await exec(stmt.body, scope);
        } on JsBreak {
          break;
        } on JsContinue {
          continue;
        }
      }
      return last;
    }
    if (stmt is DoWhileStmt) {
      Object? last = JsUndefined.instance;
      do {
        try {
          last = await exec(stmt.body, scope);
        } on JsBreak {
          break;
        } on JsContinue {
          continue;
        }
      } while (truthy(await eval(stmt.test, scope)));
      return last;
    }
    if (stmt is ForStmt) {
      final loopScope = Scope(scope);
      final init = stmt.init;
      if (init != null) await exec(init, loopScope);
      Object? last = JsUndefined.instance;
      while (stmt.test == null || truthy(await eval(stmt.test!, loopScope))) {
        try {
          last = await exec(stmt.body, loopScope);
        } on JsBreak {
          break;
        } on JsContinue {
          // 继续执行 update
        }
        final update = stmt.update;
        if (update != null) await eval(update, loopScope);
      }
      return last;
    }
    if (stmt is ForInStmt) {
      final iterable = await eval(stmt.iterable, scope);
      final items = <Object?>[];
      if (stmt.mode == 'in') {
        if (iterable is Map) {
          items.addAll(iterable.keys);
        } else if (iterable is List) {
          for (var i = 0; i < iterable.length; i++) {
            items.add('$i');
          }
        }
      } else {
        if (iterable is List) items.addAll(iterable);
        if (iterable is String) items.addAll(iterable.split(''));
        if (iterable is Map) items.addAll(iterable.values);
      }
      Object? last = JsUndefined.instance;
      for (final item in items) {
        final loopScope = Scope(scope);
        loopScope.declare(stmt.name, item);
        try {
          last = await exec(stmt.body, loopScope);
        } on JsBreak {
          break;
        } on JsContinue {
          continue;
        }
      }
      return last;
    }
    if (stmt is ReturnStmt) {
      throw JsReturn(stmt.value == null ? JsUndefined.instance : await eval(stmt.value!, scope));
    }
    if (stmt is BreakStmt) throw const JsBreak();
    if (stmt is ContinueStmt) throw const JsContinue();
    if (stmt is ThrowStmt) {
      throw JsRuntimeError(toStringJs(await eval(stmt.value, scope)));
    }
    if (stmt is TryStmt) {
      try {
        return await exec(stmt.body, scope);
      } catch (e) {
        final handler = stmt.catchBody;
        if (handler == null) rethrow;
        final catchScope = Scope(scope);
        final name = stmt.catchName;
        if (name != null) catchScope.declare(name, '$e');
        return exec(handler, catchScope);
      } finally {
        final fin = stmt.finallyBody;
        if (fin != null) await exec(fin, scope);
      }
    }
    throw JsRuntimeError('未知语句：$stmt');
  }

  Future<Object?> eval(JsNode node, Scope scope) async {
    if (node is NumLit) return node.value;
    if (node is StrLit) return node.value;
    if (node is BoolLit) return node.value;
    if (node is NullLit) return null;
    if (node is UndefinedLit) return JsUndefined.instance;
    if (node is Ident) {
      if (node.name == 'undefined') return JsUndefined.instance;
      return scope.get(node.name);
    }
    if (node is ArrayLit) {
      final out = <Object?>[];
      for (final item in node.items) {
        out.add(await eval(item, scope));
      }
      return out;
    }
    if (node is ObjectLit) {
      final map = <String, Object?>{};
      for (final entry in node.entries) {
        map[entry.key] = await eval(entry.value, scope);
      }
      return map;
    }
    if (node is Member) return getMember(await eval(node.target, scope), node.name);
    if (node is Index) {
      final target = await eval(node.target, scope);
      final index = await eval(node.index, scope);
      return getIndex(target, index);
    }
    if (node is Call) {
      final callee = await eval(node.callee, scope);
      final args = <Object?>[];
      for (final arg in node.args) {
        args.add(await eval(arg, scope));
      }
      return await callValue(callee, args);
    }
    if (node is NewExpr) {
      final callee = await eval(node.callee, scope);
      final args = <Object?>[];
      for (final arg in node.args) {
        args.add(await eval(arg, scope));
      }
      return await callValue(callee, args);
    }
    if (node is Unary) {
      final value = await eval(node.operand, scope);
      switch (node.op) {
        case '!':
          return !truthy(value);
        case '-':
          return -toNumber(value);
        case '+':
          return toNumber(value);
        case 'typeof':
          return jsTypeOf(value);
      }
    }
    if (node is Update) {
      final oldValue = await eval(node.target, scope);
      final next = toNumber(oldValue) + (node.op == '++' ? 1 : -1);
      await assignTo(node.target, next, scope);
      return node.prefix ? next : toNumber(oldValue);
    }
    if (node is Binary) {
      if (node.logical) {
        final left = await eval(node.left, scope);
        if (node.op == '&&') {
          return truthy(left) ? eval(node.right, scope) : left;
        }
        return truthy(left) ? left : eval(node.right, scope);
      }
      final left = await eval(node.left, scope);
      final right = await eval(node.right, scope);
      return binaryOp(node.op, left, right);
    }
    if (node is Conditional) {
      return truthy(await eval(node.test, scope))
          ? eval(node.consequent, scope)
          : eval(node.alternate, scope);
    }
    if (node is Assign) {
      var value = await eval(node.value, scope);
      if (node.op != '=') {
        final current = await eval(node.target, scope);
        value = binaryOp(node.op.substring(0, 1), current, value);
      }
      await assignTo(node.target, value, scope);
      return value;
    }
    if (node is FuncExpr) {
      return _AsyncFunction(node.params, node.body, scope, name: node.name);
    }
    throw JsRuntimeError('未知表达式：$node');
  }

  /// 调用值：原生的 Future 结果会被透明等待。
  Future<Object?> callValue(Object? callee, List<Object?> args) async {
    if (callee is _AsyncFunction) return callee.call(this, args);
    if (callee is JsFunction) {
      final native = callee.native;
      if (native == null) {
        throw JsRuntimeError('异步求值不支持同步闭包函数：${callee.name ?? ''}');
      }
      return maybeAwait(native(args));
    }
    throw JsRuntimeError('不可调用的值：${toStringJs(callee)}');
  }

  Future<Object?> assignTo(JsNode target, Object? value, Scope scope) async {
    if (target is Ident) {
      scope.set(target.name, value);
      return null;
    }
    if (target is Member) {
      final object = await eval(target.target, scope);
      if (object is Map) {
        object[target.name] = value;
        return null;
      }
      throw JsRuntimeError('无法给 ${toStringJs(object)} 的属性赋值');
    }
    if (target is Index) {
      final object = await eval(target.target, scope);
      final index = await eval(target.index, scope);
      if (object is Map) {
        object[toStringJs(index)] = value;
        return null;
      }
      if (object is List && index is num) {
        final i = index.toInt();
        while (object.length <= i) {
          object.add(JsUndefined.instance);
        }
        object[i] = value;
        return null;
      }
      throw JsRuntimeError('无法按索引赋值');
    }
    throw JsRuntimeError('非法的赋值目标');
  }
}

/// 异步语义的宿主兜底：Future 值自动等待。
Future<Object?> maybeAwait(Object? value) async {
  if (value is Future) return await value;
  return value;
}

class _AsyncFunction {
  _AsyncFunction(this.params, this.body, this.closure, {this.name});

  final List<String> params;
  final List<JsStmt> body;
  final Scope closure;
  final String? name;

  Future<Object?> call(AsyncInterpreter interp, List<Object?> args) async {
    final scope = Scope(closure);
    for (var i = 0; i < params.length; i++) {
      scope.declare(params[i], i < args.length ? args[i] : JsUndefined.instance);
    }
    final self = name;
    if (self != null) scope.declare(self, this);
    try {
      await interp.execBlock(body, scope);
    } on JsReturn catch (ret) {
      return ret.value;
    }
    return JsUndefined.instance;
  }
}