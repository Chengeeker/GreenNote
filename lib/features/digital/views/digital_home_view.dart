import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../../../core/network/coolapk_api.dart';
import '../../../core/widgets/review_refresh_header.dart';
import '../../feed/feed_pages.dart';
import '../../shared/api_list_page.dart';
import '../widgets/digital_cards.dart';

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

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });

    try {
      final res = await widget.api.request(
        '/v6/page/dataList',
        query: const {'url': 'V10_DIGITAL_HOME', 'page': 1},
      );
      if (!mounted) return;

      final dataList = res['data'];
      if (dataList is List) {
        setState(() {
          _serverCards = dataList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
      _error = null;
    } catch (error) {
      _error = '数码首页加载失败：$error';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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

    // If server returned cards, check if we can parse custom blocks from them
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

    // Look for category grid card in server response
    Map<String, dynamic>? serverCategoryCard;
    Map<String, dynamic>? serverRankCard;
    Map<String, dynamic>? serverBannerCard;
    Map<String, dynamic>? serverFollowCard;
    final otherCards = <Map<String, dynamic>>[];

    if (hasServerCards) {
      for (final card in _serverCards) {
        final template = (card['entityTemplate'] ?? '')
            .toString()
            .toLowerCase();
        final rawTitle = (card['title'] ?? '').toString();

        if (rawTitle.contains('我的关注') || template.contains('follow')) {
          serverFollowCard = card;
        } else if (template.contains('iconlinkgrid') ||
            template.contains('icontablinkgrid')) {
          serverCategoryCard = card;
        } else if (template.contains('iconlongtitlegrid') ||
            template.contains('iconminigrid') ||
            rawTitle.contains('热门') ||
            card['withRanking'] == 1 ||
            card['withRanking'] == '1') {
          serverRankCard = card;
        } else if (template.contains('imagecarousel') ||
            template.contains('imagecard')) {
          serverBannerCard ??= card;
        } else {
          otherCards.add(card);
        }
      }
    }

    final List<Map<String, dynamic>>? categoryItems =
        serverCategoryCard != null && serverCategoryCard['entities'] is List
        ? (serverCategoryCard['entities'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : null;

    final List<Map<String, dynamic>>? rankItems =
        serverRankCard != null && serverRankCard['entities'] is List
        ? (serverRankCard['entities'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : null;

    final List<Map<String, dynamic>> followItems =
        serverFollowCard != null && serverFollowCard['entities'] is List
        ? (serverFollowCard['entities'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const [];

    final bannerUrl = serverBannerCard != null
        ? (serverBannerCard['pic'] ??
                  (serverBannerCard['entities'] is List &&
                          (serverBannerCard['entities'] as List).isNotEmpty
                      ? (serverBannerCard['entities'] as List)[0]['pic']
                      : null))
              ?.toString()
        : null;

    return EasyRefresh(
      header: reviewDefaultRefreshHeader,
      onRefresh: _loadData,
      child: filterHorizontalScrollNotifications(
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            0,
            8,
            0,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // 1. "我的关注"（仅当有关注设备时展示）
            DigitalFollowCard(
              api: widget.api,
              items: followItems,
              onMoreTap: () => widget.onSelectTab?.call(0),
            ),

            // 2. 10个品类5列网格
            DigitalCategoryGridCard(
              api: widget.api,
              items: categoryItems,
              onCategoryTap: _handleCategoryTap,
            ),

            // 3. 推荐横幅
            DigitalBannerCard(
              api: widget.api,
              imageUrl: bannerUrl,
              title: serverBannerCard?['title']?.toString() ?? '数码精选',
              targetUrl: serverBannerCard?['url']?.toString(),
            ),

            // 4. "今日热门" 8款机型榜单
            DigitalRankGridCard(
              api: widget.api,
              title: serverRankCard?['title']?.toString() ?? '今日热门',
              subTitle: serverRankCard?['subTitle']?.toString() ?? '榜单',
              items: rankItems,
              onMoreTap: () {
                if (widget.onSelectTab != null) {
                  widget.onSelectTab!(3); // Navigate to 排行榜
                }
              },
            ),

            // 5. 其余服务端卡片 (如热门系统、评分榜、时间线、动态等)
            if (otherCards.isNotEmpty)
              for (final card in otherCards) _buildDynamicServerCard(card),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicServerCard(Map<String, dynamic> card) {
    final template = (card['entityTemplate'] ?? '').toString().toLowerCase();
    final type = (card['entityType'] ?? '').toString().toLowerCase();
    final title = (card['title'] ?? '').toString();

    if (template.contains('producttimeline')) {
      final entities = card['entities'] is List
          ? (card['entities'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      return DigitalTimelineCard(
        api: widget.api,
        title: title.isNotEmpty ? title : '新品日历',
        items: entities,
      );
    }

    if (type.contains('feed') ||
        (type.isEmpty && card.containsKey('message'))) {
      final feed = CoolapkFeed.fromJson(card);
      if (feed.id.isNotEmpty) {
        return FeedCard(api: widget.api, feed: feed);
      }
    }

    if (title.isNotEmpty &&
        (template.contains('title') || template.contains('header'))) {
      return DigitalSectionHeaderCard(
        title: title,
        onTap: () {
          final url = (card['url'] ?? '').toString();
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
        },
      );
    }

    return ApiEntityCard(api: widget.api, entity: card);
  }
}
