import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/script/crypto_ops.dart';
import 'package:reader/services/script/hetu_engine.dart';
import 'package:reader/services/script/script_runner.dart';

/// 已知答案（KAT）测试：用公开标准向量验证实现正确，而不是自证自洽。
void main() {
  group('编码与摘要（已知答案）', () {
    test('base64 / hex 双向', () {
      expect(CryptoOps.base64Encode(utf8.encode('hello')), 'aGVsbG8=');
      expect(utf8.decode(CryptoOps.base64Decode('aGVsbG8=')), 'hello');
      expect(CryptoOps.hexEncode([0x00, 0x0f, 0xff]), '000fff');
      expect(CryptoOps.hexDecode('000fff'), [0x00, 0x0f, 0xff]);
    });

    test('md5 / sha1 / sha256 标准向量', () {
      // RFC 1321 / FIPS 180 公开向量
      expect(CryptoOps.digest('md5', 'abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        CryptoOps.digest('sha1', 'abc'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(
        CryptoOps.digest('sha256', 'abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('hmac-sha256 标准向量（RFC 4231 第 1 组）', () {
      expect(
        CryptoOps.hmac('sha256', 'Hi There', List.filled(20, 0x0b)),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });
  });

  group('AES（已知答案）', () {
    test('AES-128-ECB 无填充：FIPS-197 附录 B 向量', () {
      // 密钥与明文均为 16 个 0，密文 66e94bd4ef8a2c3b884cfa59ca342b2e
      final cipher = CryptoOps.aes(
        data: List.filled(16, 0),
        key: List.filled(16, 0),
        mode: 'ecb',
        padding: 'none',
        decrypt: false,
        inputEncoding: 'raw',
      );
      expect(CryptoOps.hexEncode(cipher), '66e94bd4ef8a2c3b884cfa59ca342b2e');

      final back = CryptoOps.aes(
        data: cipher,
        key: List.filled(16, 0),
        mode: 'ecb',
        padding: 'none',
        inputEncoding: 'raw',
      );
      expect(back, List.filled(16, 0));
    });

    test('AES-128-CBC（NIST SP 800-38A 第 1 组）：加密后能解回', () {
      const keyText = '2b7e151628aed2a6abf7158809cf4f3c';
      const ivText = '000102030405060708090a0b0c0d0e0f';
      const plainText = '6bc1bee22e409f96e93d7e117393172a';
      final encrypted = CryptoOps.aes(
        data: CryptoOps.hexEncode(CryptoOps.hexDecode(plainText)),
        key: keyText,
        keyEncoding: 'hex',
        iv: ivText,
        ivEncoding: 'hex',
        mode: 'cbc',
        padding: 'none',
        decrypt: false,
        inputEncoding: 'hex',
      );
      // NIST 期望密文
      expect(CryptoOps.hexEncode(encrypted), '7649abac8119b246cee98e9b12e9197d');

      final decrypted = CryptoOps.aes(
        data: encrypted,
        key: keyText,
        keyEncoding: 'hex',
        iv: ivText,
        ivEncoding: 'hex',
        mode: 'cbc',
        padding: 'none',
        inputEncoding: 'raw',
      );
      expect(CryptoOps.hexEncode(decrypted), plainText);
    });

    test('PKCS7 往返（utf8 密钥与 base64 输入，贴合实际接口）', () {
      final key = utf8.encode('0123456789abcdef');
      final plain = utf8.encode('自建书源的加密正文 Content');
      final encrypted = CryptoOps.aes(
        data: utf8.decode(plain),
        key: key,
        mode: 'cbc',
        iv: utf8.encode('abcdefghijklmnop'),
        decrypt: false,
      );
      final decrypted = CryptoOps.aes(
        data: CryptoOps.base64Encode(encrypted),
        key: key,
        mode: 'cbc',
        iv: utf8.encode('abcdefghijklmnop'),
      );
      expect(utf8.decode(decrypted), utf8.decode(plain));
    });
  });

  group('gzip 与 XOR', () {
    test('gzip 往返（响应头缺失或 .gz 文件场景）', () {
      final raw = utf8.encode('{"items":[1,2,3]}');
      final packed = CryptoOps.gzipBytes(raw);
      expect(CryptoOps.gunzip(packed), raw);
    });

    test('XOR 往返', () {
      final data = utf8.encode('秘密文本');
      final masked = CryptoOps.xor(data, 'key');
      expect(CryptoOps.xor(masked, 'key'), data);
    });
  });

  group('脚本可用（隔离执行 + 能力白名单）', () {
    test('脚本内可直接做 AES 解密与摘要', () async {
      // 用已知向量在脚本里做 AES-128-ECB 解密与 md5
      const cipherHex = '66e94bd4ef8a2c3b884cfa59ca342b2e';
      final runner = ScriptRunner(entry: HetuScriptEngine.isolateEntry);
      final result = await runner.run('''
        var zeroKey = '00000000000000000000000000000000'
        var plain = aesDecrypt({
          'data': '$cipherHex',
          'key': zeroKey,
          'keyEncoding': 'hex',
          'inputEncoding': 'hex',
          'mode': 'ecb',
          'padding': 'none'
        })
        var payload = {}
        payload['plainHex'] = hexEncode(plain)
        payload['md5'] = digest('md5', 'abc')
        payload['gzipOk'] = gunzip(gzipBytes(base64Decode('aGVsbG8='))).length
        result(payload)
      ''');
      expect(result.ok, isTrue, reason: result.error);
      final payload = result.result as Map;
      expect(
        payload['plainHex'],
        '00000000000000000000000000000000',
        reason: '脚本内 AES 解密应还原全零明文',
      );
      expect(payload['md5'], '900150983cd24fb0d6963f7d28e17f72');
      expect(payload['gzipOk'], 5, reason: '脚本内 gzip 往返应还原 hello 的 5 字节');
    });
  });
}
