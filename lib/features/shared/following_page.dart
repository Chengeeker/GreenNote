import 'package:flutter/material.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../shell/main_pages.dart' show MessageChatPage;
import 'api_list_page.dart';
import 'community_ui.dart';
import 'home_destination_page.dart' show officialHomeTheme;

Map<String, dynamic> relationUser(
  Map<String, dynamic> row, {
  bool fans = false,
}) {
  final user = communityMap(
    fans ? row['userInfo'] : row['fUserInfo'] ?? row['userInfo'],
  );
  return {
    ...row,
    ...user,
    'uid': user['uid'] ?? (fans ? row['uid'] : row['fuid'] ?? row['uid']),
    'username':
        user['username'] ??
        user['displayUsername'] ??
        user['displayUserName'] ??
        (fans ? row['username'] : row['fusername'] ?? row['username']),
    'userAvatar':
        user['userAvatar'] ??
        user['avatar'] ??
        (fans ? row['userAvatar'] : row['fUserAvatar'] ?? row['userAvatar']),
  };
}

Map<String, dynamic> relationQuery(String uid, int tab) => {
  'uid': uid,
  if (tab == 0) ...{'isSpecialFollow': -1, 'isFriend': 0},
  if (tab == 1) 'isSpecialFollow': 1,
  if (tab == 2) 'isFriend': 1,
};

class CoolFriendListPage extends StatefulWidget {
  const CoolFriendListPage({
    super.key,
    required this.api,
    required this.uid,
    this.initialTab = 0,
  });
  final CoolapkApi api;
  final String uid;
  final int initialTab;
  @override
  State<CoolFriendListPage> createState() => _CoolFriendListPageState();
}

class _CoolFriendListPageState extends State<CoolFriendListPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  late final String _session;
  int _revision = 0;
  bool _writing = false;
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
    _tabs.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_changed);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _manage(String action, Map<String, dynamic> user) async {
    if (_writing) return;
    final uid = communityText(user, ['uid']);
    if (uid.isEmpty) return;
    final special = communityFlag(user['isSpecialFollow']);
    if (action == 'unfollow' &&
        !await confirmCommunityAction(context, '取消关注？', '将不再关注这位酷友。')) {
      return;
    }
    _writing = true;
    try {
      await communityRequest(
        widget.api,
        _session,
        action == 'special'
            ? '/v6/user/specialFollowUser'
            : '/v6/user/unfollow',
        method: action == 'special' ? 'POST' : 'GET',
        query: {
          'uid': uid,
          if (action == 'special') 'special': special ? 0 : 1,
        },
      );
      if (mounted) setState(() => _revision++);
    } catch (error) {
      if (mounted) AppToast.show(context, '$error');
    } finally {
      _writing = false;
    }
  }

  Widget _row(BuildContext context, Map<String, dynamic> raw) {
    final user = relationUser(raw, fans: _tabs.index == 3);
    final uid = communityText(user, ['uid']);
    final scheme = Theme.of(context).colorScheme;
    final active = communityText(user, [
      'lastlogin_text',
      'lastLoginText',
      'activeTime',
      'active_time_text',
    ]);
    final last = communityText(user, ['lastlogin', 'lastLogin', 'logintime']);
    final activity = active.isNotEmpty
        ? active
        : last.isEmpty
        ? ''
        : '${formatRelativeTime(last)}活跃';
    final bio = communityText(user, ['bio', 'signature', 'description']);
    final owner = widget.uid == widget.api.currentUid && widget.api.hasCookie;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: uid.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserSpacePage(api: widget.api, uid: uid),
                    ),
                  ),
            child: AppAvatar(
              api: widget.api,
              url: communityText(user, ['userAvatar']),
              size: 44,
              verified: communityFlag(user['verify_status']),
              verifiedType: int.tryParse('${user['verify_show_type']}') ?? 0,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: uid.isEmpty
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UserSpacePage(api: widget.api, uid: uid),
                      ),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    communityText(user, ['username']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (user['follow'] != null || user['follow_num'] != null)
                        '${user['follow'] ?? user['follow_num']}关注',
                      if (user['fans'] != null || user['fans_num'] != null)
                        '${user['fans'] ?? user['fans_num']}粉丝',
                      if (activity.isNotEmpty) activity,
                    ].join('  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 30),
              tapTargetSize: MaterialTapTargetSize.padded,
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: uid.isEmpty
                ? null
                : () {
                    if (!widget.api.hasCookie ||
                        widget.api.notificationSessionKey != _session) {
                      AppToast.show(context, '请先使用酷安账号登录');
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MessageChatPage(
                          api: widget.api,
                          uid: uid,
                          ukey: '',
                          username: communityText(user, ['username']),
                          avatar: communityText(user, ['userAvatar']),
                        ),
                      ),
                    );
                  },
            child: const Text('私信', style: TextStyle(fontSize: 14)),
          ),
          if (owner && _tabs.index != 3)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
              tooltip: '更多关注操作',
              onSelected: (value) => _manage(value, user),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'special',
                  child: Text(
                    communityFlag(user['isSpecialFollow'])
                        ? '取消特别关注'
                        : '设为特别关注',
                  ),
                ),
                const PopupMenuItem(value: 'unfollow', child: Text('取消关注')),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: officialHomeTheme(Theme.of(context)),
    child: Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : null,
      appBar: ReviewFrostedAppBar(
        title: const Text('酷友列表'),
        leading: const BackButton(),
        showBottomBorder: false,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : null,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: MediaQuery.textScalerOf(context).scale(16) > 20,
            tabAlignment: MediaQuery.textScalerOf(context).scale(16) > 20
                ? TabAlignment.start
                : TabAlignment.fill,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 16),
            indicatorSize: TabBarIndicatorSize.label,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: Color(0xFF009688), width: 3),
              insets: EdgeInsets.symmetric(horizontal: 12),
            ),
            tabs: [
              for (final title in ['关注', '特别关注', '互相关注', '粉丝'])
                Tab(text: title),
            ],
          ),
          Expanded(
            child: ApiListPage(
              key: ValueKey('${_tabs.index}:$_revision'),
              api: widget.api,
              title: '酷友列表',
              path: _tabs.index == 3
                  ? '/v6/user/fansList'
                  : '/v6/user/followList',
              query: relationQuery(widget.uid, _tabs.index),
              showAppBar: false,
              showAccessErrors: true,
              itemBuilder: _row,
            ),
          ),
        ],
      ),
    ),
  );
}

