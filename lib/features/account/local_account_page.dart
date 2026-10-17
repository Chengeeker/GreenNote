import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../feed/feed_pages.dart';
import '../shared/api_list_page.dart';
import '../shell/main_pages.dart' show CookieLoginPage;
import 'anonymous_accounts_page.dart';

Future<void> showLoginOptions(BuildContext context, CoolapkApi api) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('选择登录方式'),
            subtitle: const Text('匿名资料保留在本机，切换账号不会删除本地收藏。'),
          ),
          ListTile(
            leading: const Icon(Icons.cookie_outlined),
            title: const Text('Cookie 登录'),
            subtitle: const Text('使用酷安账号及云端功能'),
            onTap: () => Navigator.pop(context, 'cookie'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('匿名登录'),
            subtitle: const Text('本地关注、收藏和 WebDAV 备份'),
            onTap: () => Navigator.pop(context, 'local'),
          ),
          if (api.localAccount.profiles.length > 1)
            ListTile(
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('切换匿名账户'),
              subtitle: Text('已有 ${api.localAccount.profiles.length} 个独立匿名账户'),
              onTap: () => Navigator.pop(context, 'switch_anon'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'cookie') {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => CookieLoginPage(api: api)));
  } else if (choice == 'switch_anon') {
    await showAnonymousAccountSwitcher(context, api);
  } else {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocalProfilePage(api: api, activate: true),
      ),
    );
  }
}

class LocalProfilePage extends StatefulWidget {
  const LocalProfilePage({required this.api, this.activate = false, super.key});
  final CoolapkApi api;
  final bool activate;
  @override
  State<LocalProfilePage> createState() => _LocalProfilePageState();
}

class _LocalProfilePageState extends State<LocalProfilePage> {
  late final _name = TextEditingController(text: widget.api.localAccount.name);
  late final _publicUid = TextEditingController(
    text: widget.api.localAccount.publicIdentity?['uid'] as String? ?? '',
  );
  late String _avatar = widget.api.localAccount.avatar;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _publicUid.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final bytes = await const MethodChannel('com.green.note/avatar')
          .invokeMethod<Uint8List>('pick');
      if (mounted && bytes != null) {
        setState(() => _avatar = base64Encode(bytes));
      }
    } catch (_) {
      if (mounted) AppToast.show(context, '无法读取头像，请选择其他图片');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final uid = _publicUid.text.trim();
      Map<String, dynamic>? publicIdentity;
      if (uid.isNotEmpty) {
        if (!RegExp(r'^\d{1,30}$').hasMatch(uid)) {
          throw const FormatException('UID 只能填写 1–30 位数字');
        }
        if (widget.activate && !widget.api.isAnonymous) {
          // Prevent a previously saved Cookie from joining this public lookup.
          await widget.api.localAccount.setActive(true);
        }
        final responses = await Future.wait([
          widget.api.getUserSpace(uid),
          widget.api.getUserProfile(uid).catchError((_) => <String, dynamic>{}),
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
        if (username.isEmpty) {
          throw const FormatException('没有读取到该 UID 的公开主页资料');
        }
        publicIdentity = {
          'uid': uid,
          'username': username,
          'userAvatar':
              '${data['userAvatar'] ?? data['avatar'] ?? data['user_avatar'] ?? ''}',
        };
      }
      await widget.api.localAccount.profile(
        _name.text,
        _avatar,
        publicIdentity: publicIdentity,
        clearPublicIdentity: uid.isEmpty,
      );
      if (widget.activate) await widget.api.localAccount.setActive(true);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: const Text('匿名账户资料'),
      actions: [
        IconButton(
          icon: const Icon(Icons.switch_account_outlined),
          tooltip: '切换/管理其他匿名账户',
          onPressed: () => showAnonymousAccountSwitcher(context, widget.api),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '用户名和头像仅在本机展示，不会创建酷安账号。可选填 UID 读取公开主页内容；'
          '这不会验证账号所有权，也不会开放云端写操作。',
        ),
        const SizedBox(height: 24),
        Center(
          child: LocalAvatar(avatar: _avatar, name: _name.text),
        ),
        TextButton(
          onPressed: _busy ? null : _pick,
          child: const Text('从设备选择头像'),
        ),
        if (_avatar.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _avatar = ''),
            child: const Text('使用默认头像'),
          ),
        TextField(
          key: const ValueKey('local-profile-name'),
          controller: _name,
          maxLength: 40,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: '用户名',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('local-profile-public-uid'),
          controller: _publicUid,
          maxLength: 30,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '用户 UID（选填）',
            helperText: '保存时读取公开资料；清空后恢复匿名资料显示。',
            prefixIcon: Icon(Icons.cloud_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? '正在保存…'
                : widget.activate
                ? '进入匿名账户'
                : '保存资料',
          ),
        ),
      ],
    ),
  );
}

class LocalAvatar extends StatelessWidget {
  const LocalAvatar({
    required this.avatar,
    required this.name,
    this.radius = 30,
    super.key,
  });
  final String avatar;
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundImage: avatar.isEmpty ? null : MemoryImage(base64Decode(avatar)),
    child: avatar.isEmpty ? Text(name.characters.firstOrNull ?? '匿') : null,
  );
}

class LocalLibraryPage extends StatelessWidget {
  const LocalLibraryPage({
    required this.api,
    this.follows = false,
    this.showAppBar = true,
    super.key,
  });
  final CoolapkApi api;
  final bool follows;
  final bool showAppBar;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showAppBar
        ? ReviewFrostedAppBar(title: Text(follows ? '本地关注' : '本地收藏'))
        : null,
    body: ListenableBuilder(
      listenable: api.localAccount,
      builder: (context, _) {
        final items =
            (follows ? api.localAccount.follows : api.localAccount.favorites)
                .entries
                .toList()
                .reversed
                .toList();
        if (items.isEmpty) {
          return Center(
            child: Text(follows ? '在博主主页点击关注，即可加入这里' : '在动态详情点击收藏，即可加入这里'),
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final entry = items[index];
            final item = Map<String, dynamic>.from(entry.value as Map);
            return ListTile(
              leading: AppAvatar(
                url: item['userAvatar'] as String?,
                name: '${item['username'] ?? ''}',
                api: api,
              ),
              title: Text(
                '${item[follows ? 'username' : 'message'] ?? entry.key}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: follows
                  ? Text('UID ${entry.key}')
                  : Text('${item['username'] ?? ''} · 已保存文字及图片地址'),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => follows
                      ? UserSpacePage(api: api, uid: entry.key)
                      : FeedDetailPage(
                          api: api,
                          feed: CoolapkFeed.fromJson(item),
                        ),
                ),
              ),
              trailing: IconButton(
                tooltip: follows ? '取消本地关注' : '移除本地收藏',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () async {
                  try {
                    await api.localAccount.toggle(
                      follows ? 'follows' : 'favorites',
                      entry.key,
                      item,
                    );
                  } catch (error) {
                    if (context.mounted) {
                      AppToast.show(context, error.toString());
                    }
                  }
                },
              ),
            );
          },
        );
      },
    ),
  );
}
