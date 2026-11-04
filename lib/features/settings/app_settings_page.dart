import '../shell/main_pages.dart' show MessageCenterPage;

import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_page_scaffold.dart';
import '../../core/design_system/components/review_preference_tile.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_section_card.dart';
import '../../core/utils/haptic_feedback_util.dart';
import 'cache_management_page.dart';
import 'personalization_page.dart';
import 'notification_center_page.dart';
import '../shared/community_library_page.dart';
import 'storage_settings_page.dart';
import 'webdav_backup_page.dart';
import 'about_app_dialog.dart';

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
  String get _loginLabel => widget.api.isAnonymous
      ? (widget.api.localAccount.publicIdentity == null
            ? '匿名登录'
            : '匿名登录（绑定公开 UID）')
      : widget.api.hasCookie
      ? '账号登录'
      : '游客（未登录）';

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
                subtitle: '当前登录方式：$_loginLabel',
                onTap: _openCookieManager,
              ),
              ReviewPreferenceTile(
                title: '屏蔽与黑名单',
                leading: const Icon(Icons.block),
                onTap: !widget.api.hasCookie
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommunityLibraryPage(
                            api: widget.api,
                            library: CommunityLibrary.blacklist,
                          ),
                        ),
                      ),
              ),
              if (widget.api.hasAccount) ...[
                ReviewPreferenceTile(
                  leading: Icon(
                    Icons.logout_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: '退出登录',
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
              ReviewPreferenceTile(
                leading: const Icon(Icons.notifications_outlined),
                title: '通知中心',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => MessageCenterPage(api: widget.api),
                  ),
                ),
              ),
              ReviewPreferenceTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: '回复提醒设置',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReplyNotificationSettingsPage(api: widget.api),
                  ),
                ),
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
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => StorageSettingsPage(api: widget.api),
                    ),
                  );
                },
              ),
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '缓存管理',
                onTap: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CacheManagementPage(),
                    ),
                  );
                },
              ),
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.cloud_sync_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: 'WebDAV备份',
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
        const SizedBox(height: 32),
        _sectionTitle(context, '关于与支持'),
        const SizedBox(height: 12),
        AppSectionCard(
          child: Column(
            children: [
              ReviewPreferenceTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: '关于 GreenNote',
                onTap: () => showAboutAppDialog(context),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 16),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
