import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app_log.dart';
import 'crypto_ops.dart';
import 'js/js_async_interpreter.dart';
import 'js/js_interpreter.dart';
import 'js/js_runtime.dart';
import 'script_storage.dart';

/// 把宿主能力挂到 JS 全局上（目标④的宿主面）。
///
/// 同步能力（本文件）：log / result / decode / urlJoin / 加解密 / 三级存储。
/// 网络与询问（http / ask）依赖异步，另行在异步求值层接入。
class ScriptVm {
  ScriptVm({
    required this.storage,
    required this.onLog,
    required this.onResult,
  });

  final ScriptStorage storage;
  final void Function(String message) onLog;
  final void Function(Object? value) onResult;

  /// 询问用户：返回 Future（可被异步求值器透明等待）。
  Future<Object?> Function(
    String question, {
    bool secret,
    String preset,
  }) onAsk = (question, {secret = false, preset = ''}) async => '';

  /// 网络请求实现可注入（测试用），默认走真实 HTTP。
  Future<Map<String, Object?>> Function(Map<String, Object?> options) httpImpl =
      _defaultHttp;

  late final Interpreter interpreter = Interpreter(globals: _globals());

  /// 注入任务信息：写入临时层保留键 `task`（JSON 文本）与 `input/<name>`（原始字节）。
  void injectTask({
    required Map<String, Object?> task,
    Map<String, List<int>> inputs = const {},
  }) {
    storage.temp.writeReservedUtf8('task', jsonEncode(task));
    inputs.forEach((name, bytes) {
      storage.temp.writeReservedRaw('input/$name', bytes);
    });
  }

  Map<String, Object?> _globals() {
    return {
      'log': _fn('log', (args) {
        onLog(args.map(toStringJs).join(' '));
        return JsUndefined.instance;
      }),
      'result': _fn('result', (args) {
        onResult(args.isEmpty ? null : args.first);
        return JsUndefined.instance;
      }),
      'decode': _fn('decode', (args) {
        if (args.isEmpty) return '';
        final bytes = _asBytes(args.first);
        final encoding = args.length > 1 ? toStringJs(args[1]) : 'auto';
        return _decode(bytes, encoding);
      }),
      'urlJoin': _fn('urlJoin', (args) {
        if (args.length < 2) return '';
        return Uri.parse(toStringJs(args[0]))
            .resolve(toStringJs(args[1]))
            .toString();
      }),
      'base64': _obj({
        'encode': _fn('encode', (args) =>
            CryptoOps.base64Encode(_asBytes(args.isEmpty ? '' : args.first))),
        'decode': _fn('decode', (args) =>
            CryptoOps.base64Decode(args.isEmpty ? '' : toStringJs(args.first))),
      }),
      'hex': _obj({
        'encode': _fn('encode', (args) =>
            CryptoOps.hexEncode(_asBytes(args.isEmpty ? '' : args.first))),
        'decode': _fn('decode', (args) =>
            CryptoOps.hexDecode(args.isEmpty ? '' : toStringJs(args.first))),
      }),
      'digest': _fn('digest', (args) {
        if (args.length < 2) return '';
        return CryptoOps.digest(
          toStringJs(args[0]),
          args[1],
          args.length > 2 ? toStringJs(args[2]) : 'utf8',
        );
      }),
      'hmac': _fn('hmac', (args) {
        if (args.length < 3) return '';
        return CryptoOps.hmac(
          toStringJs(args[0]),
          args[1],
          args[2],
          args.length > 3 ? toStringJs(args[3]) : 'utf8',
        );
      }),
      'http': _httpGlobals(),
      'ask': _fn('ask', (args) {
        final question = args.isEmpty ? '' : toStringJs(args.first);
        final options = args.length > 1 && args[1] is Map
            ? (args[1] as Map).cast<String, Object?>()
            : const <String, Object?>{};
        return onAsk(
          question,
          secret: options['secret'] == true,
          preset: toStringJs(options['preset'] ?? ''),
        );
      }),
      'mem': _tierGlobals(storage.memory),
      'tmp': _tierGlobals(storage.temp),
      'perm': _tierGlobals(storage.perm),
    };
  }

