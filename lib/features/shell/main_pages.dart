import 'package:easy_refresh/easy_refresh.dart';

import '../../core/widgets/review_refresh_header.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/design_system/components/review_card.dart';
import '../../core/widgets/app_avatar.dart';
import '../settings/app_settings_page.dart';
import '../../core/widgets/app_section_card.dart';
import '../feed/feed_pages.dart';
import '../shared/api_list_page.dart';
import '../../core/utils/haptic_feedback_util.dart';
export '../digital/digital_page.dart';

class _DiscoveryChannel {
  const _DiscoveryChannel(this.title, this.fallback);
  final String title;
  final String? fallback;
}

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({required this.api, this.onTopBarChanged, super.key});
  final CoolapkApi api;
  final ValueChanged<PreferredSizeWidget?>? onTopBarChanged;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  static const _channels = [
    _DiscoveryChannel('酷品', '/page?url=V11_FIND_GOODS'),
    _DiscoveryChannel('生活', null),
    _DiscoveryChannel('二手', '/page?url=V11_DISCOVERY_SECOND_HAND'),
    _DiscoveryChannel('酷图', '#/feed/coolPictureRankList'),
    _DiscoveryChannel('宠物', null),
    _DiscoveryChannel('运动', null),
    _DiscoveryChannel('看看号', '/user/dyhSubscribe'),
    _DiscoveryChannel('商家', null),
    _DiscoveryChannel('好物榜', '/page?url=V11_FIND_GOOD_GOODS_HOME'),
  ];

  late final TabController _tabs = TabController(
    length: _channels.length,
    initialIndex: 3,
    vsync: this,
  );
  Map<String, String> _serverRoutes = const {};
  Object? _routeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTopBarChanged?.call(_buildTabBar());
    });
    widget.api
        .loadDiscoveryTabRoutes()
        .then((routes) {
          if (mounted) setState(() => _serverRoutes = routes);
        })
        .catchError((Object error) {
          if (mounted) setState(() => _routeError = error);
        });
  }

  PreferredSizeWidget _buildTabBar() => PreferredSize(
    preferredSize: const Size.fromHeight(kTextTabBarHeight),
    child: Builder(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: colors.primary,
          indicatorWeight: 3,
          labelColor: colors.primary,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelColor: colors.onSurfaceVariant,
          unselectedLabelStyle: const TextStyle(fontSize: 15),
          tabs: [for (final channel in _channels) Tab(text: channel.title)],
        );
      },
    ),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: _tabs,
      children: [for (final channel in _channels) _channelPage(channel)],
    );
  }

  Widget _channelPage(_DiscoveryChannel channel) {
    if (channel.title == '酷图') {
      return CoolPicPage(api: widget.api);
    }
    final route = _serverRoutes[channel.title] ?? channel.fallback;
    if (route == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _routeError == null
                ? '${channel.title}频道暂未提供可用路由配置'
                : '发现频道配置加载失败：$_routeError',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final parsed = _parseRoute(route);
    return ApiListPage(
      key: ValueKey('discover-${channel.title}'),
      api: widget.api,
      title: channel.title,
      path: parsed.$1,
      query: parsed.$2,
      showAppBar: false,
    );
  }

  (String, Map<String, dynamic>) _parseRoute(String route) {
    if (route.startsWith('#/')) {
      return ('/v6/page/dataList', {'url': route});
    }
    final uri = Uri.parse(route);
    if (uri.path == '/page' || uri.queryParameters.containsKey('url')) {
      return (
        '/v6/page/dataList',
        Map<String, dynamic>.from(uri.queryParameters),
      );
    }
    if (uri.path.startsWith('/user/')) {
      return ('/v6${uri.path}', Map<String, dynamic>.from(uri.queryParameters));
    }
    if (uri.path.startsWith('/v6/')) {
      return (uri.path, Map<String, dynamic>.from(uri.queryParameters));
    }
    return ('/v6/page/dataList', {'url': route});
  }
}

class SearchHubPage extends StatefulWidget {
  const SearchHubPage({required this.api, super.key});
  final CoolapkApi api;

  @override
  State<SearchHubPage> createState() => _SearchHubPageState();
}

class _SearchHubPageState extends State<SearchHubPage> {
  static const _historyKey = 'greennote_search_history';

