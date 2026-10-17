import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_page_scaffold.dart';
import '../../core/design_system/components/review_preference_tile.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_section_card.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../account/anonymous_accounts_page.dart';
import 'cache_management_page.dart';
import 'personalization_page.dart';
import 'storage_settings_page.dart';
import 'webdav_backup_page.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    super.key,
    required this.api,
    required this.onOpenCookieManager,
    required this.onAccountChanged,
  });

  final CoolapkApi api;
  final Future<void> Function() onOpenCookieManager;
  final VoidCallback onAccountChanged;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _working = false;

  Future<void> _openCookieManager() async {
    HapticFeedbackUtil.light();
    await widget.onOpenCookieManager();
    if (mounted) setState(() {});
    widget.onAccountChanged();
  }

  Future<void> _logout() async {
    final sure = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出酷安？'),
        content: Text(
          widget.api.isAnonymous
              ? '将退出匿名模式并进入游客状态，本地资料、关注和收藏保留。'
              : '将清除本机保存的登录凭据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (!mounted || sure != true || _working) return;
    setState(() => _working = true);
    try {
      await widget.api.logout();
      if (mounted) {
        AppToast.show(context, widget.api.isAnonymous ? '已退出匿名账户' : '已退出酷安账号');
      }
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
      widget.onAccountChanged();
    }
  }

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    title: '设置',
    bodyBuilder: (context, contentInsets) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16).add(contentInsets),
      children: [
        _sectionTitle(context, '账号'),
        const SizedBox(height: 12),
        AppSectionCard(
          child: Column(
            children: [
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.manage_accounts_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '登录方式与账号管理',
                subtitle: widget.api.isAnonymous
                    ? '匿名账户：关注和收藏保存在本地'
                    : widget.api.hasCookie
                    ? '管理本机安全保存的酷安登录凭据'
                    : '登录并管理本机保存的酷安 Cookie',
                onTap: _openCookieManager,
              ),
              const Divider(height: 1, indent: 56),
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.switch_account_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '多匿名账户管理',
                subtitle: widget.api.isAnonymous
                    ? '当前: ${widget.api.localAccount.name} · 共 ${widget.api.localAccount.profiles.length} 个账户'
                    : '管理或切换本机独立匿名账户（共 ${widget.api.localAccount.profiles.length} 个）',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => AnonymousAccountsPage(api: widget.api),
                    ),
                  );
                },
              ),
              if (widget.api.hasAccount) ...[
                const Divider(height: 1, indent: 56),
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: widget.api.isAnonymous ? '退出匿名账户' : '退出登录',
                  subtitle: widget.api.isAnonymous
                      ? '退出后保留本地资料、关注和收藏'
                      : '清除本机保存的登录凭据',
                  trailing: _working
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _working ? null : _logout,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 32),
        _sectionTitle(context, '偏好与功能'),
        const SizedBox(height: 12),
        AppSectionCard(
          child: Column(
            children: [
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.palette_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '个性化',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PersonalizationPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _sectionTitle(context, '存储与备份'),
        const SizedBox(height: 12),
        AppSectionCard(
          child: Column(
            children: [
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.folder_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '存储设置',
                subtitle: '设置图片与视频的存储保存路径',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => StorageSettingsPage(api: widget.api),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '缓存管理',
                subtitle: '一键物理深度清理，支持设置自动清理阈值',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CacheManagementPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.cloud_sync_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: 'WebDAV备份',
                subtitle: '仅备份应用设置，不包含酷安登录凭据或 WebDAV 密码',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const WebDavBackupPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}
