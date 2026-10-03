import 'dart:io';
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
  static void isolateEntry(Map<String, Object?> job, SendPort send) async {
    final source = '${job['source'] ?? ''}';
    final inputs = ((job['inputs'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', (value as List).cast<int>()));
    final outputPath = job['outputDir']?.toString();
    final params = ((job['params'] as Map?) ?? const {})
        .map((key, value) => MapEntry('$key', '$value'));
    final host = ScriptHost(
      onLog: (message) => send.send(message),
      inputs: inputs,
      outputDir: (outputPath == null || outputPath.isEmpty)
          ? null
          : Directory(outputPath),
      params: params,
      // 提问往返：向主 isolate 发请求，等它把用户回答送到本 isolate 的临时端口
      askRelay: (question, secret, preset) async {
        final port = ReceivePort();
        send.send({
          'type': 'ask',
          'question': question,
          'secret': secret,
          'default': preset,
          'replyTo': port.sendPort,
        });
        try {
          final reply = await port.first.timeout(
            const Duration(minutes: 5),
            onTimeout: () => {'ok': false, 'answer': ''},
          );
          return reply is Map
              ? reply.map((key, value) => MapEntry('$key', value))
              : <String, Object?>{'ok': false, 'answer': ''};
        } finally {
          port.close();
        }
      },
    );
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
        // 脚本工作目录（沙箱）：可完全操控，但路径越界会被拒绝
        'sandboxDir': ({positionalArgs, namedArgs}) => host.sandboxDir(),
        'fileWrite': ({positionalArgs, namedArgs}) => host.fileWrite(
          '${positionalArgs[0]}',
          (positionalArgs[1] as List).cast<int>(),
        ),
        'fileRead': ({positionalArgs, namedArgs}) =>
            host.fileRead('${positionalArgs[0]}'),
        'fileText': ({positionalArgs, namedArgs}) =>
            host.fileText('${positionalArgs[0]}'),
        'fileList': ({positionalArgs, namedArgs}) => host.fileList(
          positionalArgs.isEmpty ? '' : '${positionalArgs[0]}',
        ),
        'fileExists': ({positionalArgs, namedArgs}) =>
            host.fileExists('${positionalArgs[0]}'),
        'fileDelete': ({positionalArgs, namedArgs}) =>
            host.fileDelete('${positionalArgs[0]}'),
        'fileSize': ({positionalArgs, namedArgs}) =>
            host.fileSize('${positionalArgs[0]}'),
        // 询问用户：脚本用 .then(...) 接答案；secret: true 时遮挡且不入日志
        // 两种写法都支持：ask('问题', {secret: true}) 与 ask('问题', secret: true)
        'ask': ({positionalArgs, namedArgs}) {
          final options = positionalArgs.length > 1
              ? (_toSendable(positionalArgs[1]) as Map?)?.map(
                      (key, value) => MapEntry('$key', value),
                    ) ??
                    const <String, Object?>{}
              : namedArgs;
          return host.ask(
            '${positionalArgs.isEmpty ? (options['question'] ?? '') : positionalArgs.first}',
            secret: options['secret'] == true,
            preset: '${options['preset'] ?? options['default'] ?? ''}',
          );
        },
        'httpGet': ({positionalArgs, namedArgs}) => host
            .httpGet(
              '${positionalArgs.first}',
              headers: _stringMap(namedArgs['headers']),
              includeBytes: namedArgs['wantBytes'] == true,
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
              includeBytes: namedArgs['wantBytes'] == true,
            )
            .then(_asStruct),
        'httpRequest': ({positionalArgs, namedArgs}) => host
            .httpRequest(
              Map<String, dynamic>.from(
                _toSendable(
                      positionalArgs.isEmpty ? namedArgs : positionalArgs.first,
                    )
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
        'param': ({positionalArgs, namedArgs}) => host.param(
          '${positionalArgs.first}',
          positionalArgs.length > 1 ? '${positionalArgs[1]}' : '',
        ),
        'params': ({positionalArgs, namedArgs}) => Map<String, String>.from(host.params),
        'inputText': ({positionalArgs, namedArgs}) => host.inputText(
          '${positionalArgs.first}',
          positionalArgs.length > 1 ? '${positionalArgs[1]}' : 'auto',
        ),
        'inputBytes': ({positionalArgs, namedArgs}) =>
            host.inputBytes('${positionalArgs.first}'),
        'saveOutput': ({positionalArgs, namedArgs}) => host.saveOutput(
          '${positionalArgs[0]}',
          (positionalArgs[1] as List).cast<int>(),
        ),
        'epubBuild': ({positionalArgs, namedArgs}) =>
            host.epubBuild(_toSendable(positionalArgs.first) as Map),
        'splitChapters': ({positionalArgs, namedArgs}) => host.splitChapters(
          '${positionalArgs[0]}',
          positionalArgs.length > 1 ? '${positionalArgs[1]}' : '',
        ),
        'cleanText': ({positionalArgs, namedArgs}) => host.cleanText(
          '${positionalArgs[0]}',
          _toSendable(positionalArgs[1]) as List,
        ),
        // 密码学与压缩：自建/私人书源常用（详见《插件开发指南》）
        'digest': ({positionalArgs, namedArgs}) => host.digest(
          '${positionalArgs[0]}',
          _toSendable(positionalArgs[1]),
          positionalArgs.length > 2 ? '${positionalArgs[2]}' : 'utf8',
        ),
        'hmac': ({positionalArgs, namedArgs}) => host.hmac(
          '${positionalArgs[0]}',
          _toSendable(positionalArgs[1]),
          _toSendable(positionalArgs[2]),
          positionalArgs.length > 3 ? '${positionalArgs[3]}' : 'utf8',
        ),
        'base64Encode': ({positionalArgs, namedArgs}) =>
            host.base64EncodeBytes((positionalArgs.first as List).cast<int>()),
        'base64Decode': ({positionalArgs, namedArgs}) =>
            host.base64DecodeText('${positionalArgs.first}'),
        'hexEncode': ({positionalArgs, namedArgs}) =>
            host.hexEncodeBytes((positionalArgs.first as List).cast<int>()),
        'hexDecode': ({positionalArgs, namedArgs}) =>
            host.hexDecodeText('${positionalArgs.first}'),
        'aesDecrypt': ({positionalArgs, namedArgs}) => host.aesDecrypt(
          (_toSendable(positionalArgs.isEmpty ? namedArgs : positionalArgs.first)
                  as Map)
              .cast<dynamic, dynamic>(),
        ),
        'aesEncrypt': ({positionalArgs, namedArgs}) => host.aesEncrypt(
          (_toSendable(positionalArgs.isEmpty ? namedArgs : positionalArgs.first)
                  as Map)
              .cast<dynamic, dynamic>(),
        ),
        'xorBytes': ({positionalArgs, namedArgs}) => host.xorBytes(
          (positionalArgs[0] as List).cast<int>(),
          _toSendable(positionalArgs[1]),
          positionalArgs.length > 2 ? '${positionalArgs[2]}' : 'utf8',
        ),
        'gunzip': ({positionalArgs, namedArgs}) =>
            host.gunzipBytes((positionalArgs.first as List).cast<int>()),
        'gzipBytes': ({positionalArgs, namedArgs}) =>
            host.gzipBytes((positionalArgs.first as List).cast<int>()),
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
          // 超时或取消：保留 eval 的返回值
        }
      }
      send.send({
        'ok': true,
        'result': _toSendable(result),
        'error': '',
      });
    } on HTError catch (error) {
      send.send({'ok': false, 'error': error.message});
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
        map[key] = _toSendable(value[key]);
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
