import 'dart:convert';
import 'dart:math' as math;

import 'js_interpreter.dart';

/// JS 语义辅助：真值、数值/字符串转换、运算符、成员访问、内建对象。

bool truthy(Object? value) {
  if (value == null) return false;
  if (identical(value, JsUndefined.instance)) return false;
  if (value is bool) return value;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty;
  return true;
}

num toNumber(Object? value) {
  if (value == null || identical(value, JsUndefined.instance)) return 0;
  if (value is num) return value;
  if (value is bool) return value ? 1 : 0;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    return num.tryParse(trimmed) ?? double.nan;
  }
  return double.nan;
}

String toStringJs(Object? value) {
  if (value == null) return 'null';
  if (identical(value, JsUndefined.instance)) return 'undefined';
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) {
    if (value is int) return '$value';
    if (value == value.truncateToDouble() && value.isFinite) {
      return '${value.toInt()}';
    }
    return '$value';
  }
  if (value is List) {
    return value.map(_joinItem).join(',');
  }
  if (value is Map) {
    return '[object Object]';
  }
  if (value is JsFunction) return 'function ${value.name ?? ''}'.trim();
  return '$value';
}

String _joinItem(Object? item) {
  if (item == null) return '';
  if (identical(item, JsUndefined.instance)) return '';
  return toStringJs(item);
}

String jsTypeOf(Object? value) {
  if (identical(value, JsUndefined.instance)) return 'undefined';
  if (value == null) return 'object';
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  if (value is String) return 'string';
  if (value is JsFunction) return 'function';
  return 'object';
}

bool looseEquals(Object? left, Object? right) {
  if (left == null && identical(right, JsUndefined.instance)) return true;
  if (right == null && identical(left, JsUndefined.instance)) return true;
  if (left is num && right is String) return left == toNumber(right);
  if (right is num && left is String) return toNumber(left) == right;
  if (left is num && right is num) return left == right;
  if (left is bool || right is bool) return toNumber(left) == toNumber(right);
  return identical(left, right) || left == right;
}

Object? binaryOp(String op, Object? left, Object? right) {
  switch (op) {
    case '+':
      if (left is String || right is String) {
        return toStringJs(left) + toStringJs(right);
      }
      if (left is num && right is num) return left + right;
      if (left is List && right is List) return [...left, ...right];
      return toNumber(left) + toNumber(right);
    case '-':
      return toNumber(left) - toNumber(right);
    case '*':
      return toNumber(left) * toNumber(right);
    case '/':
      final divisor = toNumber(right);
      if (divisor == 0) {
        final dividend = toNumber(left);
        if (dividend == 0) return double.nan;
        return dividend > 0 ? double.infinity : double.negativeInfinity;
      }
      return toNumber(left) / divisor;
    case '%':
      return toNumber(left) % toNumber(right);
    case '<':
      return _compare(left, right) < 0;
    case '>':
      return _compare(left, right) > 0;
    case '<=':
      return _compare(left, right) <= 0;
    case '>=':
      return _compare(left, right) >= 0;
    case '===':
      return _strictEquals(left, right);
    case '!==':
      return !_strictEquals(left, right);
    case '==':
      return looseEquals(left, right);
    case '!=':
      return !looseEquals(left, right);
  }
  throw JsRuntimeError('不支持的运算符：$op');
}

int _compare(Object? left, Object? right) {
  if (left is String && right is String) return left.compareTo(right);
  final a = toNumber(left);
  final b = toNumber(right);
  if (a.isNaN) return 1;
  if (b.isNaN) return -1;
  return a.compareTo(b);
}

bool _strictEquals(Object? left, Object? right) {
  if (identical(left, JsUndefined.instance) && identical(right, JsUndefined.instance)) {
    return true;
  }
  if (left == null || right == null) return identical(left, right);
  if (left is num && right is num) return left == right;
  return left == right;
}

Object? getIndex(Object? target, Object? index) {
  if (target is List) {
    if (index == 'length') return target.length;
    final i = toNumber(index).toInt();
    if (i < 0 || i >= target.length) return JsUndefined.instance;
    return target[i];
  }
  if (target is String) {
    if (index == 'length') return target.length;
    final i = toNumber(index).toInt();
    if (i < 0 || i >= target.length) return JsUndefined.instance;
    return target[i];
  }
  if (target is Map) {
    return target[toStringJs(index)] ?? JsUndefined.instance;
  }
  return JsUndefined.instance;
}

