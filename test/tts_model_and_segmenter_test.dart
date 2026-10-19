import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/tts/tts_model_store.dart';
import 'package:reader/services/tts/tts_segmenter.dart';

Archive _properZip({bool withEspeak = true, bool withTokens = true, int onnxBytes = 2 * 1024 * 1024}) {
  final a = Archive();
  void add(String name, List<int> bytes) {
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('my-voice/zh_CN-huayan-medium.onnx', Uint8List(onnxBytes));
  if (withTokens) {
    final buf = StringBuffer();
    for (var i = 0; i < 300; i++) {
      buf.writeln('tok$i $i');
    }
    add('my-voice/tokens.txt', buf.toString().codeUnits);
  }
  if (withEspeak) {
    for (var i = 0; i < 25; i++) {
      add('my-voice/espeak-ng-data/f$i', 'x'.codeUnits);
    }
  }
  return a;
}

void main() {
  group('模型 zip 导入与校验', () {
    late Directory root;
    late Directory tmp;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tts_root');
      tmp = await Directory.systemTemp.createTemp('tts_zip');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<File> zipOf(Archive a, [String name = 'm.zip']) async {
      final f = File('${tmp.path}/$name');
      await f.writeAsBytes(ZipEncoder().encode(a), flush: true);
      return f;
    }

    test('完整 Piper 包 → 导入成功并可列举', () async {
      final store = TtsModelStore(root: () async => root);
      final model = await store.importPackage(await zipOf(_properZip()));
      expect(model.kind, 'piper');
      expect(model.hasEspeakData, isTrue);
      expect(model.language, 'zh');
      expect(File(model.onnxFile).existsSync(), isTrue);
      expect((await store.load()).length, 1);
    });

    test('缺 tokens.txt → 明确报错，且不留下半成品', () async {
      final store = TtsModelStore(root: () async => root);
      await expectLater(
        store.importPackage(await zipOf(_properZip(withTokens: false))),
        throwsA(isA<TtsModelImportException>().having(
          (e) => e.message, 'message', contains('tokens.txt'))),
      );
      expect(await store.load(), isEmpty);
      expect(root.listSync().whereType<Directory>().where((d) => d.path.contains('.import')).length, 0);
    });

    test('既无 espeak-ng-data 也无 lexicon → 报错', () async {
      final store = TtsModelStore(root: () async => root);
      await expectLater(
        store.importPackage(await zipOf(_properZip(withEspeak: false))),
        throwsA(isA<TtsModelImportException>().having(
          (e) => e.message, 'message', contains('espeak-ng-data'))),
      );
    });

    test('模型文件过小（像是错误页）→ 报错', () async {
      final store = TtsModelStore(root: () async => root);
      await expectLater(
        store.importPackage(await zipOf(_properZip(onnxBytes: 1024))),
        throwsA(isA<TtsModelImportException>().having(
          (e) => e.message, 'message', contains('KB'))),
      );
    });

    test('zip 内越界路径 → 拒绝', () async {
      final store = TtsModelStore(root: () async => root);
      final bad = Archive();
      bad.addFile(ArchiveFile('../evil.onnx', 4, Uint8List(2 * 1024 * 1024)));
      await expectLater(
        store.importPackage(await zipOf(bad)),
        throwsA(isA<TtsModelImportException>().having(
          (e) => e.message, 'message', contains('越界'))),
      );
    });

    test('官方 .tar.bz2 包可直接导入（不看扩展名，按内容识别）', () async {
      final store = TtsModelStore(root: () async => root);
      final tar = TarEncoder().encode(_properZip());
      final bz = BZip2Encoder().encode(tar);
      final f = File('${tmp.path}/official.tar.bz2');
      await f.writeAsBytes(bz, flush: true);
      final model = await store.importPackage(f);
      expect(model.kind, 'piper');
      expect(File(model.onnxFile).existsSync(), isTrue);
    });

    test('.tar.gz 同样可导入', () async {
      final store = TtsModelStore(root: () async => root);
      final tar = TarEncoder().encode(_properZip());
      final gz = GZipEncoder().encode(tar);
      final f = File('${tmp.path}/pack.tar.gz');
      await f.writeAsBytes(gz, flush: true);
      expect((await store.importPackage(f)).language, 'zh');
    });

    test('乱码文件 → 给出可照做的错误提示', () async {
      final store = TtsModelStore(root: () async => root);
      final f = File('${tmp.path}/junk.bin');
      await f.writeAsBytes(List<int>.filled(512, 7), flush: true);
      await expectLater(
        store.importPackage(f),
        throwsA(isA<TtsModelImportException>()),
      );
    });

    test('删除模型会同时清掉目录与清单', () async {
      final store = TtsModelStore(root: () async => root);
      final model = await store.importPackage(await zipOf(_properZip()));
      await store.delete(model);
      expect(await store.load(), isEmpty);
      expect(Directory(model.dirPath).existsSync(), isFalse);
    });
  });

  group('朗读分句（治断句/连读）', () {
    test('按句末标点切分，并把收尾引号并入本句', () {
      final parts = TtsSegmenter.split('他说：“走吧。”她点头。天亮了！');
      expect(parts, ['他说：“走吧。”', '她点头。', '天亮了！']);
    });

    test('完整短句保持独立；只有末尾残片会与上一句合并', () {
      expect(TtsSegmenter.split('好。我们出发吧。'), ['好。', '我们出发吧。']);
      expect(TtsSegmenter.split('我们出发吧。走'), ['我们出发吧。走']);
    });

    test('长句在次级标点处再切，且不丢内容', () {
      const long = '他站在船舷边看江水一层层推过来，夜色很深远处灯塔的光每隔几秒扫过一次，'
          '把江面照出一条淡淡的白线，更夫敲过三更巷子里只剩下水声和风声。';
      final parts = TtsSegmenter.split(long, maxLen: 30);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.replaceAll(RegExp(r'\s'), '').length <= 31), isTrue);
      expect(parts.join(), long);
    });

    test('空文本返回空列表', () {
      expect(TtsSegmenter.split('   \n  '), isEmpty);
    });
  });
}
