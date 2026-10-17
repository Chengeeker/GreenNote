import 'dart:convert';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../../core/widgets/review_refresh_header.dart';
import '../../shared/api_list_page.dart';
import '../utils/digital_system_helper.dart';
import '../widgets/digital_cards.dart' show formatDigitalHot;
import '../widgets/rank_ribbon.dart';

/// Keeps the server's card data and actions, while laying digital channel cards
/// out as the compact grouped sections used by Coolapk's mobile channel.
class DigitalServerChannelView extends StatefulWidget {
  const DigitalServerChannelView({
    required this.api,
    required this.url,
    this.system = false,
    this.bottomPadding = 100,
    this.groupProductRows = false,
    this.initialSortTitle,
    super.key,
  });

  final CoolapkApi api;
  final String url;
  final bool system;
  final double bottomPadding;
  final bool groupProductRows;
  final String? initialSortTitle;

  @override
  State<DigitalServerChannelView> createState() =>
      _DigitalServerChannelViewState();
}

class _DigitalServerChannelViewState extends State<DigitalServerChannelView>
    with AutomaticKeepAliveClientMixin {
  final _items = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _more = true;
  String? _error;
  int _page = 0;
  String _first = '';
  String _last = '';
  String _selectedSortTitle = '最近回复';
  late String _activeUrl;
  List<Map<String, dynamic>>? _cachedRecentFeeds;
  List<Map<String, dynamic>>? _cachedHotFeeds;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.url;
    _selectedSortTitle = widget.initialSortTitle ?? '最近回复';
    _load(refresh: true);
  }

  Future<void> _load({required bool refresh}) async {
    if (_loading || (!refresh && !_more)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final page = refresh ? 1 : _page + 1;
    try {
      var result = await widget.api.getList(
        '/v6/page/dataList',
        query: {
          'url': _activeUrl,
          'page': page,
          if (!refresh && _first.isNotEmpty) 'firstItem': _first,
          if (!refresh && _last.isNotEmpty) 'lastItem': _last,
        },
      );
      if (!mounted) return;
      var rawItems = result.items;
      var retainedSortCard = _items
          .where(
            (item) =>
                (item['entityTemplate'] ?? '').toString().toLowerCase() ==
                'sortselectcard',
          )
          .firstOrNull;
      String? markedSortTitle;
      String? initialSortUrl;
      if (refresh) {
        for (final item in rawItems) {
          if ((item['entityTemplate'] ?? '').toString().toLowerCase() !=
              'sortselectcard') {
            continue;
          }
          retainedSortCard = item;
          final options = item['entities'];
          if (options is List) {
            for (final option in options.whereType<Map>()) {
              if (_page == 0 &&
                  widget.initialSortTitle != null &&
                  option['title'] == widget.initialSortTitle) {
                initialSortUrl = option['url']?.toString();
              }
              final selected =
                  option['selected'] ??
                  option['isSelected'] ??
                  option['is_selected'];
              if (selected == true || selected == 1 || selected == '1') {
                markedSortTitle = (option['title'] ?? '').toString();
              }
            }
          }
          break;
        }
      }
      if (initialSortUrl != null &&
          initialSortUrl.isNotEmpty &&
          initialSortUrl != _activeUrl) {
        _activeUrl = initialSortUrl;
        result = await widget.api.getList(
          '/v6/page/dataList',
          query: {'url': _activeUrl, 'page': 1},
        );
        if (!mounted) return;
        rawItems = result.items;
      }
      // Sort leaf endpoints may omit the controls returned by the series page.
      if (widget.initialSortTitle != null &&
          refresh &&
          retainedSortCard != null &&
          !rawItems.any(
            (item) =>
                (item['entityTemplate'] ?? '').toString().toLowerCase() ==
                'sortselectcard',
          )) {
        rawItems = [retainedSortCard, ...rawItems];
      }
      setState(() {
        if (refresh) {
          _items.clear();
          _cachedRecentFeeds = null;
          _cachedHotFeeds = null;
          if (widget.initialSortTitle == null) {
            _selectedSortTitle = markedSortTitle ?? '最近回复';
          }
        }
        final existingKeys = _items.map(_key).toSet();
        final newItems = <Map<String, dynamic>>[];
        for (final item in rawItems) {
          final k = _key(item);
          if (existingKeys.add(k)) {
            newItems.add(item);
          }
        }
        final processed = widget.system
            ? _combineSystemZones(newItems)
            : _combineChannelCards(newItems);
        _items.addAll(processed);
        if (refresh) {
          final dynamicIndex = _items.indexWhere(
            (item) =>
                (item['title'] ?? '').toString().contains('动态区') ||
                (item['entityTemplate'] ?? '').toString().toLowerCase() ==
                    'sortselectcard',
          );
          if (dynamicIndex >= 0 && dynamicIndex + 1 < _items.length) {
            _cachedRecentFeeds = _items
                .sublist(dynamicIndex + 1)
                .where(
                  (it) =>
                      (it['entityType'] ?? '').toString().toLowerCase() !=
                      'card',
                )
                .toList();
          }
        }
        _page = page;
        _first = result.firstItem;
        _last = result.lastItem;
        _more = result.hasMore && result.items.isNotEmpty;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return EasyRefresh(
      triggerAxis: Axis.vertical,
      header: reviewDefaultRefreshHeader,
      onRefresh: () => _load(refresh: true),
      onLoad: _more ? () => _load(refresh: false) : null,
      child: filterHorizontalScrollNotifications(
        _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * .55,
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error ?? '服务端暂未返回内容'),
                                if (_error != null)
                                  TextButton(
                                    onPressed: () => _load(refresh: true),
                                    child: const Text('重试'),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  0,
                  8,
                  0,
                  widget.bottomPadding + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: _items.length + (_loading || _error != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    if (_error != null) {
                      return TextButton(
                        onPressed: () => _load(refresh: false),
                        child: Text('加载失败，点击重试：$_error'),
                      );
                    }
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final entity = _items[index];
                  if (widget.groupProductRows && _isDirectProduct(entity)) {
                    final startsGroup =
                        index == 0 || !_isDirectProduct(_items[index - 1]);
                    final endsGroup =
                        index == _items.length - 1 ||
                        !_isDirectProduct(_items[index + 1]);
                    final colorScheme = Theme.of(context).colorScheme;
                    final radius = BorderRadius.vertical(
                      top: startsGroup
                          ? const Radius.circular(18)
                          : Radius.zero,
                      bottom: endsGroup
                          ? const Radius.circular(18)
                          : Radius.zero,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).cardTheme.color ??
                              colorScheme.surfaceContainerHigh,
                          borderRadius: radius,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _buildProductListItem(entity),
                        ),
                      ),
                    );
                  }
                  return _section(entity);
                },
              ),
      ),
    );
  }

  bool _isDirectProduct(Map<String, dynamic> entity) =>
      (entity['entityType'] ?? '').toString().toLowerCase() == 'product';

  List<Map<String, dynamic>> _combineSystemZones(
    List<Map<String, dynamic>> raw,
  ) {
    final processed = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final cur = raw[i];
      final title = (cur['title'] ?? '').toString();
      if (title.contains('系统区')) {
        Map<String, dynamic>? featureCard;
        if (i + 1 < raw.length) {
          final next = raw[i + 1];
          final nextTitle = (next['title'] ?? '').toString();
          final nextTpl = (next['entityTemplate'] ?? '')
              .toString()
              .toLowerCase();
          if (nextTitle.isEmpty && nextTpl.contains('grid')) {
            featureCard = next;
            i++;
          }
        }
        processed.add({
          'entityType': 'system_zone_card',
          'title': title,
          'mainCard': cur,
          'featureCard': featureCard,
        });
      } else {
        processed.add(cur);
      }
    }
    return processed;
  }

  List<Map<String, dynamic>> _combineChannelCards(
    List<Map<String, dynamic>> raw,
  ) {
    final processed = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final cur = Map<String, dynamic>.from(raw[i]);
      final curTemplate = (cur['entityTemplate'] ?? '')
          .toString()
          .toLowerCase();

      // Combine imageCarouselCard_1 with following iconMiniLinkGridCard
      if (curTemplate.startsWith('imagecarouselcard') && i + 1 < raw.length) {
        final next = raw[i + 1];
        final nextTemplate = (next['entityTemplate'] ?? '')
            .toString()
            .toLowerCase();
        if (nextTemplate == 'iconminilinkgridcard') {
          final quickEntities =
              (next['entities'] is List ? next['entities'] as List : const [])
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(growable: false);
          cur['quickLinks'] = quickEntities;
          processed.add(cur);
          i++; // Skip iconMiniLinkGridCard as it's merged into cur
          continue;
        }
      }
      processed.add(cur);
    }
    return processed;
  }

  Widget _section(Map<String, dynamic> entity) {
    if (entity['entityType'] == 'system_zone_card') {
      return _buildSystemZoneCard(entity);
    }
    final type = (entity['entityType'] ?? '').toString().toLowerCase();
    if (type == 'product') return _buildProductListItem(entity);
    if (type != 'card') return ApiEntityCard(api: widget.api, entity: entity);
    final title = (entity['title'] ?? entity['subTitle'] ?? '').toString();
    final children =
        (entity['entities'] is List ? entity['entities'] as List : const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    final template = (entity['entityTemplate'] ?? '').toString().toLowerCase();
    if (template == 'nomoredatacard' ||
        template == 'configcard' ||
        template == 'sponsorcard') {
      return const SizedBox.shrink();
    }
    if (children.isEmpty && title.isEmpty && _image(entity).isEmpty) {
      return const SizedBox.shrink();
    }

    if (widget.system && (title == '新系统' || title.contains('新系统'))) {
      return _buildNewSystemCard(entity, children);
    }

    if (widget.system && (title == '热门功能' || title.contains('热门功能'))) {
      return _buildHotFeaturesCard(entity, children);
    }

    if (title == '动态区' ||
        title.contains('动态区') ||
        template == 'sortselectcard') {
      return _buildDynamicAreaHeader(entity, children);
    }

    if (template == 'iconlongtitlegridcard' || title == '今日热门') {
      return _buildRankGridCard(entity, children);
    }

    if (template == 'icongridhorizoncard') {
      return _buildBrandHorizonCard(entity, children);
    }

    if (template == 'iconminilinkgridcard') {
      return _buildMiniLinkGridCard(entity, children);
    }

    if (template.startsWith('imagecarouselcard') ||
        template.startsWith('imagecard')) {
      return _buildBannerCard(entity, children);
    }

    final products =
        children.isNotEmpty &&
        children.every(
          (item) =>
              (item['entityType'] ?? '').toString().toLowerCase() == 'product',
        );

    if (template == 'iconlistcard' ||
        template == 'listcard' ||
        (products && !template.contains('grid'))) {
      return _buildIconListCard(entity, children);
    }

    if (template == 'icongridcard' ||
        (template.contains('grid') &&
            !template.contains('link') &&
            !template.contains('carousel'))) {
      if (widget.system) {
        return ReviewCard(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                ],
                _buildTwoColumnGrid(children),
              ],
            ),
          ),
        );
      }
      return _buildIconGridCard(entity, children);
    }

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
            ],
            for (final child in children) _section(child),
            if (children.isEmpty)
              ApiEntityCard(api: widget.api, entity: entity),
          ],
        ),
      ),
    );
  }

  Widget _buildTwoColumnGrid(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < items.length ? 8 : 0),
          child: Row(
            children: [
              Expanded(child: _systemShortcut(left)),
              const SizedBox(width: 10),
              Expanded(
                child: right != null
                    ? _systemShortcut(right)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _buildNewSystemCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? '新系统').toString();
    final subTitle = (entity['subTitle'] ?? '更多').toString();
    final moreUrl = (entity['moreUrl'] ?? entity['url'] ?? '').toString();

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                InkWell(
                  onTap: () {
                    final targetUrl = moreUrl.isNotEmpty
                        ? moreUrl
                        : '#/topic/tagList?withSymbol=0&keywords=2026rom&sort=hot_num&cacheExpires=300&title=新系统';
                    HapticFeedbackUtil.selection();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ApiListPage(
                          api: widget.api,
                          title: title,
                          path: '/v6/page/dataList',
                          query: {'url': targetUrl},
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          subTitle.isNotEmpty ? subTitle : '更多',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildTwoColumnGrid(children),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemZoneCard(Map<String, dynamic> zone) {
    final title = zone['title'].toString();
    final mainCard = zone['mainCard'] as Map<String, dynamic>?;
    final featureCard = zone['featureCard'] as Map<String, dynamic>?;

    final mainEntities =
        (mainCard?['entities'] is List
                ? mainCard!['entities'] as List
                : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
    final mainItem = mainEntities.isNotEmpty
        ? mainEntities.first
        : <String, dynamic>{};

    final featureEntities =
        (featureCard?['entities'] is List
                ? featureCard!['entities'] as List
                : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);

    final mainImage = _image(mainItem);
    final mainTitle = (mainItem['title'] ?? mainItem['name'] ?? '').toString();
    final hot = _formatNum(
      mainItem['hot_num_txt'] ?? mainItem['hot_num'] ?? '',
    );
    final comments = _formatNum(
      mainItem['commentnum'] ??
          mainItem['commentNum'] ??
          mainItem['feedCommentNumTxt'] ??
          '',
    );
    final score = (mainItem['star_average_score'] ?? mainItem['score'] ?? '')
        .toString();
    final scoreNum = (double.tryParse(score) ?? 0.0) / 2.0;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (mainItem.isNotEmpty) ...[
              InkWell(
                onTap: () => _openRoute(mainItem),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (mainImage.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            normalizeCoolapkImageUrl(mainImage),
                            headers: coolapkImageHeaders(
                              mainImage,
                              api: widget.api,
                            ),
                            width: 58,
                            height: 58,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.system_update_alt_rounded,
                              size: 38,
                            ),
                          ),
                        )
                      else
                        const Icon(Icons.system_update_alt_rounded, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              mainTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              [
                                if (hot.isNotEmpty) '🔥 $hot热度',
                                if (comments.isNotEmpty) '$comments讨论',
                              ].join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (score.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              score,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < 5; i++)
                                  Icon(
                                    _starIcon(scoreNum, i),
                                    size: 13,
                                    color: const Color(0xFFFFB300),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (featureEntities.isNotEmpty)
              _buildTwoColumnGrid(featureEntities),
          ],
        ),
      ),
    );
  }

  Widget _buildHotFeaturesCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? '热门功能').toString();
    final subTitle = (entity['subTitle'] ?? '榜单').toString();
    final moreUrl = (entity['url'] ?? entity['moreUrl'] ?? '').toString();

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                InkWell(
                  onTap: () {
                    final targetUrl = moreUrl.isNotEmpty
                        ? moreUrl
                        : '#/topic/tagList?filterId=1&keywords=系统功能&ratingUI=1&withConfigCard=1&configCardExtraData=%7B%22withRanking%22%3A1%7D&title=热门功能';
                    HapticFeedbackUtil.selection();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ApiListPage(
                          api: widget.api,
                          title: title,
                          path: '/v6/page/dataList',
                          query: {'url': targetUrl},
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          subTitle.isNotEmpty ? subTitle : '榜单',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _buildHotFeatureItem(children[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHotFeatureItem(Map<String, dynamic> item) {
    final image = _image(item);
    final title = (item['title'] ?? item['name'] ?? '').toString();
    final hot = _formatNum(item['hot_num_txt'] ?? item['hot_num'] ?? '');
    final comments = _formatNum(
      item['commentnum'] ??
          item['commentNum'] ??
          item['feedCommentNumTxt'] ??
          '',
    );
    final score = (item['star_average_score'] ?? item['score'] ?? '')
        .toString();
    final scoreNum = (double.tryParse(score) ?? 0.0) / 2.0;

    return InkWell(
      onTap: () => _openRoute(item),
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                normalizeCoolapkImageUrl(image),
                headers: coolapkImageHeaders(image, api: widget.api),
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.apps_rounded, size: 36),
              ),
            )
          else
            const Icon(Icons.apps_rounded, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (hot.isNotEmpty) '🔥 $hot热度',
                    if (comments.isNotEmpty) '$comments讨论',
                  ].join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (score.isNotEmpty) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        _starIcon(scoreNum, i),
                        size: 13,
                        color: const Color(0xFFFFB300),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicAreaHeader(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? '动态区').toString();
    final sortEntities = children.isNotEmpty
        ? children
        : [
            {
              'title': '最近回复',
              'url': '#/feed/targetFeedList?tagKeywords=2024rom&sortField=lastupdate_desc',
            },
            {
              'title': '热门排序',
              'url': '#/feed/targetFeedList?tagKeywords=2024rom&sortField=rank_score',
            },
          ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(2.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sort in sortEntities)
                  _buildSortTab(
                    sort['title'].toString(),
                    sort['url'].toString(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortTab(String title, String url) {
    final isSelected = _selectedSortTitle == title;
    return InkWell(
      onTap: () => _onSortTabChanged(title, url),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _onSortTabChanged(String title, String url) async {
    if (_selectedSortTitle == title || _loading) return;
    final previousTitle = _selectedSortTitle;
    final previousUrl = _activeUrl;
    HapticFeedbackUtil.selection();
    setState(() {
      _selectedSortTitle = title;
    });
    if (widget.initialSortTitle != null) {
      _activeUrl = url;
      await _load(refresh: true);
      if (mounted && _error != null) {
        setState(() {
          _selectedSortTitle = previousTitle;
          _activeUrl = previousUrl;
        });
      }
      return;
    }

    final dynamicIndex = _items.indexWhere(
      (item) =>
          (item['title'] ?? '').toString().contains('动态区') ||
          (item['entityTemplate'] ?? '').toString().toLowerCase() ==
              'sortselectcard',
    );
    if (dynamicIndex < 0) return;

    if (title.contains('最近回复') && _cachedRecentFeeds != null) {
      setState(() {
        _items.removeRange(dynamicIndex + 1, _items.length);
        _items.addAll(_cachedRecentFeeds!);
      });
      return;
    }

    if (title.contains('热门') && _cachedHotFeeds != null) {
      setState(() {
        _items.removeRange(dynamicIndex + 1, _items.length);
        _items.addAll(_cachedHotFeeds!);
      });
      return;
    }

    try {
      final res = await widget.api.getList(
        '/v6/page/dataList',
        query: {'url': url, 'page': 1},
      );
      if (!mounted) return;
      final newFeeds = res.items
          .where(
            (it) => (it['entityType'] ?? '').toString().toLowerCase() != 'card',
          )
          .toList();
      setState(() {
        if (title.contains('热门')) {
          _cachedHotFeeds = newFeeds;
        } else {
          _cachedRecentFeeds = newFeeds;
        }
        _items.removeRange(dynamicIndex + 1, _items.length);
        _items.addAll(newFeeds);
      });
    } catch (_) {
      // Keep existing feeds on error
    }
  }

  IconData _starIcon(double stars, int index) {
    final diff = stars - index;
    if (diff >= 0.6) {
      return Icons.star_rounded;
    } else if (diff >= 0.2) {
      return Icons.star_half_rounded;
    } else {
      return Icons.star_outline_rounded;
    }
  }

  static String _formatNum(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    if (s.contains('万') || s.contains('w') || s.contains('W')) return s;
    final numVal = int.tryParse(s);
    if (numVal != null && numVal >= 10000) {
      final v = (numVal / 10000.0).toStringAsFixed(1);
      return v.endsWith('.0') ? '${v.substring(0, v.length - 2)}万' : '$v万';
    }
    return s;
  }

  String _image(Map<String, dynamic> item) {
    final raw =
        (item['logo'] ??
                item['icon'] ??
                item['pic'] ??
                item['cover'] ??
                item['image'] ??
                item['thumb'] ??
                item['tagLogo'] ??
                item['tag_logo'] ??
                item['img'] ??
                item['avatar'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;
    if (widget.system) {
      final title = (item['title'] ?? item['name'] ?? '').toString();
      final preset = DigitalSystemHelper.getSystemPresetLogo(title);
      if (preset != null && preset.isNotEmpty) return preset;
    }
    return '';
  }

  Widget _systemShortcut(Map<String, dynamic> item) {
    final image = _image(item);
    final title = (item['title'] ?? item['name'] ?? '').toString();
    return InkWell(
      onTap: () => _openRoute(item),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(image),
                  headers: coolapkImageHeaders(image, api: widget.api),
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.system_update_alt_rounded, size: 20),
                ),
              )
            else
              const Icon(Icons.system_update_alt_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRoute(Map<String, dynamic> item) {
    final url = (item['url'] ?? '').toString();
    final title = (item['title'] ?? item['name'] ?? '').toString();
    final logo = _image(item);
    if (url.isEmpty) return;
    HapticFeedbackUtil.selection();

    if (url.startsWith('/t/')) {
      final tag = Uri.decodeComponent(url.substring(3));
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(
            api: widget.api,
            tag: tag,
            initialTitle: title.isNotEmpty ? title : tag,
            initialLogo: logo.isNotEmpty ? logo : null,
          ),
        ),
      );
      return;
    }

    final entityType = (item['entityType'] ?? '').toString().toLowerCase();
    if (entityType == 'topic') {
      final tag = (item['title'] ?? item['name'] ?? '').toString();
      if (tag.isNotEmpty) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => TopicPage(
              api: widget.api,
              tag: tag,
              initialTitle: title,
              initialLogo: logo.isNotEmpty ? logo : null,
            ),
          ),
        );
        return;
      }
    }

    if (entityType == 'product' || url.contains('/product/')) {
      var id = (item['id'] ?? item['productId'] ?? item['entityId'] ?? '')
          .toString();
      if (id.isEmpty && url.contains('/product/')) {
        final rest = url.substring(
          url.indexOf('/product/') + '/product/'.length,
        );
        id = rest.split(RegExp(r'[/?#&]')).first;
      }
      if (id.isNotEmpty && int.tryParse(id) != null) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ProductPage(api: widget.api, id: id, title: title),
          ),
        );
        return;
      }
    }

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

  String _cleanHeat(String text) {
    return text.replaceAll('热度', '').replaceAll('讨论', '').trim();
  }

  static double _parseBannerAspectRatio(String url) {
    if (url.isNotEmpty) {
      final match = RegExp(r'@(\d+)x(\d+)').firstMatch(url);
      if (match != null) {
        final w = double.tryParse(match.group(1)!) ?? 1080.0;
        final h = double.tryParse(match.group(2)!) ?? 360.0;
        final rawRatio = w / h;
        if (rawRatio < 3.4) {
          return 3.0;
        }
        return rawRatio.clamp(3.0, 4.5);
      }
    }
    return 3.0;
  }

  Widget _buildBannerCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final banners = (children.isNotEmpty ? children : [entity])
        .where((b) => _image(b).isNotEmpty)
        .toList();
    if (banners.isEmpty) return const SizedBox.shrink();

    final quickLinks = entity['quickLinks'] is List
        ? (entity['quickLinks'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : null;

    final colorScheme = Theme.of(context).colorScheme;
    final firstBannerUrl = _image(banners.first);
    final ratio = _parseBannerAspectRatio(firstBannerUrl);
    final hasQuickLinks = quickLinks != null && quickLinks.isNotEmpty;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: hasQuickLinks
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: ratio,
              child: PageView.builder(
                itemCount: banners.length,
                itemBuilder: (context, index) {
                  final banner = banners[index];
                  final url = _image(banner);
                  return InkWell(
                    onTap: () => _openRoute(banner),
                    child: CachedNetworkImage(
                      normalizeCoolapkImageUrl(url),
                      headers: coolapkImageHeaders(url, api: widget.api),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ),
          ),
          if (hasQuickLinks)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Row(
                children: [
                  for (final link in quickLinks)
                    Expanded(
                      child: InkWell(
                        onTap: () => _openRoute(link),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_image(link).isNotEmpty) ...[
                                CachedNetworkImage(
                                  normalizeCoolapkImageUrl(_image(link)),
                                  headers: coolapkImageHeaders(
                                    _image(link),
                                    api: widget.api,
                                  ),
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                (link['title'] ?? link['name'] ?? '')
                                    .toString(),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniLinkGridCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            for (final link in children)
              Expanded(
                child: InkWell(
                  onTap: () => _openRoute(link),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_image(link).isNotEmpty) ...[
                          CachedNetworkImage(
                            normalizeCoolapkImageUrl(_image(link)),
                            headers: coolapkImageHeaders(
                              _image(link),
                              api: widget.api,
                            ),
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          (link['title'] ?? link['name'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankGridCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? '今日热门').toString();
    final subTitle = (entity['subTitle'] ?? '').toString();
    final moreUrl = (entity['moreUrl'] ?? entity['url'] ?? '').toString();
    final colorScheme = Theme.of(context).colorScheme;
    final displayItems = children.take(8).toList();

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.isNotEmpty ? title : '今日热门',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                InkWell(
                  onTap: () {
                    final target = moreUrl.isNotEmpty
                        ? moreUrl
                        : '#/product/hotProductList?hotType=day&category_id[]=1001&withConfigCard=1&configCardExtraData=%7B%22withRanking%22%3A1%7D&title=今日热门';
                    _openRoute({'url': target, 'title': title});
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (subTitle.isNotEmpty && subTitle != title)
                          Text(
                            subTitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: i < displayItems.length
                        ? _buildRankItem(displayItems[i], i + 1)
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            if (displayItems.length > 4) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 4; i < 8; i++)
                    Expanded(
                      child: i < displayItems.length
                          ? _buildRankItem(displayItems[i], i + 1)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRankItem(Map<String, dynamic> item, int rank) {
    final title = (item['title'] ?? item['name'] ?? '产品').toString();
    final image = _image(item);
    final hot = (item['hot_num_txt'] ?? item['hot_num'] ?? '').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openRoute(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: image.isNotEmpty
                      ? CachedNetworkImage(
                          normalizeCoolapkImageUrl(image),
                          headers: coolapkImageHeaders(image, api: widget.api),
                          height: 54,
                          width: 50,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.tablet_android_rounded,
                            size: 36,
                          ),
                        )
                      : const Icon(Icons.tablet_android_rounded, size: 36),
                ),
                Positioned(left: 0, top: 0, child: RankRibbon(rank: rank)),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_fire_department,
                  size: 13,
                  color: Color(0xFFFF6D00),
                ),
                const SizedBox(width: 2),
                Text(
                  formatDigitalHot(hot),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6D00),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHorizonCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    if (children.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: SizedBox(
        height: 126,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: (children.length + 1) ~/ 2,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, colIndex) {
            final topIndex = colIndex * 2;
            final bottomIndex = colIndex * 2 + 1;
            final topBrand = children[topIndex];
            final bottomBrand = bottomIndex < children.length
                ? children[bottomIndex]
                : null;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBrandTile(topBrand, colorScheme),
                const SizedBox(height: 8),
                if (bottomBrand != null)
                  _buildBrandTile(bottomBrand, colorScheme)
                else
                  const SizedBox(width: 68, height: 58),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandTile(Map<String, dynamic> brand, ColorScheme colorScheme) {
    final title = (brand['title'] ?? brand['name'] ?? '').toString();
    final logo = _image(brand);

    return InkWell(
      onTap: () => _openRoute(brand),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            alignment: Alignment.center,
            child: logo.isNotEmpty
                ? CachedNetworkImage(
                    normalizeCoolapkImageUrl(logo),
                    headers: coolapkImageHeaders(logo, api: widget.api),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 68,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconGridCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? entity['subTitle'] ?? '').toString();
    final subTitle = (entity['subTitle'] ?? '').toString();
    final moreUrl = (entity['moreUrl'] ?? entity['url'] ?? '').toString();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (moreUrl.isNotEmpty || subTitle.isNotEmpty)
                    InkWell(
                      onTap: () => _openRoute({'url': moreUrl, 'title': title}),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              subTitle.isNotEmpty && subTitle != title
                                  ? subTitle
                                  : '更多',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: i < children.length
                        ? _buildIconGridItem(children[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconGridItem(Map<String, dynamic> item) {
    final title = (item['title'] ?? item['name'] ?? '').toString();
    final subTitle = (item['subTitle'] ?? '').toString();
    final image = _image(item);
    final heat = item['hot_num_txt'] ?? item['hot_num'] ?? subTitle;
    final heatText = _cleanHeat(heat.toString());
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _openRoute(item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: image.isNotEmpty
                    ? CachedNetworkImage(
                        normalizeCoolapkImageUrl(image),
                        headers: coolapkImageHeaders(image, api: widget.api),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.computer_rounded, size: 28),
                      )
                    : const Icon(Icons.computer_rounded, size: 28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (heatText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 1),
                  Flexible(
                    child: Text(
                      heatText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIconListCard(
    Map<String, dynamic> entity,
    List<Map<String, dynamic>> children,
  ) {
    final title = (entity['title'] ?? entity['subTitle'] ?? '').toString();
    final subTitle = (entity['subTitle'] ?? '').toString();
    final moreUrl = (entity['moreUrl'] ?? entity['url'] ?? '').toString();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (moreUrl.isNotEmpty || subTitle.isNotEmpty)
                    InkWell(
                      onTap: () => _openRoute({'url': moreUrl, 'title': title}),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subTitle.isNotEmpty && subTitle != title)
                              Text(
                                subTitle,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            else if (title != '最新产品')
                              Text(
                                '更多',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            for (final child in children) _buildProductListItem(child),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListItem(Map<String, dynamic> product) {
    final title = (product['title'] ?? product['name'] ?? '数码产品').toString();
    final image = _image(product);
    final hotRaw = product['hot_num_txt'] ?? product['hot_num'] ?? '';
    final hotTxt = formatDigitalHot(hotRaw);
    final comments =
        (product['feed_comment_num'] ??
                product['feedCommentNumTxt'] ??
                product['commentnum'] ??
                product['commentNum'] ??
                '')
            .toString();
    final scoreStr =
        (product['star_average_score'] ??
                product['score'] ??
                product['rating_score'] ??
                '')
            .toString();
    final scoreNum = double.tryParse(scoreStr) ?? 0.0;
    final isUnreleased =
        product['release_status'] == 0 || product['release_status'] == '0';
    final releaseTime = (product['release_time'] ?? '').toString();

    Map<String, dynamic>? extra;
    try {
      final rawExtra = product['extraData'];
      if (rawExtra is Map) {
        extra = Map<String, dynamic>.from(rawExtra);
      } else if (rawExtra is String && rawExtra.isNotEmpty) {
        extra = jsonDecode(rawExtra) as Map<String, dynamic>?;
      }
    } catch (_) {}

    final extraRightTop = extra?['rightTopText']?.toString() ?? '';
    final extraRightBottom = extra?['rightBottomText']?.toString() ?? '';
    final hasExtraRank = extraRightTop.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final isBrandProductList = widget.groupProductRows;
    final productImage = image.isNotEmpty
        ? CachedNetworkImage(
            normalizeCoolapkImageUrl(image),
            headers: coolapkImageHeaders(image, api: widget.api),
            width: isBrandProductList ? 60 : 54,
            height: isBrandProductList ? 60 : 54,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.devices_other_rounded, size: 32),
          )
        : const Icon(Icons.devices_other_rounded, size: 32);

    return InkWell(
      onTap: () => _openRoute(product),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left thumbnail
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isBrandProductList)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: productImage,
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: productImage,
                    ),
                  if (isUnreleased)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '-- 未发布 --',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Middle title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isBrandProductList
                          ? FontWeight.w400
                          : FontWeight.bold,
                      color: isBrandProductList ? colorScheme.onSurface : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (hotTxt.isNotEmpty) ...[
                        const Icon(
                          Icons.local_fire_department,
                          size: 13,
                          color: Color(0xFFFF5722),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$hotTxt热度',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (comments.isNotEmpty && comments != '0') ...[
                        const SizedBox(width: 8),
                        Text(
                          '$comments讨论',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right status/score/date
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasExtraRank) ...[
                  Text(
                    extraRightTop,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8F00),
                    ),
                  ),
                  Text(
                    extraRightBottom,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (isUnreleased && releaseTime.isNotEmpty) ...[
                  Text(
                    releaseTime,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00B074),
                    ),
                  ),
                  Text(
                    '发布时间',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (scoreNum > 0) ...[
                  Text(
                    scoreStr,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isBrandProductList
                          ? colorScheme.onSurface
                          : const Color(0xFFFF8F00),
                    ),
                  ),
                  if (isBrandProductList) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < 5; index++) ...[
                          if (index > 0) const SizedBox(width: 2),
                          _buildProductRatingStar(scoreNum, index, colorScheme),
                        ],
                      ],
                    ),
                  ] else
                    Text(
                      '综合评分',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ] else ...[
                  Text(
                    '暂无人评分',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRatingStar(
    double score,
    int index,
    ColorScheme colorScheme,
  ) {
    final roundedScore = score.roundToDouble() / 2;
    final icon = _starIcon(roundedScore, index);
    final isEmpty = icon == Icons.star_outline_rounded;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isEmpty ? colorScheme.outlineVariant : const Color(0xFFDFA900),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Icon(
        isEmpty ? Icons.star_rounded : icon,
        size: 9,
        color: isEmpty ? Colors.white54 : Colors.white,
      ),
    );
  }
}

String _key(Map<String, dynamic> item) {
  final id =
      (item['id'] ?? item['entityId'] ?? item['url'] ?? item['title'] ?? '')
          .toString();
  if (id.isNotEmpty) {
    return '${item['entityType']}:$id:${item['entityTemplate']}';
  }
  final entities = item['entities'];
  if (entities is List && entities.isNotEmpty) {
    final first = entities.first;
    if (first is Map) {
      final childId =
          (first['id'] ??
                  first['entityId'] ??
                  first['url'] ??
                  first['title'] ??
                  first['name'] ??
                  '')
              .toString();
      if (childId.isNotEmpty) {
        return '${item['entityType']}:child_$childId:${item['entityTemplate']}';
      }
    }
  }
  return '${item['entityType']}:${identityHashCode(item)}:${item['entityTemplate']}';
}
