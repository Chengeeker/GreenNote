import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/review_refresh_header.dart';
import '../feed/feed_pages.dart' show openHeadlineTarget;
import '../feed/video_player_page.dart';
import '../shell/main_pages.dart' show SearchResultsPage;
import 'api_list_page.dart';
import 'app_management_page.dart';
import 'app_detail_page.dart';
import 'home_destination_page.dart' show officialHomeTheme;

const marketTabs = <(String, String)>[
  ('精选', 'V10_MARKET_HOME'),
  ('应用', 'V8_MARKET_APP'),
  ('游戏', 'V8_MARKET_GAME'),
  ('应用集', 'V8_MARKET_ALBUM'),
  ('排行', 'V10_MARKET_RANK'),
];

String _field(Map data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

Map<String, dynamic> marketExtra(Map<String, dynamic> data) {
  final value = data['extraDataArr'] ?? data['extraData'];
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Some legacy extraData strings are JavaScript objects; use top-level fields.
    }
  }
  return {};
}

({String path, Map<String, dynamic> query}) marketRequest(String route) {
  if (route.startsWith('/page?')) {
    return (path: '/v6/page/dataList', query: Uri.parse(route).queryParameters);
  }
  if (route.startsWith('#') || !route.startsWith('/')) {
    return (path: '/v6/page/dataList', query: {'url': route});
  }
  final uri = Uri.parse(route);
  final query = <String, dynamic>{...uri.queryParameters};
  if (uri.path == '/apk/recommendList') {
    query.putIfAbsent('apkType', () => '1');
    query.putIfAbsent('title', () => '好软推荐');
  }
  return (
    path: uri.path.startsWith('/v6/') ? uri.path : '/v6${uri.path}',
    query: query,
  );
}

class AppMarketPage extends StatelessWidget {
  const AppMarketPage({required this.api, super.key});
  final CoolapkApi api;

  @override
  Widget build(BuildContext context) => Theme(
    data: officialHomeTheme(Theme.of(context)),
    child: DefaultTabController(
      length: marketTabs.length,
      child: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final surface = dark
              ? const Color(0xFF1E1E1E)
              : Theme.of(context).colorScheme.surface;
          return Scaffold(
            backgroundColor: dark ? const Color(0xFF101010) : null,
            appBar: AppBar(
              toolbarHeight: 44,
              backgroundColor: surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 0,
              title: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF2B2B2B)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: TextField(
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: '搜索',
                    prefixIcon: Icon(Icons.search, size: 22),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 7),
                    isDense: true,
                  ),
                  onSubmitted: (query) {
                    if (query.trim().isEmpty) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => SearchResultsPage(
                          api: api,
                          query: query.trim(),
                          initialType: 'apk',
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                IconButton(
                  tooltip: '应用管理',
                  icon: const Icon(Icons.install_mobile_outlined),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AppManagementPage(),
                    ),
                  ),
                ),
              ],
              bottom: TabBar(
                labelColor: const Color(0xFF009688),
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
                labelStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 17),
                indicatorColor: const Color(0xFF009688),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: UnderlineTabIndicator(
                  borderSide: const BorderSide(
                    color: Color(0xFF009688),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(2),
                  insets: EdgeInsets.symmetric(
                    horizontal:
                        (MediaQuery.sizeOf(context).width / 5 - 12).clamp(
                          0,
                          double.infinity,
                        ) /
                        2,
                  ),
                ),
                dividerHeight: 0,
                labelPadding: EdgeInsets.zero,
                tabs: [
                  for (final tab in marketTabs) Tab(text: tab.$1, height: 40),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final tab in marketTabs)
                  MarketList(api: api, title: tab.$1, route: tab.$2),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class MarketList extends StatefulWidget {
  const MarketList({
    required this.api,
    required this.title,
    required this.route,
    this.showAppBar = false,
    super.key,
  });
  final CoolapkApi api;
  final String title;
  final String route;
  final bool showAppBar;
  @override
  State<MarketList> createState() => _MarketListState();
}

class _MarketListState extends State<MarketList>
    with AutomaticKeepAliveClientMixin {
  String? _selected;
  String? _rootSelected;
  List<Map<String, dynamic>> _selectors = [];
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final request = marketRequest(_selected ?? widget.route);
    final list = ApiListPage(
      api: widget.api,
      title: widget.title,
      path: request.path,
      query: request.query,
      showAppBar: false,
      itemFilter: (item) =>
          !{'configCard', 'noMoreDataCard'}.contains(item['entityTemplate']),
      header: _selectors.isEmpty
          ? const SizedBox.shrink()
          : _selector(_selectors, header: true),
      itemBuilder: (context, item) {
        if (item['entityTemplate'] == 'selectorLinkCard') {
          return _selector(_rows(item['entities']));
        }
        return MarketCard(api: widget.api, data: item);
      },
    );
    if (!widget.showAppBar) return list;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF101010)
          : null,
      appBar: AppBar(
        title: Text(widget.title),
        surfaceTintColor: Colors.transparent,
      ),
      body: list,
    );
  }

