import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

/// 纯 Dart 密码学与压缩工具（宿主暴露给脚本/规则的白名单能力）。
///
/// 目标是覆盖"自建/私人书源"常见的加密与编码：
///   - 编码：base64 / hex / utf8（双向）
///   - 摘要：md5 / sha1 / sha256 / hmac-sha1 / hmac-sha256（输出 hex）
///   - 对称加密：AES-128/192/256，ECB / CBC，PKCS7 / Zero / 无填充
///   - 其它：按字节 XOR、gzip 解压/压缩
///
/// 全部为纯 Dart 实现（pointycastle + crypto + dart:io），因此
/// **Android 与 Linux 行为一致**，也不需要任何原生库。
class CryptoOps {
  CryptoOps._();

  // ---------- 编码 ----------

  static Uint8List base64Decode(String text) =>
      base64.decode(text.replaceAll(RegExp(r'\s'), ''));

  static String base64Encode(List<int> bytes) => base64.encode(bytes);

  /// 也支持 URL-safe 与无填充的 base64。
  static Uint8List base64UrlDecode(String text) {
    var value = text.replaceAll('-', '+').replaceAll('_', '/');
    while (value.length % 4 != 0) {
      value += '=';
    }
    return base64.decode(value);
  }

  static Uint8List hexDecode(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// 按名字把输入转成字节：utf8（默认）/ base64 / hex / latin1。
  static Uint8List bytesOf(Object? value, [String encoding = 'utf8']) {
    if (value is List) return Uint8List.fromList(value.map(_asByte).toList());
    final text = '${value ?? ''}';
    switch (encoding.toLowerCase()) {
      case 'base64':
        return base64Decode(text);
      case 'base64url':
        return base64UrlDecode(text);
      case 'hex':
        return hexDecode(text);
      case 'latin1':
      case 'iso-8859-1':
        return Uint8List.fromList(text.codeUnits.map((c) => c & 0xff).toList());
      default:
        return Uint8List.fromList(utf8.encode(text));
    }
  }

  static int _asByte(Object? value) =>
      value is int ? (value & 0xff) : int.parse('$value') & 0xff;

  /// 按名字把字节转成输出：utf8 / base64（默认）/ hex / raw。
  static Object outputOf(Uint8List bytes, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'utf8':
      case 'text':
        return utf8.decode(bytes, allowMalformed: true);
      case 'hex':
        return hexEncode(bytes);
      case 'raw':
      case 'bytes':
        return bytes.toList();
      default:
        return base64Encode(bytes);
    }
  }

  // ---------- 摘要 ----------

  static String digest(String algorithm, Object? input, [String encoding = 'utf8']) {
    final bytes = bytesOf(input, encoding);
    final value = switch (algorithm.toLowerCase()) {
      'md5' => crypto.md5.convert(bytes),
      'sha1' => crypto.sha1.convert(bytes),
      'sha256' => crypto.sha256.convert(bytes),
      'sha512' => crypto.sha512.convert(bytes),
      _ => throw ArgumentError('不支持的摘要算法：$algorithm'),
    };
    return value.toString();
  }

  static String hmac(
    String algorithm,
    Object? input,
    Object? key, [
    String encoding = 'utf8',
  ]) {
    final secret = crypto.Hmac(
      switch (algorithm.toLowerCase()) {
        'md5' => crypto.md5,
        'sha1' => crypto.sha1,
        'sha256' => crypto.sha256,
        'sha512' => crypto.sha512,
        _ => throw ArgumentError('不支持的 HMAC 算法：$algorithm'),
      },
      bytesOf(key, encoding),
    );
    return secret.convert(bytesOf(input, encoding)).toString();
  }

  // ---------- AES ----------

  static Uint8List aes({
    required Object? data,
    required Object? key,
    String mode = 'cbc',
    Object? iv,
    String padding = 'pkcs7',
    bool decrypt = true,
    String keyEncoding = 'utf8',
    String? inputEncoding,
    String ivEncoding = 'utf8',
  }) {
    final keyBytes = bytesOf(key, keyEncoding);
    if (![16, 24, 32].contains(keyBytes.length)) {
      throw ArgumentError('AES 密钥长度必须是 16/24/32 字节，当前 ${keyBytes.length}');
    }
    // 输入编码按方向取默认：解密默认 base64（接口返回的密文形态），加密默认 utf8
    final input = bytesOf(data, inputEncoding ?? (decrypt ? 'base64' : 'utf8'));
    final ivBytes = bytesOf(iv, ivEncoding);

    final engine = pc.AESEngine();
    final blockCipher = switch (mode.toLowerCase()) {
      'ecb' => pc.ECBBlockCipher(engine),
      'cbc' => pc.CBCBlockCipher(engine),
      _ => throw ArgumentError('AES 只支持 ecb / cbc，收到 $mode'),
    };
    // ECB 只接受 KeyParameter；CBC 需要 ParametersWithIV 包装
    final pc.CipherParameters chain = mode.toLowerCase() == 'ecb'
        ? pc.KeyParameter(keyBytes)
        : pc.ParametersWithIV<pc.KeyParameter>(
            pc.KeyParameter(keyBytes),
            ivBytes.isEmpty ? Uint8List(16) : ivBytes,
          );

    final normalized = padding.toLowerCase();
    if (normalized == 'none') {
      // 无填充：直接用底层分组密码（长度必须是 16 的整数倍）
      if (input.length % 16 != 0) {
        throw ArgumentError('无填充时数据长度必须是 16 的整数倍，当前 ${input.length}');
      }
      // 注意：pointycastle 的 init 参数是 forEncryption，与本方法的 decrypt 相反
      blockCipher.init(!decrypt, chain);
      return blockCipher.process(input);
    }

    final pc.Padding padder = switch (normalized) {
      'iso7816' || 'iso7816-4' => pc.ISO7816d4Padding(),
      _ => pc.PKCS7Padding(),
    };
    padder.init();
    final cipher = pc.PaddedBlockCipherImpl(padder, blockCipher)
      ..init(
        // pointycastle 语义：true 表示加密
        !decrypt,
        pc.PaddedBlockCipherParameters<pc.CipherParameters?, pc.CipherParameters?>(
          chain,
          null,
        ),
      );
    return cipher.process(input);
  }

  // ---------- 其它 ----------

  static Uint8List xor(List<int> bytes, Object? key, [String keyEncoding = 'utf8']) {
    final keyBytes = bytesOf(key, keyEncoding);
    if (keyBytes.isEmpty) return Uint8List.fromList(bytes);
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ keyBytes[i % keyBytes.length];
    }
    return out;
  }

  static Uint8List gunzip(List<int> bytes) {
    try {
      return Uint8List.fromList(gzip.decode(bytes));
    } catch (error) {
      throw ArgumentError('gzip 解压失败：$error');
    }
  }

  static Uint8List gzipBytes(List<int> bytes) =>
      Uint8List.fromList(gzip.encode(bytes));
}
