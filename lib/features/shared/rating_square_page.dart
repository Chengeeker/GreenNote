import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/widgets/cached_network_image.dart';
import 'api_list_page.dart';
import 'community_ui.dart' show communityRequest;
import 'home_destination_page.dart' show officialHomeTheme;

const ratingSquareRoutes = [
  'V16_RATINGSHOP_RECOMMEND',
  'V16_RATINGSHOP_SHUMA',
  'V16_RATINGSHOP_GAME',
  'V16_RATINGSHOP_LIFE',
];

int ratingNodeCount(Map<String, dynamic> item) {
  final owner = int.tryParse('${item['owner_star_total_count']}') ?? 0;
  return owner > 0
      ? owner
      : int.tryParse(
              '${item['star_total_count'] ?? item['rating_total_num']}',
            ) ??
            0;
}

double ratingNodeScore(Map<String, dynamic> item) {
  final owner = int.tryParse('${item['owner_star_total_count']}') ?? 0;
  return double.tryParse(
        '${(owner > 0 ? item['owner_star_average_score'] : null) ?? item['rating_average_score'] ?? item['star_average_score']}',
      ) ??
      0;
}

String ratingNodeCountLabel(Map<String, dynamic> item) =>
    '${ratingNodeCount(item)}${(int.tryParse('${item['owner_star_total_count']}') ?? 0) > 0 ? '机主' : '人'}点评';

List<Map<String, dynamic>> ratingSquareCards(List<Map<String, dynamic>> items) {
  final cards = <Map<String, dynamic>>[];
  Map<String, dynamic>? group;
  for (final item in items) {
    if (item['entityTemplate'] == 'configCard') continue;
    if (item['entityTemplate'] == 'titleCard' && item['title'] != null) {
      group = {
        ...item,
        'entities': item['entities'] is List
            ? List.of(item['entities'] as List)
            : <Map<String, dynamic>>[],
      };
      cards.add(group);
    } else if (group != null &&
        ['product', 'topic'].contains(item['entityType'])) {
      (group['entities'] as List).add(item);
    } else {
      group = null;
      cards.add(item);
    }
  }
  return cards;
}

class RatingSquarePage extends StatefulWidget {
  const RatingSquarePage({
    required this.api,
    this.selectOnly = false,
    super.key,
  });
  final CoolapkApi api;
  final bool selectOnly;

  @override
  State<RatingSquarePage> createState() => _RatingSquarePageState();
}