JsFunction _native(String name, Object? Function(List<Object?> args) fn) =>
    JsFunction(const [], null, Scope(null), name: name, native: fn);

Object? getMember(Object? target, String name) {
  if (target == null || identical(target, JsUndefined.instance)) {
    throw JsRuntimeError('读取了 null/undefined 的属性：$name');
  }
  if (target is String) return _stringMember(target, name);
  if (target is List) return _listMember(target, name);
  if (target is Map) {
    if (target.containsKey(name)) return target[name];
    return JsUndefined.instance;
  }
  throw JsRuntimeError('无法读取 ${jsTypeOf(target)} 的属性：$name');
}

Object? _stringMember(String target, String name) {
  switch (name) {
    case 'length':
      return target.length;
    case 'split':
      return _native('split', (args) {
        final sep = args.isEmpty ? '' : toStringJs(args.first);
        if (sep.isEmpty) return target.split('');
        return target.split(sep);
      });
    case 'replace':
      return _native('replace', (args) {
        final from = args.isEmpty ? '' : toStringJs(args[0]);
        final to = args.length > 1 ? toStringJs(args[1]) : '';
        return target.replaceFirst(from, to);
      });
    case 'trim':
      return _native('trim', (_) => target.trim());
    case 'toUpperCase':
      return _native('toUpperCase', (_) => target.toUpperCase());
    case 'toLowerCase':
      return _native('toLowerCase', (_) => target.toLowerCase());
    case 'indexOf':
      return _native('indexOf', (args) =>
          target.indexOf(args.isEmpty ? '' : toStringJs(args[0])));
    case 'substring':
      return _native('substring', (args) {
        final start = args.isEmpty ? 0 : toNumber(args[0]).toInt();
        final end = args.length > 1 ? toNumber(args[1]).toInt() : target.length;
        final a = start.clamp(0, target.length);
        final b = end.clamp(0, target.length);
        return a <= b ? target.substring(a, b) : target.substring(b, a);
      });
    case 'slice':
      return _native('slice', (args) {
        final start = args.isEmpty ? 0 : toNumber(args[0]).toInt();
        final end = args.length > 1 ? toNumber(args[1]).toInt() : target.length;
        final a = (start < 0 ? target.length + start : start).clamp(0, target.length);
        final b = (end < 0 ? target.length + end : end).clamp(0, target.length);
        return a >= b ? '' : target.substring(a, b);
      });
    case 'startsWith':
      return _native('startsWith', (args) =>
          target.startsWith(args.isEmpty ? '' : toStringJs(args[0])));
    case 'endsWith':
      return _native('endsWith', (args) =>
          target.endsWith(args.isEmpty ? '' : toStringJs(args[0])));
    case 'includes':
      return _native('includes', (args) =>
          target.contains(args.isEmpty ? '' : toStringJs(args[0])));
    case 'charAt':
      return _native('charAt', (args) {
        final i = args.isEmpty ? 0 : toNumber(args[0]).toInt();
        if (i < 0 || i >= target.length) return '';
        return target[i];
      });
    case 'repeat':
      return _native('repeat', (args) {
        final count = args.isEmpty ? 1 : toNumber(args[0]).toInt();
        return target * (count < 0 ? 0 : count);
      });
  }
  throw JsRuntimeError('字符串不支持方法：$name');
}

