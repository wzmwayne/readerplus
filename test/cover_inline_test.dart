import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/plugin/source_service.dart';

/// 封面的三种形态与优先级：coverData(裸 base64) > cover(data: URI) > cover(URL)。
void main() {
  final png = base64Encode(utf8.encode('fake-image-bytes'));

  test('裸 base64 可解析（coverData）', () {
    expect(SourceService.decodeInlineCover(png), utf8.encode('fake-image-bytes'));
  });

  test('data: URI 可解析（带 meta 前缀）', () {
    expect(
      SourceService.decodeInlineCover('data:image/png;base64,$png'),
      utf8.encode('fake-image-bytes'),
    );
  });

  test('普通图片地址返回 null（交给网络图加载）', () {
    expect(SourceService.decodeInlineCover('https://a/b.jpg'), isNull);
    expect(SourceService.decodeInlineCover(''), isNull);
  });

  test('坏 base64 返回 null，不抛异常', () {
    expect(SourceService.decodeInlineCover('data:image/png;base64,!!!!'), isNull);
    expect(SourceService.decodeInlineCover('%%%'), isNull);
  });
}
