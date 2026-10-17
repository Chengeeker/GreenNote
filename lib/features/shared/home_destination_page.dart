import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../../core/widgets/review_refresh_header.dart';
import '../feed/feed_pages.dart';
import '../shell/main_pages.dart' show ComposeFeedPage;
import 'api_list_page.dart';
import 'product_selector_page.dart';
import 'activity_pages.dart';

enum HomeDestination {
  editorial,
  news,
  activities,
  users,
  polls,
  headlines,
  official,
}

ThemeData officialHomeTheme(ThemeData base) {
  if (base.brightness != Brightness.dark) return base;
  const foreground = Color(0xFFCCCCCC);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFF009688),
      onSurface: foreground,
      onSurfaceVariant: const Color(0xFF999999),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      foregroundColor: foreground,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(color: foreground),
    ),
  );
}

const homeDestinationEntries = <String, (HomeDestination, String, String)>{
  '值得看': (HomeDestination.editorial, '编辑精选', '/page?url=V8_ZHUANTI_20180327'),
  '热闻': (HomeDestination.news, '每日热闻', '/page?url=V8_JINRI_NEWS'),
  '活动': (HomeDestination.activities, '活动', '/page?url=V11_ACTIVITIES'),
  '玩机大神': (HomeDestination.users, '推荐关注', '/page?url=V8_RECOMMEND_USER'),
  '投票': (
    HomeDestination.polls,
    '投票',
    '#/feed/digestList?type=16&message_status=all',
  ),
  '头条榜': (HomeDestination.headlines, '更多精彩', '/page?url=V9_LISHITOUTIAO_NEW'),
  '官方频道': (
    HomeDestination.official,
    '官方频道',
    '/page?url=V11_ZHUANTI_EDITORIALDEPARTMENT_20211117',
  ),
};

bool openHomeDestination(
  BuildContext context,
  CoolapkApi api,
  String title,
  String route,
) {
  if (title == '选机中心' ||
      route.contains('/productSelector/configSearch') ||
      route.contains('V9_DEVICE_SELECTOR')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: officialHomeTheme(Theme.of(context)),
          child: ProductSelectorPage(api: api),
        ),
      ),
    );
    return true;
  }
  var entry = homeDestinationEntries[title];
  entry ??= homeDestinationEntries.values
      .where(
        (value) =>
            route == value.$3 ||
            route.contains(
              Uri.parse(value.$3.replaceFirst('#', ''))
                      .queryParameters['url'] ??
                  '\u0000',
            ),
      )
      .firstOrNull;
  if (entry == null) return false;
  final target = entry;
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Theme(
        data: officialHomeTheme(Theme.of(context)),
        child: HomeDestinationPage(
          api: api,
          destination: target.$1,
          title: target.$2,
          // The old V9 placeholders never existed on the server.
          route:
              route.contains('V9_FIND_RECOMMEND') ||
                  route.contains('V9_HOME_TAB_HOT_NEWS') ||
                  route.contains('V9_ACTIVITY_LIST') ||
                  route.contains('V9_FEED_HOT_USER') ||
                  route.contains('V9_VOTE_LIST') ||
                  route.contains('V9_HEADLINE_RANK') ||
                  route.contains('V9_OFFICIAL_CHANNEL') ||
                  route.isEmpty
              ? target.$3
              : route,
        ),
      ),
    ),
  );
  return true;
}

({String path, Map<String, dynamic> query}) homePageRequest(String route) {
  if (route.startsWith('/page?')) {
    return (
      path: '/v6/page/dataList',
      query: Map<String, dynamic>.from(Uri.parse(route).queryParameters),
    );
  }
  if (route.startsWith('/v6/')) {
    final uri = Uri.parse(route);
    return (
      path: uri.path,
      query: Map<String, dynamic>.from(uri.queryParameters),
    );
  }
  return (path: '/v6/page/dataList', query: {'url': route});
}

bool visibleHomeEntity(Map<String, dynamic> item) => !const {
  'configCard',
  'sponsorCard',
  'noMoreDataCard',
  'fabCard',
  'iconTabLinkGridCard',
}.contains(item['entityTemplate']);

class HomeDestinationPage extends StatefulWidget {
  const HomeDestinationPage({
    required this.api,
    required this.destination,
    required this.title,
    required this.route,
    super.key,
  });
  final CoolapkApi api;
  final HomeDestination destination;
  final String title;
  final String route;
  @override
  State<HomeDestinationPage> createState() => _HomeDestinationPageState();
}

