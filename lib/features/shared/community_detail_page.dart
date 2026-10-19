import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../feed/feed_pages.dart';
import '../feed/video_player_page.dart';
import 'api_list_page.dart';
import 'community_ui.dart';
import 'goods_ranking_body.dart';
import 'captcha_page.dart';
import 'home_destination_page.dart' show officialHomeTheme;
import 'reply_notifications_page.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/network/coolapk_image.dart';

enum CommunityKind { question, live, collection, dyh, album, goods, anylist }

class CommunityDetailPage extends StatefulWidget {
  const CommunityDetailPage({
    super.key,
    required this.api,
    required this.id,
    required this.kind,
    this.initial = const {},
  });
  final CoolapkApi api;
  final String id;
  final CommunityKind kind;
  final Map<String, dynamic> initial;
  @override
  State<CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<CommunityDetailPage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _revision = 0, _loadVersion = 0;
  late final String _session;
  int _tab = 0;
  String _sort = 'reply';
  String _search = '';
  String _answerDraft = '';
  Map<String, String>? _collectionDraft;
  bool _goodsMore = false, _goodsBusy = false;
  int _goodsPage = 1;
  String? _goodsError;
  bool _detailLoaded = false;
  CoolapkCaptchaException? _captcha;
  bool _verifying = false;
  CoolapkApi get api => widget.api;
  CommunityKind get kind => widget.kind;
  String get id => widget.id;
  String get _title => switch (kind) {
    CommunityKind.question => '问题详情',
    CommunityKind.live => '直播详情',
    CommunityKind.collection => '收藏单',
    CommunityKind.dyh => '看看号',
    CommunityKind.album => '应用集',
    CommunityKind.goods => '好物榜单',
    CommunityKind.anylist => '万物清单',
  };
  @override
  void initState() {
    super.initState();
    _session = api.notificationSessionKey;
    if (kind == CommunityKind.goods && widget.initial.isNotEmpty) {
      _data = {...widget.initial, 'id': id};
    }
    _load();
  }

