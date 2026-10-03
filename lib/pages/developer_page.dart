
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
  List<String> _exported = const [];

  Future<void> _export() async {
    try {
      final written = await AppLog.exportToDownloads(
        AppLog.buildReport(context: '开发者页面导出'),
      );
      if (mounted) setState(() => _exported = written);
    } catch (error) {
      if (mounted) setState(() => _exported = ['导出失败：$error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLog.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者'),
        actions: [
          IconButton(
            tooltip: '导出日志',
            icon: const Icon(Icons.save_alt),
            onPressed: _export,
          ),
        ],
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
              '${AppLog.logPath}\n（单个文件，自动追加；共记录 ${lines.length} 行）',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('导出日志与报告到下载目录'),
            subtitle: Text(
              _exported.isEmpty ? '包含系统环境、应用信息与全部日志' : _exported.join('\n'),
            ),
            onTap: _export,
          ),
          const Divider(),
          const ListTile(dense: true, title: Text('实时日志（最近 400 行）')),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF101418),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              lines.length > 400
                  ? lines.sublist(lines.length - 400).join('\n')
                  : lines.join('\n'),
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