class _HomeDestinationPageState extends State<HomeDestinationPage> {
  late Future<ApiPage> _page = _load();
  int _revision = 0;
  Future<ApiPage> _load() {
    final request = homePageRequest(widget.route);
    return widget.api.getList(
      request.path,
      query: {...request.query, 'page': 1},
    );
  }

  void _refresh() => setState(() {
    _revision++;
    _page = _load();
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark
        ? const Color(0xFF1E1E1E)
        : Theme.of(context).colorScheme.surface;
    final isPoll = widget.destination == HomeDestination.polls;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF101010) : null,
      appBar: ReviewFrostedAppBar(
        toolbarHeight: 56,
        titleSpacing: 4,
        centerTitle: false,
        backgroundColor: surface,
        showBottomBorder: false,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        actions:
            widget.destination == HomeDestination.activities ||
                widget.destination == HomeDestination.users ||
                isPoll ||
                widget.destination == HomeDestination.headlines
            ? null
            : [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
      ),
      floatingActionButton: widget.destination == HomeDestination.news
          ? greenComposeFab(
              context: context,
              heroTag: 'home_dest_news_fab',
              useLiquidGlass: true,
              onPressed: () {
                if (!widget.api.hasAccount) {
                  AppToast.show(context, widget.api.loginRequiredMessage);
                  return;
                }
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ComposeFeedPage(api: widget.api),
                  ),
                );
              },
            )
          : null,
      body: isPoll
          ? _list(widget.route)
          : FutureBuilder<ApiPage>(
              future: _page,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(
                    child: snapshot.hasError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${snapshot.error}'),
                              TextButton(
                                onPressed: _refresh,
                                child: const Text('重试'),
                              ),
                            ],
                          )
                        : const CircularProgressIndicator(),
                  );
                }
                final cards = snapshot.data!.items;
                final tabs = <Map<String, dynamic>>[
                  for (final card in cards)
                    if (card['entityTemplate'] == 'iconTabLinkGridCard')
                      ..._children(card),
                ];
                final headers = cards
                    .where(visibleHomeEntity)
                    .toList(growable: false);
                if (tabs.isEmpty) return _list(widget.route);
                return DefaultTabController(
                  key: ValueKey(_revision),
                  length: tabs.length,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, inner) => [
                      if (headers.isNotEmpty)
                        SliverToBoxAdapter(
                          child: ColoredBox(
                            color: surface,
                            child: Column(
                              children: [
                                for (final card in headers)
                                  HomeChannelCard(
                                    api: widget.api,
                                    entity: card,
                                    destination: widget.destination,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _HomeTabs(
                          surface,
                          TabBar(
                            isScrollable: tabs.length > 4,
                            tabAlignment: tabs.length > 4
                                ? TabAlignment.start
                                : TabAlignment.fill,
                            labelColor: const Color(0xFF009688),
                            unselectedLabelColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            labelStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            indicator: const UnderlineTabIndicator(
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                              borderSide: BorderSide(
                                color: Color(0xFF009688),
                                width: 3,
                              ),
                              insets: EdgeInsets.symmetric(horizontal: 12),
                            ),
                            indicatorSize: TabBarIndicatorSize.label,
                            dividerHeight: 0,
                            tabs: [
                              for (final tab in tabs)
                                Tab(text: '${tab['title'] ?? ''}'),
                            ],
                          ),
                        ),
                      ),
                    ],
                    body: TabBarView(
                      children: [
                        for (final tab in tabs)
                          _list('${tab['url'] ?? ''}', nested: true),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _list(String route, {bool nested = false}) {
    final request = homePageRequest(route);
    return ApiListPage(
      key: ValueKey('$route:$_revision'),
      api: widget.api,
      title: widget.title,
      path: request.path,
      query: request.query,
      nested: nested,
      showAppBar: false,
      itemFilter: visibleHomeEntity,
      itemBuilderWithIndex: (context, item, index) => HomeChannelCard(
        api: widget.api,
        entity: item,
        destination: widget.destination,
        index: index,
      ),
    );
  }
}

class _HomeTabs extends SliverPersistentHeaderDelegate {
  _HomeTabs(this.color, this.tabs);
  final Color color;
  final TabBar tabs;
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: color,
    child: protectHorizontalDragFromVerticalRefresh(tabs),
  );
  @override
  bool shouldRebuild(_HomeTabs old) => color != old.color || tabs != old.tabs;
}

List<Map<String, dynamic>> _children(Map<String, dynamic> row) =>
    (row['entities'] is List ? row['entities'] as List : const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
String _text(dynamic value) => value == null ? '' : value.toString().trim();
String _plain(dynamic value) =>
    html.parse(_text(value)).body?.text.trim() ?? _text(value);
String _image(Map<String, dynamic> row) =>
    ['message_cover', 'pic', 'logo', 'cover', 'image', 'icon']
        .map((key) => _text(row[key]))
        .firstWhere((value) => value.startsWith('http'), orElse: () => '');

class HomeChannelCard extends StatelessWidget {
  const HomeChannelCard({
    required this.api,
    required this.entity,
    required this.destination,
    this.index = 0,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> entity;
  final HomeDestination destination;
  final int index;
  @override
  Widget build(BuildContext context) {
    if (!visibleHomeEntity(entity)) return const SizedBox.shrink();
    final template = _text(entity['entityTemplate']);
    final type = _text(entity['entityType']);
    final children = _children(entity);
    if (destination == HomeDestination.activities && type == 'pear_goods') {
      return _OfflineActivityCard(api: api, goods: entity);
    }
    if (destination == HomeDestination.activities &&
        template == 'imageCarouselCard_1') {
      final extra = entity['extraDataArr'];
      final dimensions = extra is Map
          ? _text(extra['dimensionRatio']).split(':')
          : <String>[];
      final width = dimensions.isNotEmpty
          ? double.tryParse(dimensions.first)
          : null;
      final height = dimensions.length == 2
          ? double.tryParse(dimensions.last)
          : null;
      final ratio = width != null && height != null && width > 0 && height > 0
          ? width / height
          : 4.5;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _plain(entity['title']),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 2),
            for (final row in children)
              _banner(context, row, ratio: ratio, caption: false),
          ],
        ),
      );
    }
    if (type == 'feed') {
      return FeedCard(
        api: api,
        feed: CoolapkFeed.fromJson(entity),
        officialLayout: true,
        editorialCover:
            destination == HomeDestination.editorial && template == 'feedCover',
      );
    }
    if (type == 'user') {
      return _HomeUserRow(api: api, user: entity, rank: index + 1);
    }
    if (template == 'messageCard') {
      return Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF192D29)
              : const Color(0xFFE7F4EF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CoolapkRichText(
          api: api,
          text: _plain(entity['description']),
          style: TextStyle(
            fontSize: 14,
            height: 1.25,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }
    if (template == 'productTimelineListCard') {
      return _calendar(context, children);
    }
    if (template == 'iconButtonGridCard') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _banner(
                  context,
                  children[i],
                  ratio: 2.44,
                  caption: false,
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (template == 'imageTextScrollCard') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, entity),
          SizedBox(
            height: 156,
            child: protectHorizontalDragFromVerticalRefresh(
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: children.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(
                  width: 216,
                  child: _banner(context, children[i], ratio: 2.22),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
    }
    if (template == 'imageTextGridCard' || type == 'imageText') {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (final row in children.isEmpty ? [entity] : children)
              _banner(context, row, ratio: 2.22),
          ],
        ),
      );
    }
    return ApiEntityCard(api: api, entity: entity);
  }

  Widget _banner(
    BuildContext context,
    Map<String, dynamic> row, {
    required double ratio,
    bool caption = true,
  }) {
    final image = _image(row);
    final rawColor = _text(
      row['picColor'] ?? row['backgroundColor'] ?? row['color'],
    ).replaceFirst('#', '');
    final color = int.tryParse(rawColor, radix: 16);
    return InkWell(
      onTap: () {
        if (destination == HomeDestination.activities &&
            _text(row['url']).contains('/t/')) {
          final tag = ApiEntityCard.extractTopicTag(row);
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ActivityTopicPage(api: api, tag: tag),
            ),
          );
        } else {
          openHeadlineTarget(context, api, row);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: ratio,
              child: image.isEmpty
                  ? const SizedBox.shrink()
                  : CachedNetworkImage(
                      normalizeCoolapkImageUrl(image),
                      headers: coolapkImageHeaders(image, api: api),
                      fit: BoxFit.cover,
                    ),
            ),
            if (caption)
              Container(
                color: color == null
                    ? const Color(0xFF434A60)
                    : Color(0xFF000000 | color),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  _plain(row['title']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, Map<String, dynamic> row) =>
      InkWell(
        onTap: () => openHeadlineTarget(context, api, row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _plain(row['title']),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      );
  Widget _calendar(BuildContext context, List<Map<String, dynamic>> rows) =>
      Column(
        children: [
          _sectionTitle(context, entity),
          for (final row in rows)
            InkWell(
              onTap: () => openHeadlineTarget(context, api, row),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 10, 36, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        _releaseTime(_text(row['release_time'])),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: Color(0xFF353535),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: CachedNetworkImage(
                        normalizeCoolapkImageUrl(_image(row)),
                        headers: coolapkImageHeaders(_image(row), api: api),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _plain(row['title']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.local_fire_department_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    Text(
                      _text(row['hot_num_txt'] ?? row['hot_num']),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
        ],
      );
  String _releaseTime(String value) {
    final m = RegExp(r'\d{4}年(\d+)月(\d+)日(\d+:\d+)').firstMatch(value);
    return m == null ? value : '${m[1]}.${m[2]}\n${m[3]}';
  }
}

class _OfflineActivityCard extends StatelessWidget {
  const _OfflineActivityCard({required this.api, required this.goods});
  final CoolapkApi api;
  final Map<String, dynamic> goods;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = _text(goods['goods_title']);
    final picture = normalizeCoolapkImageUrl(_text(goods['goods_pic']));
    final tags = _text(goods['goods_tags'])
        .split(RegExp('[,，]'))
        .where((tag) => tag.trim().isNotEmpty)
        .toList();
    final uri = activityGoodsUrl(goods);
    void open() {
      if (uri != null) {
        openActivityDocument(context, api, uri, title: title);
      } else {
        AppToast.show(context, '活动详情地址暂不可用');
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1E1E1E)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final imageSize = (constraints.maxWidth * .335).clamp(
                72.0,
                104.0,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      picture,
                      headers: coolapkImageHeaders(picture, api: api),
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          SizedBox(width: imageSize, height: imageSize),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, height: 1.45),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 20,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: tags.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 5),
                            itemBuilder: (_, index) => Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDD4436)
                                    .withValues(alpha: index == 0 ? .05 : .02),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                tags[index],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: index == 0
                                      ? const Color(0xFFD94436)
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              _text(goods['goods_promo_title']),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFDD4436),
                              ),
                            ),
                            SizedBox(
                              height: 28,
                              child: FilledButton(
                                onPressed: open,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDD4436),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  minimumSize: const Size(0, 28),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  _text(goods['goods_buy_text']).isEmpty
                                      ? '查看详情'
                                      : _text(goods['goods_buy_text']),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeUserRow extends StatefulWidget {
  const _HomeUserRow({
    required this.api,
    required this.user,
    required this.rank,
  });
  final CoolapkApi api;
  final Map<String, dynamic> user;
  final int rank;
  @override
  State<_HomeUserRow> createState() => _HomeUserRowState();
}

class _HomeUserRowState extends State<_HomeUserRow> {
  late bool _following = '${widget.user['isFollow']}' == '1';
  bool _busy = false;
  Future<void> _follow() async {
    if (_busy) return;
    if (!widget.api.hasAccount) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = _text(widget.user['uid']);
      if (widget.api.isAnonymous) await widget.api.getUserSpace(uid);
      await widget.api.followUser(uid, following: _following);
      if (mounted) setState(() => _following = !_following);
    } catch (e) {
      if (mounted) AppToast.show(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final rank = widget.rank;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: rank == 1
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : null,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Theme.of(context).colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank <= 3
                    ? [Colors.red, Colors.orange, Colors.amber][rank - 1]
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  color: rank <= 3
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      UserSpacePage(api: widget.api, uid: _text(user['uid'])),
                ),
              ),
              child: AppAvatar(
                api: widget.api,
                url: _text(user['userAvatar']),
                size: 40,
                name: _text(user['username']),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        UserSpacePage(api: widget.api, uid: _text(user['uid'])),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(user['username']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_text(user['follow'])}关注  ${_text(user['fans'])}粉丝',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: _busy ? null : _follow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF009688),
                  side: const BorderSide(color: Color(0xFF009688)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  _following ? '已关注' : '关注',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