List<Map<String, dynamic>> recentFollowingUsers(
  List<Map<String, dynamic>> cards,
  List<CoolapkFeed> feeds,
) {
  final users = <Map<String, dynamic>>[];
  void visit(Map<String, dynamic> item) {
    final type = communityText(item, ['entityType']).toLowerCase();
    if (type == 'user' || type == 'user_follow') users.add(relationUser(item));
    if (item['entities'] is List) {
      for (final child in (item['entities'] as List).whereType<Map>()) {
        visit(communityMap(child));
      }
    }
  }

  for (final card in cards) {
    final title = communityText(card, ['title']);
    final template = communityText(card, ['entityTemplate']).toLowerCase();
    if (title.contains('最近更新') ||
        template.contains('userfollow') ||
        template.contains('useravatar') ||
        template == 'iconMiniScrollCard'.toLowerCase()) {
      visit(card);
    }
  }
  if (users.isEmpty) {
    final sorted = [...feeds]
      ..sort(
        (a, b) => (int.tryParse('${b.raw['dateline']}') ?? 0).compareTo(
          int.tryParse('${a.raw['dateline']}') ?? 0,
        ),
      );
    users.addAll(
      sorted.map(
        (feed) => {
          ...communityMap(feed.raw['userInfo']),
          'uid': feed.uid,
          'username': feed.username,
          'userAvatar': feed.avatar,
        },
      ),
    );
  }
  final known = <String>{};
  return users
      .where((user) {
        final id = communityText(user, ['uid']);
        return id.isNotEmpty && known.add(id);
      })
      .take(30)
      .toList();
}

bool followingAuthor(CoolapkFeed feed) =>
    communityFlag(feed.raw['isFollow']) ||
    communityFlag(communityMap(feed.raw['userInfo'])['isFollow']) ||
    communityFlag(communityMap(feed.raw['userAction'])['follow']);

String followFilterRoute(String route, String type) {
  final uri = Uri.tryParse(route);
  if (uri == null) return route;
  final params = {...uri.queryParameters}..remove('type');
  return uri
      .replace(queryParameters: {...params, if (type.isNotEmpty) 'type': type})
      .toString();
}

class FollowingChannelHeader extends StatelessWidget {
  const FollowingChannelHeader({
    super.key,
    required this.api,
    required this.cards,
    required this.feeds,
    required this.selected,
    required this.onSelect,
  });
  final CoolapkApi api;
  final List<Map<String, dynamic>> cards;
  final List<CoolapkFeed> feeds;
  final String selected;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    final users = recentFollowingUsers(cards, feeds);
    final theme = officialHomeTheme(Theme.of(context));
    final scheme = theme.colorScheme;
    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF101010)
            : scheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 58,
                    child: InkWell(
                      onTap: () => onSelect(''),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: const Color(0xFF00AC86),
                            child: Icon(
                              Icons.people,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('最近更新', style: TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ),
                  for (final user in users)
                    SizedBox(
                      width: 58,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserSpacePage(
                              api: api,
                              uid: communityText(user, ['uid']),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            AppAvatar(
                              api: api,
                              url: communityText(user, ['userAvatar']),
                              size: 38,
                              verified: communityFlag(user['verify_status']),
                              verifiedType:
                                  int.tryParse('${user['verify_show_type']}') ??
                                  0,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              communityText(user, ['username']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (recentFollowingUsers(cards, const []).isEmpty &&
                users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 1, bottom: 2),
                child: Text(
                  '按已加载动态的发布时间排序',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
              child: Row(
                children: [
                  for (final entry in const {
                    '': '全部',
                    'circle': '好友关注',
                    'topic': '话题关注',
                    'product': '数码关注',
                    'apk': '应用关注',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        labelPadding: EdgeInsets.zero,
                        label: Text(entry.value),
                        selected: selected == entry.key,
                        selectedColor: theme.brightness == Brightness.dark
                            ? const Color(0xFF1E1E1E)
                            : scheme.primaryContainer,
                        backgroundColor: theme.brightness == Brightness.dark
                            ? const Color(0xFF1E1E1E)
                            : scheme.surfaceContainerLow,
                        side: BorderSide(
                          color: selected == entry.key
                              ? scheme.primary
                              : Colors.transparent,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: selected == entry.key
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                        showCheckmark: false,
                        onSelected: (_) => onSelect(entry.key),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
