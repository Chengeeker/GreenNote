import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/widgets/app_avatar.dart';
import '../shared/community_ui.dart';

class OfficialProfilePage extends StatefulWidget {
  const OfficialProfilePage({super.key, required this.api});
  final CoolapkApi api;
  @override
  State<OfficialProfilePage> createState() => _OfficialProfilePageState();
}

class _OfficialProfilePageState extends State<OfficialProfilePage> {
  Map<String, dynamic>? _data;
  String? _error;
  final _drafts = <String, String>{};
  late final String _session;
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
    if (widget.api.hasCookie) _load();
  }

  Future<void> _load() async {
    try {
      final root = communityData(
        await widget.api.getUserProfile(widget.api.currentUid),
      );
      final data = root['userInfo'] is Map
          ? communityMap(root['userInfo'])
          : root;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '读取个人资料失败，点击重试');
    }
  }

  Future<void> _field(String key, String title, String old) async {
    final values = await editCommunityFields(
      context,
      '修改$title',
      {'内容': _drafts[key] ?? old},
      limits: {'内容': key == 'bio' ? 60 : 100},
    );
    if (values == null) return;
    _drafts[key] = values['内容']!;
    await communityRequest(
      widget.api,
      _session,
      '/v6/account/changeProfile',
      method: 'POST',
      body: {'key': key, 'value': values['内容']},
    );
    _drafts.remove(key);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: const Text('酷安个人资料')),
    body: !widget.api.hasCookie
        ? const Center(child: Text('请先使用酷安官方 Cookie 登录'))
        : _data == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : TextButton(onPressed: _load, child: Text(_error!)),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: AppAvatar(
                  url: communityText(_data!, ['userAvatar', 'avatar']),
                  api: widget.api,
                  size: 96,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: CommunityAction(
                  api: widget.api,
                  label: '更换头像',
                  icon: Icons.photo_outlined,
                  action: () async {
                    final bytes = await const MethodChannel(
                      'com.green.note/avatar',
                    ).invokeMethod<Uint8List>('pick');
                    if (bytes == null || !mounted) return;
                    if (!await confirmCommunityAction(
                      this.context,
                      '更换官方账号头像？',
                      '所选图片将上传到酷安并替换你的账号头像。',
                    )) {
                      return;
                    }
                    await widget.api.officialMultipart(
                      '/v6/account/changeAvatar',
                      avatar: bytes,
                      expectedScope: _session,
                    );
                    await _load();
                  },
                ),
              ),
              ListTile(
                title: const Text('昵称'),
                subtitle: Text(communityText(_data!, ['username'])),
              ),
              ListTile(
                title: const Text('UID'),
                subtitle: Text(widget.api.currentUid),
              ),
              const Divider(),
              ListTile(
                title: const Text('个性签名'),
                subtitle: Text(communityText(_data!, ['bio', 'intro'])),
              ),
              CommunityAction(
                api: widget.api,
                label: '修改签名',
                icon: Icons.edit_outlined,
                action: () => _field(
                  'bio',
                  '签名',
                  communityText(_data!, ['bio', 'intro']),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '性别：${switch ('${_data!['gender']}') {
                  '1' => '男',
                  '0' => '女',
                  _ => '未设置',
                }}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {'1': '男', '0': '女'}.entries)
                    CommunityAction(
                      api: widget.api,
                      label: '设为${entry.value}',
                      icon: Icons.person_outline,
                      action: () async {
                        await communityRequest(
                          widget.api,
                          _session,
                          '/v6/account/changeProfile',
                          method: 'POST',
                          body: {'key': 'gender', 'value': entry.key},
                        );
                        await _load();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('修改直接保存到酷安官方账号，不影响本机匿名资料。'),
              if (_error != null)
                TextButton(onPressed: _load, child: Text(_error!)),
            ],
          ),
  );
}
