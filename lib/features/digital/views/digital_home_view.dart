import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/network/coolapk_api.dart';
import '../../../core/widgets/review_refresh_header.dart';
import '../../feed/feed_pages.dart';
import '../../shared/api_list_page.dart';
import '../widgets/digital_cards.dart';
import '../widgets/digital_home_cards.dart';

class DigitalHomeView extends StatefulWidget {
  const DigitalHomeView({
    required this.api,
    this.onSelectTab,
    this.onSelectLibraryCategory,
    super.key,
  });

  final CoolapkApi api;
  final void Function(int tabIndex)? onSelectTab;
  final void Function(String categoryId)? onSelectLibraryCategory;

  @override
  State<DigitalHomeView> createState() => _DigitalHomeViewState();
}

class _DigitalHomeViewState extends State<DigitalHomeView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = false;
  String? _error;
  String? _followError;
  int _page = 0;
  bool _hasMore = true;
  String _first = '';
  String _last = '';
  List<Map<String, dynamic>> _serverCards = [];

  static const _libraryCategoryIds = {
    '手机': '1000',
    '平板': '1001',
    '耳机': '1037',
    '笔记本': '1054',
    '智能家居': '1004',
    '穿戴设备': '1005',
    '数码配件': '1006',
    '游戏': '1039',
    '路由器': '1048',
    '全部': '0',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<IndicatorResult> _loadData({bool refresh = true}) async {
    if (_loading) return IndicatorResult.none;
    if (!refresh && !_hasMore) return IndicatorResult.noMore;
    setState(() => _loading = true);
    try {
      final result = await widget.api.getList(
        '/v6/page/dataList',
        query: {
          'url': 'V10_DIGITAL_HOME',
          'page': refresh ? 1 : _page + 1,
          if (!refresh && _first.isNotEmpty) 'firstItem': _first,
          if (!refresh && _last.isNotEmpty) 'lastItem': _last,
        },
      );
      if (!mounted) return IndicatorResult.none;
      final cards = result.items
          .where(
            (c) =>
                c['entityTemplate'] != 'configCard' && c['entityType'] != 'ad',
          )
          .toList();
      if (refresh) {
        final follow = cards
            .where(
              (c) =>
                  c['title'] == '我的关注' ||
                  '${c['entityTemplate']}'.toLowerCase().contains('follow'),
            )
            .firstOrNull;
        cards.remove(follow);
        _followError = null;
        var followed = widget.api.isAnonymous
            ? widget.api.localAccount.productFollows.values
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList()
            : widget.api.hasCookie && follow != null
            ? digitalHomeEntities(follow)
            : <Map<String, dynamic>>[];
        if (follow == null && widget.api.hasCookie) {
          try {
            final result = await widget.api.getList(
              '/v6/page/dataList',
              query: const {'url': '#/product/followProductList', 'page': 1},
            );
            followed = result.items
                .where((c) => c['entityType'] == 'product')
                .toList();
          } catch (error) {
            _followError = '关注加载失败，点击重试';
          }
        }
        if (!mounted) return IndicatorResult.none;
        cards.insert(0, {
          'entityTemplate': 'followCard',
          'title': '我的关注',
          'entities': followed,
        });
      }
      setState(() {
        if (refresh) _serverCards = [];
        final known = _serverCards.map(coolapkEntityKey).toSet();
        _serverCards.addAll(cards.where((c) => known.add(coolapkEntityKey(c))));
        _page = result.page;
        _hasMore = result.hasMore;
        _first = result.firstItem;
        _last = result.lastItem;
        _error = null;
      });
      return refresh || _hasMore
          ? IndicatorResult.success
          : IndicatorResult.noMore;
    } catch (error) {
      if (mounted) setState(() => _error = '数码首页加载失败：$error');
      return IndicatorResult.fail;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleCategoryTap(String title, Map<String, dynamic> item) {
    final categoryId = _libraryCategoryIds[title];
    if (categoryId != null && widget.onSelectLibraryCategory != null) {
      widget.onSelectLibraryCategory!(categoryId);
      return;
    }

    if (title == '手机' && widget.onSelectTab != null) {
      widget.onSelectTab!(2);
      return;
    }
    if (title == '平板' && widget.onSelectTab != null) {
      widget.onSelectTab!(5);
      return;
    }
    if (title == '全部' && widget.onSelectTab != null) {
      widget.onSelectTab!(0);
      return;
    }

    final url = (item['url'] ?? '').toString();
    if (url.isNotEmpty) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApiListPage(
            api: widget.api,
            title: title,
            path: '/v6/page/dataList',
            query: {'url': url},
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final hasServerCards = _serverCards.isNotEmpty;
    if (_loading && !hasServerCards) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!hasServerCards && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme.copyWith(
        cardTheme: theme.cardTheme.copyWith(
          color: dark
              ? const Color(0xFF1E1E1E)
              : theme.colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        colorScheme: theme.colorScheme.copyWith(
          onSurface: dark
              ? const Color(0xFFCCCCCC)
              : theme.colorScheme.onSurface,
          onSurfaceVariant: dark
              ? const Color(0xFF999999)
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: EasyRefresh(
        triggerAxis: Axis.vertical,
        header: ClassicHeader(
          textDimension: MediaQuery.sizeOf(context).width - 80,
          dragText: '下拉刷新',
          armedText: '释放立即刷新',
          readyText: '正在刷新...',
          processingText: '正在刷新...',
          processedText: '刷新成功',
          failedText: '刷新失败',
          noMoreText: '没有更多了',
          messageText: '最后更新于 %T',
          showMessage: true,
        ),
        footer: const ClassicFooter(
          showMessage: false,
          dragText: '上拉加载',
          armedText: '释放加载',
          readyText: '正在加载...',
          processingText: '正在加载...',
          processedText: '加载完成',
          failedText: '加载失败',
          noMoreText: '没有更多了',
        ),
        onRefresh: () => _loadData(),
        onLoad: () => _loadData(refresh: false),
        child: filterHorizontalScrollNotifications(
          ListView.builder(
            scrollCacheExtent: const ScrollCacheExtent.pixels(1000.0),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: 4,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: _serverCards.length,
            itemBuilder: (context, index) => KeyedSubtree(
              key: ValueKey(coolapkEntityKey(_serverCards[index])),
              child: RepaintBoundary(
                child: _buildDynamicServerCard(_serverCards[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(Map<String, dynamic> item) =>
      openHeadlineTarget(context, widget.api, item);

  Widget _buildDynamicServerCard(Map<String, dynamic> card) {
    final template = (card['entityTemplate'] ?? '').toString().toLowerCase();
    final type = (card['entityType'] ?? '').toString().toLowerCase();
    final title = (card['title'] ?? '').toString();
    final items = digitalHomeEntities(card);
    if (template.contains('config') ||
        template.contains('ad') && type == 'ad') {
      return const SizedBox.shrink();
    }
    if (title == '我的关注' || template.contains('follow')) {
      return DigitalFollowCard(
        api: widget.api,
        items: items.take(2).toList(),
        emptyText:
            _followError ?? (widget.api.hasAccount ? '还没有关注的机型' : '登录后查看关注的机型'),
        onEmptyTap: _followError == null ? null : () => _loadData(),
      );
    }
    if (template.contains('iconlinkgrid') ||
        template.contains('icontablinkgrid')) {
      return DigitalCategoryGridCard(
        api: widget.api,
        items: items,
        onCategoryTap: _handleCategoryTap,
      );
    }
    if (template.contains('imagecarousel') || template == 'imagecard') {
      return DigitalHomeCarousel(
        key: ValueKey(items.map((e) => e['pic']).join('|')),
        api: widget.api,
        card: card,
        onTap: _open,
      );
    }
    if (template.contains('producttimeline')) {
      return DigitalTimelineCard(
        api: widget.api,
        title: title,
        items: items,
        onMoreTap: () => _open(card),
      );
    }
    if (template.contains('grid')) {
      final extra = digitalHomeExtra(card);
      return DigitalRankGridCard(
        api: widget.api,
        title: title,
        subTitle: (card['subTitle'] ?? '更多').toString(),
        items: items,
        showRanking: '${extra['withRanking'] ?? card['withRanking']}' == '1',
        onItemTap: _open,
        onMoreTap: () => _open(card),
      );
    }
    if (template == 'iconlistcard' || template == 'feedlistcard') {
      return DigitalHomeListCard(api: widget.api, card: card, onTap: _open);
    }
    if (type == 'feed' || type == 'feedcover') {
      final feed = CoolapkFeed.fromJson(card);
      if (feed.id.isNotEmpty) return FeedCard(api: widget.api, feed: feed);
    }
    return ApiEntityCard(api: widget.api, entity: card);
  }
}