class _RatingSquarePageState extends State<RatingSquarePage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _pages = <int, Widget>{};
  int _index = 0;
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _find() => setState(() => _keyword = _search.text.trim());

  @override
  Widget build(BuildContext context) {
    _pages.putIfAbsent(
      _index,
      () => _RatingSquareTab(
        api: widget.api,
        route: ratingSquareRoutes[_index],
        selectOnly: widget.selectOnly,
        onRequestSearch: _searchFocus.requestFocus,
      ),
    );
    return Theme(
      data: officialHomeTheme(Theme.of(context)),
      child: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  ColoredBox(
                    color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: dark
                                        ? const Color(0xFF2B2B2D)
                                        : const Color(0xFFF0F0F0),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Row(
                                    children: [
                                      BackButton(
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _search,
                                          focusNode: _searchFocus,
                                          textInputAction:
                                              TextInputAction.search,
                                          onSubmitted: (_) => _find(),
                                          decoration: const InputDecoration(
                                            hintText: '搜索点评对象',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '搜索点评对象',
                                        onPressed: _find,
                                        icon: const Icon(
                                          Icons.search,
                                          size: 26,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '我的点评',
                                icon: const Icon(
                                  Icons.person_outline,
                                  size: 28,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ApiListPage(
                                      api: widget.api,
                                      title: '我的点评',
                                      path: '/v6/page/dataList',
                                      query: {
                                        'url': '#/feed/nodeRatingList',
                                        'uid': widget.api.currentUid,
                                        'targetType': 'all',
                                        'parseRatingToFeed': 1,
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            for (final (i, title) in [
                              '推荐',
                              '数码',
                              '游戏',
                              '生活',
                            ].indexed)
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _index = i;
                                    _keyword = '';
                                    _search.clear();
                                  }),
                                  child: SizedBox(
                                    height: 40,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: _index == i
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: _index == i
                                                ? const Color(0xFF009688)
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Container(
                                          width: 10,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: _index == i
                                                ? const Color(0xFF009688)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
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
                  ),
                  Expanded(
                    child: _keyword.isNotEmpty
                        ? _RatingSquareTab(
                            key: ValueKey((_index, _keyword)),
                            api: widget.api,
                            route: '',
                            keyword: _keyword,
                            searchType: _index >= 2 ? 'feedTopic' : 'product',
                            selectOnly: widget.selectOnly,
                          )
                        : IndexedStack(
                            index: _index,
                            children: [
                              for (var i = 0; i < 4; i++)
                                _pages[i] ?? const SizedBox(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RatingSquareTab extends StatefulWidget {
  const _RatingSquareTab({
    super.key,
    required this.api,
    required this.route,
    required this.selectOnly,
    this.keyword = '',
    this.searchType = 'product',
    this.onRequestSearch,
  });
  final CoolapkApi api;
  final String route, keyword, searchType;
  final bool selectOnly;
  final VoidCallback? onRequestSearch;
  @override
  State<_RatingSquareTab> createState() => _RatingSquareTabState();
}

class _RatingSquareTabState extends State<_RatingSquareTab> {
  double get _rowHeight =>
      (widget.route == ratingSquareRoutes.first ? 78 : 74) *
      (MediaQuery.textScalerOf(context).scale(15) / 15).clamp(
        1.0,
        double.infinity,
      );
  List<Map<String, dynamic>> _cards = [];
  final _personal = <String, Map<String, dynamic>>{};
  final _profile = <String, String>{};
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.route == ratingSquareRoutes.first) unawaited(_loadPersonal());
  }

  Future<void> _loadPersonal() async {
    try {
      final profile = await const MethodChannel('com.green.note/ui')
          .invokeMapMethod<String, dynamic>('getDeviceProfile');
      if (!mounted || profile == null) return;
      setState(() {
        _profile['我的机型'] = '${profile['marketName'] ?? ''}';
        _profile['我的系统'] = '${profile['osName'] ?? ''}';
      });
      String normalized(String value, bool system) {
        final compact = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        return system ? compact.replaceFirst(RegExp(r'(\.0)+$'), '') : compact;
      }

      await Future.wait(
        _profile.entries.where((e) => e.value.isNotEmpty).map((entry) async {
          try {
            final result = await widget.api.getList(
              '/v6/search',
              query: {
                'type': entry.key == '我的机型' ? 'product' : 'feedTopic',
                'searchValue': entry.key == '我的系统'
                    ? entry.value.replaceFirst(RegExp(r'(\.0)+$'), '')
                    : entry.value,
                'page': 1,
              },
            );
            final matches =
                [
                  ...result.items,
                  for (final card in result.items) ..._children(card),
                ].where(
                  (item) =>
                      normalized(
                            '${item['title'] ?? ''}',
                            entry.key == '我的系统',
                          ) ==
                          normalized(entry.value, entry.key == '我的系统') &&
                      '${item['id'] ?? ''}'.isNotEmpty,
                );
            if (mounted && matches.isNotEmpty) {
              setState(() => _personal[entry.key] = matches.first);
            }
          } catch (_) {
            /* A failed optional match must not replace the main page's error state. */
          }
        }),
      );
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.api.getList(
        widget.keyword.isEmpty ? '/v6/page/dataList' : '/v6/search',
        query: {
          if (widget.keyword.isEmpty)
            'url': widget.route
          else ...{
            'searchValue': widget.keyword,
            'type': widget.searchType,
          },
          'page': 1,
        },
      );
      if (mounted) {
        setState(() => _cards = ratingSquareCards(page.items));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _children(Map<String, dynamic> card) =>
      (card['entities'] is List ? card['entities'] as List : const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  void _open(Map<String, dynamic> item) {
    if ('${item['id'] ?? ''}'.trim().isEmpty) return;
    if (widget.selectOnly) {
      Navigator.pop(context, item);
      return;
    }
    if ([0, '0', false].contains(item['allow_rating'] ?? item['allow_rate'])) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RatingEditor(api: widget.api, item: item),
    );
  }

  Future<void> _openCategory(String title, String route) async {
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _RatingCategoryPage(
          api: widget.api,
          title: title,
          route: route,
          selectOnly: widget.selectOnly,
        ),
      ),
    );
    if (mounted && widget.selectOnly && selected != null) {
      Navigator.pop(context, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF111111)
          : const Color(0xFFF5F5F5),
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView.builder(
          key: PageStorageKey(widget.route),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount:
              (_cards.isEmpty ? 1 : _cards.length) +
              (widget.route == ratingSquareRoutes.first ? 1 : 0),
          itemBuilder: (context, index) {
            if (widget.route == ratingSquareRoutes.first) {
              if (index == 0) return _personalTargets();
              index--;
            }
            if (_cards.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无点评对象', textAlign: TextAlign.center),
              );
            }
            final card = _cards[index];
            final children = _children(card);
            if (children.isEmpty &&
                ['product', 'topic'].contains(card['entityType'])) {
              return _section('', [card]);
            }
            if (children.isEmpty) {
              if (card['title'] == '我的装备') return _section('我的装备', const []);
              return const SizedBox();
            }
            if (card['entityTemplate'] == 'ratingNodeHorizonList') {
              return _section(
                '${card['title'] ?? ''}',
                children,
                route: '${card['url'] ?? ''}',
              );
            }
            // Recommendation cards contain account/device-specific nodes; render only returned nodes.
            return _section('${card['title'] ?? ''}', children);
          },
        ),
      ),
    );
  }

  Widget _personalTargets() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Row(
      children: [
        for (final (title, fallback, icon) in [
          ('我的机型', '未关联机型', Icons.phone_android),
          ('我的系统', '未关联系统', Icons.android),
        ])
          Expanded(
            child: Container(
              margin: EdgeInsets.only(
                right: title == '我的机型' ? 4 : 0,
                left: title == '我的系统' ? 4 : 0,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E1E)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor
                                .withValues(alpha: 0.2),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: '${_personal[title]?['logo'] ?? ''}'.isEmpty
                            ? Icon(icon, size: 28)
                            : CachedNetworkImage(
                                normalizeCoolapkImageUrl(
                                  '${_personal[title]!['logo']}',
                                ),
                                fit: BoxFit.cover,
                                width: 44,
                                height: 44,
                                headers: coolapkImageHeaders(
                                  '${_personal[title]!['logo']}',
                                  api: widget.api,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_profile[title]?.isNotEmpty == true ? _profile[title] : _personal[title]?['title'] ?? fallback}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (_personal[title] == null)
                              const Text(
                                '暂无评分',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF999999),
                                ),
                              )
                            else
                              _stars(ratingNodeScore(_personal[title]!)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    color: Theme.of(context).dividerColor
                        .withValues(alpha: 0.2),
                  ),
                  InkWell(
                    onTap: _personal[title] == null
                        ? widget.onRequestSearch
                        : () => _open(_personal[title]!),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _personal[title] == null
                                  ? '搜索后去点评'
                                  : ratingNodeCountLabel(_personal[title]!),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          if (_personal[title] != null)
                            const Text('去点评', style: TextStyle(fontSize: 11)),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _section(
    String title,
    List<Map<String, dynamic>> items, {
    String route = '',
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = items.length.clamp(0, 3);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            InkWell(
              onTap: route.isEmpty ? null : () => _openCategory(title, route),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: title == '我的装备'
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (route.isNotEmpty)
                      const Icon(Icons.chevron_right, size: 22),
                  ],
                ),
              ),
            ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('暂无装备，搜索对象即可去点评', style: TextStyle(fontSize: 13)),
            )
          else if (widget.route == ratingSquareRoutes.first)
            Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _node(item),
                  ),
              ],
            )
          else
            SizedBox(
              height: rows * _rowHeight + 10,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 12),
                  itemExtent: constraints.maxWidth * 0.9,
                  itemCount: (items.length / 3).ceil(),
                  itemBuilder: (context, column) => Column(
                    children: [
                      for (final item in items.skip(column * 3).take(3))
                        _node(item),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stars(double score) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Container(
            width: 9,
            height: 9,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF777777),
              borderRadius: BorderRadius.circular(1.5),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (score / 2 - i + 1).clamp(0.0, 1.0),
                    child: const ColoredBox(color: Color(0xFFD99F18)),
                  ),
                ),
                const Center(
                  child: Icon(Icons.star, size: 8, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      Text(
        score.toStringAsFixed(1),
        style: const TextStyle(fontSize: 11, color: Color(0xFFD99F18)),
      ),
    ],
  );

  Widget _node(Map<String, dynamic> item) {
    final title = '${item['title'] ?? ''}';
    final score = ratingNodeScore(item);
    final ownerCount = int.tryParse('${item['owner_star_total_count']}') ?? 0;
    final count = ratingNodeCount(item);
    final allowed = ![
      0,
      '0',
      false,
    ].contains(item['allow_rating'] ?? item['allow_rate']);
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(right: 18, top: 6, bottom: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: '${item['logo'] ?? ''}'.isEmpty
                  ? Container(
                      width: 60,
                      height: 60,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.devices_other, size: 30),
                    )
                  : CachedNetworkImage(
                      normalizeCoolapkImageUrl('${item['logo'] ?? ''}'),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      headers: coolapkImageHeaders(
                        '${item['logo'] ?? ''}',
                        api: widget.api,
                      ),
                    ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: InkWell(
                onTap: () => _open(item),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    if (widget.route == ratingSquareRoutes.first) ...[
                      _stars(score),
                      const SizedBox(height: 3),
                      Text(
                        count == 0 ? '暂无人评分' : ratingNodeCountLabel(item),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ] else
                      Text.rich(
                        TextSpan(
                          children: [
                            if (count > 0)
                              TextSpan(
                                text:
                                    '${score.toStringAsFixed(score == 10 ? 0 : 1)}分  ',
                                style: const TextStyle(
                                  color: Color(0xFFD99F18),
                                ),
                              ),
                            TextSpan(
                              text: count == 0
                                  ? '暂无人评分'
                                  : '$count${ownerCount > 0 ? '机主' : '人'}点评',
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 3),
            SizedBox(
              width: 60,
              height: 30,
              child: FilledButton(
                onPressed: allowed ? () => _open(item) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF009F91),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  textStyle: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
                ),
                child: Text(
                  widget.selectOnly
                      ? '选择'
                      : !allowed
                      ? '不可点评'
                      : count == 0
                      ? '首评'
                      : '去点评',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingCategoryPage extends StatelessWidget {
  const _RatingCategoryPage({
    required this.api,
    required this.title,
    required this.route,
    required this.selectOnly,
  });
  final CoolapkApi api;
  final String title, route;
  final bool selectOnly;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: _RatingSquareTab(api: api, route: route, selectOnly: selectOnly),
  );
}

class _RatingEditor extends StatefulWidget {
  const _RatingEditor({required this.api, required this.item});
  final CoolapkApi api;
  final Map<String, dynamic> item;
  @override
  State<_RatingEditor> createState() => _RatingEditorState();
}

class _RatingEditorState extends State<_RatingEditor> {
  final _message = TextEditingController();
  int _stars = 0;
  bool _owner = false, _busy = false;
  String? _error;
  late final String _session;
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_busy || _stars == 0) return;
    if (!widget.api.hasCookie) {
      setState(() => _error = widget.api.loginRequiredMessage);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final product = widget.item['entityType'] == 'product';
      await communityRequest(
        widget.api,
        _session,
        '/v6/feed/createFeed',
        method: 'POST',
        body: {
          'type': 'rating',
          'message': _message.text.trim(),
          'targetType': product ? 'product_phone' : 'tag',
          'targetId': '${widget.item['id']}',
          'rating_score_1': '$_stars',
          if (product) 'buy_status': _owner ? '1' : '0',
          'comment_good': '',
          'comment_general': '',
          'comment_bad': '',
          'comment_good_pic': '',
          'comment_general_pic': '',
          'comment_bad_pic': '',
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '点评 ${widget.item['title']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i星',
                  onPressed: _busy ? null : () => setState(() => _stars = i),
                  icon: Icon(
                    i <= _stars ? Icons.star : Icons.star_border,
                    color: const Color(0xFFD99F18),
                  ),
                ),
            ],
          ),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: const InputDecoration(hintText: '写下你的使用体验'),
          ),
          if (widget.item['entityType'] == 'product')
            CheckboxListTile(
              value: _owner,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _owner = v == true),
              title: const Text('我已购买 / 正在使用'),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _busy || _stars == 0 ? null : _publish,
            child: Text(_busy ? '发布中…' : '发布点评'),
          ),
        ],
      ),
    ),
  );
}