  Widget _selector(List<Map<String, dynamic>> rows, {bool header = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 8,
          children: [
            for (final row in rows)
              ChoiceChip(
                label: Text(_field(row, ['title'])),
                selected:
                    (header ? _rootSelected : _selected) == row['url'] ||
                    (header ? _rootSelected : _selected) == null &&
                        row == rows.first,
                onSelected: (_) => setState(() {
                  if (_selectors.isEmpty || header) {
                    _selectors = rows;
                    _rootSelected = row['url'].toString();
                  }
                  _selected = row['url'].toString();
                }),
              ),
          ],
        ),
      );
}

class MarketCard extends StatelessWidget {
  const MarketCard({required this.api, required this.data, super.key});
  final CoolapkApi api;
  final Map<String, dynamic> data;

  void _open(BuildContext context, Map<String, dynamic> item) {
    final route = _field(item, ['url', 'apkUrl']);
    final type = _field(item, ['entityType']);
    final title = _field(item, ['title', 'name']);
    Widget? page;
    final package = _field(item, ['apkname', 'packageName']);
    if (type == 'apk' ||
        package.isNotEmpty ||
        RegExp(r'^/(apk|game)/[^/?]+\.[^/?]+$').hasMatch(route)) {
      page = AppDetailPage(
        api: api,
        id: package.isNotEmpty ? package : route.split('/').last,
        initialEntity: item,
      );
    } else if (type == 'album' || RegExp(r'^/album/\d+$').hasMatch(route)) {
      page = _MarketAlbumPage(
        api: api,
        id: _field(item, ['id', 'entityId']).isNotEmpty
            ? _field(item, ['id', 'entityId'])
            : route.split('/').last,
        title: title,
      );
    } else if (route.startsWith('/apk/') ||
        route.startsWith('/album/') ||
        route.startsWith('#') ||
        route.startsWith('/page?') ||
        route.startsWith('/v6/')) {
      page = MarketList(api: api, title: title, route: route, showAppBar: true);
    }
    if (page != null) {
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => page!));
    } else {
      openHeadlineTarget(context, api, item);
    }
  }

  Widget _image(String url, {double? size}) => ClipRRect(
    borderRadius: BorderRadius.circular(size == null ? 0 : 13),
    child: url.isEmpty
        ? SizedBox(width: size, height: size, child: const Icon(Icons.apps))
        : CachedNetworkImage(
            normalizeCoolapkImageUrl(url),
            headers: coolapkImageHeaders(url, api: api),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: size,
              height: size,
              child: const Icon(Icons.apps),
            ),
          ),
  );

  Widget _row(
    BuildContext context,
    Map<String, dynamic> item, {
    String? subtitle,
  }) {
    final isApk =
        item['entityType'] == 'apk' ||
        _field(item, ['apkname', 'packageName']).isNotEmpty;
    final description =
        html
            .parse(_field(item, ['description', 'note', 'related_text']))
            .body
            ?.text ??
        '';
    final counts =
        '${_field(item, ['downCount', 'downnum'])}下载  ${_field(item, ['commentnum', 'commentCount'])}评论';
    return InkWell(
      onTap: () => _open(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _image(_field(item, ['logo', 'icon', 'pic']), size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _field(item, ['cardTitle', 'title', 'name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle ?? (isApk ? counts : description),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isApk)
              AppDownloadButton(api: api, data: item, compact: true)
            else
              const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final title = _field(data, ['title']);
    if (title.isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: _field(data, ['url']).isEmpty ? null : () => _open(context, data),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_field(data, ['url']).isNotEmpty)
              const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _field(data, ['entityTemplate']);
    final children = _rows(data['entities']);
    if (template == 'configCard' || template == 'noMoreDataCard') {
      return const SizedBox.shrink();
    }
    if (template == 'linkCard' || template == 'iconButtonGridCard') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: Row(
          children: [
            for (final item in children)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF009688),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: () => _open(context, item),
                    child: Text(_field(item, ['title'])),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (template == 'titleCard') return _heading(context);
    if (template == 'imageScaleCard') {
      final ratio = _field(marketExtra(data), ['dimensionRatio']).split(':');
      final width = ratio.isNotEmpty ? double.tryParse(ratio.first) : null;
      final height = ratio.length == 2 ? double.tryParse(ratio.last) : null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _open(context, data),
            child: AspectRatio(
              aspectRatio:
                  width != null && height != null && width > 0 && height > 0
                  ? width / height
                  : 16 / 9,
              child: _image(_field(data, ['pic', 'cover'])),
            ),
          ),
        ),
      );
    }
    if (children.isEmpty) {
      if (_field(data, ['entityType']) == 'category') {
        return ListTile(
          leading: _image(_field(data, ['logo']), size: 48),
          title: Text(_field(data, ['title'])),
          subtitle: Text(_field(data, ['keywords'])),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, data),
        );
      }
      return _row(context, data);
    }
    final horizontal =
        template.contains('Scroll') || template == 'colorfulScrollCard';
    final grid = template == 'iconGridCard' || template == 'gridCard';
    final hero = template == 'apkImageCard';
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget content;
    if (hero) {
      content = Column(
        children: [for (final item in children) _hero(context, item)],
      );
    } else if (horizontal) {
      final wide = template.contains('Image') || template == 'imageScrollCard';
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      content = SizedBox(
        height: (wide ? 190 : 148) + (scale - 1) * 40,
        child: protectHorizontalDragFromVerticalRefresh(
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = children[index];
              return SizedBox(
                width: wide ? 240 : 72,
                child: InkWell(
                  onTap: () => _open(context, item),
                  child: Column(
                    children: [
                      if (wide)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: _image(_field(item, ['cover', 'pic', 'logo'])),
                        )
                      else
                        _image(_field(item, ['logo', 'icon', 'pic']), size: 56),
                      const SizedBox(height: 8),
                      Text(
                        _field(item, ['title']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!wide)
                        Text(
                          _field(item, ['apksize', 'score']),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else if (grid) {
      content = Wrap(
        children: [
          for (final item in children)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 16) / 4,
              child: InkWell(
                onTap: () => _open(context, item),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      _image(_field(item, ['logo', 'pic']), size: 48),
                      const SizedBox(height: 6),
                      Text(
                        _field(item, ['title']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      content = Column(
        children: [for (final item in children) _row(context, item)],
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF1E1E1E)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_heading(context), content],
      ),
    );
  }

  Widget _hero(BuildContext context, Map<String, dynamic> item) {
    final extra = marketExtra(item);
    final cover = _field({...item, ...extra}, ['cover', 'pic']);
    Map<String, dynamic> video = {};
    final rawVideo = item['videoParams'] ?? extra['videoParams'];
    if (rawVideo is Map) video = Map<String, dynamic>.from(rawVideo);
    if (rawVideo is String) {
      try {
        final decoded = jsonDecode(rawVideo);
        if (decoded is Map) {
          video = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        /* Malformed video metadata leaves an app-detail link. */
      }
    }
    final requestParams = _field(video, ['requestParams']);
    final videoUrl = _field(video, ['url', 'videoUrl']);
    final canPlay = requestParams.isNotEmpty || videoUrl.isNotEmpty;
    final duration = Duration(
      milliseconds: int.tryParse(_field(video, ['duration'])) ?? 0,
    );
    final durationLabel = [
      duration.inHours,
      duration.inMinutes % 60,
      duration.inSeconds % 60,
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
    return Column(
      children: [
        InkWell(
          onTap: () {
            if (!canPlay) {
              _open(context, item);
              return;
            }
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CoolapkVideoPlayerPage(
                  api: api,
                  videoUrl: videoUrl,
                  requestParams: requestParams,
                  coverUrl: cover,
                  title: _field(item, ['title']),
                ),
              ),
            );
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _image(cover),
                if (canPlay)
                  const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                if (canPlay && duration > Duration.zero)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: Text(
                      durationLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _row(
          context,
          item,
          subtitle: _field({...item, ...extra}, ['subTitle', 'description']),
        ),
      ],
    );
  }
}

class _MarketAlbumPage extends StatefulWidget {
  const _MarketAlbumPage({
    required this.api,
    required this.id,
    required this.title,
  });
  final CoolapkApi api;
  final String id;
  final String title;
  @override
  State<_MarketAlbumPage> createState() => _MarketAlbumPageState();
}

class _MarketAlbumPageState extends State<_MarketAlbumPage> {
  late Future<dynamic> _detail = _load();
  Future<dynamic> _load() =>
      widget.api.request('/v6/album/detail', query: {'id': widget.id});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<dynamic>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _detail = _load()),
              child: Text('${snapshot.error}\n点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final root = snapshot.data;
        final data = root is Map && root['data'] is Map
            ? root['data'] as Map
            : <String, dynamic>{};
        return ApiListPage(
          api: widget.api,
          title: widget.title,
          path: '/v6/album/apkList',
          query: {'id': widget.id},
          showAppBar: false,
          header: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_field(data, ['description', 'intro', 'title'])),
          ),
          itemBuilder: (context, item) => MarketCard(
            api: widget.api,
            data: {
              ...item,
              'entityType': 'apk',
              'logo': item['pic'] ?? item['logo'],
            },
          ),
        );
      },
    ),
  );
}