Object? _listMember(List<Object?> target, String name) {
  switch (name) {
    case 'length':
      return target.length;
    case 'push':
      return _native('push', (args) {
        target.addAll(args);
        return target.length;
      });
    case 'pop':
      return _native('pop', (_) => target.isEmpty ? JsUndefined.instance : target.removeLast());
    case 'shift':
      return _native('shift', (_) => target.isEmpty ? JsUndefined.instance : target.removeAt(0));
    case 'unshift':
      return _native('unshift', (args) {
        target.insertAll(0, args);
        return target.length;
      });
    case 'join':
      return _native('join', (args) {
        final sep = args.isEmpty ? ',' : toStringJs(args.first);
        return target.map(toStringJs).join(sep);
      });
    case 'indexOf':
      return _native('indexOf', (args) {
        if (args.isEmpty) return -1;
        return target.indexWhere((item) => _strictEquals(item, args.first));
      });
    case 'includes':
      return _native('includes', (args) {
        if (args.isEmpty) return false;
        return target.any((item) => _strictEquals(item, args.first));
      });
    case 'slice':
      return _native('slice', (args) {
        final start = args.isEmpty ? 0 : toNumber(args[0]).toInt();
        final end = args.length > 1 ? toNumber(args[1]).toInt() : target.length;
        final a = (start < 0 ? target.length + start : start).clamp(0, target.length);
        final b = (end < 0 ? target.length + end : end).clamp(0, target.length);
        return a >= b ? <Object?>[] : target.sublist(a, b);
      });
    case 'reverse':
      return _native('reverse', (_) {
        final copy = target.reversed.toList();
        target
          ..clear()
          ..addAll(copy);
        return target;
      });
  }
  throw JsRuntimeError('数组不支持方法：$name');
}

/// 安装内建对象（JSON / Math / parseInt / String / Number / Array / Object）。
void installBuiltins(Scope scope) {
  scope.declare(
    'JSON',
    <String, Object?>{
      'parse': _native('parse', (args) {
        if (args.isEmpty) throw const JsRuntimeError('JSON.parse 需要字符串');
        return jsonDecode(toStringJs(args.first));
      }),
      'stringify': _native('stringify', (args) {
        if (args.isEmpty) return 'undefined';
        return jsonEncode(args.first);
      }),
    },
  );
  scope.declare(
    'Math',
    <String, Object?>{
      'floor': _native('floor', (args) =>
          args.isEmpty ? 0 : toNumber(args.first).floor()),
      'ceil': _native('ceil', (args) =>
          args.isEmpty ? 0 : toNumber(args.first).ceil()),
      'round': _native('round', (args) =>
          args.isEmpty ? 0 : toNumber(args.first).round()),
      'abs': _native('abs', (args) =>
          args.isEmpty ? 0 : toNumber(args.first).abs()),
      'max': _native('max', (args) {
        if (args.isEmpty) return double.negativeInfinity;
        var best = toNumber(args.first);
        for (final arg in args.skip(1)) {
          final value = toNumber(arg);
          if (value > best) best = value;
        }
        return best;
      }),
      'min': _native('min', (args) {
        if (args.isEmpty) return double.infinity;
        var best = toNumber(args.first);
        for (final arg in args.skip(1)) {
          final value = toNumber(arg);
          if (value < best) best = value;
        }
        return best;
      }),
      'random': _native('random', (_) => math.Random().nextDouble()),
      'pow': _native('pow', (args) => args.length < 2
          ? 0
          : math.pow(toNumber(args[0]), toNumber(args[1]))),
      'PI': math.pi,
      'E': math.e,
    },
  );
  scope.declare('parseInt',
      _native('parseInt', (args) => toNumber(args.isEmpty ? '' : args.first).toInt()));
  scope.declare('parseFloat',
      _native('parseFloat', (args) => toNumber(args.isEmpty ? '' : args.first)));
  scope.declare('String',
      _native('String', (args) => toStringJs(args.isEmpty ? '' : args.first)));
  scope.declare('Number', _native('Number', (args) => toNumber(args.isEmpty ? 0 : args.first)));
  scope.declare('Boolean',
      _native('Boolean', (args) => truthy(args.isEmpty ? null : args.first)));
  scope.declare('isNaN', _native('isNaN', (args) =>
      args.isEmpty ? true : toNumber(args.first).isNaN));
  scope.declare('Object', <String, Object?>{
    'keys': _native('keys', (args) {
      final value = args.isEmpty ? null : args.first;
      if (value is Map) return value.keys.toList();
      if (value is List) return [for (var i = 0; i < value.length; i++) '$i'];
      return <Object?>[];
    }),
    'values': _native('values', (args) {
      final value = args.isEmpty ? null : args.first;
      if (value is Map) return value.values.toList();
      return <Object?>[];
    }),
  });
  scope.declare('Array', <String, Object?>{
    'isArray': _native('isArray', (args) =>
        args.isNotEmpty && args.first is List),
  });
}