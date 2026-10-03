import 'dart:async';
import 'dart:isolate';

import 'package:hetu_script/hetu_script.dart';

import 'script_host.dart';
import 'script_runner.dart';

/// Hetu 脚本引擎：把宿主能力以白名单函数绑定给脚本，并在 isolate 内执行。
///
/// 脚本可用的能力（全部由宿主提供，脚本无法绕过）：
///   log(msg)                        写日志（实时回传界面）
///   result(value)                   交回结果（最后一次生效）
///   httpGet(url, headers?)          简单请求
///   httpPost(url, body?, headers?, contentType?)  简单请求
///   httpRequest(options)            高自由度请求（方法/多值头/原头/字节体/cookie/
///                                   重定向/代理/超时/证书策略）
///   decode(bytes, encoding?)        解码（UTF-8/GBK/…）
///   regexp(pattern, input, group?)  正则首个匹配
///   regexpAll(pattern, input, group?) 正则全部匹配
///   urlJoin(base, relative) / urlEncode(value)
class HetuScriptEngine {
  HetuScriptEngine._();

  /// 供 [ScriptRunner] 使用的 isolate 内入口（静态，可跨 isolate 传递）。
  static void isolateEntry(String source, SendPort send) async {
    final host = ScriptHost(onLog: (message) => send.send(message));
    Hetu? hetu;
    _hetu = null;
    try {
      final functions = <String, Function>{
        'log': ({positionalArgs, namedArgs}) {
          host.log(positionalArgs.isEmpty ? '' : positionalArgs.first);
          return null;
        },
        'result': ({positionalArgs, namedArgs}) {
          host.setResult(positionalArgs.isEmpty ? null : positionalArgs.first);
          return null;
        },
        'httpGet': ({positionalArgs, namedArgs}) => host
            .httpGet(
              '${positionalArgs.first}',
              headers: _stringMap(namedArgs['headers']),
            )
            .then(_asStruct),
        'httpPost': ({positionalArgs, namedArgs}) => host
            .httpPost(
              '${positionalArgs.first}',
              body:
                  namedArgs['body'] ??
                  (positionalArgs.length > 1 ? positionalArgs[1] : null),
              contentType: namedArgs['contentType']?.toString(),
              headers: _stringMap(namedArgs['headers']),
            )
            .then(_asStruct),
        'httpRequest': ({positionalArgs, namedArgs}) => host
            .httpRequest(
              Map<String, dynamic>.from(
                (positionalArgs.isEmpty ? namedArgs : positionalArgs.first)
                    as Map,
              ),
            )
            .then(_asStruct),
        'decode': ({positionalArgs, namedArgs}) => host.decodeText(
          (positionalArgs.first as List).map((e) => e as int).toList(),
          positionalArgs.length > 1 ? '${positionalArgs[1]}' : 'auto',
        ),
        'regexp': ({positionalArgs, namedArgs}) => host.regExp(
          '${positionalArgs[0]}',
          '${positionalArgs[1]}',
          positionalArgs.length > 2 ? '${positionalArgs[2]}' : '0',
        ),
        'regexpAll': ({positionalArgs, namedArgs}) => host.regExpAll(
          '${positionalArgs[0]}',
          '${positionalArgs[1]}',
          positionalArgs.length > 2 ? '${positionalArgs[2]}' : '0',
        ),
        'urlJoin': ({positionalArgs, namedArgs}) =>
            host.urlJoin('${positionalArgs[0]}', '${positionalArgs[1]}'),
        'urlEncode': ({positionalArgs, namedArgs}) =>
            host.urlEncode('${positionalArgs.first}'),
      };
      hetu = Hetu();
      _hetu = hetu;
      // 官方用法：init(externalFunctions: ...) 注册；脚本侧还必须声明
      // `external function <名字>` 才能按名字调用，因此这里把声明自动前置，
      // 让插件作者不必手写（对作者透明）。
      hetu.init(externalFunctions: functions);
      final preamble = functions.keys
          .map((name) => 'external function $name')
          .join('\n');
      final evaluated = hetu.eval(
        '$preamble\n$source',
        filename: 'plugin.ht',
      );
      // Hetu 的异步惯例是 .then(...)：eval 返回时回调可能尚未执行，
      // 因此这里等待结果被交回（脚本同步 result() 则立即返回）。
      Object? result = host.result ?? evaluated;
      if (host.result == null) {
        try {
          result = await host.waitResult().timeout(
            const Duration(seconds: 120),
          );
        } catch (_) {
          result ??= evaluated;
        }
      }
      send.send({
        'ok': true,
        'result': _toSendable(result),
        'error': '',
      });
    } on HTError catch (error) {
      send.send({'ok': false, 'error': '${error.message ?? error}'});
    } catch (error, stack) {
      send.send({'ok': false, 'error': '$error\n$stack'});
    } finally {
      // isolate 结束即释放，无需显式关闭
    }
  }

  static Hetu? _hetu;

  /// 把宿主返回的 Dart Map 转成 Hetu 结构体，脚本即可自然用 `.field` 取值。
  static Object? _asStruct(Object? value) {
    final hetu = _hetu;
    if (hetu == null || value is! Map) return value;
    try {
      return hetu.interpreter.createStructfromJSON(
        value.map((k, v) => MapEntry('$k', v)),
      );
    } catch (_) {
      return value;
    }
  }

  static Map<String, String>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry('$key', '$item'));
  }

  /// 结果需可跨 isolate 传递：Hetu 结构体用其自带 toJSON() 转成 JSON 友好值。
  static Object? _toSendable(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is HTStruct) {
      // 递归转换（HTStruct.toJSON() 遇到嵌套结构体可能抛异常，故自己走 keys/values）
      final map = <String, Object?>{};
      for (final key in value.keys) {
        map['$key'] = _toSendable(value[key]);
      }
      return map;
    }
    if (value is List) return value.map(_toSendable).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry('$k', _toSendable(v)));
    }
    return value.toString();
  }
}
