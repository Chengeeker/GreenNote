import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/network/webdav_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/widgets/app_section_card.dart';

class WebDavBackupPage extends ConsumerStatefulWidget {
  const WebDavBackupPage({super.key});

  @override
  ConsumerState<WebDavBackupPage> createState() => _WebDavBackupPageState();
}

class _WebDavBackupPageState extends ConsumerState<WebDavBackupPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController(
    text: defaultWebDavDirectory,
  );
  final _secureStorage = const FlutterSecureStorage();
  final _service = WebDavService();
  String? _status;
  bool _busy = false;
  String _operation = '';
  bool get _isTesting => _busy && _operation == 'test';
  bool get _isBackingUp => _busy && _operation == 'backup';
  bool get _isRestoring => _busy && _operation == 'restore';
  bool _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    try {
      final config = await ref
          .read(appSettingsProvider.notifier)
          .loadWebDavConfig();
      final password = await _secureStorage.read(
        key: 'greennote.webdav.password',
      );
      if (!mounted) return;
      _urlController.text = config['url'] ?? '';
      _usernameController.text = config['username'] ?? '';
      _directoryController.text = config['directory'] ?? defaultWebDavDirectory;
      _passwordController.text = password ?? '';
    } catch (_) {
      _status = '无法读取本机 WebDAV 配置，请重新填写。';
    } finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final url = WebDavService.normalizeServerUrl(_urlController.text);
    final directory = WebDavService.directorySegments(_directoryController.text)
        .join('/');
    await ref
        .read(appSettingsProvider.notifier)
        .saveWebDavConfig(
          url: url,
          username: _usernameController.text.trim(),
          directory: directory,
        );
    final password = _passwordController.text;
    if (password.isEmpty) {
      await _secureStorage.delete(key: 'greennote.webdav.password');
    } else {
      await _secureStorage.write(
        key: 'greennote.webdav.password',
        value: password,
      );
    }
  }

  bool _validate() => _formKey.currentState?.validate() ?? false;

  Future<void> _testConnection() async {
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _operation = 'test';
      _status = '正在测试连接…';
    });
    try {
      await _saveConfig();
      final success = await _service.testConnection(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        setState(
          () => _status = success ? '连接成功。' : '连接失败，请检查服务器地址、账号、密码和 WebDAV 权限。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message
              : '无法保存 WebDAV 配置。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _operation = 'backup';
      _status = '正在备份设置…';
    });
    try {
      await _saveConfig();
      final backup = await ref
          .read(appSettingsProvider.notifier)
          .exportBackup(
            webDavUrl: _urlController.text.trim(),
            webDavUsername: _usernameController.text.trim(),
            webDavDirectory: _directoryController.text.trim(),
          );
      final success = await _service.uploadBackup(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        directory: _directoryController.text,
        data: backup,
      );
      if (mounted) {
        setState(
          () => _status = success
              ? '匿名账户与设置已备份到 WebDAV。'
              : '备份失败，请检查连接、目录权限和服务器空间。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message
              : '备份失败，请检查 WebDAV 配置。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (!_validate()) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复 WebDAV 备份？'),
        content: const Text(
          '云端快照将替换本地匿名账户及应用设置；恢复前的匿名数据会保留，可在匿名账户页找回。旧版设置备份不会改动匿名账户。酷安 Cookie 与 WebDAV 密码不会备份或恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复设置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _operation = 'restore';
      _status = '正在读取云端备份…';
    });
    try {
      await _saveConfig();
      final backup = await _service.downloadLatestBackup(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        directory: _directoryController.text,
      );
      if (backup == null) {
        if (mounted) setState(() => _status = '没有找到兼容的 Greennote 备份。');
        return;
      }
      final previousUrl = _urlController.text.trim();
      final previousUsername = _usernameController.text.trim();
      final config = await ref
          .read(appSettingsProvider.notifier)
          .restoreBackup(backup);
      final api = await ref.read(coolapkApiProvider.future);
      api.localAccount.reload();
      final restoredUrl = config['url'] ?? '';
      final restoredUsername = config['username'] ?? '';
      String comparableUrl(String value) {
        try {
          return WebDavService.normalizeServerUrl(value);
        } on FormatException {
          return value.trim();
        }
      }

      final credentialsChanged =
          comparableUrl(previousUrl) != comparableUrl(restoredUrl) ||
          previousUsername != restoredUsername;
      if (credentialsChanged) {
        await _secureStorage.delete(key: 'greennote.webdav.password');
      }
      if (!mounted) return;
      _urlController.text = restoredUrl;
      _usernameController.text = restoredUsername;
      _directoryController.text = config['directory'] ?? defaultWebDavDirectory;
      if (credentialsChanged) {
        _passwordController.clear();
      }
      setState(
        () => _status = credentialsChanged
            ? '设置已恢复；服务器或用户名已更改，请重新输入 WebDAV 密码。'
            : '备份已恢复；匿名数据副本可在匿名账户页找回。',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message
              : '恢复失败，当前设置未能完整恢复。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ReviewFrostedAppBar(
        title: const Text(
          'WebDAV 云端备份与恢复',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
            16,
            14,
          ),
          children: [
            // 1. Info Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '安全备份 (Greennote)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '备份匿名账户头像、用户名、本地关注、收藏文字及图片地址，以及应用设置。酷安 Cookie、Token 与 WebDAV 密码不会上传。图片文件不包含在内；这是手动快照，多设备请先恢复再修改及备份。',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Configuration Card
            AppSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WebDAV 服务器配置',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      enabled: !_busy && !_loadingConfig,
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: '服务器 URL',
                        hintText: '例如: https://dav.jianguoyun.com/dav/',
                        prefixIcon: Icon(Icons.link_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => WebDavService.isValidServerUrl(v ?? '')
                          ? null
                          : '请输入 HTTPS 地址（本机回环可使用 HTTP）',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_busy && !_loadingConfig,
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '账号 / 邮箱',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_busy && !_loadingConfig,
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '应用密码 / Token',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入密码或授权 Token'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      enabled: !_busy && !_loadingConfig,
                      controller: _directoryController,
                      validator: (value) {
                        try {
                          WebDavService.directorySegments(value ?? '');
                          return null;
                        } on FormatException catch (error) {
                          return error.message;
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: '备份文件夹名称',
                        hintText: '默认: GreenNote',
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.wifi_tethering_rounded,
                                size: 18,
                              ),
                        label: Text(_isTesting ? '正在测试连接...' : '测试服务器连接'),
                        onPressed: _busy || _loadingConfig
                            ? null
                            : _testConnection,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Actions Section
            AppSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '云端备份与还原操作',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_rounded),
                            label: Text(_isBackingUp ? '正在上传...' : '立即备份到云端'),
                            onPressed: (_busy || _loadingConfig)
                                ? null
                                : _backup,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_rounded),
                            label: Text(_isRestoring ? '正在拉取...' : '从云端恢复备份'),
                            onPressed: (_busy || _loadingConfig)
                                ? null
                                : _restore,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_status!)),
            ],
          ],
        ),
      ),
    );
  }
}
