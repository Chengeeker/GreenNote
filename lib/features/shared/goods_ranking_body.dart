import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_navigation_bar.dart';
import '../../core/settings/app_settings.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../feed/feed_pages.dart';
import 'api_list_page.dart';
import 'community_ui.dart';

Map<String, dynamic> rankingProduct(Map<String, dynamic> item) {
  final extra = item['extra_entities'] ?? item['extraEntities'];
  return {
    ...item,
    if (extra is List && extra.isNotEmpty) ...communityMap(extra.first),
  };
}

class GoodsRankingBody extends ConsumerStatefulWidget {
  const GoodsRankingBody({
    super.key,
    required this.api,
    required this.data,
    required this.session,
    required this.complete,
    required this.error,
    required this.reload,
    this.verify,
  });
  final CoolapkApi api;
  final Map<String, dynamic> data;
  final String session;
  final bool complete;
  final String? error;
  final Future<void> Function() reload;
  final Future<void> Function()? verify;
  @override
  ConsumerState<GoodsRankingBody> createState() => _GoodsRankingBodyState();
}

class _GoodsRankingBodyState extends ConsumerState<GoodsRankingBody> {
  String _draft = '';
  final Set<String> _busy = {};
  Map<String, dynamic> get data => widget.data;
  Map<String, dynamic> get info => {
    ...data,
    ...communityMap(data['goodsListInfo']),
  };
  String get id => communityText(data, ['id', 'feed_id']);
  Color get _card => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1E1E1E)
      : Theme.of(context).colorScheme.surfaceContainerLow;

  Future<void> _write(String key, Future<void> Function() action) async {
    if (_busy.contains(key)) return;
    if (!widget.api.hasCookie) {
      AppToast.show(context, '请先使用酷安账号登录');
      return;
    }
    setState(() => _busy.add(key));
    try {
      if (widget.api.notificationSessionKey != widget.session ||
          !await widget.api.notificationSessionMatches(widget.session)) {
        throw StateError('账号已切换，请重新打开榜单');
      }
      await action();
    } catch (error) {
      if (mounted) AppToast.show(context, '$error');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _comment() async {
    final result = await editCommunityFields(
      context,
      '写评论',
      {'内容': _draft},
      limits: {'内容': 10000},
    );
    if (result == null || !mounted) return;
    _draft = result['内容']!;
    await communityRequest(
      widget.api,
      widget.session,
      '/v6/feed/reply',
      method: 'POST',
      body: coolapkReplyForm(id, _draft),
    );
    _draft = '';
    if (mounted) AppToast.show(context, '评论已发送');
    await widget.reload();
  }

  Future<void> _toggleFeedAction(bool favorite) async {
    final key = favorite ? 'collect' : 'like';
    final action = communityMap(data['userAction']);
    final selected = communityFlag(action[key]);
    await communityRequest(
      widget.api,
      widget.session,
      '/v6/feed/${favorite ? (selected ? 'unfavorite' : 'favorite') : (selected ? 'unlike' : 'like')}',
      method: 'POST',
      query: {'id': id},
    );
    if (!mounted) return;
    setState(() {
      action[key] = selected ? 0 : 1;
      data['userAction'] = action;
      final target = favorite ? info : data;
      final count = favorite ? 'fav_num' : 'likenum';
      target[count] =
          ((int.tryParse('${target[count]}') ?? 0) + (selected ? -1 : 1)).clamp(
            0,
            1 << 31,
          );
      if (favorite) data['goodsListInfo'] = target;
    });
  }

  void _comments() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FeedDetailPage(
        api: widget.api,
        feed: CoolapkFeed.fromJson(data),
        adaptCommunity: false,
      ),
    ),
  );

  Future<void> _copyInvite() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${communityText(info, ['title'])}\nhttps://www.coolapk.com/feed/$id',
      ),
    );
    if (mounted) AppToast.show(context, '邀请链接已复制，可发送给酷友');
  }

  Future<void> _recommend() async {
    final goods = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _RankingGoodsPicker(api: widget.api)),
    );
    if (goods == null || !mounted) return;
    final note = await editCommunityFields(
      context,
      '推荐好物',
      {'推荐理由': ''},
      limits: {'推荐理由': 1000},
    );
    if (note == null || !mounted) return;
    await communityRequest(
      widget.api,
      widget.session,
      '/v6/goodsList/addGoods',
      method: 'POST',
      body: {
        'feedId': info['id'] ?? id,
        'goodsId': goods['id'] ?? goods['entityId'],
        'note': note['推荐理由'],
        'pic': communityText(goods, [
          'product_goods_cover',
          'goods_pic',
          'pic',
        ]),
      },
    );
    if (mounted) AppToast.show(context, '已提交推荐');
    await widget.reload();
  }

  Widget _photo(String url, {double? size}) => url.isEmpty
      ? SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.shopping_bag_outlined),
        )
      : CachedNetworkImage(
          normalizeCoolapkImageUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: coolapkImageHeaders(url, api: widget.api),
          cacheWidth: size == null
              ? 900
              : (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
        );

  Widget _action(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool selected = false,
    bool compact = false,
    String? semanticsLabel,
  }) => Expanded(
    child: Semantics(
      label: semanticsLabel ?? label,
      button: true,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          minimumSize: Size(0, compact ? 44 : 48),
          padding: EdgeInsets.symmetric(
            vertical: compact ? 3 : 10,
            horizontal: 4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 22 : 25),
            SizedBox(height: compact ? 0 : 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: compact ? 10 : 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header(int itemCount) {
    final cover = communityText(info, ['cover']);
    final date = DateTime.fromMillisecondsSinceEpoch(
      (int.tryParse('${info['dateline'] ?? data['dateline']}') ?? 0) * 1000,
    );
    return Stack(
      children: [
        if (cover.isNotEmpty)
          Positioned.fill(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Opacity(opacity: .13, child: _photo(cover)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 76, 18, 8),
          child: Column(
            children: [
              Text(
                communityText(info, ['title']).isEmpty
                    ? communityText(data, [
                        'title',
                        'message_title',
                        'entityTitle',
                      ])
                    : communityText(info, ['title']),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 16),
              CoolapkRichText(
                api: widget.api,
                text: communityText(info, ['message', 'description']),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  if (communityText(data, [
                    'username',
                    'userAvatar',
                  ]).isNotEmpty)
                    AppAvatar(
                      api: widget.api,
                      url: communityText(data, ['userAvatar']),
                      size: 21,
                    ),
                  const SizedBox(width: 7),
                  Text(
                    communityText(data, ['username']),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        if (date.year > 1970)
                          '${date.year}-${date.month}-${date.day}',
                        if (info['item_num'] != null ||
                            widget.complete ||
                            itemCount > 0)
                          '${info['item_num'] ?? itemCount}个好物',
                        if (info['vote_num'] != null || widget.complete)
                          '${info['vote_num'] ?? 0}人投票',
                      ].join(' · '),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _action(
                    Icons.thumb_up_outlined,
                    '${data['likenum'] ?? 0}',
                    () => _write('like', () => _toggleFeedAction(false)),
                    selected: communityFlag(
                      communityMap(data['userAction'])['like'],
                    ),
                  ),
                  _action(
                    Icons.chat_bubble_outline,
                    '${data['replynum'] ?? 0}',
                    _comments,
                  ),
                  _action(Icons.person_add_alt_outlined, '邀请推荐', _copyInvite),
                  _action(
                    Icons.add_box_outlined,
                    '我要推荐',
                    communityFlag(info['is_allow_recommend_goods']) ||
                            '${data['uid']}' == widget.api.currentUid
                        ? () => _write('recommend', _recommend)
                        : null,
                  ),
                ],
              ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      Text(
                        widget.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (!widget.complete)
                        const Text(
                          '当前展示入口预览，完整榜单尚未加载',
                          style: TextStyle(fontSize: 12),
                        ),
                      if (widget.verify != null)
                        FilledButton.icon(
                          onPressed: widget.verify,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('完成验证并加载榜单'),
                        ),
                      TextButton.icon(
                        onPressed: widget.reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新加载完整榜单'),
                      ),
                    ],
                  ),
                ),
              if (widget.error == null && !widget.complete)
                const LinearProgressIndicator(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(Map<String, dynamic> item, int rank) {
    final product = rankingProduct(item);
    final source = communityMap(item['userInfo']);
    final vote = communityMap(item['goodsListInfo']);
    final voted = communityFlag(
      vote['is_vote'] ?? item['isVote'] ?? item['is_vote'],
    );
    final itemId = communityText(vote, ['item_id']).isEmpty
        ? communityText(item, ['id', 'feed_id'])
        : communityText(vote, ['item_id']);
    final url = communityText(product, [
      'product_goods_url',
      'goods_buy_url',
      'goods_url',
      'sell_url',
      'url',
    ]);
    final uri = Uri.tryParse(url);
    final canBuy =
        uri != null &&
        ['https', 'http'].contains(uri.scheme) &&
        uri.userInfo.isEmpty;
    final price = communityText(product, [
      'price',
      'product_goods_price',
      'goods_price',
    ]);
    final note = communityText(item, ['note', 'message']);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 3),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canBuy
                ? () => launchUrl(uri, mode: LaunchMode.externalApplication)
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _photo(
                        communityText(product, [
                          'product_goods_cover',
                          'product_goods_logo',
                          'cover',
                          'logo',
                          'goods_pic',
                          'pic',
                        ]),
                        size: 100,
                      ),
                    ),
                    Positioned(
                      left: -5,
                      top: -9,
                      child: Semantics(
                        label: '第$rank名',
                        child: _RankMedal(rank: rank),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        communityText(product, [
                          'product_goods_title',
                          'productGoodsTitle',
                          'goods_title',
                          'title',
                        ]),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (price.isNotEmpty)
                            Text(
                              price.startsWith('¥') || price.startsWith('￥')
                                  ? price
                                  : '¥$price',
                              style: const TextStyle(fontSize: 16),
                            ),
                          if (canBuy)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  color: const Color(0xFFF44336),
                                  size: 18,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  communityText(product, [
                                        'mall_name',
                                        'mall_title',
                                      ]).isEmpty
                                      ? '购买'
                                      : communityText(product, [
                                          'mall_name',
                                          'mall_title',
                                        ]),
                                  style: const TextStyle(
                                    color: Color(0xFFF44336),
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (note.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Divider(),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(
                  api: widget.api,
                  url: communityText(item, ['userAvatar']).isEmpty
                      ? communityText(source, ['userAvatar'])
                      : communityText(item, ['userAvatar']),
                  size: 23,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CoolapkRichText(
                    api: widget.api,
                    text: note,
                    prefixSpans: [
                      TextSpan(
                        text: '${communityText(source, ['username'])}: ',
                        style: const TextStyle(color: Color(0xFF009688)),
                      ),
                    ],
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed:
                  communityFlag(info['is_open_vote']) &&
                      itemId.isNotEmpty &&
                      !_busy.contains(itemId)
                  ? () => _write(itemId, () async {
                      await communityRequest(
                        widget.api,
                        widget.session,
                        '/v6/goodsList/vote',
                        method: 'POST',
                        body: {
                          'id': info['id'] ?? id,
                          'item_id': itemId,
                          'value': voted ? -1 : 1,
                        },
                      );
                      // Keep the server's item order until the user explicitly refreshes the ranking.
                      if (mounted) {
                        setState(() {
                          item['isVote'] = voted ? 0 : 1;
                          item['vote_num'] =
                              ((int.tryParse(
                                            '${vote['vote_num'] ?? item['vote_num']}',
                                          ) ??
                                          0) +
                                      (voted ? -1 : 1))
                                  .clamp(0, 1 << 31);
                          vote['is_vote'] = item['isVote'];
                          vote['vote_num'] = item['vote_num'];
                          if (item['goodsListInfo'] is Map) {
                            item['goodsListInfo'] = vote;
                          }
                        });
                      }
                    })
                  : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                color: voted ? Theme.of(context).colorScheme.primary : null,
              ),
              label: Text('${vote['vote_num'] ?? item['vote_num'] ?? 0}'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capsule(Widget child, double height, bool glass) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: glass ? Colors.transparent : _card,
          borderRadius: BorderRadius.circular(28),
          border: glass
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: .4),
                  width: .7,
                ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (glass)
              AdaptiveGlass(
                shape: const LiquidRoundedSuperellipse(borderRadius: 9999),
                settings: ReviewNavigationBar.liquidGlassSettingsFor(context),
                quality: ReviewNavigationBar.liquidGlassQuality,
                child: const SizedBox.expand(),
              ),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw = data['goodsListItem'];
    final items = raw is List
        ? raw.whereType<Map>().cast<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final glass = ref.watch(
      appSettingsProvider.select((state) => state.useLiquidGlassNavBar),
    );
    final height =
        48.0 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24);
    final userAction = communityMap(data['userAction']);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: widget.reload,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + height + 30,
            ),
            itemCount: items.length + 2,
            itemBuilder: (context, index) => index == 0
                ? _header(items.length)
                : index == items.length + 1
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        widget.complete ? '已显示榜单全部好物' : '完整榜单加载后显示更多好物',
                      ),
                    ),
                  )
                : _item(items[index - 1], index),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  flex: 9,
                  child: _capsule(
                    TextButton.icon(
                      onPressed: () => _write('comment', _comment),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('写评论'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface,
                      ),
                    ),
                    height,
                    glass,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 12,
                  child: _capsule(
                    Row(
                      children: [
                        _action(
                          communityFlag(userAction['like'])
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          '${data['likenum'] ?? 0}',
                          () => _write('like', () => _toggleFeedAction(false)),
                          compact: true,
                          semanticsLabel: '点赞，${data['likenum'] ?? 0}',
                          selected: communityFlag(userAction['like']),
                        ),
                        _action(
                          Icons.chat_bubble_outline,
                          '${data['replynum'] ?? 0}',
                          _comments,
                          compact: true,
                          semanticsLabel: '评论，${data['replynum'] ?? 0}',
                        ),
                        _action(
                          communityFlag(userAction['collect'])
                              ? Icons.star
                              : Icons.star_border,
                          '${info['fav_num'] ?? 0}',
                          () =>
                              _write('favorite', () => _toggleFeedAction(true)),
                          compact: true,
                          semanticsLabel: '收藏，${info['fav_num'] ?? 0}',
                          selected: communityFlag(userAction['collect']),
                        ),
                        _action(
                          Icons.refresh_rounded,
                          '${data['forwardnum'] ?? 0}',
                          _copyInvite,
                          compact: true,
                          semanticsLabel: '分享榜单链接',
                        ),
                      ],
                    ),
                    height,
                    glass,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RankMedal extends StatelessWidget {
  const _RankMedal({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MedalPainter(rank),
    child: SizedBox(
      width: 28,
      height: 37,
      child: Padding(
        padding: const EdgeInsets.only(top: 11),
        child: Center(
          child: Text(
            '$rank',
            style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
          ),
        ),
      ),
    ),
  );
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter(this.rank);
  final int rank;
  @override
  void paint(Canvas canvas, Size size) {
    final color = rank == 1
        ? const Color(0xFFFFD15D)
        : rank == 2
        ? const Color(0xFFAECBF0)
        : rank == 3
        ? const Color(0xFFE3B592)
        : const Color(0xFFC7C7C7);
    final ribbon = Path()
      ..moveTo(0, 0)
      ..lineTo(28, 0)
      ..lineTo(18, 10)
      ..lineTo(10, 10)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = color);
    canvas.drawCircle(const Offset(14, 23), 13, Paint()..color = color);
    canvas.drawCircle(
      const Offset(14, 23),
      11,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MedalPainter oldDelegate) => rank != oldDelegate.rank;
}

class _RankingGoodsPicker extends StatefulWidget {
  const _RankingGoodsPicker({required this.api});
  final CoolapkApi api;
  @override
  State<_RankingGoodsPicker> createState() => _RankingGoodsPickerState();
}

class _RankingGoodsPickerState extends State<_RankingGoodsPicker> {
  String _keyword = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索推荐好物')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '输入商品名称',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (value) => setState(() => _keyword = value.trim()),
          ),
        ),
        if (_keyword.isNotEmpty)
          Expanded(
            child: ApiListPage(
              key: ValueKey(_keyword),
              api: widget.api,
              title: '商品搜索',
              path: '/v6/goods/search',
              query: {
                'keyword': _keyword,
                'sortName': '',
                'sort': '',
                'isCoupon': 0,
              },
              showAppBar: false,
              showAccessErrors: true,
              itemBuilder: (context, item) => ListTile(
                title: Text(
                  communityText(item, [
                    'product_goods_title',
                    'goods_title',
                    'title',
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  communityText(item, ['price', 'goods_promo_title']),
                ),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: communityText(item, ['id', 'entityId']).isEmpty
                    ? null
                    : () => Navigator.pop(context, item),
              ),
            ),
          ),
      ],
    ),
  );
}
