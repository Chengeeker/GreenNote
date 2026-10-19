import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/network/official_device_identity.dart';
import '../../core/utils/app_dialog.dart';
import 'device_identity_guide_page.dart';

class DeviceIdentityPage extends StatefulWidget {
  const DeviceIdentityPage({required this.api, super.key});
  final CoolapkApi api;
  @override
  State<DeviceIdentityPage> createState() => _DeviceIdentityPageState();
}

class _DeviceIdentityPageState extends State<DeviceIdentityPage> {
  final _text = TextEditingController();
  String? _pending;
  String? _status;
  bool _error = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _pending = null;
    super.dispose();
  }

  void _message(String message, {bool error = false}) {
    if (mounted) {
      setState(() {
        _status = message;
        _error = error;
      });
    }
  }

  void _recognize(String value) {
    try {
      final id = OfficialDeviceIdentity.parse(value);
      _text.clear();
      setState(() {
        _pending = id;
        _status = '已识别数盟 ID，点击“保存并应用”生效';
        _error = false;
      });
      FocusScope.of(context).unfocus();
    } on FormatException catch (error) {
      setState(() => _pending = null);
      _message(error.message.toString(), error: true);
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pending = null;
      _status = null;
    });
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        _message('剪贴板没有文本，请先在官方酷安完成复制', error: true);
      } else {
        _recognize(text);
      }
    } catch (_) {
      _message('无法读取剪贴板，请在下方输入框长按粘贴后识别', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final id = _pending;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.importOfficialDeviceIdentity('ShuzlmID: $id');
      if (!mounted) return;
      setState(() => _pending = null);
      _message('已保存并用于后续请求，请返回内容页刷新');
    } on FormatException catch (error) {
      _message(error.message.toString(), error: true);
    } catch (_) {
      _message('保存失败，设备标识未应用，请重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final confirm = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复原设备码？'),
        content: const Text('将移除导入的设备标识，恢复本机原先的设备码。账号登录、匿名资料和收藏会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.restoreOriginalDeviceIdentity();
      if (!mounted) return;
      setState(() {
        _pending = null;
        _text.clear();
      });
      _message('已恢复原设备码，请返回内容页刷新');
    } catch (_) {
      _message('恢复失败，原有配置保持不变，请重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOfficial() async {
    try {
      final opened = await const MethodChannel('com.green.note/ui')
          .invokeMethod<bool>('openOfficialIdSettings');
      if (opened != true) _message('无法打开官方页面，请确认官方酷安已启用并更新后重试', error: true);
    } on PlatformException catch (error) {
      _message(
        error.code == 'official_not_installed'
            ? '请先安装官方酷安，再打开其“检查日志和测试”页面'
            : '无法打开官方页面，请在官方酷安中手动进入',
        error: true,
      );
    } catch (_) {
      _message('无法打开官方页面，请在官方酷安中手动进入', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('导入官方设备标识')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.api.hasOfficialDeviceIdentity
                      ? '当前已使用导入的设备标识'
                      : '当前使用本机原设备码',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text('可尝试改善反复人机验证的情况，有效期与验证要求仍由酷安服务端决定。此功能不代替账号登录。'),
                const SizedBox(height: 16),
                const Text(
                  '1. 打开官方酷安的“检查日志和测试”页。\n2. 在同一页面累计点击“复制 OAID”5次。\n3. 返回此处粘贴完整内容，识别后保存。',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _openOfficial,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('打开酷安 OAID 界面'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const DeviceIdentityGuidePage(),
                              ),
                            ),
                      child: const Text('查看操作教程'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '实际使用的是 ShuzlmID（数盟 ID），不是 OAID、AndroidID 或 UUID。仅保存所需设备编码，其余复制字段会丢弃；不会后台读取剪贴板，不会加入 WebDAV 备份。',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 5,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) => setState(() {
                    _pending = null;
                    _status = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: '官方复制内容',
                    hintText: '粘贴包含 ShuzlmID 的完整文本',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _paste,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴并识别'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _recognize(_text.text),
                      child: const Text('识别输入内容'),
                    ),
                  ],
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _status!,
                        style: TextStyle(
                          color: _error
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                  ),
                if (_busy)
                  const LinearProgressIndicator(semanticsLabel: '正在处理设备标识'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _pending == null ? null : _save,
                  child: const Text('保存并应用'),
                ),
                if (widget.api.hasOfficialDeviceIdentity)
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('恢复原设备码'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
