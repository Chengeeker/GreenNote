import 'dart:async';
import 'dart:convert';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/review_refresh_header.dart';
import '../feed/feed_pages.dart';
import '../feed/image_gallery_page.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/utils/spring_page_route.dart';
import 'api_list_page.dart';
import 'home_destination_page.dart' show officialHomeTheme;
import 'community_library_page.dart';
import 'community_ui.dart';

({String path, Map<String, dynamic> query}) discoveryPageRequest(String route) {
  final resolved = route.replaceAll(r'${uid}', '');
  final uri = Uri.parse(resolved);
  if (resolved.startsWith('/page?') || resolved.startsWith('/page/dataList?')) {
    return (path: '/v6/page/dataList', query: {...uri.queryParameters});
  }
  if (resolved.startsWith('/v6/') || resolved.startsWith('/user/')) {
    return (
      path: resolved.startsWith('/v6/') ? uri.path : '/v6${uri.path}',
      query: {...uri.queryParameters},
    );
  }
  return (path: '/v6/page/dataList', query: {'url': resolved});
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.isNotEmpty) {
    try {
      return _map(jsonDecode(value));
    } on FormatException {
      return {};
    }
  }
  return {};
}

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : [];
String _text(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _plain(String text) => html.parseFragment(text).text ?? '';
String _template(Map<String, dynamic> row) => _text(row, ['entityTemplate']);
bool _body(Map<String, dynamic> row) =>
    _text(row, ['entityType']).toLowerCase().contains('feed') ||
    _text(row, ['entityType']).toLowerCase().contains('dyharticle');
bool _pearGoods(Map<String, dynamic> row) =>
    _text(row, ['entityType']).toLowerCase() == 'pear_goods';
bool _visible(Map<String, dynamic> row) => !const {
  'configCard',
  'sponsorCard',
  'noMoreDataCard',
  'noMoreData',
  'fabCard',
}.contains(_template(row));

class DiscoveryChannelPage extends StatefulWidget {
  const DiscoveryChannelPage({
    required this.api,
    required this.title,
    required this.route,
    super.key,
  });
  final CoolapkApi api;
  final String title;
  final String route;
  @override
  State<DiscoveryChannelPage> createState() => _DiscoveryChannelPageState();
}

class _DiscoveryChannelPageState extends State<DiscoveryChannelPage>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _headers = [];
  final _items = <Map<String, dynamic>>[];
  late String _source = widget.route;
  String _selected = '';
  String _first = '', _last = '';
  int _page = 0, _revision = 0;
  bool _loading = false, _more = true;
  Object? _error;
  List<Map<String, dynamic>> _subscriptions = [];
  bool _subscriptionsMore = false;
  String? _subscriptionError;
  late String _subscriptionSession = widget.api.notificationSessionKey;
  int _subscriptionVersion = 0;
  ({String source, String selected, bool refresh})? _failedRequest;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void didUpdateWidget(covariant DiscoveryChannelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route || oldWidget.api != widget.api) {
      _subscriptions = [];
      _source = widget.route;
      _selected = '';
      _headers = [];
      _load(refresh: true, replaceRequest: true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_error == null &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 500) {
      _load(refresh: false);
    }
  }

  Future<ApiPage> _request(String route, int page, {bool refresh = false}) {
    final request = discoveryPageRequest(route);
    return widget.api.getList(
      request.path,
      query: {
        ...request.query,
        'page': page,
        if (!refresh && _first.isNotEmpty) 'firstItem': _first,
        if (!refresh && _last.isNotEmpty) 'lastItem': _last,
      },
    );
  }

  Future<void> _load({
    required bool refresh,
    bool replaceRequest = false,
  }) async {
    if (_loading && !replaceRequest || !refresh && !_more) return;
    final revision = ++_revision;
    final source = _source;
    if (refresh && widget.title == '看看号') unawaited(_loadSubscriptions());
    final next = refresh ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = await _request(source, next, refresh: refresh);
      if (!mounted || revision != _revision) return;
      if (refresh && source == widget.route) {
        final productFeed = widget.title == '酷品';
        final headers = result.items
            .where(
              (row) =>
                  !_body(row) &&
                  !(productFeed && _pearGoods(row)) &&
                  _visible(row),
            )
            .where(
              (row) =>
                  widget.title != '看看号' ||
                  (!const {
                        'unLoginCard',
                        'imageCard',
                      }.contains(_template(row)) &&
                      !_text(row, ['title']).contains('我订阅')),
            )
            .toList();
        // Flex channel roots contain only configuration and header modules.
        final config = result.items
            .where((row) => _template(row) == 'configCard')
            .map((row) => _map(row['extraDataArr'] ?? row['extraData']))
            .where((extra) => '${extra['flexList']}' == '1')
            .firstOrNull;
        setState(() => _headers = headers);
        final flex = _text(config ?? {}, ['url']);
        if (flex.isNotEmpty) {
          _source = flex;
          result = await _request(flex, 1, refresh: true);
          if (!mounted || revision != _revision) return;
        } else {
          final selector = headers
              .where(
                (row) => const {
                  'selectorLinkCard',
                  'sortSelectCard',
                }.contains(_template(row)),
              )
              .firstOrNull;
          final options = _rows(selector?['entities']);
          if (options.isNotEmpty) {
            final extra = _map(
              selector?['extraDataArr'] ?? selector?['extraData'],
            );
            final chosen =
                options
                    .where((row) => row['title'] == extra['selectedTab'])
                    .firstOrNull ??
                options.first;
            _selected = _text(chosen, ['url']);
            if (_selected.isNotEmpty) _source = _selected;
          }
        }
      }
      final bodies = result.items.where(
        (row) =>
            (_body(row) || widget.title == '酷品' && _pearGoods(row)) &&
            _visible(row),
      );
      setState(() {
        if (refresh) _items.clear();
        final known = _items.map(coolapkEntityKey).toSet();
        _items.addAll(bodies.where((row) => known.add(coolapkEntityKey(row))));
        _page = next;
        _first = result.firstItem;
        _last = result.lastItem;
        _more = result.hasMore && result.items.isNotEmpty;
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = error;
          _failedRequest = (
            source: _source,
            selected: _selected,
            refresh: refresh,
          );
        });
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _loadSubscriptions() async {
    final version = ++_subscriptionVersion;
    if (!widget.api.hasCookie) {
      if (mounted) {
        setState(() {
          _subscriptions = [];
          _subscriptionError = null;
        });
      }
      return;
    }
    final scope = widget.api.notificationSessionKey;
    _subscriptionSession = scope;
    try {
      final page = await widget.api.getList(
        '/v6/user/dyhFollowList',
        query: {'page': 1},
      );
      if (!mounted ||
          version != _subscriptionVersion ||
          scope != widget.api.notificationSessionKey ||
          scope != _subscriptionSession) {
        return;
      }
      setState(() {
        _subscriptions = page.items;
        _subscriptionsMore = page.hasMore;
        _subscriptionError = null;
      });
    } catch (_) {
      if (mounted &&
          version == _subscriptionVersion &&
          scope == widget.api.notificationSessionKey) {
        setState(() => _subscriptionError = '订阅状态暂未加载');
      }
    }
  }

  List<Object> _displayItems() {
    final rows = <Object>[];
    for (var index = 0; index < _items.length;) {
      if (widget.title == '酷品' && _pearGoods(_items[index])) {
        final products = <Map<String, dynamic>>[];
        while (index < _items.length && _pearGoods(_items[index])) {
          products.add(_items[index++]);
          if (products.length == 3) break;
        }
        rows.add(products);
      } else {
        rows.add(_items[index++]);
      }
    }
    return rows;
  }

  void _select(String route) async {
    if (route.isEmpty || route == _selected) return;
    final previousSource = _source;
    final previousSelected = _selected;
    setState(() {
      _source = route;
      _selected = route;
    });
    final revision = _revision + 1;
    await _load(refresh: true, replaceRequest: true);
    if (mounted &&
        revision == _revision &&
        _source == route &&
        _error != null) {
      setState(() {
        _source = previousSource;
        _selected = previousSelected;
      });
    }
  }

  void _retry() {
    final failed = _failedRequest;
    if (failed == null) return;
    if (failed.selected != _selected) {
      _select(failed.source);
    } else {
      _source = failed.source;
      _load(refresh: failed.refresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = officialHomeTheme(Theme.of(context));
    final coolPictures = widget.title == '酷图';
    final waterfall =
        coolPictures || widget.title == '二手' || widget.title == '商家';
    final lanes = List.generate(
      coolPictures ? 3 : 2,
      (_) => <({Map<String, dynamic> row, int imageIndex})>[],
    );
    final heights = List.filled(lanes.length, 0.0);
    if (coolPictures) {
      for (final row in _items) {
        final feed = CoolapkFeed.fromJson(row);
        final imageCount = feed.pictures.isNotEmpty
            ? feed.pictures.length
            : (feed.coverUrl.isEmpty ? 0 : 1);
        for (var imageIndex = 0; imageIndex < imageCount; imageIndex++) {
          final lane = heights.indexOf(heights.reduce((a, b) => a < b ? a : b));
          lanes[lane].add((row: row, imageIndex: imageIndex));
          heights[lane] += 1 / _coolPictureAspectRatioAt(feed, row, imageIndex);
        }
      }
    } else {
      for (var index = 0; index < _items.length; index++) {
        final row = _items[index];
        final lane = index % 2;
        lanes[lane].add((row: row, imageIndex: 0));
        heights[lane]++;
      }
    }
    final displayItems = _displayItems();
    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF101010)
            : theme.colorScheme.surface,
        child: EasyRefresh(
          header: reviewDefaultRefreshHeader,
          triggerAxis: Axis.vertical,
          onRefresh: () => _load(refresh: true),
          child: filterHorizontalScrollNotifications(
            CustomScrollView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                if (widget.title == '看看号')
                  SliverToBoxAdapter(
                    child: _surfaceCard(
                      context,
                      InkWell(
                        onTap: () {
                          if (!widget.api.hasCookie) {
                            AppToast.show(
                              context,
                              widget.api.loginRequiredMessage,
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommunityLibraryPage(
                                api: widget.api,
                                library: CommunityLibrary.dyh,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '我订阅的看看号',
                                      style: TextStyle(fontSize: 17),
                                    ),
                                    if (_subscriptionError != null)
                                      Text(
                                        _subscriptionError!,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                  ],
                                ),
                              ),
                              for (final sub in _subscriptions.take(2))
                                Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: AppAvatar(
                                    api: widget.api,
                                    url: _text(sub, ['logo', 'userAvatar']),
                                    size: 28,
                                  ),
                                ),
                              if (_subscriptions.isNotEmpty)
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: const Color(0xFF009688),
                                  child: Text(
                                    '${_subscriptions.length}${_subscriptionsMore ? '+' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverList.builder(
                  itemCount: _headers.length,
                  itemBuilder: (context, index) => DiscoveryModule(
                    api: widget.api,
                    channel: widget.title,
                    row: _headers[index],
                    selectedRoute: _selected,
                    onSelect: _select,
                  ),
                ),
                if (waterfall)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    sliver: SliverCrossAxisGroup(
                      slivers: [
                        for (var lane = 0; lane < lanes.length; lane++)
                          SliverCrossAxisExpanded(
                            flex: 1,
                            sliver: SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              sliver: SliverList.builder(
                                itemCount: lanes[lane].length,
                                itemBuilder: (context, index) {
                                  final item = lanes[lane][index];
                                  return RepaintBoundary(
                                    child: coolPictures
                                        ? DiscoveryPictureTile(
                                            key: ValueKey(
                                              'coolpic-${coolapkEntityKey(item.row)}-${item.imageIndex}',
                                            ),
                                            api: widget.api,
                                            row: item.row,
                                            imageIndex: item.imageIndex,
                                          )
                                        : DiscoveryWaterfallCard(
                                            key: ValueKey(
                                              coolapkEntityKey(item.row),
                                            ),
                                            api: widget.api,
                                            row: item.row,
                                            secondhand: widget.title == '二手',
                                          ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: displayItems.length,
                    itemBuilder: (context, index) {
                      final item = displayItems[index];
                      if (item is List<Map<String, dynamic>>) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var column = 0; column < 3; column++) ...[
                                if (column > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: column < item.length
                                      ? _DiscoveryPearGoodsTile(
                                          key: ValueKey(
                                            'cool-products-${coolapkEntityKey(item[column])}',
                                          ),
                                          api: widget.api,
                                          row: item[column],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      final row = item as Map<String, dynamic>;
                      if (_template(row) == 'goodsRankingCard') {
                        return DiscoveryGoodsRanking(api: widget.api, row: row);
                      }
                      final subscription = widget.title == '看看号'
                          ? _rows(row['relationRows'])
                                .where(
                                  (item) =>
                                      _text(item, ['url']).startsWith('/dyh/'),
                                )
                                .firstOrNull
                          : null;
                      return FeedCard(
                        key: ValueKey(coolapkEntityKey(row)),
                        api: widget.api,
                        feed: CoolapkFeed.fromJson(row),
                        officialLayout: true,
                        picturesBeforeText: widget.title == '酷图',
                        authorHeader: subscription == null
                            ? null
                            : DiscoveryArticleHeader(
                                api: widget.api,
                                row: row,
                                source: subscription,
                              ),
                      );
                    },
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _error != null
                        ? TextButton(
                            onPressed: _retry,
                            child: Text('加载失败，点击重试：$_error'),
                          )
                        : _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _items.isEmpty && _headers.isEmpty
                        ? const Center(child: Text('暂无内容'))
                        : const SizedBox.shrink(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 90 + MediaQuery.paddingOf(context).bottom,
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

Color _surface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF1E1E1E)
    : Theme.of(context).colorScheme.surfaceContainerLow;
Widget _surfaceCard(
  BuildContext context,
  Widget child, {
  EdgeInsetsGeometry? padding,
  BorderRadius? borderRadius,
  Color? color,
}) => Container(
  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
  padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
  decoration: BoxDecoration(
    color: color ?? _surface(context),
    borderRadius: borderRadius ?? BorderRadius.circular(12),
  ),
  child: child,
);

class DiscoveryModule extends StatelessWidget {
  const DiscoveryModule({
    required this.api,
    required this.channel,
    required this.row,
    required this.selectedRoute,
    required this.onSelect,
    super.key,
  });
  final CoolapkApi api;
  final String channel;
  final Map<String, dynamic> row;
  final String selectedRoute;
  final ValueChanged<String> onSelect;
  void _open(BuildContext context, Map<String, dynamic> item) =>
      openHeadlineTarget(context, api, item);
  Widget _heading(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: InkWell(
      onTap: _text(row, ['url']).isEmpty ? null : () => _open(context, row),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _text(row, ['title']),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
          ),
          if (_text(row, ['url']).isNotEmpty) ...[
            Text(
              _text(row, ['subTitle']),
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 23),
          ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final template = _template(row);
    final items = _rows(row['entities']);
    if (template == 'sortSelectCard' || template == 'selectorLinkCard') {
      if (items.isEmpty) return const SizedBox.shrink();
      final selected = selectedRoute.isEmpty
          ? _text(items.first, ['url'])
          : selectedRoute;
      final sort = template == 'sortSelectCard';
      final buttons = protectHorizontalDragFromVerticalRefresh(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: sort ? const EdgeInsets.all(2) : EdgeInsets.zero,
            decoration: sort
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  )
                : null,
            child: Row(
              children: [
                for (final item in items)
                  Padding(
                    padding: EdgeInsets.only(right: sort ? 0 : 8),
                    child: Material(
                      color: _text(item, ['url']) == selected
                          ? sort
                                ? _surface(context)
                                : const Color(0xFF009688)
                          : sort
                          ? Colors.transparent
                          : _surface(context),
                      borderRadius: BorderRadius.circular(sort ? 20 : 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(sort ? 20 : 10),
                        onTap: () => onSelect(_text(item, ['url'])),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: sort ? 10 : 13,
                            vertical: sort ? 6 : 8,
                          ),
                          child: Text(
                            _text(item, ['title']),
                            style: TextStyle(
                              fontSize: sort ? 13 : 15,
                              color: _text(item, ['url']) == selected && !sort
                                  ? Colors.white
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(sort ? 18 : 8, sort ? 4 : 0, 8, 8),
        child: sort
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      _text(row, ['title']),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Flexible(flex: 2, child: buttons),
                ],
              )
            : buttons,
      );
    }
    if (channel == '酷品' && template == 'iconButtonGridCard') {
      return _DiscoveryPromoGrid(api: api, row: row, items: items);
    }
    if (channel == '酷品' && template == 'iconLargeScrollCard') {
      return _DiscoveryGoodsCarousel(api: api, row: row, items: items);
    }
    if (template == 'iconMiniGridCard') {
      return _surfaceCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context),
            const SizedBox(height: 6),
            for (var i = 0; i < items.length; i += 2)
              Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(
                      child: i + col >= items.length
                          ? const SizedBox()
                          : InkWell(
                              onTap: () => _open(context, items[i + col]),
                              child: SizedBox(
                                height: 36,
                                child: Row(
                                  children: [
                                    _DiscoveryImage(
                                      api: api,
                                      url: _text(items[i + col], [
                                        'logo',
                                        'pic',
                                      ]),
                                      width: 20,
                                      height: 20,
                                      radius: 4,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        _text(items[i + col], ['title']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      );
    }
    if (template == 'imageSquareScrollCard' ||
        template == 'imageCarouselCard_1') {
      if (items.isEmpty) return const SizedBox.shrink();
      final square = template == 'imageSquareScrollCard';
      final width = MediaQuery.sizeOf(context).width - 16;
      final extra = _map(row['extraDataArr'] ?? row['extraData']);
      final dims = '${extra['dimensionRatio'] ?? '1080:240'}'.split(':');
      final configuredRatio = dims.length == 2
          ? (double.tryParse(dims[0]) ?? 1080) /
                (double.tryParse(dims[1]) ?? 240)
          : 4.5;
      final imageSize = RegExp('@([0-9]+)x([0-9]+)')
          .firstMatch(_text(items.first, ['pic', 'logo']));
      final imageWidth = double.tryParse(imageSize?.group(1) ?? '');
      final imageHeight = double.tryParse(imageSize?.group(2) ?? '');
      final ratio =
          channel == '酷品' &&
              imageWidth != null &&
              imageHeight != null &&
              imageWidth > 0 &&
              imageHeight > 0
          ? imageWidth / imageHeight
          : configuredRatio;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          key: channel == '酷品' ? const ValueKey('cool-products-banner') : null,
          height: square ? 68 : width / ratio,
          child: protectHorizontalDragFromVerticalRefresh(
            ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  onTap: () => _open(context, item),
                  child: SizedBox(
                    width: square ? 68 : width,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _DiscoveryImage(
                            api: api,
                            url: _text(item, ['pic', 'logo']),
                            fit: BoxFit.cover,
                          ),
                          if (square) ...[
                            const ColoredBox(color: Color(0x40000000)),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  _text(item, ['title']),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    if (template == 'iconLinkGridCard') {
      return _surfaceCard(
        context,
        Column(
          children: [
            for (var i = 0; i < items.length; i += 5)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < 5; col++)
                    Expanded(
                      child: i + col >= items.length
                          ? const SizedBox()
                          : InkWell(
                              onTap: () {
                                if (channel == '酷图') {
                                  onSelect(_text(items[i + col], ['url']));
                                } else {
                                  _open(context, items[i + col]);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  children: [
                                    _DiscoveryImage(
                                      api: api,
                                      url: _text(items[i + col], [
                                        'pic',
                                        'logo',
                                      ]),
                                      width: 32,
                                      height: 32,
                                      fit: BoxFit.contain,
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      _text(items[i + col], ['title']),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        borderRadius: channel == '好物榜'
            ? const BorderRadius.vertical(bottom: Radius.circular(12))
            : null,
      );
    }
    if (template == 'iconLongTitleGridCard') {
      final subscriptions = items.any((item) => item['entityType'] == 'dyh');
      final columns = subscriptions ? 3 : 4;
      return _surfaceCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i += columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < columns; col++)
                    Expanded(
                      child: i + col >= items.length
                          ? const SizedBox()
                          : subscriptions
                          ? _DyhRecommendation(api: api, row: items[i + col])
                          : InkWell(
                              onTap: () => _open(context, items[i + col]),
                              child: SizedBox(
                                height: 112,
                                child: Column(
                                  children: [
                                    Stack(
                                      children: [
                                        Center(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              6,
                                              8,
                                              6,
                                            ),
                                            child: _DiscoveryImage(
                                              api: api,
                                              url: _text(items[i + col], [
                                                'logo',
                                                'pic',
                                              ]),
                                              width: 58,
                                              height: 60,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          child: _RankRibbon(rank: i + col + 1),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _text(items[i + col], ['title']),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                ],
              ),
          ],
        ),
      );
    }
    if (template == 'iconGridCard') {
      return _surfaceCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(context),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final item in items.take(4))
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 4,
                    child: InkWell(
                      onTap: () => _open(context, item),
                      child: Column(
                        children: [
                          AppAvatar(
                            api: api,
                            url: _text(item, ['userAvatar', 'logo']),
                            size: 48,
                            name: _text(item, ['username', 'title']),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _text(item, ['username', 'title']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    }
    if (template == 'messageCard') {
      return _surfaceCard(
        context,
        Text.rich(
          TextSpan(
            children: [
              for (final node
                  in html
                      .parseFragment(_text(row, ['description', 'title']))
                      .nodes)
                if (node is dom.Element && node.localName == 'a')
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      onTap: () => _open(context, {
                        'url': node.attributes['href'] ?? '',
                      }),
                      child: Text(
                        node.text,
                        style: const TextStyle(
                          color: Color(0xFF009688),
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    ),
                  )
                else
                  TextSpan(text: node.text),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.25),
        ),
        padding: const EdgeInsets.all(12),
        color:
            channel == '二手' && Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0B201D)
            : null,
      );
    }
    if (template == 'iconListCard' &&
        items.any((item) => item['entityType'] == 'goodsList')) {
      return Column(
        children: [for (final item in items) _GoodsBanner(api: api, row: item)],
      );
    }
    if (template == 'unLoginCard') {
      return _surfaceCard(
        context,
        InkWell(
          onTap: () => AppToast.show(context, api.loginRequiredMessage),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('我订阅的看看号', style: TextStyle(fontSize: 17)),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }
    if (template == 'imageCard' || template == 'imageScaleCard') {
      final image = _text(row, ['pic', 'cover']);
      if (image.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: InkWell(
          onTap: () => _open(context, row),
          child: AspectRatio(
            aspectRatio: 1000 / 375,
            child: _DiscoveryImage(api: api, url: image, radius: 12),
          ),
        ),
      );
    }
    return ApiEntityCard(api: api, entity: row);
  }
}

class DiscoveryArticleHeader extends StatelessWidget {
  const DiscoveryArticleHeader({
    required this.api,
    required this.row,
    required this.source,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row, source;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      InkWell(
        onTap: () => openHeadlineTarget(context, api, source),
        child: _DiscoveryImage(
          api: api,
          url: _text(source, ['logo']),
          width: 32,
          height: 32,
          radius: 4,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => openHeadlineTarget(context, api, source),
              child: Text(
                _text(source, ['title']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 2),
            InkWell(
              onTap: () => openHeadlineTarget(context, api, {
                'url': '/u/${row['uid']}',
                'title': row['username'],
              }),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '来自 ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: _text(row, ['username']),
                      style: const TextStyle(color: Color(0xFF009688)),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      Text(
        _text(row, ['dateline_text']),
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
      const SizedBox(width: 8),
      const Icon(Icons.chevron_right, size: 22),
    ],
  );
}

class _DiscoveryImage extends StatelessWidget {
  const _DiscoveryImage({
    required this.api,
    required this.url,
    this.width,
    this.height,
    this.radius = 0,
    this.fit = BoxFit.cover,
  });
  final CoolapkApi api;
  final String url;
  final double? width, height;
  final double radius;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? SizedBox(width: width, height: height)
          : CachedNetworkImage(
              normalizeCoolapkImageUrl(url),
              headers: coolapkImageHeaders(url, api: api),
              width: width,
              height: height,
              fit: fit,
              cacheWidth: width != null || constraints.hasBoundedWidth
                  ? ((width ?? constraints.maxWidth) *
                            MediaQuery.devicePixelRatioOf(context))
                        .clamp(1, 1600)
                        .round()
                  : null,
              errorBuilder: (_, _, _) => SizedBox(
                width: width,
                height: height,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 20),
                ),
              ),
            ),
    ),
  );
}

class _DiscoveryPromoGrid extends StatelessWidget {
  const _DiscoveryPromoGrid({
    required this.api,
    required this.row,
    required this.items,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Column(
      children: [
        for (var start = 0; start < items.length; start += 2)
          Padding(
            padding: EdgeInsets.only(bottom: start + 2 < items.length ? 8 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < 2; column++)
                  Expanded(
                    child: start + column >= items.length
                        ? const SizedBox()
                        : Padding(
                            padding: EdgeInsets.only(
                              right: column == 0 ? 8 : 0,
                            ),
                            child: _banner(
                              context,
                              items[start + column],
                              start + column,
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _banner(BuildContext context, Map<String, dynamic> item, int index) {
    final image = _text(item, ['pic', 'logo']);
    final dimensions = RegExp('@([0-9]+)x([0-9]+)').firstMatch(image);
    final imageWidth = double.tryParse(dimensions?.group(1) ?? '');
    final imageHeight = double.tryParse(dimensions?.group(2) ?? '');
    final ratio =
        imageWidth != null &&
            imageHeight != null &&
            imageWidth > 0 &&
            imageHeight > 0
        ? imageWidth / imageHeight
        : 2.4;
    return InkWell(
      key: ValueKey('cool-products-promo-${_text(row, ['entityId'])}-$index'),
      onTap: () => openHeadlineTarget(context, api, item),
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: ratio,
          child: _DiscoveryImage(api: api, url: image),
        ),
      ),
    );
  }
}

class _DiscoveryGoodsCarousel extends StatelessWidget {
  const _DiscoveryGoodsCarousel({
    required this.api,
    required this.row,
    required this.items,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final width = ((MediaQuery.sizeOf(context).width - 56) / 3).clamp(
      96.0,
      160.0,
    );
    return _surfaceCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _text(row, ['url']).isEmpty
                ? null
                : () => openHeadlineTarget(context, api, row),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _text(row, ['title']),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_text(row, ['subTitle']).isNotEmpty)
                    Text(
                      _text(row, ['subTitle']),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 270,
            child: protectHorizontalDragFromVerticalRefresh(
              ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                  width: width,
                  child: _DiscoveryGoodsTile(
                    key: ValueKey('cool-products-item-$index'),
                    api: api,
                    row: items[index],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      borderRadius: BorderRadius.circular(18),
    );
  }
}

class _DiscoveryGoodsTile extends StatelessWidget {
  const _DiscoveryGoodsTile({required this.api, required this.row, super.key});
  final CoolapkApi api;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final title = _text(row, ['goods_title', 'title']);
    final image = _text(row, ['goods_pic', 'pic']);
    final price = _text(row, ['goods_promo_title']);
    final buyText = _text(row, ['goods_buy_text']);
    final buyUrl = _text(row, ['goods_buy_url']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _text(row, ['goods_url']).isEmpty
              ? null
              : () => openHeadlineTarget(context, api, {
                  ...row,
                  'url': _text(row, ['goods_url']),
                }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: _DiscoveryImage(api: api, url: image, radius: 9),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.2),
              ),
              if (price.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFF5149),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (buyText.isNotEmpty && buyUrl.isNotEmpty) ...[
          const Spacer(),
          SizedBox(
            height: 32,
            child: Material(
              color: const Color(0xFFE94D45),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () =>
                    openHeadlineTarget(context, api, {...row, 'url': buyUrl}),
                child: Center(
                  child: Text(
                    buyText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DiscoveryPearGoodsTile extends StatelessWidget {
  const _DiscoveryPearGoodsTile({
    required this.api,
    required this.row,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final buyUrl = _text(row, ['goods_buy_url']);
    final buyText = _text(row, ['goods_buy_text']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _text(row, ['goods_url']).isEmpty
              ? null
              : () => openHeadlineTarget(context, api, {
                  ...row,
                  'url': _text(row, ['goods_url']),
                }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: _DiscoveryImage(
                  api: api,
                  url: _text(row, ['goods_pic']),
                  radius: 10,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _text(row, ['goods_title', 'title']),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                _text(row, ['goods_promo_title']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFF5149),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (buyText.isNotEmpty && buyUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Material(
              color: const Color(0xFFE94D45),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: () =>
                    openHeadlineTarget(context, api, {...row, 'url': buyUrl}),
                borderRadius: BorderRadius.circular(18),
                child: Center(
                  child: Text(
                    buyText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DyhRecommendation extends StatefulWidget {
  const _DyhRecommendation({required this.api, required this.row});
  final CoolapkApi api;
  final Map<String, dynamic> row;
  @override
  State<_DyhRecommendation> createState() => _DyhRecommendationState();
}

class _DyhRecommendationState extends State<_DyhRecommendation> {
  late bool _following = '${_map(widget.row['userAction'])['follow']}' == '1';
  late final String _session;
  bool _working = false;
  @override
  void initState() {
    super.initState();
    _session = widget.api.hasCookie ? widget.api.notificationSessionKey : '';
  }

  Future<void> _subscribe() async {
    if (!widget.api.hasCookie) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    if (_working || _following) return;
    setState(() => _working = true);
    try {
      await communityRequest(
        widget.api,
        _session,
        '/v6/dyh/follow',
        method: 'POST',
        query: {'dyhId': widget.row['id']},
      );
      if (mounted) setState(() => _following = true);
    } catch (error) {
      if (mounted) AppToast.show(context, '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      children: [
        InkWell(
          onTap: () => openHeadlineTarget(context, widget.api, widget.row),
          child: Column(
            children: [
              _DiscoveryImage(
                api: widget.api,
                url: _text(widget.row, ['logo']),
                width: 56,
                height: 56,
                radius: 8,
              ),
              const SizedBox(height: 8),
              Text(
                _text(widget.row, ['title']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${_text(widget.row, ['follownum'])}人订阅',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _working || _following ? null : _subscribe,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF009688),
            foregroundColor: Colors.white,
            minimumSize: const Size(56, 28),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text(
            _working
                ? '…'
                : _following
                ? '已订阅'
                : '订阅',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _RankRibbon extends StatelessWidget {
  const _RankRibbon({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _RibbonClipper(),
    child: Container(
      width: 14,
      height: 18,
      alignment: Alignment.topCenter,
      color: [
        const Color(0xFFFF473B),
        const Color(0xFFFF9500),
        const Color(0xFFFFC400),
        const Color(0xFFC7DA27),
        const Color(0xFFB7B7B7),
      ][(rank - 1).clamp(0, 4)],
      child: Text(
        '$rank',
        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
      ),
    ),
  );
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width / 2, size.height - 4)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

class _GoodsBanner extends StatelessWidget {
  const _GoodsBanner({required this.api, required this.row});
  final CoolapkApi api;
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
    child: InkWell(
      onTap: () => openHeadlineTarget(context, api, row),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: AspectRatio(
          aspectRatio: 1680 / 720,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _DiscoveryImage(api: api, url: _text(row, ['cover', 'pic'])),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x88000000)],
                  ),
                ),
              ),
              if ('${row['recommend']}' != '0')
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC044),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '♨ 推荐',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 42,
                child: Text(
                  _text(row, ['title']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 16,
                child: Text(
                  '${row['item_num'] ?? 0}个好物  ${row['vote_num'] ?? 0}人投票',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DiscoveryGoodsRanking extends StatelessWidget {
  const DiscoveryGoodsRanking({
    required this.api,
    required this.row,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final info = _map(row['goodsListInfo']);
    final items = _rows(row['goodsListItem']).take(3).toList();
    void open() => openHeadlineTarget(context, api, row);
    return _surfaceCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _text(row, ['title', 'message_title']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF009688),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(20),
                    ),
                  ),
                  child: const Text(
                    '查看更多',
                    style: TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: open,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.07),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Stack(
                              children: [
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: _DiscoveryImage(
                                    api: api,
                                    url: _text(items[i], [
                                      'product_goods_cover',
                                      'pic',
                                    ]),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: [
                                        const Color(0xFFFFECA2),
                                        const Color(0xFFD0E7F7),
                                        const Color(0xFFFFDCB7),
                                      ][i],
                                      borderRadius: const BorderRadius.only(
                                        bottomRight: Radius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'TOP${i + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _text(items[i], [
                                      'product_goods_title',
                                      'title',
                                    ]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '¥${_text(items[i], ['price'])}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${info['item_num'] ?? items.length}个好物 · ${info['vote_num'] ?? 0}人投票',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                _text(row, ['dateline_text']),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    );
  }
}

@visibleForTesting
double coolPictureAspectRatioAt(Map<String, dynamic> row, int imageIndex) {
  final feed = CoolapkFeed.fromJson(row);
  return _coolPictureAspectRatioAt(feed, row, imageIndex);
}

double _coolPictureAspectRatioAt(
  CoolapkFeed feed,
  Map<String, dynamic> row,
  int imageIndex,
) {
  final url = imageIndex >= 0 && imageIndex < feed.pictures.length
      ? feed.pictures[imageIndex]
      : feed.coverUrl;
  final metadata = feed.pictureMetadata[url] ?? const <String, dynamic>{};
  final geo = _map(metadata['geo']);
  final size = RegExp(r'@(\d+)x(\d+)').firstMatch(url);
  final width = double.tryParse(
    '${metadata['width'] ?? metadata['w'] ?? geo['width'] ?? size?.group(1)}',
  );
  final height = double.tryParse(
    '${metadata['height'] ?? metadata['h'] ?? geo['height'] ?? size?.group(2)}',
  );
  return width != null && height != null && width > 0 && height > 0
      ? (width / height).clamp(0.35, 2.0)
      : 0.5;
}

class DiscoveryPictureTile extends StatefulWidget {
  const DiscoveryPictureTile({
    required this.api,
    required this.row,
    this.imageIndex = 0,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  final int imageIndex;

  @override
  State<DiscoveryPictureTile> createState() => _DiscoveryPictureTileState();
}

class _DiscoveryPictureTileState extends State<DiscoveryPictureTile> {
  double? _decodedRatio;
  String _decodedUrl = '';

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final row = widget.row;
    final feed = CoolapkFeed.fromJson(row);
    final imageIndex = widget.imageIndex;
    final urls = feed.pictures.isNotEmpty
        ? feed.pictures
        : [if (feed.coverUrl.isNotEmpty) feed.coverUrl];
    final pics = urls
        .map((url) => GalleryImage(url, raw: feed.pictureMetadata[url]))
        .toList();
    final currentPic = imageIndex < pics.length ? pics[imageIndex] : null;
    final imageUrl = currentPic?.previewUrl ?? '';
    if (_decodedUrl != imageUrl) {
      _decodedUrl = imageUrl;
      _decodedRatio = null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        label: '查看${feed.username}的酷图',
        child: GestureDetector(
          onTap: pics.isEmpty
              ? null
              : () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push(
                    PhysicsSpringGalleryRoute(
                      child: ImageGalleryPage(
                        api: api,
                        pics: pics,
                        initialIndex: imageIndex,
                        statusId: feed.id,
                        authorName: feed.username,
                        feed: feed,
                        heroScope: row,
                      ),
                    ),
                  );
                },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AspectRatio(
              aspectRatio:
                  _decodedRatio ?? coolPictureAspectRatioAt(row, imageIndex),
              child: pics.isEmpty
                  ? const Icon(Icons.broken_image_outlined)
                  : ImageGalleryHeroThumbnail(
                      api: api,
                      scope: row,
                      index: imageIndex,
                      pic: currentPic!,
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            ExtendedImage.network(
                              imageUrl,
                              cache: true,
                              headers: coolapkImageHeaders(imageUrl, api: api),
                              cacheWidth:
                                  (constraints.maxWidth *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round()
                                      .clamp(1, 720),
                              fit: BoxFit.cover,
                              loadStateChanged: (state) {
                                final info = state.extendedImageInfo;
                                if (state.extendedImageLoadState ==
                                        LoadState.completed &&
                                    info != null) {
                                  final ratio =
                                      (info.image.width / info.image.height)
                                          .clamp(0.35, 2.0);
                                  if (_decodedRatio != ratio) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted &&
                                              _decodedUrl == imageUrl &&
                                              _decodedRatio != ratio) {
                                            setState(
                                              () => _decodedRatio = ratio,
                                            );
                                          }
                                        });
                                  }
                                }
                                return null;
                              },
                            ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class DiscoveryWaterfallCard extends StatelessWidget {
  const DiscoveryWaterfallCard({
    required this.api,
    required this.row,
    required this.secondhand,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  final bool secondhand;
  @override
  Widget build(BuildContext context) {
    final feed = CoolapkFeed.fromJson(row);
    final media = _map(row['media_info']);
    final goods = _map(row[secondhand ? 'ershou_info' : 'goods']);
    final image = _text(media, ['cover']).isNotEmpty
        ? _text(media, ['cover'])
        : feed.pictures.firstOrNull ?? _text(goods, ['cover', 'product_logo']);
    final dimension = RegExp(r'@(\d+)x(\d+)').firstMatch(image);
    final width = double.tryParse(
      '${media['width'] ?? dimension?.group(1) ?? ''}',
    );
    final height = double.tryParse(
      '${media['height'] ?? dimension?.group(2) ?? ''}',
    );
    final ratio = !secondhand
        ? 0.75
        : width != null && height != null && height > 0
        ? (width / height).clamp(0.65, 1.4)
        : 0.75;
    final title = secondhand
        ? _text(row, ['message_title', 'title'])
        : feed.message;
    final price = _text(goods, secondhand ? ['product_price'] : ['price']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _surface(context),
        borderRadius: BorderRadius.circular(secondhand ? 5 : 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => FeedDetailPage(api: api, feed: feed),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: ratio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _DiscoveryImage(api: api, url: image),
                    if (!secondhand && '${row['media_type']}' == '2')
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          width: 21,
                          height: 21,
                          decoration: const BoxDecoration(
                            color: Color(0x66000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 19,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _plain(title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.25),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            price.isEmpty ? '' : '¥$price',
                            style: const TextStyle(
                              fontSize: 17,
                              color: Color(0xFFF44336),
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            secondhand
                                ? _text(goods, [
                                    'store_type_txt',
                                    'link_source',
                                  ])
                                : '${feed.replyCount}人评论',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (secondhand) ...[
                      const Divider(height: 22),
                      Row(
                        children: [
                          AppAvatar(
                            api: api,
                            url: feed.avatar,
                            size: 24,
                            name: feed.username,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feed.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '${feed.date}·${_text(goods, ['province'])} ${_text(goods, ['city'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
