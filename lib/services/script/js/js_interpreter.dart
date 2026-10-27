import 'js_parser.dart';
import 'js_runtime.dart';

/// JS 的 undefined（与 Dart 的 null 区分：null 表示 JS 的 null）。
class JsUndefined {
  const JsUndefined._();
  static const JsUndefined instance = JsUndefined._();
  @override
  String toString() => 'undefined';
}

class JsBreak implements Exception {
  const JsBreak();
}

class JsContinue implements Exception {
  const JsContinue();
}

class JsReturn implements Exception {
  const JsReturn(this.value);
  final Object? value;
}

/// 脚本抛出的运行时错误（可被 try/catch 捕获）。
class JsRuntimeError implements Exception {
  const JsRuntimeError(this.message);
  final String message;
  @override
  String toString() => message;
}

class JsReturnArrow<T> {
  const JsReturnArrow();
}

/// 原生函数：参数已求值。
typedef JsNativeFn = Object? Function(List<Object?> args);

class JsFunction {
  JsFunction(this.params, this.body, this.closure, {this.name, this.native});

  final List<String> params;
  final List<JsStmt>? body;
  final Scope closure;
  final String? name;
  final JsNativeFn? native;

  Object? call(Interpreter interp, List<Object?> args) {
    final fn = native;
    if (fn != null) return fn(args);
    final scope = Scope(closure);
    for (var i = 0; i < params.length; i++) {
      scope.declare(params[i], i < args.length ? args[i] : JsUndefined.instance);
    }
    if (name != null) scope.declare(name!, this);
    try {
      interp.execBlock(body!, scope);
    } on JsReturn catch (ret) {
      return ret.value;
    }
    return JsUndefined.instance;
  }
}

class Scope {
  Scope(this.parent);
  final Scope? parent;
  final Map<String, Object?> _vars = {};

  void declare(String name, Object? value) {
    _vars[name] = value;
  }

  bool has(String name) => _vars.containsKey(name);

  Object? get(String name) {
    Scope? scope = this;
    while (scope != null) {
      if (scope._vars.containsKey(name)) return scope._vars[name];
      scope = scope.parent;
    }
    throw JsRuntimeError('变量未定义：$name');
  }

  void set(String name, Object? value) {
    Scope? scope = this;
    while (scope != null) {
      if (scope._vars.containsKey(name)) {
        scope._vars[name] = value;
        return;
      }
      scope = scope.parent;
    }
    _vars[name] = value;
  }

  Map<String, Object?> get ownVars => _vars;
}

class Interpreter {
  Interpreter({Map<String, Object?>? globals}) {
    _globals = Scope(null);
    installBuiltins(_globals);
    globals?.forEach((key, value) => _globals.declare(key, value));
  }

  late final Scope _globals;

  Scope get globals => _globals;

  /// 执行源码，返回最后一个表达式的值（若有）。
  Object? run(String source) {
    final program = JsParser.parse(source).parseProgram();
    return execBlock(program, _globals);
  }

  Object? execBlock(List<JsStmt> body, Scope scope) {
    Object? last = JsUndefined.instance;
    for (final stmt in body) {
      last = exec(stmt, scope);
    }
    return last;
  }

  Object? exec(JsStmt stmt, Scope scope) {
    if (stmt is Block) {
      return execBlock(stmt.body, Scope(scope));
    }
    if (stmt is EmptyStmt) return JsUndefined.instance;
    if (stmt is VarDecl) {
      final value = stmt.init == null ? JsUndefined.instance : eval(stmt.init!, scope);
      scope.declare(stmt.name, value);
      return value;
    }
    if (stmt is FuncDecl) {
      final fn = JsFunction(stmt.params, stmt.body, scope, name: stmt.name);
      scope.declare(stmt.name, fn);
      return fn;
    }
    if (stmt is ExprStmt) return eval(stmt.expr, scope);
    if (stmt is IfStmt) {
      if (truthy(eval(stmt.test, scope))) {
        return exec(stmt.consequent, scope);
      }
      final alternate = stmt.alternate;
      if (alternate != null) return exec(alternate, scope);
      return JsUndefined.instance;
    }
    if (stmt is WhileStmt) {
      Object? last = JsUndefined.instance;
      while (truthy(eval(stmt.test, scope))) {
        try {
          last = exec(stmt.body, scope);
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
          last = exec(stmt.body, scope);
        } on JsBreak {
          break;
        } on JsContinue {
          continue;
        }
      } while (truthy(eval(stmt.test, scope)));
      return last;
    }
    if (stmt is ForStmt) {
      final loopScope = Scope(scope);
      final init = stmt.init;
      if (init != null) exec(init, loopScope);
      Object? last = JsUndefined.instance;
      while (stmt.test == null || truthy(eval(stmt.test!, loopScope))) {
        try {
          last = exec(stmt.body, loopScope);
        } on JsBreak {
          break;
        } on JsContinue {
          // 继续执行 update
        }
        final update = stmt.update;
        if (update != null) eval(update, loopScope);
      }
      return last;
    }
    if (stmt is ForInStmt) {
      final iterable = eval(stmt.iterable, scope);
      final items = <Object?>[];
      if (stmt.mode == 'in') {
        if (iterable is Map) {
          items.addAll(iterable.keys);
        } else if (iterable is List) {
          for (var i = 0; i < iterable.length; i++) {
            items.add('$i');
          }
        } else if (iterable is String) {
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
          last = exec(stmt.body, loopScope);
        } on JsBreak {
          break;
        } on JsContinue {
          continue;
        }
      }
      return last;
    }
    if (stmt is ReturnStmt) {
      throw JsReturn(stmt.value == null ? JsUndefined.instance : eval(stmt.value!, scope));
    }
    if (stmt is BreakStmt) throw const JsBreak();
    if (stmt is ContinueStmt) throw const JsContinue();
    if (stmt is ThrowStmt) {
      throw JsRuntimeError(toStringJs(eval(stmt.value, scope)));
    }
    if (stmt is TryStmt) {
      try {
        return exec(stmt.body, scope);
      } catch (e) {
        final handler = stmt.catchBody;
        if (handler == null) rethrow;
        final catchScope = Scope(scope);
        final name = stmt.catchName;
        if (name != null) catchScope.declare(name, '$e');
        return exec(handler, catchScope);
      } finally {
        final fin = stmt.finallyBody;
        if (fin != null) exec(fin, scope);
      }
    }
    throw JsRuntimeError('未知语句：$stmt');
  }