  Future<void> _load({
    CoolapkCaptchaException? challenge,
    String? validate,
  }) async {
    final version = ++_loadVersion;
    setState(() {
      _error = null;
      _captcha = null;
    });
    try {
      final Map<String, dynamic> data;
      if (kind == CommunityKind.anylist) {
        data = {...widget.initial};
        try {
          data.addAll(await api.getFeedDetail(id));
        } catch (_) {
          if (data.isEmpty) rethrow;
        }
        final uid = communityText(data, ['uid']).isEmpty
            ? api.currentUid
            : communityText(data, ['uid']);
        if (uid.isNotEmpty) {
          try {
            final page = await api.getList(
              '/v6/goodsList/list',
              query: {'uid': uid, 'goodsId': id, 'page': 1},
            );
            final existing = data['productItems'] is List
                ? data['productItems'] as List
                : const [];
            data['productItems'] = [...existing, ...page.items];
            _goodsMore = page.hasMore;
            _goodsPage = 1;
            _goodsError = null;
          } catch (_) {
            _goodsError = '部分商品加载失败，点击重试';
          }
        }
      } else if ([CommunityKind.question, CommunityKind.goods].contains(kind)) {
        data =
            kind == CommunityKind.goods && challenge != null && validate != null
            ? await api.verifyFeedDetail(id, challenge, validate)
            : await api.getFeedDetail(id);
      } else {
        final path = switch (kind) {
          CommunityKind.live => '/v6/live/detail',
          CommunityKind.collection => '/v6/collection/detail',
          CommunityKind.dyh => '/v6/dyh/detail',
          _ => '/v6/album/detail',
        };
        data = communityData(
          await api.request(
            path,
            query: {kind == CommunityKind.dyh ? 'dyhId' : 'id': id},
          ),
        );
      }
      if (data.isEmpty) throw const FormatException('详情为空');
      if (mounted && version == _loadVersion) {
        setState(() {
          _data = {...widget.initial, ...data};
          _detailLoaded = true;
          _revision++;
        });
      }
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _error = error is CoolapkApiException
              ? error.toString()
              : '详情加载失败，请稍后重试';
          _captcha =
              kind == CommunityKind.goods && error is CoolapkCaptchaException
              ? error
              : null;
        });
      }
    }
  }

  Future<void> _verifyGoods() async {
    final challenge = _captcha;
    if (challenge == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      final validate = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => CoolapkCaptchaPage(challenge: challenge.challenge),
        ),
      );
      if (mounted && validate != null) {
        await _load(challenge: challenge, validate: validate);
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  bool get _hasRankingPreview {
    final data = _data ?? {};
    return communityText(data, [
          'title',
          'message_title',
          'entityTitle',
        ]).isNotEmpty ||
        communityText(communityMap(data['goodsListInfo']), [
          'title',
        ]).isNotEmpty ||
        (data['goodsListItem'] is List &&
            (data['goodsListItem'] as List).isNotEmpty);
  }

  Widget _loadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? '正在加载榜单', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (_captcha != null)
            FilledButton.icon(
              onPressed: _verifying ? null : _verifyGoods,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('完成验证并加载榜单'),
            ),
          TextButton(onPressed: _load, child: const Text('重新加载')),
        ],
      ),
    ),
  );

  bool get _owner {
    final data = _data ?? {};
    return api.hasCookie &&
        api.currentUid.isNotEmpty &&
        communityText(data, ['uid', 'userId']) == api.currentUid;
  }

  bool get _followed {
    final data = _data ?? {};
    return communityFlag(data['isFollow']) ||
        communityFlag(data['is_follow']) ||
        communityFlag(communityMap(data['userAction'])['follow']);
  }

  Future<void> _follow() async {
    final prefix = switch (kind) {
      CommunityKind.question => 'question',
      CommunityKind.live => 'live',
      CommunityKind.collection => 'collection',
      CommunityKind.dyh => 'dyh',
      _ => 'album',
    };
    await communityRequest(
      api,
      _session,
      '/v6/$prefix/${_followed ? 'unFollow' : 'follow'}',
      query: {kind == CommunityKind.dyh ? 'dyhId' : 'id': id},
    );
    await _load();
  }

  Future<void> _answer() async {
    final values = await editCommunityFields(
      context,
      '添加回答',
      {'内容': _answerDraft},
      limits: {'内容': 10000},
    );
    if (values == null || !mounted) return;
    _answerDraft = values['内容']!;
    await api.officialMultipart(
      '/v6/feed/createFeed',
      fields: {
        for (final key in [
          'id',
          'pic',
          'location',
          'long_location',
          'media_url',
          'media_pic',
          'message_title',
          'message_brief',
          'extra_title',
          'extra_url',
          'extra_key',
          'extra_pic',
          'extra_info',
          'message_cover',
          'forwardid',
          'dyhId',
          'targetType',
          'productId',
          'targetId',
          'location_city',
          'location_country',
          'media_info',
          'goods_list_id',
        ])
          key: '',
        for (final key in [
          'publish_status',
          'media_type',
          'original_type',
          'is_editInDyh',
          'disallow_reply',
          'vote_score',
          'replyWithForward',
          'insert_product_media',
          'is_ks_doc',
          'is_html_article',
        ])
          key: '0',
        'message': _answerDraft,
        'type': 'answer',
        'fid': id,
        'status': '1',
        'latitude': '0.0',
        'longitude': '0.0',
      },
      expectedScope: _session,
    );
    _answerDraft = '';
    await _load();
  }

  Future<void> _editCollection() async {
    final data = _data!;
    final fields = await editCommunityFields(
      context,
      '编辑收藏单',
      {
        '标题': _collectionDraft?['标题'] ?? communityText(data, ['title']),
        '说明': _collectionDraft?['说明'] ?? communityText(data, ['description']),
      },
      limits: {'标题': 100},
    );
    if (fields == null || !mounted) return;
    _collectionDraft = fields;
    await communityRequest(
      api,
      _session,
      '/v6/collection/update',
      method: 'POST',
      body: {
        'id': id,
        'title': fields['标题'],
        'description': fields['说明'],
        'pic': communityText(data, ['pic', 'cover']),
        'isOpen': communityFlag(data['isOpen'] ?? data['is_open']) ? 1 : 0,
      },
    );
    _collectionDraft = null;
    await _load();
  }

  Future<void> _deleteCollection() async {
    if (!await confirmCommunityAction(
      context,
      '删除收藏单？',
      '收藏单及其中内容的归属将被移除，此操作无法撤销。',
    )) {
      return;
    }
    if (!mounted) return;
    await communityRequest(
      api,
      _session,
      '/v6/collection/delete',
      method: 'POST',
      body: {'id': id},
    );
    if (mounted) Navigator.pop(context);
  }

  List<Widget> _actions() => [
    if ([
          CommunityKind.question,
          CommunityKind.collection,
          CommunityKind.dyh,
        ].contains(kind) &&
        !(kind == CommunityKind.collection && _owner))
      CommunityAction(
        api: api,
        label: _followed ? '已关注 · 取消' : '关注',
        action: _follow,
      ),
    if (kind == CommunityKind.question)
      CommunityAction(
        api: api,
        label: '添加回答',
        icon: Icons.edit_outlined,
        action: _answer,
      ),
    if (kind == CommunityKind.collection && _owner) ...[
      CommunityAction(
        api: api,
        label: '编辑',
        icon: Icons.edit_outlined,
        action: _editCollection,
      ),
      if (!communityFlag(_data!['isDefault'] ?? _data!['is_default']))
        CommunityAction(
          api: api,
          label: '删除收藏单',
          danger: true,
          icon: Icons.delete_outline,
          action: _deleteCollection,
        ),
      CommunityAction(
        api: api,
        label: communityFlag(_data!['isOpen'] ?? _data!['is_open'])
            ? '设为私密'
            : '设为公开',
        icon: Icons.lock_outline,
        action: () async {
          await communityRequest(
            api,
            _session,
            '/v6/collection/update',
            method: 'POST',
            body: {
              'id': id,
              'title': _data!['title'],
              'description': _data!['description'] ?? '',
              'pic': _data!['pic'] ?? '',
              'isOpen': communityFlag(_data!['isOpen'] ?? _data!['is_open'])
                  ? 0
                  : 1,
            },
          );
          await _load();
        },
      ),
    ],
  ];

  Widget _header() {
    final data = _data!;
    final info = communityMap(
      data['goodsListInfo'] ?? data['productAlbumInfo'],
    );
    return CommunityHero(
      api: api,
      kind: _title,
      data: {...data, ...info},
      actions: _actions(),
      children: [
        if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
        if (kind == CommunityKind.question)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  'reply': '热门',
                  'like': '高赞',
                  'dateline': '最新',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _sort == entry.key,
                    onSelected: (_) => setState(() => _sort = entry.key),
                  ),
              ],
            ),
          ),
        if ([CommunityKind.dyh, CommunityKind.album].contains(kind)) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final entry
                  in (kind == CommunityKind.dyh ? ['精选', '广场'] : ['应用', '评论'])
                      .indexed)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _tab == entry.$1,
                  onSelected: (_) => setState(() => _tab = entry.$1),
                ),
            ],
          ),
        ],
        if (kind == CommunityKind.dyh)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              initialValue: _search,
              decoration: const InputDecoration(
                labelText: '搜索号内内容',
                suffixIcon: Icon(Icons.search),
              ),
              onFieldSubmitted: (value) =>
                  setState(() => _search = value.trim()),
            ),
          ),
      ],
    );
  }

  ({String path, Map<String, dynamic> query}) _list() => switch (kind) {
    CommunityKind.question => (
      path: '/v6/question/answerList',
      query: {'id': id, 'sort': _sort},
    ),
    CommunityKind.collection => (
      path: '/v6/collection/itemlist',
      query: {'id': id},
    ),
    CommunityKind.dyh =>
      _search.isEmpty
          ? (
              path: '/v6/dyhArticle/list',
              query: {'dyhId': id, 'type': _tab == 0 ? 'all' : 'square'},
            )
          : (
              path: '/v6/search',
              query: {
                'searchValue': _search,
                'type': 'feed',
                'pageType': 'tag',
                'pageParam': communityText(_data!, ['title']).isEmpty
                    ? id
                    : communityText(_data!, ['title']),
              },
            ),
    CommunityKind.album => (path: '/v6/album/replyList', query: {'id': id}),
    _ => (path: '/v6/feed/replyList', query: {'id': id, 'feedType': 'feed'}),
  };
  Widget _reply(BuildContext context, Map<String, dynamic> item) => ListTile(
    title: Text(communityText(item, ['username', 'fromusername'])),
    subtitle: CoolapkRichText(
      api: api,
      text: communityText(item, ['message', 'note']),
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReplyThreadPage(
          api: api,
          id: communityText(item, ['id']),
          initial: item,
        ),
      ),
    ),
  );

  Widget _answerCard(BuildContext context, Map<String, dynamic> item) =>
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              communityText(item, ['username']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CoolapkRichText(
              api: api,
              text: communityText(item, ['message']),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text('${item['likenum'] ?? 0} 赞 · ${item['replynum'] ?? 0} 条评论'),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FeedDetailPage(
                    api: api,
                    feed: CoolapkFeed.fromJson(item),
                    adaptCommunity: false,
                    questionId: id,
                  ),
                ),
              ),
              child: const Text('查看完整回答'),
            ),
            const Divider(),
          ],
        ),
      );
  Widget _collectionItem(BuildContext context, Map<String, dynamic> item) =>
      Column(
        children: [
          ApiEntityCard(api: api, entity: item),
          if (_owner && communityText(item, ['itemId', 'item_id']).isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: CommunityAction(
                api: api,
                label: '移出收藏单',
                icon: Icons.remove_circle_outline,
                action: () async {
                  if (!await confirmCommunityAction(
                    context,
                    '移出收藏单？',
                    '此内容将从当前收藏单移除。',
                  )) {
                    return;
                  }
                  await communityRequest(
                    api,
                    _session,
                    '/v6/collection/removeItem',
                    method: 'POST',
                    body: {'itemId': item['itemId'] ?? item['item_id']},
                  );
                  if (mounted) setState(() => _revision++);
                },
              ),
            ),
        ],
      );
  Future<void> _loadMoreGoods() async {
    if (_goodsBusy) return;
    setState(() => _goodsBusy = true);
    try {
      final data = _data!;
      final uid = communityText(data, ['uid']).isEmpty
          ? api.currentUid
          : communityText(data, ['uid']);
      final page = await api.getList(
        '/v6/goodsList/list',
        query: {'uid': uid, 'goodsId': id, 'page': _goodsPage + 1},
      );
      if (!mounted) return;
      setState(() {
        data['productItems'] = [
          ...(data['productItems'] as List? ?? []),
          ...page.items,
        ];
        _goodsPage++;
        _goodsMore = page.hasMore && page.items.isNotEmpty;
        _goodsError = null;
      });
    } catch (_) {
      if (mounted) setState(() => _goodsError = '商品加载失败，点击重试');
    } finally {
      if (mounted) setState(() => _goodsBusy = false);
    }
  }

  Widget _goods() {
    final data = _data!;
    if (kind == CommunityKind.goods) {
      return GoodsRankingBody(
        api: api,
        data: data,
        session: _session,
        complete: _detailLoaded,
        error: _error,
        reload: _load,
        verify: _captcha != null && !_verifying ? _verifyGoods : null,
      );
    }
    final info = communityMap(data['productAlbumInfo']);
    final raw =
        data['goodsListItem'] ??
        data['productItems'] ??
        info['productItems'] ??
        info['items'];
    final known = <String>{};
    final items = raw is List
        ? raw.whereType<Map>().map(communityMap).where((item) {
            final key = communityText(item, [
              'item_id',
              'id',
              'product_goods_id',
              'feed_id',
              'item_name',
            ]);
            return key.isEmpty || known.add(key);
          }).toList()
        : <Map<String, dynamic>>[];
    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      itemCount: items.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '清单商品（${items.length}）',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (items.isEmpty && _goodsError == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('清单暂无商品'),
                ),
              if (_goodsError != null)
                TextButton(onPressed: _load, child: Text(_goodsError!)),
            ],
          );
        }
        if (index == items.length + 1) {
          return Column(
            children: [
              if (_goodsMore)
                TextButton(
                  onPressed: _goodsBusy ? null : _loadMoreGoods,
                  child: Text(_goodsBusy ? '正在加载…' : '加载更多商品'),
                ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FeedDetailPage(
                      api: api,
                      feed: CoolapkFeed.fromJson(data),
                      adaptCommunity: false,
                    ),
                  ),
                ),
                icon: const Icon(Icons.comment_outlined),
                label: const Text('查看动态与评论'),
              ),
            ],
          );
        }
        final item = items[index - 1];
        final extra = item['extra_entities'] ?? item['extraEntities'];
        final product = {
          ...item,
          if (extra is List && extra.isNotEmpty) ...communityMap(extra.first),
        };
        final image = communityText(product, [
          'item_logo',
          'product_goods_cover',
          'pic',
          'logo',
        ]);
        final url = communityText(product, [
          'product_goods_url',
          'goods_buy_url',
          'goods_url',
          'sell_url',
          'url',
        ]);
        final vote = communityMap(item['goodsListInfo']);
        final listInfo = communityMap(data['goodsListInfo']);
        final voted = communityFlag(vote['is_vote'] ?? item['is_vote']);
        final itemId = communityText(vote, ['item_id']).isEmpty
            ? communityText(item, ['id', 'feed_id', 'entityId'])
            : communityText(vote, ['item_id']);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$index', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 12),
                  if (image.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        normalizeCoolapkImageUrl(image),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        headers: coolapkImageHeaders(image, api: api),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          communityText(product, [
                            'item_name',
                            'product_goods_title',
                            'goods_title',
                            'title',
                            'name',
                          ]),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          communityText(product, [
                            'item_description',
                            'note',
                            'message',
                            'description',
                          ]),
                        ),
                        if (communityText(product, [
                          'product_goods_price',
                          'price',
                        ]).isNotEmpty)
                          Text(
                            '¥${communityText(product, ['product_goods_price', 'price'])}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (['http', 'https'].contains(Uri.tryParse(url)?.scheme))
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('查看商品'),
                    ),
                  if (kind == CommunityKind.goods &&
                      communityFlag(listInfo['is_open_vote']) &&
                      itemId.isNotEmpty)
                    CommunityAction(
                      api: api,
                      label:
                          '${voted ? '取消投票' : '投票'} · ${vote['vote_num'] ?? item['vote_num'] ?? 0}',
                      icon: Icons.thumb_up_outlined,
                      action: () async {
                        await communityRequest(
                          api,
                          _session,
                          '/v6/goodsList/vote',
                          method: 'POST',
                          body: {
                            'id': listInfo['id'] ?? id,
                            'item_id': itemId,
                            'value': voted ? -1 : 1,
                          },
                        );
                        await _load();
                      },
                    ),
                ],
              ),
              const Divider(),
            ],
          ),
        );
      },
    );
  }

  Widget _live() {
    final data = {
      ..._data!,
      ...communityMap(
        _data!['live'] ?? _data!['liveInfo'] ?? _data!['live_info'],
      ),
    };
    final video = communityText(data, [
      'videoLiveUrl',
      'video_live_url',
      'videoPlaybackUrl',
      'video_playback_url',
      'videoUrl',
      'video_url',
      'playUrl',
      'play_url',
      'liveUrl',
    ]);
    final url =
        communityText(data, ['url', 'liveUrl', 'live_url', 'webUrl']).isEmpty
        ? 'https://www.coolapk.com/live/$id'
        : communityText(data, ['url', 'liveUrl', 'live_url', 'webUrl']);
    final status = int.tryParse(
      '${data['liveStatus'] ?? data['live_status'] ?? data['status']}',
    );
    return ListView(
      children: [
        CommunityHero(
          api: api,
          data: data,
          kind: status == 0
              ? '即将开始'
              : status == 1
              ? '直播中'
              : '直播详情',
          actions: [
            if (status == 0)
              CommunityAction(
                api: api,
                label: _followed ? '取消预约' : '预约直播',
                action: _follow,
              ),
            if (video.isNotEmpty)
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('播放'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CoolapkVideoPlayerPage(
                      api: api,
                      videoUrl: video,
                      title: communityText(data, ['title']),
                    ),
                  ),
                ),
              ),
            if (Uri.tryParse(url)?.scheme == 'https' ||
                Uri.tryParse(url)?.scheme == 'http')
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: const Text('浏览器打开'),
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list();
    return Theme(
      data: kind == CommunityKind.goods
          ? officialHomeTheme(Theme.of(context))
          : Theme.of(context),
      child: Scaffold(
        backgroundColor:
            kind == CommunityKind.goods &&
                Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF101010)
            : null,
        appBar: ReviewFrostedAppBar(
          title: kind == CommunityKind.goods ? null : Text(_title),
          leading: kind == CommunityKind.goods ? const BackButton() : null,
          showBottomBorder: kind != CommunityKind.goods,
          backgroundColor:
              kind == CommunityKind.goods &&
                  Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF101010)
              : null,
          actions: [
            if (kind == CommunityKind.goods)
              PopupMenuButton<String>(
                tooltip: '更多榜单操作',
                onSelected: (action) {
                  if (action == 'refresh') {
                    _load();
                  } else {
                    launchUrl(
                      Uri.parse('https://www.coolapk.com/feed/$id'),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'refresh', child: Text('刷新榜单')),
                  PopupMenuItem(value: 'web', child: Text('在官方网页查看')),
                ],
              )
            else
              IconButton(
                tooltip: '刷新详情',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body:
            kind == CommunityKind.goods &&
                !_detailLoaded &&
                !_hasRankingPreview &&
                _error != null
            ? _loadError()
            : _data == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : _loadError(),
              )
            : kind == CommunityKind.live
            ? _live()
            : [CommunityKind.goods, CommunityKind.anylist].contains(kind)
            ? _goods()
            : kind == CommunityKind.album && _tab == 0
            ? RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _header(),
                    if (_data!['apkList'] is List &&
                        (_data!['apkList'] as List).isNotEmpty)
                      for (final item
                          in (_data!['apkList'] as List).whereType<Map>())
                        ApiEntityCard(
                          api: api,
                          entity: {...item, 'entityType': 'apk'},
                        )
                    else
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('此应用集暂未返回应用')),
                      ),
                  ],
                ),
              )
            : ApiListPage(
                key: ValueKey('$id:$_revision:$_tab:$_sort:$_search'),
                api: api,
                title: _title,
                path: list.path,
                query: list.query,
                showAppBar: false,
                showAccessErrors: true,
                header: _header(),
                itemBuilder: kind == CommunityKind.question
                    ? _answerCard
                    : kind == CommunityKind.album && _tab == 1
                    ? _reply
                    : kind == CommunityKind.collection
                    ? _collectionItem
                    : null,
              ),
      ),
    );
  }
}
