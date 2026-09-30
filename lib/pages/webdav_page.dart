import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// WebDAV 同步配置与手动同步入口。
/// 同步单位为单个备份包：`<remoteDir>/reader-backup.zip`
class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key});

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _dir;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppState>().webdav;
    _url = TextEditingController(text: cfg.url);
    _user = TextEditingController(text: cfg.username);
    _pass = TextEditingController(text: cfg.password);
    _dir = TextEditingController(text: cfg.remoteDir);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _dir.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    state.webdav
      ..url = _url.text.trim()
      ..username = _user.text.trim()
      ..password = _pass.text
      ..remoteDir = _dir.text.trim().isEmpty ? 'reader-sync' : _dir.text.trim()
      ..enabled = _url.text.trim().isNotEmpty;
    await state.saveWebdav();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dav.example.com/remote.php/dav/files/user/',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            decoration: const InputDecoration(labelText: '账号', border: OutlineInputBorder()),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码 / 应用密码',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dir,
            decoration: const InputDecoration(
              labelText: '远程目录',
              helperText: '会在此目录下生成 reader-backup.zip',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                  onPressed: state.busy ? null : () => state.testWebdav(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传到云端'),
                  onPressed: state.busy || !state.webdav.configured ? null : () => state.syncUpload(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('从云端恢复'),
                  onPressed: state.busy || !state.webdav.configured ? null : () => _confirmDownload(state),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (state.busy) const LinearProgressIndicator(),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.message!, style: const TextStyle(fontSize: 13)),
            ),
          const Divider(height: 40),
          const Text(
            '说明：同步以单个备份包为单位，包含书架、目录、正文与设置。'
            '从云端恢复会覆盖本地数据，建议先导出一份本地备份。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDownload(AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端恢复'),
        content: const Text('将覆盖本地书架与设置，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('继续')),
        ],
      ),
    );
    if (ok == true) await state.syncDownload();
  }
}
