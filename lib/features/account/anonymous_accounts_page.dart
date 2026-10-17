import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/accounts/local_account.dart';
import '../../core/design_system/components/review_card.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/haptic_feedback_util.dart';
import 'local_account_page.dart';

/// 弹出底部快捷切换或管理匿名账户弹窗
Future<void> showAnonymousAccountSwitcher(
  BuildContext context,
  CoolapkApi api,
) async {
  HapticFeedbackUtil.light();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _AnonymousAccountSwitcherSheet(api: api),
  );
}

class _AnonymousAccountSwitcherSheet extends StatefulWidget {
  const _AnonymousAccountSwitcherSheet({required this.api});

  final CoolapkApi api;

  @override
  State<_AnonymousAccountSwitcherSheet> createState() =>
      _AnonymousAccountSwitcherSheetState();
}

class _AnonymousAccountSwitcherSheetState
    extends State<_AnonymousAccountSwitcherSheet> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final local = widget.api.localAccount;

    return ListenableBuilder(
      listenable: local,
      builder: (context, _) {
        final profiles = local.profiles;
        final activeId = local.activeProfileId;
        final isAnonymousActive = widget.api.isAnonymous;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择匿名账户',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('管理账户'),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => AnonymousAccountsPage(api: widget.api),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '每个匿名账户拥有各自独立的 UID 身份、关注和收藏，互不干扰。',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final p = profiles[index];
                      final isCurrent = isAnonymousActive && p.id == activeId;
                      final uid = p.publicIdentity?['uid'] as String?;

                      return ReviewCard(
                        margin: EdgeInsets.zero,
                        color: isCurrent
                            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                            : null,
                        child: ListTile(
                          leading: LocalAvatar(
                            avatar: p.avatar,
                            name: p.name,
                            radius: 20,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '当前使用',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            uid != null
                                ? 'UID: $uid · 关注 ${p.follows.length} · 收藏 ${p.favorites.length}'
                                : '纯本地 · 关注 ${p.follows.length} · 收藏 ${p.favorites.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: isCurrent
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: colorScheme.primary,
                                )
                              : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                          onTap: () async {
                            HapticFeedbackUtil.light();
                            Navigator.pop(context);
                            await local.switchProfile(p.id);
                            if (context.mounted) {
                              AppToast.show(context, '已切换至 ${p.name}');
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建匿名账户'),
                    onPressed: () async {
                      Navigator.pop(context);
                      await _showCreateAccountDialog(context, widget.api);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 弹出新建匿名账户对话框
Future<void> _showCreateAccountDialog(
  BuildContext context,
  CoolapkApi api,
) async {
  final nameController = TextEditingController(
    text: '匿名账户${api.localAccount.profiles.length + 1}',
  );
  final uidController = TextEditingController();

  final created = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建匿名账户'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '账户名称',
              hintText: '例如：匿名账户1、刷机测试',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: uidController,
            maxLength: 30,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '用户 UID（选填）',
              hintText: '可选填酷安数字 UID 绑定公开主页',
              prefixIcon: Icon(Icons.cloud_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('创建并进入'),
        ),
      ],
    ),
  );

  if (created == true && context.mounted) {
    final name = nameController.text.trim();
    final uid = uidController.text.trim();
    Map<String, dynamic>? publicIdentity;

    if (uid.isNotEmpty) {
      try {
        final responses = await Future.wait([
          api.getUserSpace(uid),
          api.getUserProfile(uid).catchError((_) => <String, dynamic>{}),
        ]);
        final spaceResponse = responses.first;
        final profileResponse = responses.last;
        final spaceData = spaceResponse['data'];
        final profileData = profileResponse['data'];
        final spaceUser = spaceData is Map
            ? (spaceData['userInfo'] ?? spaceData['user_info'])
            : null;
        final profileUser = profileData is Map
            ? (profileData['userInfo'] ?? profileData['user_info'])
            : null;
        final data = <String, dynamic>{
          if (spaceUser is Map) ...Map<String, dynamic>.from(spaceUser),
          if (profileUser is Map) ...Map<String, dynamic>.from(profileUser),
          if (spaceData is Map) ...Map<String, dynamic>.from(spaceData),
          if (profileData is Map) ...Map<String, dynamic>.from(profileData),
          ...spaceResponse,
        };
        final username =
            '${data['username'] ?? data['userName'] ?? data['name'] ?? ''}'
                .trim();
        if (username.isNotEmpty) {
          publicIdentity = {
            'uid': uid,
            'username': username,
            'userAvatar':
                '${data['userAvatar'] ?? data['avatar'] ?? data['user_avatar'] ?? ''}',
          };
        }
      } catch (_) {
        // UID lookup failed or offline; leave publicIdentity null
      }
    }

    final newProfile = await api.localAccount.createProfile(
      name: name,
      publicIdentity: publicIdentity,
      switchNow: true,
    );
    if (context.mounted) {
      AppToast.show(context, '已创建并切换至 ${newProfile.name}');
    }
  }
}

/// 匿名账户完整管理页面
class AnonymousAccountsPage extends StatefulWidget {
  const AnonymousAccountsPage({required this.api, super.key});

  final CoolapkApi api;

  @override
  State<AnonymousAccountsPage> createState() => _AnonymousAccountsPageState();
}

class _AnonymousAccountsPageState extends State<AnonymousAccountsPage> {
  Future<void> _deleteAccount(AnonymousProfile profile) async {
    final local = widget.api.localAccount;
    final isLast = local.profiles.length <= 1;

    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${profile.name}？'),
        content: Text(
          isLast
              ? '当前仅剩一个匿名账户，删除后将重置为全新的空账户。确定重置吗？'
              : '删除后，该匿名账户独立的关注、收藏与主页资料将无法恢复。确定删除吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isLast ? '重置账户' : '删除账户'),
          ),
        ],
      ),
    );

    if (sure == true && mounted) {
      await local.deleteProfile(profile.id);
      if (mounted) {
        AppToast.show(context, isLast ? '已重置匿名账户' : '已删除账户 ${profile.name}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final local = widget.api.localAccount;

    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('匿名账户管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建匿名账户',
            onPressed: () => _showCreateAccountDialog(context, widget.api),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: local,
        builder: (context, _) {
          final profiles = local.profiles;
          final activeId = local.activeProfileId;
          final isAnonymousActive = widget.api.isAnonymous;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '支持同时保留多个匿名账户，每个账户拥有独立的 UID 身份、关注列表、收藏列表及设备关注，互不影响；退出登录不会删除资料。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '已有账户 (${profiles.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              for (final p in profiles) ...[
                Builder(
                  builder: (context) {
                    final isCurrent = isAnonymousActive && p.id == activeId;
                    final uid = p.publicIdentity?['uid'] as String?;

                    return ReviewCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: isCurrent
                          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: LocalAvatar(
                            avatar: p.avatar,
                            name: p.name,
                            radius: 24,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '当前使用',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                uid != null
                                    ? '绑定公开 UID: $uid (${p.publicIdentity?['username'] ?? ''})'
                                    : '纯本地匿名账户（未绑定公开主页）',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '关注: ${p.follows.length} · 收藏: ${p.favorites.length} · 机型关注: ${p.productFollows.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: '账户操作',
                            onSelected: (val) async {
                              if (val == 'switch') {
                                HapticFeedbackUtil.light();
                                await local.switchProfile(p.id);
                                if (context.mounted) {
                                  AppToast.show(context, '已切换至 ${p.name}');
                                }
                              } else if (val == 'edit') {
                                if (p.id != local.activeProfileId) {
                                  await local.switchProfile(p.id);
                                }
                                if (context.mounted) {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          LocalProfilePage(api: widget.api),
                                    ),
                                  );
                                }
                              } else if (val == 'delete') {
                                await _deleteAccount(p);
                              }
                            },
                            itemBuilder: (ctx) => [
                              if (!isCurrent)
                                const PopupMenuItem(
                                  value: 'switch',
                                  child: Row(
                                    children: [
                                      Icon(Icons.swap_horiz_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('切换登录此账户'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('编辑名称与主页UID'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded,
                                        size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('删除此账户',
                                        style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            if (!isCurrent) {
                              HapticFeedbackUtil.light();
                              await local.switchProfile(p.id);
                              if (context.mounted) {
                                AppToast.show(context, '已切换至 ${p.name}');
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('新建匿名账户'),
                onPressed: () => _showCreateAccountDialog(context, widget.api),
              ),
            ],
          );
        },
      ),
    );
  }
}
