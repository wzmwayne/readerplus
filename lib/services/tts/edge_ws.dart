import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 极简 WebSocket 客户端（客户端 → 服务端）。
///
/// 为什么不用 `dart:io` 的 [WebSocket.connect]：
///   - 它会强制给 User-Agent 加 `Dart/x.y (dart:io), ` 前缀，并附带
///     `Sec-WebSocket-Extensions: permessage-deflate`，无法完全控制握手头部，
///     而 Edge TTS 的网关会因此拒绝（HTTP 403）；
///   - 自己基于 [SecureSocket] 实现后，握手头部在各端完全一致、无平台分支。
class EdgeWebSocket {
  EdgeWebSocket._(this._socket);

  final SecureSocket _socket;
  final StreamController<dynamic> _events = StreamController<dynamic>();
  final List<int> _buffer = [];
  bool _closed = false;

  /// 事件流：文本帧为 [String]，二进制帧为 `List<int>`。
  Stream<dynamic> get events => _events.stream;

  static Future<EdgeWebSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = await SecureSocket.connect(
      uri.host,
      uri.port == 0 ? 443 : uri.port,
      timeout: timeout,
    );
    final client = EdgeWebSocket._(socket);
    final ready = Completer<void>();

    socket.listen(
      (data) {
        client._buffer.addAll(data);
        if (!ready.isCompleted) {
          if (_headerEnd(client._buffer) > 0) ready.complete();
          return;
        }
        client._parseFrames();
      },
      onError: (Object e, StackTrace s) {
        if (!ready.isCompleted) ready.completeError(e, s);
        if (!client._events.isClosed) client._events.addError(e, s);
        client._shutdown();
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(const SocketException('握手期间连接被关闭'));
        }
        client._shutdown();
      },
      cancelOnError: true,
    );

    final key = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final path = uri.query.isEmpty ? uri.path : '${uri.path}?${uri.query}';
    final request = StringBuffer()
      ..write('GET $path HTTP/1.1\r\n')
      ..write('Host: ${uri.host}\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Key: $key\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n');
    headers.forEach((k, v) => request.write('$k: $v\r\n'));
    request.write('\r\n');
    socket.write(request.toString());
    await socket.flush();

    await ready.future.timeout(
      timeout,
      onTimeout: () => throw const SocketException('WS 握手超时'),
    );

    final end = _headerEnd(client._buffer);
    final head = latin1.decode(client._buffer.sublist(0, end));
    client._buffer.removeRange(0, end);
    final statusLine = head.split('\r\n').first;
    if (!statusLine.contains(' 101 ')) {
      client._shutdown();
      throw SocketException('WS 握手失败：$statusLine');
    }
    // 握手响应之后可能已经带上了数据帧
    client._parseFrames();
    return client;
  }

  static int _headerEnd(List<int> bytes) {
    for (var i = 3; i < bytes.length; i++) {
      if (bytes[i - 3] == 13 &&
          bytes[i - 2] == 10 &&
          bytes[i - 1] == 13 &&
          bytes[i] == 10) {
        return i + 1;
      }
    }
    return -1;
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      _sendFrame(0x8, const []);
    } catch (_) {}
    _shutdown();
  }

  /// 发送文本帧（Edge TTS 的 speech.config / ssml 走这里）。
  void sendText(String text) => _sendFrame(0x1, utf8.encode(text));

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    if (!_events.isClosed) _events.close();
    try {
      _socket.destroy();
    } catch (_) {}
  }

  void _sendFrame(int opcode, List<int> payload) {
    if (_closed) return;
    final mask = List<int>.generate(4, (_) => Random.secure().nextInt(256));
    final header = <int>[0x80 | opcode];
    final length = payload.length;
    if (length < 126) {
      header.add(0x80 | length);
    } else if (length <= 0xFFFF) {
      header.add(0x80 | 126);
      header.addAll([length >> 8 & 0xFF, length & 0xFF]);
    } else {
      header.add(0x80 | 127);
      for (var i = 7; i >= 0; i--) {
        header.add(length >> (8 * i) & 0xFF);
      }
    }
    header.addAll(mask);
    _socket.add(header);
    _socket.add(List<int>.generate(length, (i) => payload[i] ^ mask[i % 4]));
  }

  void _parseFrames() {
    while (true) {
      if (_buffer.length < 2) return;
      final b0 = _buffer[0];
      final b1 = _buffer[1];
      final opcode = b0 & 0x0F;
      final masked = (b1 & 0x80) != 0;
      var length = b1 & 0x7F;
      var offset = 2;
      if (length == 126) {
        if (_buffer.length < 4) return;
        length = (_buffer[2] << 8) | _buffer[3];
        offset = 4;
      } else if (length == 127) {
        if (_buffer.length < 10) return;
        length = 0;
        for (var i = 0; i < 8; i++) {
          length = (length << 8) | _buffer[2 + i];
        }
        offset = 10;
      }
      final maskLength = masked ? 4 : 0;
      if (_buffer.length < offset + maskLength + length) return;
      final mask = masked ? _buffer.sublist(offset, offset + 4) : const <int>[];
      final start = offset + maskLength;
      final payload = _buffer.sublist(start, start + length);
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= mask[i % 4];
        }
      }
      _buffer.removeRange(0, start + length);

      switch (opcode) {
        case 0x1:
          if (!_events.isClosed) {
            _events.add(utf8.decode(payload, allowMalformed: true));
          }
        case 0x2:
          if (!_events.isClosed) _events.add(Uint8List.fromList(payload));
        case 0x8:
          _shutdown();
          return;
        case 0x9:
          _sendFrame(0xA, payload);
        default:
          break;
      }
    }
  }
}