  Object? eval(JsNode node, Scope scope) {
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
      return [for (final item in node.items) eval(item, scope)];
    }
    if (node is ObjectLit) {
      final map = <String, Object?>{};
      for (final entry in node.entries) {
        map[entry.key] = eval(entry.value, scope);
      }
      return map;
    }
    if (node is Member) {
      return getMember(eval(node.target, scope), node.name);
    }
    if (node is Index) {
      final target = eval(node.target, scope);
      final index = eval(node.index, scope);
      return getIndex(target, index);
    }
    if (node is Call) {
      final callee = eval(node.callee, scope);
      final args = [for (final arg in node.args) eval(arg, scope)];
      final fn = callee;
      if (fn is JsFunction) return fn.call(this, args);
      throw JsRuntimeError('不可调用的值：${toStringJs(fn)}');
    }
    if (node is NewExpr) {
      final callee = eval(node.callee, scope);
      final args = [for (final arg in node.args) eval(arg, scope)];
      if (callee is JsFunction) return callee.call(this, args);
      throw JsRuntimeError('new 的目标不是函数');
    }
    if (node is Unary) {
      final value = eval(node.operand, scope);
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
      final oldValue = eval(node.target, scope);
      final next = toNumber(oldValue) + (node.op == '++' ? 1 : -1);
      assignTo(node.target, next, scope);
      return node.prefix ? next : toNumber(oldValue);
    }
    if (node is Binary) {
      if (node.logical) {
        final left = eval(node.left, scope);
        if (node.op == '&&') {
          return truthy(left) ? eval(node.right, scope) : left;
        }
        return truthy(left) ? left : eval(node.right, scope);
      }
      final left = eval(node.left, scope);
      final right = eval(node.right, scope);
      return binaryOp(node.op, left, right);
    }
    if (node is Conditional) {
      return truthy(eval(node.test, scope))
          ? eval(node.consequent, scope)
          : eval(node.alternate, scope);
    }
    if (node is Assign) {
      var value = eval(node.value, scope);
      if (node.op != '=') {
        final current = eval(node.target, scope);
        value = binaryOp(node.op.substring(0, 1), current, value);
      }
      assignTo(node.target, value, scope);
      return value;
    }
    if (node is FuncExpr) {
      final fn = JsFunction(node.params, node.body, scope, name: node.name);
      return fn;
    }
    throw JsRuntimeError('未知表达式：$node');
  }

  void assignTo(JsNode target, Object? value, Scope scope) {
    if (target is Ident) {
      scope.set(target.name, value);
      return;
    }
    if (target is Member) {
      final object = eval(target.target, scope);
      if (object is Map) {
        object[target.name] = value;
        return;
      }
      throw JsRuntimeError('无法给 ${toStringJs(object)} 的属性赋值');
    }
    if (target is Index) {
      final object = eval(target.target, scope);
      final index = eval(target.index, scope);
      if (object is Map) {
        object[toStringJs(index)] = value;
        return;
      }
      if (object is List && index is num) {
        final i = index.toInt();
        while (object.length <= i) {
          object.add(JsUndefined.instance);
        }
        object[i] = value;
        return;
      }
      throw JsRuntimeError('无法按索引赋值');
    }
    throw JsRuntimeError('非法的赋值目标');
  }
}