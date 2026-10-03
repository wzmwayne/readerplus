import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_log.dart';

/// 开发者页面：连续点击「版本」进入，提供日志与排查相关的工具。
///
/// 日志框默认展示**日志文件**的全部内容——文件是单个且永远追加，
/// 因此包含历史各轮运行与本次运行；也可切到「实时」看内存中的本轮日志。
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  String? _fileContent;
  bool _loading = true;
  bool _showLive = false;
  int _fileLines = 0;

  static const int _tailLimitBytes = 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() => _loading = true);
    var content = '';
    var lines = 0;
    try {
      File? source;
      for (final path in AppLog.logPaths) {
        if (path.startsWith('(')) continue;
        final file = File(path);
        if (file.existsSync()) {
          source = file;
          break;
        }
      }
      if (source == null) {
        content = '（还没有日志文件）';
      } else {
        final length = source.lengthSync();
        if (length > _tailLimitBytes) {
          final raf = source.openSync();
          raf.setPositionSync(length - _tailLimitBytes);
          content =
              '（文件 ${(length / 1024 / 1024).toStringAsFixed(1)}MB，'
              '仅展示末尾 1MB）\n' +
              utf8.decode(raf.readSync(_tailLimitBytes), allowMalformed: true);
          raf.closeSync();
        } else {
          content = await source.readAsString();
        }
        if (content.trim().isEmpty) content = '（日志文件为空）';
        lines = '\n'.allMatches(content).length + 1;
      }
    } catch (error) {
      content = '读取日志文件失败：$error';
    }
    if (!mounted) return;
    setState(() {
      _fileContent = content;
      _fileLines = lines;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLog.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者'),
        actions: [
          IconButton(
            tooltip: '重新读取日志文件',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadFile,
          ),
        ],
      ),
      body: ListView(
        children: [
          const ListTile(dense: true, title: Text('应用与环境')),
          ListTile(
            dense: true,
            title: const Text('版本'),
            subtitle: Text(appVersionLabel),
          ),
          ListTile(
            dense: true,
            title: const Text('环境'),
            subtitle: Text(AppLog.environmentSummary()),
          ),
          ListTile(
            dense: true,
            title: const Text('日志文件（单个、永远追加）'),
            subtitle: Text(AppLog.logPaths.join('\n')),
          ),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(
              _showLive
                  ? '实时日志（本次运行，内存中 ${lines.length} 行）'
                  : '日志文件（历史 + 本次，共 $_fileLines 行）',
            ),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('文件')),
                ButtonSegment<bool>(value: true, label: Text('实时')),
              ],
              selected: <bool>{_showLive},
              onSelectionChanged: (value) =>
                  setState(() => _showLive = value.first),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minHeight: 240),
            decoration: BoxDecoration(
              color: const Color(0xFF101418),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _loading && !_showLive
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SelectableText(
                    _showLive
                        ? (lines.length > 400
                              ? lines.sublist(lines.length - 400).join('\n')
                              : lines.join('\n'))
                        : (_fileContent ?? ''),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFD7E2EA),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
