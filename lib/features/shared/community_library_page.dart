import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/editor_keyboard.dart';
import 'api_list_page.dart';
import 'community_ui.dart';
import 'community_detail_page.dart';
import 'following_page.dart';
import 'home_destination_page.dart' show officialHomeTheme;
import 'rating_square_page.dart';
import '../../core/utils/coolapk_url_handler.dart';

enum CommunityLibrary {
  blacklist,
  history,
  following,
  fans,
  anylist,
  dyh,
  albums,
}

class CommunityLibraryPage extends StatefulWidget {
  const CommunityLibraryPage({
    super.key,
    required this.api,
    required this.library,
    this.uid = '',
  });
  final CoolapkApi api;
  final CommunityLibrary library;
  final String uid;
  @override
  State<CommunityLibraryPage> createState() => _CommunityLibraryPageState();
}

class _CommunityLibraryPageState extends State<CommunityLibraryPage> {
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
  }

  int _tab = 0, _revision = 0;
  late final String _session;
  String _search = '';
  final _blacklistUsers = <String>{};
  final _removing = <String>{};
  int? _blacklistTotal;
  bool _blacklistMore = false;

  String get _uid => widget.uid.isEmpty ? widget.api.currentUid : widget.uid;
  List<(String, String)> get _routes => switch (widget.library) {
    CommunityLibrary.blacklist => [
      ('拉黑', '/v6/user/blackList'),
      ('屏蔽', '/v6/user/ignoreList'),
      ('限制', '/v6/user/limitList'),
    ],
    CommunityLibrary.history => [('浏览历史', '/v6/user/hitHistoryList')],
    CommunityLibrary.following => [('关注', '/v6/user/followList')],
    CommunityLibrary.fans => [('粉丝', '/v6/user/fansList')],
    CommunityLibrary.anylist => [('万物清单', '/v6/user/productAlbumList')],
    CommunityLibrary.dyh => [
      ('关注的号', '/v6/user/dyhFollowList'),
      ('订阅的号', '/v6/user/dyhSubscribe'),
      ('管理的号', '/v6/user/editorDyhList'),
    ],
    CommunityLibrary.albums => [('我的应用集', '/v6/user/albumList')],
  };
  bool get _users => [
    CommunityLibrary.blacklist,
    CommunityLibrary.following,
    CommunityLibrary.fans,
  ].contains(widget.library);
  Future<void> _removeBlacklisted(String uid) async {
    if (uid.isEmpty || _removing.contains(uid)) return;
    if (!await confirmCommunityAction(
      context,
      '移出名单？',
      '将解除对该用户的${_tab == 0 ? '拉黑' : '屏蔽'}。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _removing.add(uid));
    try {
      await communityRequest(
        widget.api,
        _session,
        _tab == 0
            ? '/v6/user/removeFromBlackList'
            : '/v6/user/removeFromIgnoreList',
        query: {'uid': uid},
      );
      if (mounted) {
        setState(() {
          _blacklistUsers.remove(uid);
          if (_blacklistTotal != null && _blacklistTotal! > 0) {
            _blacklistTotal = _blacklistTotal! - 1;
          }
          _revision++;
        });
      }
    } catch (_) {
      if (mounted) AppToast.show(context, '操作失败，请确认登录有效、网络正常后重试');
    } finally {
      if (mounted) setState(() => _removing.remove(uid));
    }
  }

  Widget _blacklist(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ['黑名单管理', '屏蔽管理', '限制名单'];
    final count =
        _blacklistTotal?.toString() ??
        '${_blacklistUsers.length}${_blacklistMore ? '+' : ''}';
    return Theme(
      data: officialHomeTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: dark ? const Color(0xFF101010) : null,
        appBar: ReviewFrostedAppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${labels[_tab]}${_tab == 0 ? ' ($count/500)' : ' ($count)'}',
            ),
          ),
          leading: const BackButton(),
          showBottomBorder: false,
          backgroundColor: dark ? const Color(0xFF1E1E1E) : null,
          actions: [
            PopupMenuButton<int>(
              tooltip: '切换名单',
              itemBuilder: (_) => [
                for (final entry in labels.indexed)
                  PopupMenuItem(value: entry.$1, child: Text(entry.$2)),
              ],
              onSelected: (tab) => setState(() {
                _tab = tab;
                _blacklistUsers.clear();
                _blacklistTotal = null;
                _blacklistMore = false;
              }),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: ColoredBox(
              color: dark
                  ? const Color(0xFF1E1E1E)
                  : Theme.of(context).colorScheme.surface,
              child: ApiListPage(
                key: ValueKey('blacklist:$_tab:$_revision'),
                api: widget.api,
                title: labels[_tab],
                path: _routes[_tab].$2,
                query: {'uid': _uid},
                showAppBar: false,
                onPageLoaded: (page) {
                  if (!mounted) return;
                  setState(() {
                    if (page.page == 1) _blacklistUsers.clear();
                    _blacklistUsers.addAll(
                      page.items
                          .map((item) => communityText(item, ['uid', 'id']))
                          .where((uid) => uid.isNotEmpty),
                    );
                    _blacklistTotal = page.total ?? _blacklistTotal;
                    _blacklistMore = page.hasMore;
                  });
                },
                itemBuilder: (context, data) {
                  final user = communityMap(data['userInfo']);
                  final uid = communityText(data, ['uid', 'id']);
                  final name =
                      communityText(data, ['username', 'title']).isEmpty
                      ? communityText(user, ['username'])
                      : communityText(data, ['username', 'title']);
                  final avatar =
                      communityText(data, ['userAvatar', 'avatar']).isEmpty
                      ? communityText(user, ['userAvatar'])
                      : communityText(data, ['userAvatar', 'avatar']);
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: uid.isEmpty
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserSpacePage(
                                      api: widget.api,
                                      uid: uid,
                                    ),
                                  ),
                                ),
                          child: AppAvatar(
                            api: widget.api,
                            url: avatar,
                            name: name,
                            size: 44,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                        if (_tab < 2) ...[
                          const SizedBox(width: 12),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF009688),
                              side: const BorderSide(color: Color(0xFF009688)),
                              minimumSize: const Size(60, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              visualDensity: VisualDensity.compact,
                              shape: const StadiumBorder(),
                            ),
                            onPressed: _removing.contains(uid)
                                ? null
                                : () => _removeBlacklisted(uid),
                            child: Text(_removing.contains(uid) ? '处理中' : '取消'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _user(BuildContext context, Map<String, dynamic> data) {
    final uid = communityText(data, ['uid', 'id']);
    final name = communityText(data, ['username', 'title']);
    final info = communityMap(data['userInfo']);
    final canRemove = widget.library == CommunityLibrary.blacklist && _tab < 2;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AppAvatar(
            api: widget.api,
            url: communityText(data, ['userAvatar', 'avatar']).isEmpty
                ? communityText(info, ['userAvatar'])
                : communityText(data, ['userAvatar', 'avatar']),
            size: 48,
          ),
          const SizedBox(width: 12),
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
                    name.isEmpty ? communityText(info, ['username']) : name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(communityText(data, ['bio', 'description', 'intro'])),
                ],
              ),
            ),
          ),
          if (canRemove)
            CommunityAction(
              api: widget.api,
              label: '移出',
              icon: Icons.remove_circle_outline,
              action: () async {
                if (!await confirmCommunityAction(
                  context,
                  '移出名单？',
                  '将解除对该用户的${_tab == 0 ? '拉黑' : '屏蔽'}。',
                )) {
                  return;
                }
                await communityRequest(
                  widget.api,
                  _session,
                  _tab == 0
                      ? '/v6/user/removeFromBlackList'
                      : '/v6/user/removeFromIgnoreList',
                  query: {'uid': uid},
                );
                if (mounted) setState(() => _revision++);
              },
            ),
          if (widget.library == CommunityLibrary.following &&
              widget.api.hasCookie &&
              uid != widget.api.currentUid)
            CommunityAction(
              api: widget.api,
              label: '取消关注',
              icon: Icons.person_remove_outlined,
              action: () async {
                if (!await confirmCommunityAction(
                  context,
                  '取消关注？',
                  '将不再关注这位酷友。',
                )) {
                  return;
                }
                if (widget.api.notificationSessionKey != _session ||
                    !await widget.api.notificationSessionMatches(_session)) {
                  throw StateError('Account changed');
                }
                await widget.api.followUser(uid, following: true);
                if (mounted) setState(() => _revision++);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.library == CommunityLibrary.blacklist) {
      return _blacklist(context);
    }
    if (widget.library == CommunityLibrary.following ||
        widget.library == CommunityLibrary.fans) {
      return CoolFriendListPage(
        api: widget.api,
        uid: _uid,
        initialTab: widget.library == CommunityLibrary.fans ? 3 : 0,
      );
    }
    final routes = _routes;
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: Text(switch (widget.library) {
          CommunityLibrary.blacklist => '屏蔽与黑名单',
          CommunityLibrary.dyh => '我的看看号',
          _ => routes.first.$1,
        }),
      ),
      floatingActionButton: widget.library == CommunityLibrary.anylist
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('创建清单'),
              onPressed: () async {
                if (!widget.api.hasCookie) {
                  AppToast.show(context, '请先使用酷安账号登录');
                  return;
                }
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnyListCreatePage(api: widget.api),
                  ),
                );
                if (created == true && mounted) setState(() => _revision++);
              },
            )
          : null,
      body: Column(
        children: [
          if (routes.length > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final entry in routes.indexed)
                    ChoiceChip(
                      label: Text(entry.$2.$1),
                      selected: _tab == entry.$1,
                      onSelected: (_) => setState(() => _tab = entry.$1),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: widget.library == CommunityLibrary.history
                ? SearchBar(
                    hintText: '筛选已加载内容',
                    leading: const Icon(Icons.search_rounded),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) =>
                        setState(() => _search = value.trim()),
                  )
                : TextFormField(
                    decoration: const InputDecoration(
                      labelText: '筛选已加载内容',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onFieldSubmitted: (value) =>
                        setState(() => _search = value.trim()),
                  ),
          ),
          Expanded(
            child: ApiListPage(
              key: ValueKey('$_tab:$_revision:$_search'),
              api: widget.api,
              title: routes[_tab].$1,
              path: routes[_tab].$2,
              query: {
                'uid': _uid,
                if (widget.library == CommunityLibrary.history) 'type': 'feed',
              },
              showAppBar: false,
              showAccessErrors: true,
              itemFilter: _search.isEmpty
                  ? null
                  : (item) =>
                        jsonEncode(item)
                            .toLowerCase()
                            .contains(_search.toLowerCase()),
              itemBuilder: widget.library == CommunityLibrary.history
                  ? (context, item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatRelativeTime(
                                    '${item['dateline'] ?? item['lastupdate'] ?? ''}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if ('${item['entityType']}'.toLowerCase() ==
                              'history')
                            ListTile(
                              title: Text(
                                communityText(item, ['title', 'name']),
                              ),
                              subtitle: Text(
                                communityText(item, [
                                  'subTitle',
                                  'description',
                                ]),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => CoolapkUrlHandler.handleUrl(
                                context,
                                widget.api,
                                communityText(item, ['url']),
                              ),
                            )
                          else
                            ApiEntityCard(api: widget.api, entity: item),
                        ],
                      ),
                    )
                  : _users
                  ? _user
                  : widget.library == CommunityLibrary.anylist ||
                        widget.library == CommunityLibrary.dyh ||
                        widget.library == CommunityLibrary.albums
                  ? (context, item) => ListTile(
                      title: Text(communityText(item, ['title', 'name'])),
                      subtitle: Text(
                        communityText(item, ['description', 'intro']),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommunityDetailPage(
                            api: widget.api,
                            id: communityText(item, ['id', 'entityId']),
                            initial: item,
                            kind: widget.library == CommunityLibrary.anylist
                                ? CommunityKind.anylist
                                : widget.library == CommunityLibrary.dyh
                                ? CommunityKind.dyh
                                : CommunityKind.album,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> productAlbumForm(
  String title,
  String description,
  List<Map<String, String>> items, {
  bool ranked = false,
  String targetType = '',
  String targetId = '',
}) {
  if (title.trim().isEmpty ||
      title.length > 100 ||
      description.length > 1000 ||
      items.length > 100 ||
      items.any(
        (item) =>
            (item['item_name']?.trim().isEmpty ?? true) ||
            (item['item_name']?.length ?? 0) > 100 ||
            (ranked && !RegExp(r'^[1-5]$').hasMatch(item['level'] ?? '1')) ||
            (item['item_description']?.length ?? 0) > 1000,
      )) {
    throw const FormatException('清单内容无效');
  }
  return {
    'title': title.trim(),
    'description': description.trim(),
    'album_type': ranked ? 1 : 0,
    'targetType': targetType,
    'targetId': targetId,
    for (final entry in items.indexed)
      for (final field in {
        ...entry.$2,
        'id': '',
        'level': ranked ? entry.$2['level'] ?? '1' : '1',
        'display_order': '${entry.$1}',
      }.entries)
        'productItems[${entry.$1}][${field.key}]': field.value,
  };
}

class AnyListCreatePage extends StatefulWidget {
  const AnyListCreatePage({
    super.key,
    required this.api,
    this.initialRank = false,
  });
  final CoolapkApi api;
  final bool initialRank;
  @override
  State<AnyListCreatePage> createState() => _AnyListCreatePageState();
}

class _AnyListCreatePageState extends State<AnyListCreatePage> {
  final _title = TextEditingController(),
      _description = TextEditingController();
  final _items = <Map<String, String>>[];
  bool _busy = false;
  late bool _ranked = widget.initialRank;
  Map<String, dynamic>? _target;
  late final String _session;
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
    _title.addListener(_changed);
    _description.addListener(_changed);
    _draftFlags = (_canCreate, _hasDraft);
  }

  late (bool, bool) _draftFlags;
  bool get _canCreate => _title.text.trim().isNotEmpty && _items.isNotEmpty;
  void _changed() {
    final flags = (_canCreate, _hasDraft);
    if (flags != _draftFlags) setState(() => _draftFlags = flags);
  }

  bool get _hasDraft =>
      _title.text.isNotEmpty ||
      _description.text.isNotEmpty ||
      _items.isNotEmpty ||
      _target != null;

  Future<void> _close() async {
    if (_busy) return;
    if (_hasDraft &&
        !await confirmCommunityAction(context, '放弃编辑？', '退出后已输入的内容将不会被保存。')) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _selectItem([int level = 1]) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('从数码库选择产品'),
              leading: const Icon(Icons.devices),
              onTap: () => Navigator.pop(ctx, 'library'),
            ),
            ListTile(
              title: const Text('自定义产品'),
              leading: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    if (source == 'custom') {
      final count = _items.length;
      await _item();
      if (mounted && _items.length > count) {
        setState(() => _items.last['level'] = '$level');
      }
      return;
    }
    final product = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RatingSquarePage(api: widget.api, selectOnly: true),
      ),
    );
    if (!mounted || product == null) return;
    setState(
      () => _items.add({
        'item_id': '${product['id']}',
        'item_name': '${product['title']}',
        'item_description': '',
        'item_logo': '${product['logo'] ?? ''}',
        'item_images': '',
        'level': '$level',
      }),
    );
  }

  Future<void> _chooseTarget() async {
    final target = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RatingSquarePage(api: widget.api, selectOnly: true),
      ),
    );
    if (mounted && target != null) setState(() => _target = target);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _item([int? index]) async {
    final values = await editCommunityFields(
      context,
      '清单商品',
      {
        '名称': index == null ? '' : _items[index]['item_name']!,
        '说明': index == null ? '' : _items[index]['item_description']!,
      },
      limits: {'名称': 100},
    );
    if (values == null || !mounted) return;
    final value = {
      if (index != null) ..._items[index],
      'item_id': index == null ? '' : _items[index]['item_id'] ?? '',
      'item_name': values['名称']!,
      'item_description': values['说明']!,
      'item_logo': index == null ? '' : _items[index]['item_logo'] ?? '',
      'item_images': index == null ? '' : _items[index]['item_images'] ?? '',
    };
    setState(() {
      if (index == null) {
        _items.add(value);
      } else {
        _items[index] = value;
      }
    });
  }

  Future<void> _save() async {
    if (!widget.api.hasCookie || _title.text.trim().isEmpty) {
      AppToast.show(context, '请使用官方账号登录并填写标题');
      return;
    }
    if (!await confirmCommunityAction(context, '发布清单？', '清单将发布到你的酷安账号。')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await communityRequest(
        widget.api,
        _session,
        '/v6/productAlbum/create',
        method: 'POST',
        body: productAlbumForm(
          _title.text,
          _description.text,
          _items,
          ranked: _ranked,
          targetType: _target == null
              ? ''
              : _target!['entityType'] == 'product'
              ? 'product_phone'
              : 'tag',
          targetId: '${_target?['id'] ?? ''}',
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppToast.show(context, '发布失败，已保留填写内容');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _addCard({int? level, String label = '', Color? color}) => InkWell(
    onTap: _busy || _items.length >= 100 ? null : () => _selectItem(level ?? 1),
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(
          color:
              color ?? Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (level != null)
              Container(
                width: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(7),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2B2B2D)
                            : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 30,
                        color: Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('添加产品', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 4),
                          const Text(
                            '支持从数码库选择产品或自定义产品',
                            style: TextStyle(fontSize: 12),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _itemRow(int index) => ListTile(
    title: Text(_items[index]['item_name']!),
    subtitle: Text(_items[index]['item_description']!),
    onTap: _busy ? null : () => _item(index),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0)
          IconButton(
            tooltip: '上移',
            icon: const Icon(Icons.arrow_upward),
            onPressed: _busy
                ? null
                : () => setState(() {
                    final item = _items.removeAt(index);
                    _items.insert(index - 1, item);
                  }),
          ),
        IconButton(
          tooltip: '移除商品',
          icon: const Icon(Icons.close),
          onPressed: _busy
              ? null
              : () => setState(() => _items.removeAt(index)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    _draftFlags = (_canCreate, _hasDraft);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = _ranked ? '天梯榜' : '清单';
    return Theme(
      data: officialHomeTheme(Theme.of(context)),
      child: PopScope(
        canPop: !_hasDraft && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            maintainBottomViewPadding: true,
            child: Column(
              children: [
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor
                            .withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '关闭',
                        onPressed: _busy ? null : _close,
                        icon: const Icon(Icons.close, size: 26),
                      ),
                      const Spacer(),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xFF333335)
                              : const Color(0xFFECECEC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            for (final (rank, title) in [
                              (false, '清单'),
                              (true, '天梯榜'),
                            ])
                              InkWell(
                                onTap: _busy
                                    ? null
                                    : () => setState(() => _ranked = rank),
                                child: Container(
                                  width: 74,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _ranked == rank
                                        ? dark
                                              ? const Color(0xFF1E1E1E)
                                              : Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: _ranked == rank
                                          ? const Color(0xFF009688)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: OutlinedButton(
                          onPressed:
                              _busy ||
                                  _title.text.trim().isEmpty ||
                                  _items.isEmpty
                              ? null
                              : _save,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(56, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          child: Text(
                            _busy ? '创建中' : '创建',
                            style: const TextStyle(fontWeight: FontWeight.w400),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      InkWell(
                        onTap: _busy ? null : _chooseTarget,
                        child: Container(
                          height: 56,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF009688)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Color(0xFF009688),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text('发布到', style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${_target?['title'] ?? '选择合适的板块会有更多的赞'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Builder(
                          builder: (fieldContext) => TextField(
                            scrollPadding: editorKeyboardScrollPadding(
                              fieldContext,
                            ),
                            key: const ValueKey('album-title'),
                            controller: _title,
                            maxLength: 100,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: '$name标题',
                              counterText: '',
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Builder(
                          builder: (fieldContext) => TextField(
                            scrollPadding: editorKeyboardScrollPadding(
                              fieldContext,
                            ),
                            key: const ValueKey('album-description'),
                            controller: _description,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 200,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: '介绍下你的$name，最多200字',
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: const EdgeInsets.only(top: 10),
                            ),
                          ),
                        ),
                      ),
                      if (!_ranked) ...[
                        for (var i = 0; i < _items.length; i++) _itemRow(i),
                        _addCard(),
                      ] else
                        for (final (level, label, color) in [
                          (5, '夯', const Color(0xFFFF5257)),
                          (4, '顶\n级', const Color(0xFFFF9800)),
                          (3, '人\n上\n人', const Color(0xFFFFC107)),
                          (2, 'N\nP\nC', const Color(0xFF8BC34A)),
                          (1, '拉', const Color(0xFF9E9E9E)),
                        ]) ...[
                          for (var i = 0; i < _items.length; i++)
                            if ((_items[i]['level'] ?? '1') == '$level')
                              _itemRow(i),
                          _addCard(level: level, label: label, color: color),
                        ],
                      const EditorKeyboardSpace(),
                    ],
                  ),
                ),
                if (!_ranked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 38, top: 12),
                    child: FilledButton.icon(
                      onPressed: _busy || _items.length >= 100
                          ? null
                          : _selectItem,
                      icon: const Icon(Icons.add_box_outlined, size: 20),
                      label: const Text(
                        '添加产品',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF009F91),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
