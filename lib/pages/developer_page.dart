
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_log.dart';

/// 开发者页面：连续点击「版本」进入，提供日志与排查相关的工具。
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  @override
  Widget build(BuildContext context) {
    final lines = AppLog.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者'),
      ),
      body: ListView(
        children: [
          const ListTile(
            dense: true,
            title: Text('应用与环境'),
          ),
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
            title: const Text('日志文件'),
            subtitle: Text(
              '${AppLog.logPaths.join('\n')}\n'
              '（单个文件、永远追加；共记录 ${lines.length} 行）',
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('日志为单个文件、始终追加；位置可用环境变量 READERPLUS_LOG_DIR 覆盖'),
          ),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(
              _showLive
                  ? '实时日志（本次运行，内存中 ${lines.length} 行）'
                  : '日志文件（全部：历史 + 本次，共 $_fileLines 行）',
            ),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('文件')),
                ButtonSegment(value: true, label: Text('实时')),
              ],
              selected: {_showLive},
              onSelectionChanged: (value) =>
                  setState(() => _showLive = value.first),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF101418),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _loading && !_showLive
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
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