  final _controller = TextEditingController();
  final _rankingController = PageController(viewportFraction: 0.82);
  Timer? _debounce;
  List<String> _suggestions = const [];
  List<String> _hot = const [];
  List<_SearchHotGroup> _hotGroups = const [];
  List<String> _history = const [];
  String? _hotError;
  bool _loadingHot = true;
  bool _loadingSuggestions = false;
  bool _historyExpanded = false;
  int _rankingPage = 0;
  int _hotRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadHot();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _rankingController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final history = preferences.getStringList(_historyKey) ?? const [];
      if (!mounted) return;
      setState(() => _history = history);
    } catch (error) {
      debugPrint('加载搜索历史失败：$error');
    }
  }

  Future<void> _loadHot({bool refresh = false}) async {
    final request = ++_hotRequest;
    if (mounted) {
      setState(() {
        _loadingHot = true;
        _hotError = null;
      });
    }
    try {
      final response = await widget.api.getHotSearch(refresh: refresh);
      final data = response['data'] ?? response;
      final groups = _searchHotGroups(data);
      final keywords = _searchHotKeywords(data).take(12).toList();
      if (!mounted || request != _hotRequest) return;
      final page = groups.isEmpty
          ? 0
          : (_rankingPage >= groups.length ? groups.length - 1 : _rankingPage);
      setState(() {
        _hot = keywords;
        _hotGroups = groups;
        _rankingPage = page;
        _loadingHot = false;
      });
      if (_rankingController.hasClients &&
          page != _rankingController.page?.round()) {
        _rankingController.jumpToPage(page);
      }
    } catch (error) {
      if (mounted && request == _hotRequest) {
        setState(() {
          _hotError = error.toString();
          _loadingHot = false;
        });
      }
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {
      _suggestions = const [];
      _loadingSuggestions = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final response = await widget.api.getSearchSuggestions(query);
        final values = _strings(response['data']);
        if (mounted && _controller.text.trim() == query) {
          setState(() {
            _suggestions = values;
            _loadingSuggestions = false;
          });
        }
      } catch (_) {
        if (mounted && _controller.text.trim() == query) {
          setState(() => _loadingSuggestions = false);
        }
      }
    });
  }

  Future<void> _search([String? value]) async {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    _controller.text = query;
    final history = [
      query,
      ..._history.where((item) => item != query),
    ].take(20).toList();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(_historyKey, history);
    } catch (error) {
      debugPrint('保存搜索历史失败：$error');
    }
    if (!mounted) return;
    setState(() => _history = history);
    FocusScope.of(context).unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SearchResultsPage(api: widget.api, query: query),
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空全部搜索历史记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var cleared = false;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_historyKey);
      cleared = true;
    } catch (error) {
      debugPrint('清除搜索历史失败：$error');
    }
    if (mounted && cleared) setState(() => _history = const []);
  }

  @override
  Widget build(BuildContext context) {
    final isQuerying = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 8, right: 16),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.25,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '选机中心',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    onChanged: _onChanged,
                    onSubmitted: _search,
                  ),
                ),
                IconButton(
                  tooltip: '搜索',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _search(),
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
      body: isQuerying ? _buildSuggestions(context) : _buildSearchHome(context),
    );
  }

  Widget _buildSearchHome(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rankingRows = _hotGroups.isEmpty
        ? 1
        : _hotGroups
              .map((group) => group.items.length)
              .reduce((count, next) => count > next ? count : next)
              .clamp(1, 10);
    return ListView(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 24 + bottom),
      children: [
        _buildHistoryCard(context, colorScheme),
        const SizedBox(height: 12),
        _buildHotSearchCard(context, colorScheme),
        if (_hotGroups.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildRankingTabs(context, colorScheme),
          const SizedBox(height: 8),
          SizedBox(
            height: 24.0 + 46.0 * rankingRows,
            child: PageView.builder(
              controller: _rankingController,
              padEnds: false,
              itemCount: _hotGroups.length,
              onPageChanged: (index) => setState(() => _rankingPage = index),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildRankingCard(
                  context,
                  colorScheme,
                  _hotGroups[index],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context, ColorScheme colorScheme) {
    final visibleHistory = _historyExpanded ? _history : _history.take(10);
    return ReviewCard(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '搜索历史',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_history.isNotEmpty)
                  IconButton(
                    tooltip: '清空搜索历史',
                    visualDensity: VisualDensity.compact,
                    onPressed: _clearHistory,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '暂无搜索历史',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final keyword in visibleHistory)
                    _SearchChip(label: keyword, onTap: () => _search(keyword)),
                ],
              ),
              if (_history.length > 10)
                Center(
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _historyExpanded = !_historyExpanded),
                    icon: Icon(
                      _historyExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                    label: Text(_historyExpanded ? '收起搜索历史' : '展开更多搜索历史'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHotSearchCard(BuildContext context, ColorScheme colorScheme) {
    return ReviewCard(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '热门搜索',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: '刷新热门搜索',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loadingHot ? null : () => _loadHot(refresh: true),
                  icon: _loadingHot
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (_hot.isEmpty && _loadingHot)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (_hot.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _hotError ?? '暂无热门搜索',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final keyword in _hot)
                    _SearchChip(label: keyword, onTap: () => _search(keyword)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingTabs(BuildContext context, ColorScheme colorScheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in _hotGroups.asMap().entries)
            InkWell(
              onTap: () => _rankingController.animateToPage(
                entry.key,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 12, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.value.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: entry.key == _rankingPage
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: entry.key == _rankingPage
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: entry.key == _rankingPage ? 44 : 0,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRankingCard(
    BuildContext context,
    ColorScheme colorScheme,
    _SearchHotGroup group,
  ) {
    return ReviewCard(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      elevation: 1,
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final entry in group.items.take(10).toList().asMap().entries)
            InkWell(
              onTap: () => _search(_searchHotTitle(entry.value)),
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _SearchRankBadge(index: entry.key),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _searchHotTitle(entry.value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                      if (_searchHotHeat(entry.value).isNotEmpty) ...[
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: colorScheme.primary,
                          size: 17,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _searchHotHeat(entry.value),
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (_loadingSuggestions)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        for (final suggestion in _suggestions.take(8))
          ListTile(
            leading: Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(suggestion),
            onTap: () => _search(suggestion),
          ),
        if (!_loadingSuggestions && _suggestions.isEmpty)
          ListTile(
            leading: Icon(Icons.search_rounded, color: colorScheme.primary),
            title: Text('搜索“${_controller.text.trim()}”'),
            onTap: () => _search(),
          ),
      ],
    );
  }
}

class _SearchHotGroup {
  const _SearchHotGroup({required this.title, required this.items});

  final String title;
  final List<Map<String, dynamic>> items;
}

class _SearchChip extends StatelessWidget {
  const _SearchChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, color: colors.onSurface),
        ),
      ),
    );
  }
}

class _SearchRankBadge extends StatelessWidget {
  const _SearchRankBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFFF44336), Color(0xFFFF9800), Color(0xFFFFC107)];
    if (index >= colors.length) {
      return SizedBox(
        width: 24,
        child: Text(
          '${index + 1}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors[index],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${index + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

const _searchHotChildKeys = [
  'entities',
  'entityList',
  'list',
  'items',
  'children',
  'data',
];

List<dynamic> _searchHotChildren(Map<dynamic, dynamic> entity) {
  for (final key in _searchHotChildKeys) {
    final children = entity[key];
    if (children is List && children.isNotEmpty) return children;
  }
  return const [];
}

List<_SearchHotGroup> _searchHotGroups(dynamic value) {
  final groups = <_SearchHotGroup>[];
  final visited = <Object>{};

  void visit(dynamic item) {
    if (item is List) {
      for (final child in item) {
        visit(child);
      }
      return;
    }
    if (item is! Map || !visited.add(item)) return;
    if (_isSearchHotSponsor(item)) return;
    final children = _searchHotChildren(item);
    final template =
        (item['entityTemplate'] ??
                item['entity_template'] ??
                item['template'] ??
                '')
            .toString()
            .toLowerCase();
    final type =
        (item['entityType'] ?? item['entity_type'] ?? item['type'] ?? '')
            .toString()
            .toLowerCase();
    final title = _searchHotTitle(item);
    final isHotCard =
        template.contains('searchhot') || type.contains('searchhot');
    final rows = children
        .whereType<Map>()
        .where(
          (row) => !_isSearchHotSponsor(row) && _searchHotTitle(row).isNotEmpty,
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (rows.isNotEmpty &&
        title.isNotEmpty &&
        (isHotCard || children.isNotEmpty)) {
      groups.add(_SearchHotGroup(title: title, items: rows));
      return;
    }
    for (final key in _searchHotChildKeys) {
      visit(item[key]);
    }
  }

  visit(value);
  return groups;
}

List<String> _searchHotKeywords(dynamic value) {
  final keywords = <String>[];
  final seen = <String>{};
  void add(String input) {
    final keyword = input.trim();
    if (keyword.isNotEmpty && seen.add(keyword)) keywords.add(keyword);
  }

  void visit(dynamic item) {
    if (item is String) {
      add(item);
    } else if (item is List) {
      for (final child in item) {
        visit(child);
      }
    } else if (item is Map) {
      if (_isSearchHotSponsor(item)) return;
      final children = _searchHotChildren(item);
      if (children.isNotEmpty) {
        visit(children);
        return;
      }
      add(_searchHotTitle(item));
    }
  }

  visit(value);
  return keywords;
}

bool _isSearchHotSponsor(Map<dynamic, dynamic> entity) {
  final markers = [
    entity['entityType'],
    entity['entity_type'],
    entity['entityTemplate'],
    entity['entity_template'],
    entity['template'],
  ].whereType<String>().join(' ').toLowerCase();
  final sponsorType = entity['sponsorType'] ?? entity['sponsor_type'];
  final hasSponsorType = sponsorType is bool
      ? sponsorType
      : sponsorType is num
      ? sponsorType != 0
      : sponsorType != null && sponsorType.toString().isNotEmpty;
  return markers.contains('sponsor') || hasSponsorType;
}

String _searchHotTitle(Map<dynamic, dynamic> entity) {
  for (final key in ['title', 'searchValue', 'keyword', 'word', 'name']) {
    final value = entity[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _searchHotHeat(Map<dynamic, dynamic> entity) =>
    (entity['hotNum'] ?? entity['hotnum'] ?? '').toString().trim();

class SearchResultsPage extends StatefulWidget {
  const SearchResultsPage({
    required this.api,
    required this.query,
    this.initialType = 'all',
    super.key,
  });

  final CoolapkApi api;
  final String query;
  final String initialType;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage>
    with SingleTickerProviderStateMixin {
  static const searchTabs = [
    (label: '综合', type: 'all'),
    (label: '数码', type: 'product'),
    (label: '动态', type: 'feed'),
    (label: '话题', type: 'feedTopic'),
    (label: '用户', type: 'user'),
    (label: '二手', type: 'ershou'),
    (label: '应用', type: 'apk'),
  ];

  late final TabController _tabController;
  late final TextEditingController _searchController;
  late String _currentQuery;

  String _allSortType = 'default';
  String _feedSortType = 'default';
  String _feedType = 'all';

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.query;
    _searchController = TextEditingController(text: _currentQuery);

    final initialIndex =
        searchTabs.indexWhere((t) => t.type == widget.initialType);
    _tabController = TabController(
      length: searchTabs.length,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed == _currentQuery) return;
    HapticFeedbackUtil.light();
    _saveHistory(trimmed);
    setState(() {
      _currentQuery = trimmed;
      _allSortType = 'default';
      _feedSortType = 'default';
      _feedType = 'all';
    });
  }

  Future<void> _saveHistory(String query) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final history =
          preferences.getStringList('greennote_search_history') ?? const [];
      final updated = [
        query,
        ...history.where((k) => k != query),
      ].take(20).toList();
      await preferences.setStringList('greennote_search_history', updated);
    } catch (_) {}
  }

  void _onSwitchToUserTab() {
    const userIndex = 4;
    if (_tabController.index != userIndex) {
      _tabController.animateTo(userIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SearchResultsScope(
      query: _currentQuery,
      allSortType: _allSortType,
      onAllSortChanged: (s) => setState(() => _allSortType = s),
      onSwitchToUserTab: _onSwitchToUserTab,
      child: Scaffold(
        appBar: ReviewFrostedAppBar(
          titleSpacing: 0,
          title: Container(
            height: 38,
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submitSearch,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '搜索酷安',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white60,
                    size: 20,
                  ),
                  onPressed: () => _submitSearch(_searchController.text),
                ),
              ],
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: const Color(0xFF00B075),
            indicatorWeight: 3.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.normal,
            ),
            dividerColor: Colors.transparent,
            tabs: [
              for (final tab in searchTabs)
                Tab(text: tab.label),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            for (final tab in searchTabs) _buildTabView(tab.type),
          ],
        ),
      ),
    );
  }

  Widget _buildTabView(String type) {
    if (type == 'all') {
      return ApiListPage(
        key: ValueKey('search-all-$_currentQuery-$_allSortType'),
        api: widget.api,
        title: '综合',
        path: '/v6/search',
        query: {
          'type': 'all',
          'searchValue': _currentQuery,
          'sort': _allSortType == 'exact' ? 'default' : _allSortType,
          'sortType': _allSortType,
          if (_allSortType == 'exact') 'isExact': 1,
          'show_flag': 1,
        },
        showAppBar: false,
      );
    }
    if (type == 'feed') {
      return ApiListPage(
        key: ValueKey('search-feed-$_currentQuery-$_feedSortType-$_feedType'),
        api: widget.api,
        title: '动态',
        path: '/v6/search',
        header: SearchFeedHeaderBar(
          currentSort: _feedSortType,
          onSortChanged: (s) => setState(() => _feedSortType = s),
          currentFilter: _feedType,
          onFilterChanged: (f) => setState(() => _feedType = f),
        ),
        query: {
          'type': 'feed',
          'searchValue': _currentQuery,
          'sort': _feedSortType == 'exact' ? 'default' : _feedSortType,
          'sortType': _feedSortType,
          if (_feedSortType == 'exact') 'isExact': 1,
          if (_feedType != 'all') 'feedType': _feedType,
          'show_flag': 1,
        },
        showAppBar: false,
      );
    }
    return ApiListPage(
      key: ValueKey('search-$type-$_currentQuery'),
      api: widget.api,
      title: '搜索',
      path: '/v6/search',
      query: {
        'type': type,
        'searchValue': _currentQuery,
        'show_flag': 1,
      },
      showAppBar: false,
    );
  }
}

class MessageCenterPage extends StatelessWidget {
  const MessageCenterPage({required this.api, super.key});
  final CoolapkApi api;

  @override
  Widget build(BuildContext context) {
    const routes = [
      ('私信', '/v6/message/list'),
      ('@我的', '/v6/notification/atMeList'),
      ('收到的评论', '/v6/notification/commentMeList'),
      ('回复与@', '/v6/notification/atCommentMeList'),
      ('收到的赞', '/v6/notification/feedLikeList'),
      ('系统通知', '/v6/notification/list'),
    ];
    return DefaultTabController(
      length: routes.length,
      child: Column(
        children: [
          _NotificationCount(api: api),
          TabBar(
            isScrollable: true,
            tabs: [for (final route in routes) Tab(text: route.$1)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final route in routes)
                  route.$1 == '私信'
                      ? _MessageSessionsPage(api: api)
                      : ApiListPage(
                          api: api,
                          title: route.$1,
                          path: route.$2,
                          showAppBar: false,
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCount extends StatefulWidget {
  const _NotificationCount({required this.api});
  final CoolapkApi api;

  @override
  State<_NotificationCount> createState() => _NotificationCountState();
}

class _NotificationCountState extends State<_NotificationCount> {
  Map<String, dynamic>? _counts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await widget.api.request('/v6/notification/checkCount');
      final data = response is Map ? response['data'] : null;
      if (mounted) {
        setState(() {
          _error = null;
          _counts = data is Map ? Map<String, dynamic>.from(data) : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    if (counts == null && _error == null) {
      return const LinearProgressIndicator();
    }
    if (counts == null) {
      return ListTile(
        dense: true,
        title: Text(_error ?? '未读消息暂不可用'),
        trailing: IconButton(
          tooltip: '刷新未读数',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      );
    }
    final entries = counts.entries
        .where(
          (entry) =>
              entry.value is num || int.tryParse('${entry.value}') != null,
        )
        .toList(growable: false);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('酷安暂未返回可识别的未读计数'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Wrap(
        spacing: 16,
        children: [
          for (final entry in entries)
            Text('${_humanLabel(entry.key)} ${entry.value}'),
        ],
      ),
    );
  }
}

class _MessageSessionsPage extends StatefulWidget {
  const _MessageSessionsPage({required this.api});
  final CoolapkApi api;

  @override
  State<_MessageSessionsPage> createState() => _MessageSessionsPageState();
}

class _MessageSessionsPageState extends State<_MessageSessionsPage> {
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _rows = const [];
  String? _error;
  bool _busy = false;
  bool _more = true;
  bool _errorOnRefresh = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 480) {
      _load(older: true);
    }
  }

  Future<void> _load({bool older = false}) async {
    if (_busy || (older && !_more)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextPage = older ? _page + 1 : 1;
      final page = await widget.api.getList(
        '/v6/message/list',
        query: {'page': nextPage},
      );
      if (mounted) {
        setState(() {
          if (!older) {
            _rows = [];
          }
          final known = _rows.map(_messageKey).toSet();
          _rows.addAll(
            page.items.where((item) => known.add(_messageKey(item))),
          );
          _page = nextPage;
          _more = page.hasMore && page.items.isNotEmpty;
          _errorOnRefresh = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _errorOnRefresh = !older;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => EasyRefresh(
    header: reviewDefaultRefreshHeader,
    onRefresh: () => _load(),
    child: _busy && _rows.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _rows.isEmpty
        ? ListView(
            children: [ListTile(title: Text(_error!), onTap: _load)],
          )
        : ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _rows.length + (_busy || _error != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _rows.length) {
                if (_busy) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (!_more && _error == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('已加载全部会话')),
                  );
                }
                return TextButton(
                  onPressed: () =>
                      _load(older: _rows.isNotEmpty && !_errorOnRefresh),
                  child: Text(_error == null ? '加载更多会话' : '加载失败，点击重试：$_error'),
                );
              }
              final row = _rows[index];
              final uid = _first(row, ['uid', 'toUid', 'targetUid']);
              final ukey = _first(row, ['ukey', 'sessionKey', 'session_id']);
              final avatar = _first(row, [
                'userAvatar',
                'avatar',
                'user_avatar',
              ]);
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatar.isEmpty
                      ? null
                      : NetworkImage(
                          normalizeCoolapkImageUrl(avatar),
                          headers: coolapkImageHeaders(avatar, api: widget.api),
                        ),
                  child: avatar.isEmpty
                      ? const Icon(Icons.person_outline_rounded)
                      : null,
                ),
                title: Text(
                  _first(row, ['username', 'userName', 'title']).isEmpty
                      ? '私信会话'
                      : _first(row, ['username', 'userName', 'title']),
                ),
                subtitle: Text(
                  _first(row, ['lastMessage', 'message', 'description']),
                ),
                trailing: ukey.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value != 'delete') return;
                          final sure = await showAppDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('删除会话？'),
                              content: const Text('会话删除请求会提交给酷安。'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (!context.mounted || sure != true) return;
                          try {
                            await widget.api.request(
                              '/v6/message/delChatSession',
                              method: 'POST',
                              query: {'ukey': ukey},
                            );
                            await _load();
                          } catch (error) {
                            if (context.mounted) {
                              _snack(context, error.toString());
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('删除会话')),
                        ],
                      ),
                onTap: ukey.isEmpty && uid.isEmpty
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => MessageChatPage(
                            api: widget.api,
                            uid: uid,
                            ukey: ukey.isEmpty ? uid : ukey,
                          ),
                        ),
                      ),
              );
            },
          ),
  );
}

class MessageChatPage extends StatefulWidget {
  const MessageChatPage({
    required this.api,
    required this.uid,
    required this.ukey,
    super.key,
  });
  final CoolapkApi api;
  final String uid;
  final String ukey;

  @override
  State<MessageChatPage> createState() => _MessageChatPageState();
}

class _MessageChatPageState extends State<MessageChatPage> {
  final _controller = TextEditingController();
  final _pictureController = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  bool _busy = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _hasOlder = true;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pictureController.dispose();
    super.dispose();
  }

  Future<void> _load({bool older = false}) async {
    if (_busy || _loadingOlder || (older && !_hasOlder)) return;
    if (older) {
      setState(() => _loadingOlder = true);
    } else {
      setState(() => _busy = true);
    }
    try {
      final nextPage = older ? _page + 1 : 1;
      final result = await widget.api.getList(
        '/v6/message/chat',
        query: {'ukey': widget.ukey, 'page': nextPage},
      );
      if (mounted) {
        setState(() {
          if (older) {
            final known = _messages.map(_messageKey).toSet();
            _messages = [
              ..._messages,
              ...result.items.where((item) => known.add(_messageKey(item))),
            ];
          } else {
            _messages = result.items;
          }
          _page = nextPage;
          _hasOlder = result.hasMore && result.items.isNotEmpty;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loadingOlder = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty || widget.uid.isEmpty || _busy || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendMessage(
        widget.uid,
        message,
        pic: _pictureController.text.trim().isEmpty
            ? null
            : _pictureController.text.trim(),
      );
      _controller.clear();
      _pictureController.clear();
      await _load();
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: const Text('私信'),
      actions: [
        IconButton(
          tooltip: '加载更早消息',
          onPressed: _busy || _loadingOlder || !_hasOlder
              ? null
              : () => _load(older: true),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: _busy && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? '还没有消息'),
                      if (_error != null)
                        TextButton(
                          onPressed: _busy ? null : () => _load(),
                          child: const Text('重试'),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final row = _messages[index];
                    final picture = _first(row, [
                      'pic',
                      'picture',
                      'image',
                      'imageUrl',
                    ]);
                    final pictureUrl = normalizeCoolapkImageUrl(picture);
                    final pictureUri = Uri.tryParse(pictureUrl);
                    return ListTile(
                      title: Text(
                        _first(row, ['username', 'userName', 'fromName']),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_first(row, ['message', 'content', 'text'])),
                          if (pictureUri != null &&
                              pictureUri.scheme == 'https' &&
                              pictureUri.host.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  pictureUrl,
                                  headers: coolapkImageHeaders(
                                    pictureUrl,
                                    api: widget.api,
                                  ),
                                  height: 180,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '发送私信',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '附加图片 URL',
                  onPressed: () async {
                    final url = await showAppDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('附加图片'),
                        content: TextField(
                          controller: _pictureController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: '图片 URL',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.pop(context, _pictureController.text),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    );
                    if (context.mounted && url != null) {
                      setState(() => _pictureController.text = url.trim());
                    }
                  },
                  icon: Icon(
                    _pictureController.text.isEmpty
                        ? Icons.attach_file_rounded
                        : Icons.image_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '发送私信',
                  onPressed: _sending || _busy ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({required this.api, this.accountRevision = 0, super.key});
  final CoolapkApi api;
  final int accountRevision;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Map<String, dynamic>? _login;
  String? _error;
  bool _checking = false;
  bool _lastObservedCookie = false;
  Future<Map<String, dynamic>>? _spaceFuture;
  Future<ApiPage>? _topicsFuture;
  Future<ApiPage>? _historyFuture;
  Future<ApiPage>? _collectionsFuture;
  Future<ApiPage>? _questionsFuture;

  @override
  void initState() {
    super.initState();
    _lastObservedCookie = widget.api.hasCookie;
    if (widget.api.hasCookie) _checkLogin();
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountRevision != widget.accountRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAccountState(forceReload: true);
      });
    }
  }

  Future<void> _checkLogin() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final response = await widget.api.checkLogin();
      final data = response['data'];
      if (mounted) {
        setState(
          () =>
              _login = data is Map ? Map<String, dynamic>.from(data) : response,
        );
        if (widget.api.currentUid.isNotEmpty) _loadDashboard();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _loginPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => CookieLoginPage(api: widget.api)),
    );
    if (mounted) _checkLogin();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AppSettingsPage(
          api: widget.api,
          onOpenCookieManager: _loginPage,
          onAccountChanged: () => _syncAccountState(forceReload: true),
        ),
      ),
    );
    if (mounted) _syncAccountState(forceReload: true);
  }

  void _syncAccountState({bool forceReload = false}) {
    if (!mounted) return;
    if (widget.api.hasCookie) {
      _lastObservedCookie = true;
      if ((forceReload || _login == null || _error != null) && !_checking) {
        _checkLogin();
      }
    } else {
      _lastObservedCookie = false;
      if (_login != null || _error != null) {
        setState(() {
          _login = null;
          _error = null;
          _spaceFuture = null;
          _topicsFuture = null;
          _historyFuture = null;
          _collectionsFuture = null;
          _questionsFuture = null;
        });
      }
    }
  }

  void _loadDashboard() {
    final uid = widget.api.currentUid;
    if (uid.isEmpty) return;
    setState(() {
      _spaceFuture = _loadSpace(uid);
      _topicsFuture = widget.api.getList('/v6/topic/myFollowTopicList');
      _historyFuture = widget.api.getList('/v6/member/recentHistoryList');
      _collectionsFuture = widget.api.getList(
        '/v6/collection/myCollectionList',
      );
      _questionsFuture = widget.api.getUserPage(
        '/v6/user/questionAndAnswerList',
        uid,
        1,
      );
    });
  }

  Future<Map<String, dynamic>> _loadSpace(String uid) async {
    final responses = await Future.wait([
      widget.api.getUserSpace(uid),
      widget.api.getUserProfile(uid).catchError((_) => <String, dynamic>{}),
    ]);
    final spaceResponse = responses.first;
    final profileResponse = responses.last;
    final spaceData = spaceResponse['data'];
    final profileData = profileResponse['data'];
    final spaceUser = spaceData is Map
        ? (spaceData['userInfo'] ?? spaceData['user_info'])
        : null;
    final profileUser = profileData is Map
        ? (profileData['userInfo'] ?? profileData['user_info'])
        : null;
    return {
      if (spaceUser is Map) ...Map<String, dynamic>.from(spaceUser),
      if (profileUser is Map) ...Map<String, dynamic>.from(profileUser),
      if (spaceData is Map) ...Map<String, dynamic>.from(spaceData),
      if (profileData is Map) ...Map<String, dynamic>.from(profileData),
      ...spaceResponse,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_lastObservedCookie != widget.api.hasCookie) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncAccountState());
    }
    final loggedIn = widget.api.hasCookie && _login != null && _error == null;
    final loginUser = _login?['userInfo'] ?? _login?['user_info'];
    final user = <String, dynamic>{
      if (loginUser is Map) ...Map<String, dynamic>.from(loginUser),
      ...?_login,
    };
    final uid = _first(_login, ['uid', 'userId', 'id']).isEmpty
        ? widget.api.currentUid
        : _first(_login, ['uid', 'userId', 'id']);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _buildProfile(user, loggedIn, uid),
        _buildStatistics(uid, enabled: loggedIn),
        _buildShortcuts(uid, enabled: loggedIn),
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 18, 5, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '我的卡片',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: loggedIn && uid.isNotEmpty
                    ? () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              UserSpacePage(api: widget.api, uid: uid),
                        ),
                      )
                    : _openSettings,
                child: const Text('更多'),
              ),
            ],
          ),
        ),
        _previewSection(
          '我关注的话题',
          '/v6/topic/myFollowTopicList',
          _topicsFuture,
          icon: Icons.tag_rounded,
        ),
        _previewSection(
          '我的常去',
          '/v6/member/recentHistoryList',
          _historyFuture,
          icon: Icons.history_rounded,
        ),
        _previewSection(
          '我的收藏单',
          '/v6/collection/myCollectionList',
          _collectionsFuture,
          icon: Icons.folder_open_rounded,
        ),
        _previewSection(
          '我的问答',
          '/v6/user/questionAndAnswerList',
          _questionsFuture,
          icon: Icons.question_answer_outlined,
          query: {'uid': uid},
        ),
        _group(context, '更多', [_CreateCollectionRow(api: widget.api)]),
      ],
    );
  }

  Widget _buildProfile(
    Map<String, dynamic> user,
    bool loggedIn,
    String uid,
  ) => FutureBuilder<Map<String, dynamic>>(
    future: _spaceFuture,
    builder: (context, snapshot) {
      final data = {...user, ...?snapshot.data};
      final name = _first(data, ['username', 'userName', 'name']);
      final level = _first(data, ['level', 'userLevel']);
      final experience = int.tryParse(_first(data, ['experience', 'exp']));
      final nextExperience = int.tryParse(
        _first(data, ['next_level_experience', 'nextLevelExperience']),
      );
      final showProgress =
          experience != null && nextExperience != null && nextExperience > 0;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loggedIn && uid.isNotEmpty
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => UserSpacePage(api: widget.api, uid: uid),
                ),
              )
            : _openSettings,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 22, 8, 12),
          child: Row(
            children: [
              AppAvatar(
                url: _first(data, ['userAvatar', 'avatar']).isEmpty
                    ? widget.api.currentUserAvatar
                    : _first(data, ['userAvatar', 'avatar']),
                api: widget.api,
                size: 82,
                name: name,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? (loggedIn ? '酷安用户' : '未登录') : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (level.isNotEmpty || showProgress) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (level.isNotEmpty)
                            Text(
                              'Lv.$level',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          const Spacer(),
                          if (showProgress) Text('$experience/$nextExperience'),
                        ],
                      ),
                      if (showProgress) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (experience / nextExperience).clamp(0, 1),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 5),
                      Text(
                        _checking
                            ? '正在校验登录状态…'
                            : _error ?? (uid.isEmpty ? '点击登录酷安' : 'UID $uid'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                loggedIn ? Icons.qr_code_2_rounded : Icons.login_rounded,
                size: 28,
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 28),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildStatistics(String uid, {required bool enabled}) =>
      FutureBuilder<Map<String, dynamic>>(
        future: _spaceFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AppSectionCard(
                child: ListTile(
                  title: const Text('个人统计加载失败'),
                  subtitle: Text(
                    snapshot.error.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            );
          }
          final data = snapshot.data;
          final values = [
            _first(data, ['feed_num', 'feedNum', 'feednum', 'feedCount']),
            _first(data, ['follow_num', 'followNum', 'follownum', 'follow']),
            _first(data, ['fans_num', 'fansNum', 'fansnum', 'fans']),
          ];
          final taps = [
            () => enabled
                ? _openRoute('/v6/user/feedList', {'uid': uid})
                : _openSettings(),
            () => enabled
                ? _openRoute('/v6/user/myFollowList', const {})
                : _openSettings(),
            () => enabled
                ? _openRoute('/v6/user/myFansList', const {})
                : _openSettings(),
          ];
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppSectionCard(
              child: Row(
                children: [
                  for (var index = 0; index < values.length; index++) ...[
                    _stat(
                      context,
                      enabled ? values[index] : '—',
                      ['动态', '关注', '粉丝'][index],
                      taps[index],
                    ),
                    if (index < values.length - 1)
                      const SizedBox(
                        height: 48,
                        child: VerticalDivider(width: 1),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );

  Widget _stat(
    BuildContext context,
    String value,
    String label,
    VoidCallback onTap,
  ) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              value.isEmpty ? '—' : value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _buildShortcuts(String uid, {required bool enabled}) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: AppSectionCard(
      child: Row(
        children: [
          _shortcut(
            context,
            Icons.star_rounded,
            '我的收藏',
            '/v6/collection/myCollectionList',
            color: const Color(0xFF2589E8),
            enabled: enabled,
          ),
          _shortcut(
            context,
            Icons.article_rounded,
            '我的图文',
            '/v6/user/htmlFeedList',
            query: {'uid': uid},
            color: const Color(0xFFE94848),
            enabled: enabled,
          ),
          _shortcut(
            context,
            Icons.apps_rounded,
            '应用管理',
            '/v6/apk/developerAppList',
            query: {'uid': uid},
            color: const Color(0xFF9862E8),
            enabled: enabled,
          ),
          Expanded(
            child: _ShortcutButton(
              icon: Icons.more_horiz_rounded,
              label: '更多',
              color: const Color(0xFF1DB8C3),
              onTap: _showMore,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _shortcut(
    BuildContext context,
    IconData icon,
    String label,
    String path, {
    Map<String, dynamic> query = const {},
    Color? color,
    required bool enabled,
  }) => Expanded(
    child: _ShortcutButton(
      icon: icon,
      label: label,
      color: color,
      onTap: () => enabled ? _openRoute(path, query) : _openSettings(),
    ),
  );

  Widget _previewSection(
    String title,
    String route,
    Future<ApiPage>? future, {
    required IconData icon,
    Map<String, dynamic> query = const {},
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: widget.api.hasCookie && _login != null
                    ? () => _openRoute(route, query)
                    : _openSettings,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('更多'),
              ),
            ],
          ),
        ),
        AppSectionCard(
          child: FutureBuilder<ApiPage>(
            future: future,
            builder: (context, snapshot) {
              if (widget.api.hasCookie && _error != null && _login == null) {
                return ListTile(
                  leading: Icon(icon),
                  title: const Text('登录状态校验失败'),
                  subtitle: Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '重试',
                    onPressed: _checkLogin,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                );
              }
              if (!widget.api.hasCookie || _login == null) {
                return ListTile(
                  leading: Icon(icon),
                  title: const Text('登录后查看'),
                  subtitle: Text(title),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openSettings,
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return ListTile(
                  leading: Icon(icon),
                  title: const Text('内容加载失败'),
                  subtitle: Text(
                    snapshot.error.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '重试',
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                );
              }
              final items =
                  snapshot.data?.items ?? const <Map<String, dynamic>>[];
              if (items.isEmpty) {
                return ListTile(
                  leading: Icon(icon),
                  title: Text(_emptyLabel(title)),
                );
              }
              if (title == '我关注的话题' || title == '我的常去') {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in items.take(8)) _accountMiniCard(item),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items.take(4))
                    ApiEntityCard(api: widget.api, entity: item),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  String _emptyLabel(String title) => switch (title) {
    '我的问答' => '还没有发布过问答',
    '我的收藏单' => '还没有创建收藏单',
    '我关注的话题' => '还没有关注话题',
    _ => '暂无最近访问内容',
  };

  Widget _accountMiniCard(Map<String, dynamic> item) {
    final type = _first(item, ['entityType', 'entity_type']).toLowerCase();
    final image = _first(item, [
      'logo',
      'icon',
      'pic',
      'cover',
      'userAvatar',
      'avatar',
    ]);
    final title = _first(item, [
      'title',
      'username',
      'userName',
      'productName',
      'apkName',
      'tag',
    ]);
    final count = _first(item, [
      'feedNumTxt',
      'feed_num_txt',
      'hotNumTxt',
      'hot_num_txt',
    ]);
    final subtitle = count.isNotEmpty
        ? (type.contains('topic') ? '$count条动态' : count)
        : _first(item, ['description', 'message']);
    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: () => _openAccountItem(item, type),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: image.isEmpty
                    ? Container(
                        width: 72,
                        height: 72,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Icon(Icons.image_outlined),
                      )
                    : CachedNetworkImage(
                        image,
                        headers: coolapkImageHeaders(image, api: widget.api),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 72,
                          height: 72,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
              const SizedBox(height: 7),
              Text(
                title.isEmpty ? '酷安内容' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAccountItem(Map<String, dynamic> item, String type) {
    final id = _first(item, [
      'uid',
      'id',
      'entityId',
      'entity_id',
      'tag',
      'tagName',
      'packageName',
      'productId',
    ]);
    if (id.isEmpty) return;
    final Widget page;
    if (type.contains('feed')) {
      page = FeedDetailPage(api: widget.api, feed: CoolapkFeed.fromJson(item));
    } else if (type.contains('topic') || type.contains('tag')) {
      final topicTag = ApiEntityCard.extractTopicTag(item);
      final finalTag = topicTag.isNotEmpty ? topicTag : id;
      final title = _first(item, ['title', 'name', 'tag', 'tagName']);
      final logo = _first(item, ['logo', 'icon', 'pic', 'avatar']);
      page = TopicPage(
        api: widget.api,
        tag: finalTag,
        initialTitle: title.isNotEmpty ? title : null,
        initialLogo: logo.isNotEmpty ? logo : null,
      );
    } else if (type.contains('user')) {
      page = UserSpacePage(api: widget.api, uid: id);
    } else if (type.contains('product') || type.contains('rating')) {
      page = ProductPage(
        api: widget.api,
        id: id,
        title: _first(item, ['title', 'name']),
      );
    } else {
      page = RawEntityPage(api: widget.api, entity: item);
    }
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openRoute(String path, Map<String, dynamic> query) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: widget.api,
          title: _routeTitle(path),
          path: path,
          query: query,
        ),
      ),
    );
  }

  String _routeTitle(String path) => switch (path) {
    '/v6/topic/myFollowTopicList' => '我关注的话题',
    '/v6/member/recentHistoryList' => '最近访问',
    '/v6/collection/myCollectionList' => '我的收藏单',
    '/v6/user/questionAndAnswerList' => '我的问答',
    '/v6/user/feedList' => '我的动态',
    '/v6/user/myFollowList' => '我的关注',
    '/v6/user/myFansList' => '我的粉丝',
    '/v6/user/htmlFeedList' => '我的图文',
    '/v6/apk/developerAppList' => '开发者应用',
    _ => '我的内容',
  };

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline_rounded),
              title: const Text('我的关注'),
              onTap: () {
                Navigator.pop(context);
                _openRoute('/v6/user/myFollowList', const {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('我的粉丝'),
              onTap: () {
                Navigator.pop(context);
                _openRoute('/v6/user/myFansList', const {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Object> children) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 5, bottom: 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AppSectionCard(
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i] is _RouteItem
                        ? _FeatureRow(
                            api: widget.api,
                            item: children[i] as _RouteItem,
                          )
                        : children[i] as Widget,
                    if (i + 1 < children.length)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color ?? Theme.of(context).colorScheme.primary,
            size: 25,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class CookieLoginPage extends StatefulWidget {
  const CookieLoginPage({required this.api, super.key});
  final CoolapkApi api;

  @override
  State<CookieLoginPage> createState() => _CookieLoginPageState();
}

class _CookieLoginPageState extends State<CookieLoginPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndCheck() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.validateAndSaveCookie(value);
      _controller.clear();
      if (mounted) setState(() => _status = '已通过酷安接口校验，Cookie 保存在本机安全存储中。');
    } catch (error) {
      if (mounted) setState(() => _status = '校验失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: const Text('登录酷安')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('在酷安官方客户端或浏览器登录后，复制自己的 Cookie 粘贴到此处。请勿把 Cookie 发给他人。'),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          obscureText: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '酷安 Cookie',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _saveAndCheck,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user_outlined),
          label: const Text('安全保存并校验'),
        ),
        if (_status != null) ...[const SizedBox(height: 12), Text(_status!)],
      ],
    ),
  );
}

class ComposeFeedPage extends StatefulWidget {
  const ComposeFeedPage({
    required this.api,
    this.initialTag,
    this.initialProductId,
    this.initialMessage,
    super.key,
  });
  final CoolapkApi api;
  final String? initialTag;
  final String? initialProductId;
  final String? initialMessage;

  @override
  State<ComposeFeedPage> createState() => _ComposeFeedPageState();
}

class _ComposeFeedPageState extends State<ComposeFeedPage> {
  late final _message = TextEditingController(
    text: widget.initialMessage ?? '',
  );
  final _picture = TextEditingController();
  final _extraTitle = TextEditingController();
  late final _tag = TextEditingController(text: widget.initialTag ?? '');
  final _location = TextEditingController();
  late final _productId = TextEditingController(
    text: widget.initialProductId ?? '',
  );
  final _voteId = TextEditingController();
  String _type = 'feed';
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    _picture.dispose();
    _extraTitle.dispose();
    _tag.dispose();
    _location.dispose();
    _productId.dispose();
    _voteId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_message.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.createFeed(
        _message.text.trim(),
        pic: _picture.text.trim().isEmpty ? null : _picture.text.trim(),
        type: _type,
        extraTitle: _extraTitle.text.trim(),
        tag: _tag.text.trim(),
        location: _location.text.trim(),
        productId: _productId.text.trim(),
        voteId: _voteId.text.trim(),
      );
      if (mounted) {
        _snack(context, '已提交给酷安');
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: const Text('发布动态'),
      actions: [
        TextButton(onPressed: _busy ? null : _submit, child: const Text('发布')),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'feed', label: Text('动态')),
            ButtonSegment(value: 'picture', label: Text('酷图')),
            ButtonSegment(value: 'article', label: Text('文章')),
            ButtonSegment(value: 'ershou', label: Text('好物')),
          ],
          selected: {_type},
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _message,
          minLines: 5,
          maxLines: 12,
          maxLength: 5000,
          decoration: const InputDecoration(
            hintText: '分享新鲜事…',
            border: OutlineInputBorder(),
          ),
        ),
        ExpansionTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('更多发布信息'),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            for (final field in [
              (_extraTitle, '文章标题'),
              (_tag, '话题标签'),
              (_location, '位置名称'),
              (_productId, '关联产品 ID'),
              (_voteId, '关联投票 ID'),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: field.$1,
                  decoration: InputDecoration(
                    labelText: field.$2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
        TextField(
          controller: _picture,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '图片 URL（可选）',
            helperText: '接口文档仅列出图片 URL 参数；本版不上传本地图片。',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
      ],
    ),
  );
}

class UpdateCheckPage extends StatefulWidget {
  const UpdateCheckPage({required this.api, super.key});
  final CoolapkApi api;

  @override
  State<UpdateCheckPage> createState() => _UpdateCheckPageState();
}

class _UpdateCheckPageState extends State<UpdateCheckPage> {
  final _packages = TextEditingController(text: '[]');
  dynamic _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _packages.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    dynamic packageList;
    try {
      packageList = jsonDecode(_packages.text);
    } on FormatException {
      setState(() => _error = '请先输入有效的 JSON');
      return;
    }
    if (packageList is! List && packageList is! Map) {
      setState(() => _error = '应用清单 JSON 必须是数组或对象');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await widget.api.request(
        '/v6/apk/updateList',
        method: 'POST',
        body: {'pkgs': jsonEncode(packageList)},
      );
      if (mounted) setState(() => _result = response);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: const Text('检查应用更新')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '为避免申请读取全部已安装应用的权限，这里由你粘贴应用包名和版本 JSON。格式需符合酷安 updateList 接口要求。',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _packages,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'pkgs JSON',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _check,
          icon: const Icon(Icons.system_update_alt_rounded),
          label: const Text('提交并检查'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[const SizedBox(height: 10), Text(_error!)],
        if (_result != null) ...[
          const SizedBox(height: 14),
          const Text('酷安返回结果'),
          SelectableText(const JsonEncoder.withIndent('  ').convert(_result)),
        ],
      ],
    ),
  );
}

class _CreateCollectionRow extends StatelessWidget {
  const _CreateCollectionRow({required this.api});
  final CoolapkApi api;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.create_new_folder_outlined),
    title: const Text('创建收藏夹'),
    onTap: () async {
      final title = TextEditingController();
      final description = TextEditingController();
      var isOpen = true;
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('新建收藏夹'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: '说明'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('公开收藏夹'),
                  value: isOpen,
                  onChanged: (value) => setDialogState(() => isOpen = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('创建'),
              ),
            ],
          ),
        ),
      );
      final titleText = title.text.trim();
      final descriptionText = description.text.trim();
      title.dispose();
      description.dispose();
      if (ok != true || titleText.isEmpty) return;
      try {
        await api.createCollection(
          titleText,
          description: descriptionText,
          isOpen: isOpen,
        );
        if (context.mounted) _snack(context, '收藏夹已创建');
      } catch (error) {
        if (context.mounted) _snack(context, error.toString());
      }
    },
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.api,
    required this.item,
  });
  final CoolapkApi api;
  final _RouteItem item;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(item.icon),
    title: Text(item.label),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ApiListPage(
                api: api,
                title: item.label,
                path: item.path,
                query: item.query,
              ),
            ),
          );
        },
  );
}

class _RouteItem {
  const _RouteItem(this.label, this.path);
  final String label;
  final String path;
  Map<String, dynamic> get query => const {};
  IconData get icon => switch (path.split('/').last) {
    'search' || 'couponSearch' => Icons.search_rounded,
    'categoryList' || 'brandList' => Icons.category_outlined,
    'rankList' || 'rating' => Icons.leaderboard_outlined,
    'gameList' || 'hotGameList' || 'giftList' => Icons.sports_esports_outlined,
    'recentHistoryList' => Icons.history_rounded,
    'myCollectionList' => Icons.bookmark_outline_rounded,
    'myFollowTopicList' || 'quickList' => Icons.tag_rounded,
    'replyList' || 'replyToMeList' => Icons.mode_comment_outlined,
    _ => Icons.explore_outlined,
  };
}

List<String> _strings(dynamic value) {
  final result = <String>[];
  void visit(dynamic item) {
    if (item is String) {
      if (item.trim().isNotEmpty) result.add(item.trim());
    } else if (item is Map) {
      for (final key in ['keyword', 'key', 'title', 'name', 'text', 'word']) {
        final text = item[key]?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          result.add(text);
          return;
        }
      }
    } else if (item is List) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return result.toSet().toList(growable: false);
}

String _first(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return '';
  for (final key in keys) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _humanLabel(String key) {
  final value = key.toLowerCase();
  if (value.contains('message')) return '私信';
  if (value.contains('at') || value.contains('mention')) return '@';
  if (value.contains('comment') || value.contains('reply')) return '评论';
  if (value.contains('like')) return '点赞';
  if (value.contains('system')) return '系统';
  return key;
}

String _messageKey(Map<String, dynamic> row) {
  final id = row['messageId'] ?? row['message_id'] ?? row['mid'] ?? row['id'];
  return id == null ? jsonEncode(row) : id.toString();
}

void _snack(BuildContext context, String message) =>
    AppToast.show(context, message);