  /// 三级存储的对象形态：{ read: {raw, utf8}, write: {raw, utf8}, remove, keys, clear }
  Map<String, Object?> _tierGlobals(dynamic tier) {
    return _obj({
      'read': _obj({
        'raw': _fn('raw', (args) {
          if (args.isEmpty) return null;
          final bytes = tier.readRaw(toStringJs(args.first)) as Uint8List?;
          return bytes?.toList();
        }),
        'utf8': _fn('utf8', (args) {
          if (args.isEmpty) return null;
          return tier.readUtf8(toStringJs(args.first));
        }),
      }),
      'write': _obj({
        'raw': _fn('raw', (args) {
          if (args.length < 2) return 0;
          return tier.writeRaw(toStringJs(args[0]), _asBytes(args[1]));
        }),
        'utf8': _fn('utf8', (args) {
          if (args.length < 2) return 0;
          return tier.writeUtf8(toStringJs(args[0]), toStringJs(args[1]));
        }),
      }),
      'remove': _fn('remove', (args) =>
          args.isEmpty ? false : tier.remove(toStringJs(args.first))),
      'keys': _fn('keys', (_) => tier.keys()),
      'clear': _fn('clear', (_) => tier.clear()),
    });
  }

  Object? run(String source) => interpreter.run(source);

  /// 异步执行（http / ask 可用）；纯同步脚本也可走这里。
  Future<Object?> runAsync(String source) async {
    final interp = AsyncInterpreter(globals: _globals());
    return interp.run(source);
  }

  /// 网络：http.get(url) / http.post(url, body) / http.request(options)
  /// 返回 { status, headers, text, bytes }。
  Map<String, Object?> _httpGlobals() {
    Future<Map<String, Object?>> send(Map<String, Object?> options) async {
      try {
        return await httpImpl(options);
      } catch (error) {
        AppLog.write('script', '网络请求失败：$error');
        return <String, Object?>{
          'status': 0,
          'headers': const <String, String>{},
          'text': '',
          'bytes': const <int>[],
          'error': '$error',
        };
      }
    }

    return _obj({
      'get': _fn('get', (args) {
        if (args.isEmpty) return Future.value(null);
        return send({'url': toStringJs(args[0]), 'method': 'GET'});
      }),
      'post': _fn('post', (args) {
        if (args.isEmpty) return Future.value(null);
        return send({
          'url': toStringJs(args[0]),
          'method': 'POST',
          'body': args.length > 1 ? toStringJs(args[1]) : '',
        });
      }),
      'request': _fn('request', (args) {
        final options = args.isNotEmpty && args.first is Map
            ? (args.first as Map).cast<String, Object?>()
            : const <String, Object?>{};
        return send(options);
      }),
    });
  }

  /// 默认 HTTP 实现（可被测试替换）。返回规范化后的响应。
  static Future<Map<String, Object?>> _defaultHttp(
    Map<String, Object?> options,
  ) async {
    final url = Uri.parse(toStringJs(options['url']));
    final method = toStringJs(options['method'] ?? 'GET').toUpperCase();
    final headers = (options['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
        <String, String>{};
    final body = options['body'] == null ? null : toStringJs(options['body']);
    final wantBytes = options['wantBytes'] == true;
    final timeoutMs =
        options['timeoutMs'] is num ? (options['timeoutMs'] as num).toInt() : 20000;
    final request = http.Request(method, url);
    request.headers.addAll(headers);
    if (body != null && body.isNotEmpty) request.body = body;
    final streamed =
        await http.Client().send(request).timeout(Duration(milliseconds: timeoutMs));
    final bytes = await streamed.stream.toBytes();
    return {
      'status': streamed.statusCode,
      'headers': streamed.headers,
      'text': wantBytes ? '' : _decode(bytes, 'auto'),
      'bytes': wantBytes ? bytes : const <int>[],
    };
  }

  static Map<String, Object?> _obj(Map<String, Object?> values) => values;

  static JsFunction _fn(String name, Object? Function(List<Object?> args) body) =>
      JsFunction(const [], null, Scope(null), name: name, native: body);

  static List<int> _asBytes(Object? value) {
    if (value is List) {
      return [for (final item in value) toNumber(item).toInt()];
    }
    if (value is String) return utf8.encode(value);
    if (value == null || identical(value, JsUndefined.instance)) return const [];
    return utf8.encode(toStringJs(value));
  }

  static String _decode(List<int> bytes, String encoding) {
    final name = encoding.toLowerCase();
    if (name.isEmpty || name == 'auto' || name.contains('utf')) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (name.contains('hex')) return CryptoOps.hexEncode(bytes);
    if (name.contains('base64')) return CryptoOps.base64Encode(bytes);
    return utf8.decode(bytes, allowMalformed: true);
  }
}