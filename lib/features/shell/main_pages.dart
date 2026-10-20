import '../shared/message_chat_content.dart';
import '../shared/official_notification_center_page.dart';
import '../shared/community_library_page.dart';
import '../shared/community_detail_page.dart';
import '../account/anonymous_accounts_page.dart';
import '../account/local_account_page.dart';

import 'package:easy_refresh/easy_refresh.dart';

import '../../core/widgets/review_refresh_header.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/design_system/components/review_card.dart';
import '../../core/widgets/app_avatar.dart';
import '../settings/app_settings_page.dart';
import '../feed/feed_pages.dart';
import '../shared/api_list_page.dart';
import '../shared/app_management_page.dart';
import '../shared/discovery_channel_page.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/utils/coolapk_url_handler.dart';
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
    _DiscoveryChannel('生活', '/page?url=V15_ZHUANTI_SHENGHUO'),
    _DiscoveryChannel('二手', '/page?url=V11_DISCOVERY_SECOND_HAND'),
    _DiscoveryChannel('酷图', '/page?url=V11_FIND_COOLPIC'),
    _DiscoveryChannel('宠物', '/page?url=V15_CHONGWU'),
    _DiscoveryChannel('运动', '/page?url=V15_YUNDONG'),
    _DiscoveryChannel('看看号', '/user/dyhSubscribe'),
    _DiscoveryChannel('商家', '/page?url=V14_SALE'),
    _DiscoveryChannel('好物榜', '/page?url=V12_FIND_KUBANG'),
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
    preferredSize: const Size.fromHeight(38),
    child: Builder(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        final primary = Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF009688)
            : colors.primary;
        return TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: primary,
          indicatorWeight: 3,
          labelColor: primary,
          labelStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelColor: colors.onSurfaceVariant,
          unselectedLabelStyle: const TextStyle(fontSize: 16),
          tabs: [for (final channel in _channels) Tab(height: 38, text: channel.title)],
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
    return DiscoveryChannelPage(
      key: ValueKey('discover-${channel.title}'),
      api: widget.api,
      title: channel.title,
      route: route,
    );
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

    final initialIndex = searchTabs.indexWhere(
      (t) => t.type == widget.initialType,
    );
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
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '搜索酷安',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.white38),
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
            tabs: [for (final tab in searchTabs) Tab(text: tab.label)],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [for (final tab in searchTabs) _buildTabView(tab.type)],
        ),
      ),
    );
  }

  Widget _buildTabView(String type) {
    if (type == 'all') {
      final isDefaultSort = _allSortType == 'default';
      return ApiListPage(
        key: ValueKey('search-all-$_currentQuery-$_allSortType'),
        api: widget.api,
        title: '综合',
        path: '/v6/search',
        header: !isDefaultSort
            ? SearchFeedSectionHeader(
                currentSort: _allSortType,
                onSortChanged: (s) => setState(() => _allSortType = s),
              )
            : null,
        query: {
          'type': isDefaultSort ? 'all' : 'feed',
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
        key: ValueKey('search-feed-$_currentQuery'),
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
      query: {'type': type, 'searchValue': _currentQuery, 'show_flag': 1},
      showAppBar: false,
    );
  }
}

class MessageCenterPage extends StatelessWidget {
  const MessageCenterPage({required this.api, super.key});
  final CoolapkApi api;
  @override
  Widget build(BuildContext context) => OfficialNotificationCenterPage(
    api: api,
    messagesBuilder: (_) => _MessageSessionsPage(api: api),
  );
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
  bool _isSelecting = false;
  final Set<String> _selectedUkeys = {};

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

  String _formatMessageTime(Map<String, dynamic> row) {
    final raw = _first(row, [
      'dateline',
      'created_at',
      'last_update',
      'time',
      'date',
      'last_time',
    ]);
    if (raw.isEmpty) return '';
    final timestamp = int.tryParse(raw);
    DateTime? dt;
    if (timestamp != null) {
      final sec = timestamp > 10000000000 ? timestamp ~/ 1000 : timestamp;
      dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } else {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return raw;

    final now = DateTime.now();
    if (dt.year == now.year) {
      if (dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}月${dt.day}日';
    } else {
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      return '$yy-$mm-$dd';
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

  void _enterSelectionMode([String? initialUkey]) {
    HapticFeedbackUtil.light();
    setState(() {
      _isSelecting = true;
      _selectedUkeys.clear();
      if (initialUkey != null && initialUkey.isNotEmpty) {
        _selectedUkeys.add(initialUkey);
      }
    });
  }

  void _exitSelectionMode() {
    HapticFeedbackUtil.light();
    setState(() {
      _isSelecting = false;
      _selectedUkeys.clear();
    });
  }

  void _toggleSelectAll() {
    HapticFeedbackUtil.selection();
    final allUkeys = _rows
        .map((r) => _first(r, ['ukey', 'sessionKey', 'session_id']))
        .where((k) => k.isNotEmpty)
        .toSet();
    setState(() {
      if (_selectedUkeys.length == allUkeys.length && allUkeys.isNotEmpty) {
        _selectedUkeys.clear();
      } else {
        _selectedUkeys.addAll(allUkeys);
      }
    });
  }

  void _toggleItem(String ukey) {
    if (ukey.isEmpty) return;
    HapticFeedbackUtil.selection();
    setState(() {
      if (_selectedUkeys.contains(ukey)) {
        _selectedUkeys.remove(ukey);
      } else {
        _selectedUkeys.add(ukey);
      }
    });
  }

  Future<void> _deleteSession(String ukey) async {
    final sure = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话？'),
        content: const Text('确定要删除此私信会话吗？删除后不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    HapticFeedbackUtil.medium();
    try {
      await widget.api.request(
        '/v6/message/deleteChat',
        query: {'ukey': ukey},
      );
      await _load();
    } catch (error) {
      if (mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _deleteSelectedSessions() async {
    if (_selectedUkeys.isEmpty) return;
    final count = _selectedUkeys.length;
    final sure = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除私信？'),
        content: Text('确定要删除选中的 $count 个会话吗？删除后不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    HapticFeedbackUtil.medium();
    final targets = _selectedUkeys.toList();
    for (final ukey in targets) {
      try {
        await widget.api.request(
          '/v6/message/deleteChat',
          query: {'ukey': ukey},
        );
      } catch (_) {}
    }
    _exitSelectionMode();
    await _load();
    if (mounted) {
      AppToast.show(context, '已删除 $count 个会话');
    }
  }

  Widget _buildBody(BuildContext context) => EasyRefresh(
    header: reviewDefaultRefreshHeader,
    onRefresh: () => _load(),
    child: _busy && _rows.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _rows.isEmpty
        ? ListView(
            children: [ListTile(title: Text(_error!), onTap: _load)],
          )
        : ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _rows.length + (_busy || _error != null ? 1 : 0),
            separatorBuilder: (context, index) {
              if (index >= _rows.length) return const SizedBox.shrink();
              return Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 74,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
              );
            },
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
                  child: Text(_error == null ? '加载更多会话' : '加载失败，点击重试：'),
                );
              }
              final row = _rows[index];
              final partner = messagePartner(row);
              final uid = partner.uid;
              final ukey = _first(row, ['ukey', 'sessionKey', 'session_id']);
              final lastMsg = sanitizeCoolapkMessage(
                _first(row, ['lastMessage', 'message', 'description']),
              );
              final timeStr = _formatMessageTime(row);
              final isSelected = _selectedUkeys.contains(ukey);

              return InkWell(
                onTap: _isSelecting
                    ? () => _toggleItem(ukey)
                    : (ukey.isEmpty && uid.isEmpty
                        ? null
                        : () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => MessageChatPage(
                                  api: widget.api,
                                  uid: uid,
                                  ukey: ukey,
                                  username: partner.name,
                                  avatar: partner.avatar,
                                ),
                              ),
                            )),
                onLongPress: ukey.isEmpty
                    ? null
                    : () {
                        if (_isSelecting) {
                          _toggleItem(ukey);
                        } else {
                          _enterSelectionMode(ukey);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      if (_isSelecting) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.5),
                            size: 22,
                          ),
                        ),
                      ],
                      AppAvatar(
                        api: widget.api,
                        url: partner.avatar,
                        name: partner.name,
                        size: 44,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    partner.name.isEmpty ? '私信会话' : partner.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (timeStr.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.75),
                                    ),
                                  ),
                                ],
                                if (!_isSelecting)
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    iconSize: 16,
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        await _deleteSession(ukey);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除会话'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              lastMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
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

  @override
  Widget build(BuildContext context) {
    final allUkeys = _rows
        .map((r) => _first(r, ['ukey', 'sessionKey', 'session_id']))
        .where((k) => k.isNotEmpty)
        .toSet();
    final isAllSelected =
        allUkeys.isNotEmpty && _selectedUkeys.length == allUkeys.length;

    return PopScope(
      canPop: !_isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelecting) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: ReviewFrostedAppBar(
          toolbarHeight: 52,
          leading: _isSelecting
              ? TextButton(
                  onPressed: _exitSelectionMode,
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 15),
                  ),
                )
              : null,
          title: Text(
            _isSelecting
                ? (_selectedUkeys.isEmpty
                    ? '选择会话'
                    : '已选择 ${_selectedUkeys.length} 项')
                : '私信',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_isSelecting) ...[
              TextButton(
                onPressed: _rows.isEmpty ? null : _toggleSelectAll,
                child: Text(
                  isAllSelected ? '取消全选' : '全选',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              IconButton(
                tooltip: '管理私信',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: const Icon(Icons.delete_outline_rounded, size: 22),
                onPressed: _rows.isEmpty ? null : _enterSelectionMode,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        body: _buildBody(context),
        bottomNavigationBar: _isSelecting
            ? Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  8 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        onPressed: _selectedUkeys.isEmpty
                            ? null
                            : _deleteSelectedSessions,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text(
                          _selectedUkeys.isEmpty
                              ? '删除'
                              : '删除 (${_selectedUkeys.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class MessageChatPage extends StatefulWidget {
  const MessageChatPage({
    required this.api,
    required this.uid,
    required this.ukey,
    this.username = '',
    this.avatar = '',
    super.key,
  });
  final CoolapkApi api;
  final String uid;
  final String ukey;
  final String username, avatar;

  @override
  State<MessageChatPage> createState() => _MessageChatPageState();
}

class _MessageChatPageState extends State<MessageChatPage> {
  final _controller = TextEditingController();
  final _pictureController = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  String _chatKey = '';
  Map<String, dynamic>? _followTip;
  bool _following = false;
  String get _partnerName {
    if (widget.username.isNotEmpty) return widget.username;
    for (final row in _messages) {
      if (chatRowKind(row) == 'message' &&
          _first(row, ['fromuid', 'fromUid']) != widget.api.currentUid) {
        final name = _first(row, ['fromusername', 'username', 'fromName']);
        if (name.isNotEmpty) return name;
      }
    }
    return '私信';
  }

  bool _busy = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _hasOlder = true;
  String? _error;
  int _page = 1;
  Uint8List? _pendingImage;
  Timer? _refreshTimer;
  bool _refreshing = false;
  int _failures = 0;
  DateTime _nextRefresh = DateTime.now();
  late final String _session = widget.api.notificationSessionKey;

  @override
  void initState() {
    super.initState();
    _chatKey = widget.ukey;
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true &&
          DateTime.now().isAfter(_nextRefresh)) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    _pictureController.dispose();
    super.dispose();
  }

  Future<void> _load({bool older = false, bool silent = false}) async {
    if (_busy || _refreshing || _loadingOlder || (older && !_hasOlder)) return;
    if (widget.api.notificationSessionKey != _session ||
        !widget.api.hasCookie) {
      return;
    }
    _refreshing = true;
    if (older) {
      setState(() => _loadingOlder = true);
    } else if (!silent) {
      setState(() => _busy = true);
    }
    try {
      if (widget.api.currentUid.isEmpty) await widget.api.checkLogin();
      if (widget.api.notificationSessionKey != _session) return;
      if (_chatKey.isEmpty) {
        final sessions = await widget.api.getList(
          '/v6/message/list',
          query: {'page': 1},
        );
        for (final row in sessions.items) {
          if (messagePartner(row).uid == widget.uid) {
            _chatKey = _first(row, ['ukey', 'sessionKey', 'session_id']);
            break;
          }
        }
        if (_chatKey.isEmpty) {
          if (mounted) setState(() => _hasOlder = false);
          return;
        }
      }
      final nextPage = older ? _page + 1 : 1;
      final result = await widget.api.getList(
        '/v6/message/chat',
        query: {'ukey': _chatKey, 'page': nextPage},
      );
      final incoming = result.items
          .where(
            (row) =>
                chatRowKind(row) != 'hidden' && chatRowKind(row) != 'follow',
          )
          .toList()
          .reversed
          .toList();
      final tip = result.items
          .where((row) => chatRowKind(row) == 'follow')
          .firstOrNull;
      _failures = 0;
      _nextRefresh = DateTime.now().add(const Duration(seconds: 10));
      if (mounted && widget.api.notificationSessionKey == _session) {
        setState(() {
          if (!older) _followTip = tip;
          if (older) {
            final known = _messages.map(_messageKey).toSet();
            _messages = [
              ..._messages,
              ...incoming.where((item) => known.add(_messageKey(item))),
            ];
          } else {
            if (silent) {
              final known = incoming.map(_messageKey).toSet();
              _messages = [
                ...incoming,
                ..._messages.where(
                  (item) => !known.contains(_messageKey(item)),
                ),
              ];
            } else {
              _messages = incoming;
            }
          }
          if (!silent) {
            _page = nextPage;
            _hasOlder = result.hasMore && incoming.isNotEmpty;
          }
          _error = null;
        });
      }
    } catch (error) {
      _failures = (_failures + 1).clamp(0, 4);
      _nextRefresh = DateTime.now().add(
        Duration(seconds: 10 * (1 << _failures)),
      );
      if (mounted) setState(() => _error = '消息读取失败，请稍后重试');
    } finally {
      _refreshing = false;
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
    if ((message.isEmpty &&
            _pendingImage == null &&
            _pictureController.text.isEmpty) ||
        widget.uid.isEmpty ||
        _busy ||
        _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (!widget.api.hasCookie ||
          widget.api.notificationSessionKey != _session) {
        throw StateError('account changed');
      }
      if (_pendingImage != null && _pictureController.text.isEmpty) {
        _pictureController.text = await widget.api.uploadMessageImage(
          _pendingImage!,
          widget.uid,
        );
      }
      if (!mounted || widget.api.notificationSessionKey != _session) return;
      await widget.api.sendMessage(
        widget.uid,
        message,
        pic: _pictureController.text.trim().isEmpty
            ? null
            : _pictureController.text.trim(),
      );
      _controller.clear();
      _pictureController.clear();
      _pendingImage = null;
      await _load();
    } catch (error) {
      if (mounted) _snack(context, '发送失败，消息和图片已保留，可重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickMessageImage() async {
    if (_sending) return;
    try {
      final bytes = await const MethodChannel('com.green.note/avatar')
          .invokeMethod<Uint8List>('pickImage');
      if (bytes != null && mounted) {
        setState(() {
          _pendingImage = bytes;
          _pictureController.clear();
        });
      }
    } catch (_) {
      if (mounted) _snack(context, '无法选择图片，请重试');
    }
  }

  Future<void> _chooseEmoji() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 6,
          children: [
            for (final emoji in [
              '🙂',
              '😀',
              '😂',
              '🥰',
              '😭',
              '😅',
              '😎',
              '👍',
              '🙏',
              '🐶',
              '🤔',
              '🎉',
            ])
              TextButton(
                onPressed: () => Navigator.pop(context, emoji),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
          ],
        ),
      ),
    );
    if (!mounted || emoji == null) return;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _followPartner() async {
    if (_following || widget.uid.isEmpty) return;
    setState(() => _following = true);
    try {
      if (!await widget.api.notificationSessionMatches(_session) ||
          widget.api.notificationSessionKey != _session) {
        throw StateError('账号已改变');
      }
      await widget.api.followUser(widget.uid, following: false);
      if (mounted) setState(() => _followTip = null);
    } catch (error) {
      if (mounted) _snack(context, '关注失败：$error');
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF101010)
        : const Color(0xFFFAFAFA),
    appBar: ReviewFrostedAppBar(
      title: Text(_partnerName),
      showBottomBorder: false,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      actions: [
        PopupMenuButton<String>(
          tooltip: '会话选项',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'history') _load(older: true);
            if (value == 'profile' && widget.uid.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      UserSpacePage(api: widget.api, uid: widget.uid),
                ),
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'history',
              enabled: !_busy && !_loadingOlder && _hasOlder,
              child: const Text('加载更早消息'),
            ),
            if (widget.uid.isNotEmpty)
              const PopupMenuItem(value: 'profile', child: Text('查看个人主页')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        if (_followTip != null)
          Material(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            child: ListTile(
              dense: true,
              title: Text(
                sanitizeCoolapkMessage(
                  _first(_followTip, ['title', 'message']),
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF009688), fontSize: 14),
              ),
              trailing: _following
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _following ? null : _followPartner,
            ),
          ),
        if (_error != null && _messages.isNotEmpty)
          TextButton(onPressed: () => _load(), child: Text(_error!)),
        if (_loadingOlder) const LinearProgressIndicator(minHeight: 2),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => ChatMessageRow(
                    key: ValueKey(_messageKey(_messages[index])),
                    api: widget.api,
                    row: _messages[index],
                    partnerName: _partnerName,
                    partnerAvatar: widget.avatar,
                  ),
                ),
        ),

        if (_pendingImage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Image.memory(
                  _pendingImage!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('图片将在点击发送后上传')),
                IconButton(
                  tooltip: '移除待发图片',
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                          _pendingImage = null;
                          _pictureController.clear();
                        }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => Row(
                  children: [
                    IconButton(
                      tooltip: '表情',
                      onPressed: _sending ? null : _chooseEmoji,
                      icon: const Icon(
                        Icons.sentiment_satisfied_alt_outlined,
                        size: 28,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        style: const TextStyle(fontSize: 17),
                        decoration: InputDecoration(
                          hintText: '写私信…',
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF262626)
                              : const Color(0xFFF3F3F3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '选择图片',
                      onPressed: _sending ? null : _pickMessageImage,
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 28,
                      ),
                    ),
                    if (value.text.trim().isNotEmpty ||
                        _pendingImage != null ||
                        _pictureController.text.isNotEmpty)
                      IconButton(
                        tooltip: '发送私信',
                        onPressed: _sending || _busy ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Color(0xFF009688),
                              ),
                      ),
                  ],
                ),
              ),
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
  static const _cardTitles = ['我关注的话题', '我的常去', '浏览历史', '我的收藏单', '我的问答'];
  Set<String> _hiddenCards = {};
  Map<String, dynamic>? _login;
  String? _error;
  bool _checking = false;
  bool _lastObservedCookie = false;
  Future<Map<String, dynamic>>? _spaceFuture;
  Future<ApiPage>? _topicsFuture;
  Future<ApiPage>? _visitsFuture;
  Future<ApiPage>? _historyFuture;
  Future<ApiPage>? _collectionsFuture;
  Future<ApiPage>? _questionsFuture;
  String _observedPublicUid = '';
  bool _observedAnonymous = false;

  @override
  void initState() {
    super.initState();
    _lastObservedCookie = widget.api.hasCookie;
    _observedPublicUid =
        widget.api.localAccount.publicIdentity?['uid'] as String? ?? '';
    _observedAnonymous = widget.api.isAnonymous;
    widget.api.localAccount.addListener(_onLocalAccountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeDashboard());
    });
  }

  Future<void> _initializeDashboard() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hiddenCards =
          (preferences.getStringList('greennote.account.hiddenCards') ?? [])
              .where(_cardTitles.contains)
              .toSet();
    });
    if (widget.api.hasCookie) {
      await _checkLogin();
    } else if (widget.api.isAnonymous && _observedPublicUid.isNotEmpty) {
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    widget.api.localAccount.removeListener(_onLocalAccountChanged);
    super.dispose();
  }

  void _onLocalAccountChanged() {
    final nextUid =
        widget.api.localAccount.publicIdentity?['uid'] as String? ?? '';
    final nextAnonymous = widget.api.isAnonymous;
    final changed =
        nextUid != _observedPublicUid || nextAnonymous != _observedAnonymous;
    _observedPublicUid = nextUid;
    _observedAnonymous = nextAnonymous;
    if (!mounted) return;
    if (changed) {
      final effectiveUid = nextAnonymous ? nextUid : widget.api.currentUid;
      if (effectiveUid.isEmpty) {
        setState(() {
          _spaceFuture = null;
          _topicsFuture = null;
          _visitsFuture = null;
          _historyFuture = null;
          _collectionsFuture = null;
          _questionsFuture = null;
        });
      } else {
        _loadDashboard();
      }
    } else {
      setState(() {});
    }
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
      if (mounted) {
        if (_login == null) {
          setState(() => _error = error.toString());
        } else {
          AppToast.show(context, '刷新账户信息失败: $error');
        }
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _loginPage() async {
    await showLoginOptions(context, widget.api);
    if (mounted) {
      setState(() {});
      if (widget.api.hasCookie) _checkLogin();
    }
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
          _visitsFuture = null;
          _historyFuture = null;
          _collectionsFuture = null;
          _questionsFuture = null;
        });
      }
    }
  }

  void _loadDashboard() {
    final anonymous = widget.api.isAnonymous;
    final identity = anonymous ? widget.api.localAccount.publicIdentity : null;
    final uid = identity?['uid'] as String? ?? widget.api.currentUid;
    if (uid.isEmpty) return;
    setState(() {
      _spaceFuture = _loadSpace(uid);
      _topicsFuture = anonymous || _hiddenCards.contains('我关注的话题')
          ? null
          : widget.api.getList('/v6/topic/myFollowTopicList');
      _visitsFuture = anonymous || _hiddenCards.contains('我的常去')
          ? null
          : widget.api.getList('/v6/user/recentHistoryList');
      _historyFuture = anonymous || _hiddenCards.contains('浏览历史')
          ? null
          : widget.api.getList('/v6/user/hitHistoryList');
      _collectionsFuture = _hiddenCards.contains('我的收藏单')
          ? null
          : widget.api.getList(
              '/v6/collection/list',
              query: {'uid': uid, 'showDefault': 1},
            );
      _questionsFuture = _hiddenCards.contains('我的问答')
          ? null
          : widget.api.getUserPage('/v6/user/questionAndAnswerList', uid, 1);
      // Offscreen cards subscribe later; FutureBuilder still receives these errors.
      for (final future in [
        _topicsFuture,
        _visitsFuture,
        _historyFuture,
        _collectionsFuture,
        _questionsFuture,
      ]) {
        future?.ignore();
      }
    });
  }

  Future<void> _refreshAccount() async {
    if (widget.api.hasCookie) {
      await _checkLogin();
    } else if (widget.api.isAnonymous && _observedPublicUid.isNotEmpty) {
      _loadDashboard();
    }
    await Future.wait<dynamic>([
      ?_spaceFuture,
      ?_topicsFuture,
      ?_visitsFuture,
      ?_historyFuture,
      ?_collectionsFuture,
      ?_questionsFuture,
    ], eagerError: false).catchError((_) => <dynamic>[]);
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
    final merged = <String, dynamic>{
      if (spaceUser is Map) ...Map<String, dynamic>.from(spaceUser),
      if (profileUser is Map) ...Map<String, dynamic>.from(profileUser),
      if (profileData is Map) ...Map<String, dynamic>.from(profileData),
      if (spaceData is Map) ...Map<String, dynamic>.from(spaceData),
      ...spaceResponse,
    };
    // Preserve a valid nested count when a shallow envelope repeats it as blank.
    final feedCount =
        [
              spaceUser,
              spaceData,
              spaceResponse,
              profileUser,
              profileData,
              profileResponse,
            ]
            .whereType<Map>()
            .map(
              (source) => _first(Map<String, dynamic>.from(source), [
                'feed_num',
                'feedNum',
                'feednum',
                'feed_count',
                'feedCount',
                'feed_num_txt',
                'feedNumTxt',
                'feed',
              ]),
            )
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (feedCount.isNotEmpty) merged['feed_num'] = feedCount;
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastObservedCookie != widget.api.hasCookie) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncAccountState());
    }
    final anonymous = widget.api.isAnonymous;
    final loggedIn =
        anonymous || widget.api.hasCookie && _login != null && _error == null;
    final publicIdentity = anonymous
        ? widget.api.localAccount.publicIdentity
        : null;
    final loginUser = _login?['userInfo'] ?? _login?['user_info'];
    final user = <String, dynamic>{
      if (!anonymous && loginUser is Map)
        ...Map<String, dynamic>.from(loginUser),
      if (!anonymous) ...?_login,
      if (anonymous)
        'username': publicIdentity?['username'] ?? widget.api.localAccount.name,
      if (anonymous && publicIdentity != null)
        'userAvatar': publicIdentity['userAvatar'],
    };
    final uid = anonymous
        ? (publicIdentity?['uid'] as String? ?? '')
        : (_first(_login, ['uid', 'userId', 'id']).isEmpty
              ? widget.api.currentUid
              : _first(_login, ['uid', 'userId', 'id']));
    const collectionRoute = '/v6/collection/list';
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF101010)
          : Theme.of(context).colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _refreshAccount,
            child: ListView(
              key: const ValueKey('account-refreshable-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                8,
                0,
                8,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _buildProfile(user, loggedIn, uid),
                _buildStatistics(uid, enabled: loggedIn),
                _buildShortcuts(uid, enabled: loggedIn),
                _buildOrders(),
                _buildHelp(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '我的卡片',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: _manageCards,
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                        child: const Text(
                          '卡片管理',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_hiddenCards.contains('我关注的话题'))
                  _previewSection(
                    '我关注的话题',
                    '/v6/topic/myFollowTopicList',
                    _topicsFuture,
                    icon: Icons.tag_rounded,
                  ),
                if (!_hiddenCards.contains('我的常去'))
                  _previewSection(
                    '我的常去',
                    '/v6/user/recentHistoryList',
                    _visitsFuture,
                    icon: Icons.history_rounded,
                  ),
                if (!_hiddenCards.contains('浏览历史'))
                  _previewSection(
                    '浏览历史',
                    '/v6/user/hitHistoryList',
                    _historyFuture,
                    icon: Icons.history_rounded,
                  ),
                if (!_hiddenCards.contains('我的收藏单'))
                  _previewSection(
                    '我的收藏单',
                    collectionRoute,
                    _collectionsFuture,
                    icon: Icons.folder_outlined,
                    query: {'uid': uid, 'showDefault': 1},
                    allowAnonymousPublicRead: publicIdentity != null,
                  ),
                if (!_hiddenCards.contains('我的问答'))
                  _previewSection(
                    '我的问答',
                    '/v6/user/questionAndAnswerList',
                    _questionsFuture,
                    icon: Icons.question_answer_outlined,
                    query: {'uid': uid},
                    allowAnonymousPublicRead: publicIdentity != null,
                  ),
                _group(context, '更多', [_CreateCollectionRow(api: widget.api)]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountSurface({required Widget child}) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _cardHeader(String title, {VoidCallback? onTap, String? trailing}) =>
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildOrders() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: _accountSurface(
      child: Column(
        children: [
          _cardHeader('酷回收订单', trailing: '官方客户端查看'),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (final action in const [
                  (Icons.inventory_2_outlined, '待发货'),
                  (Icons.local_shipping_outlined, '已发货'),
                  (Icons.verified_user_outlined, '验机中'),
                  (Icons.receipt_long_outlined, '待确认'),
                  (Icons.headset_mic_outlined, '在线客服'),
                ])
                  Expanded(
                    child: _ShortcutButton(
                      icon: action.$1,
                      label: action.$2,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      tooltip: '请在官方酷安客户端查看酷回收订单',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildHelp() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: _accountSurface(
      child: InkWell(
        onTap: () async {
          try {
            final opened = await launchUrl(
              Uri.parse('https://m.coolapk.com/mp/do?c=help&m=questionNew'),
              mode: LaunchMode.externalApplication,
            );
            if (!opened && mounted) AppToast.show(context, '无法打开帮助页面');
          } catch (_) {
            if (mounted) AppToast.show(context, '无法打开帮助页面');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.volume_up_rounded,
                size: 22,
                color: Color(0xFF2196F3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '有疑惑请参考「酷安常见问题」 >>>',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _manageCards() async {
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('卡片管理', style: TextStyle(fontSize: 18)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final title in _cardTitles)
                      SwitchListTile(
                        title: Text(title),
                        value: !_hiddenCards.contains(title),
                        onChanged: saving
                            ? null
                            : (visible) async {
                                updateSheet(() => saving = true);
                                final next = {..._hiddenCards};
                                if (visible) {
                                  next.remove(title);
                                } else {
                                  next.add(title);
                                }
                                try {
                                  final preferences =
                                      await SharedPreferences.getInstance();
                                  if (!await preferences.setStringList(
                                    'greennote.account.hiddenCards',
                                    next.toList(),
                                  )) {
                                    throw StateError('保存失败');
                                  }
                                  if (!mounted) return;
                                  setState(() => _hiddenCards = next);
                                  if (visible) _loadDashboard();
                                } catch (_) {
                                  if (mounted) {
                                    AppToast.show(this.context, '卡片设置保存失败，请重试');
                                  }
                                } finally {
                                  if (sheetContext.mounted) {
                                    updateSheet(() => saving = false);
                                  }
                                }
                              },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfile(
    Map<String, dynamic> user,
    bool loggedIn,
    String uid,
  ) => FutureBuilder<Map<String, dynamic>>(
    key: ValueKey('profile-$uid'),
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
      final anonymous = widget.api.isAnonymous;
      final publicIdentity = anonymous
          ? widget.api.localAccount.publicIdentity
          : null;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: anonymous && publicIdentity == null
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => LocalProfilePage(api: widget.api),
                ),
              )
            : loggedIn && uid.isNotEmpty
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => UserSpacePage(api: widget.api, uid: uid),
                ),
              )
            : _openSettings,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
          child: Row(
            children: [
              if (anonymous && publicIdentity == null)
                LocalAvatar(
                  avatar: widget.api.localAccount.avatar,
                  name: widget.api.localAccount.name,
                  radius: 36,
                )
              else
                AppAvatar(
                  url: _first(data, ['userAvatar', 'avatar']).isEmpty
                      ? widget.api.currentUserAvatar
                      : _first(data, ['userAvatar', 'avatar']),
                  api: widget.api,
                  size: 72,
                  name: name,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isEmpty ? (loggedIn ? '酷安用户' : '未登录') : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (publicIdentity != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: '匿名登录 · 公开主页身份',
                            child: Icon(
                              Icons.cloud_outlined,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
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
                          if (showProgress)
                            Flexible(
                              child: Text(
                                '$experience/$nextExperience',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                      if (showProgress) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (experience / nextExperience).clamp(0, 1),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ] else ...[
                      const SizedBox(height: 5),
                      Text(
                        anonymous
                            ? publicIdentity != null
                                  ? '公开主页 · UID $uid · 只读'
                                  : '匿名账户 · 本地保存'
                            : _checking
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
              if (anonymous) ...[
                IconButton(
                  icon: const Icon(Icons.switch_account_outlined, size: 24),
                  tooltip: '切换/管理匿名账户',
                  onPressed: () =>
                      showAnonymousAccountSwitcher(context, widget.api),
                ),
                const SizedBox(width: 4),
              ],
              if (!(anonymous && publicIdentity != null)) ...[
                Icon(
                  anonymous
                      ? Icons.edit_outlined
                      : loggedIn
                      ? Icons.qr_code_2_rounded
                      : Icons.login_rounded,
                  size: 28,
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, size: 28),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildStatistics(String uid, {required bool enabled}) =>
      FutureBuilder<Map<String, dynamic>>(
        key: ValueKey('statistics-$uid'),
        future: _spaceFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _accountSurface(
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
          final anonymous = widget.api.isAnonymous;
          final publicIdentity = anonymous
              ? widget.api.localAccount.publicIdentity
              : null;
          final localOnly = anonymous && publicIdentity == null;
          final values = [
            localOnly
                ? '0'
                : _first(data, [
                    'feed_num',
                    'feedNum',
                    'feednum',
                    'feed_count',
                    'feedCount',
                    'feed_num_txt',
                    'feedNumTxt',
                  ]),
            localOnly
                ? '${widget.api.localAccount.follows.length}'
                : _first(data, [
                    'follow_num',
                    'followNum',
                    'follownum',
                    'follow',
                  ]),
            localOnly
                ? '—'
                : _first(data, ['fans_num', 'fansNum', 'fansnum', 'fans']),
          ];
          final taps = [
            () => localOnly
                ? _showLoginRequired()
                : enabled
                ? _openRoute('/v6/user/feedList', {'uid': uid})
                : _openSettings(),
            () => localOnly
                ? _openLocalLibrary(follows: true)
                : _openFollowingList(enabled: enabled),
            () => localOnly
                ? _showLoginRequired()
                : anonymous
                ? _openRoute('/v6/user/userFansList', {'uid': uid})
                : enabled
                ? _openRoute('/v6/user/myFansList', const {})
                : _openSettings(),
          ];
          return Padding(
            padding: const EdgeInsets.only(top: 0),
            child: _accountSurface(
              child: Row(
                children: [
                  for (var index = 0; index < values.length; index++) ...[
                    _stat(
                      context,
                      enabled || anonymous ? values[index] : '—',
                      ['动态', '关注', '粉丝'][index],
                      taps[index],
                    ),
                    if (index < values.length - 1)
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.04),
                        ),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              value.isEmpty ? '—' : value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _buildShortcuts(String uid, {required bool enabled}) {
    final publicIdentity = widget.api.isAnonymous
        ? widget.api.localAccount.publicIdentity
        : null;
    final canReadPublic = publicIdentity != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _accountSurface(
        child: Row(
          children: [
            _shortcut(
              context,
              Icons.star_rounded,
              '我的收藏',
              '/v6/collection/list',
              query: {'uid': uid, 'showDefault': 1},
              color: const Color(0xFF2589E8),
              enabled: enabled && (!widget.api.isAnonymous || canReadPublic),
            ),
            _shortcut(
              context,
              Icons.article_rounded,
              '我的图文',
              '/v6/user/htmlFeedList',
              query: {'uid': uid},
              color: const Color(0xFFE94848),
              enabled: enabled && (!widget.api.isAnonymous || canReadPublic),
            ),
            Expanded(
              child: _ShortcutButton(
                icon: Icons.stay_current_portrait_rounded,
                label: '应用管理',
                color: const Color(0xFF9862E8),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AppManagementPage(api: widget.api),
                  ),
                ),
              ),
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
  }

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
      onTap: () {
        if (widget.api.isAnonymous) {
          if (widget.api.localAccount.publicIdentity != null) {
            _openRoute(path, query);
          } else if (label == '我的收藏') {
            _openLocalLibrary(follows: false);
          } else {
            _showLoginRequired();
          }
        } else if (enabled) {
          _openRoute(path, query);
        } else {
          _openSettings();
        }
      },
    ),
  );

  void _showLoginRequired() =>
      AppToast.show(context, widget.api.loginRequiredMessage);

  void _openFollowingList({bool enabled = true}) {
    if (widget.api.isAnonymous) {
      final uid = widget.api.localAccount.publicIdentity?['uid'];
      if (uid is String && uid.isNotEmpty) {
        _openRoute('/v6/user/followList', {'uid': uid});
      } else {
        _openLocalLibrary(follows: true);
      }
    } else if (enabled) {
      _openRoute('/v6/user/myFollowList', const {});
    } else {
      _openSettings();
    }
  }

  void _openLocalLibrary({required bool follows}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LocalLibraryPage(api: widget.api, follows: follows),
        ),
      );

  Widget _previewSection(
    String title,
    String route,
    Future<ApiPage>? future, {
    required IconData icon,
    Map<String, dynamic> query = const {},
    bool allowAnonymousPublicRead = false,
  }) {
    final canReadAnonymous = _canReadAnonymousPublic(
      query,
      allowAnonymousPublicRead,
    );
    void open() {
      if (canReadAnonymous || widget.api.hasCookie && _login != null) {
        _openRoute(route, query);
      } else if (widget.api.isAnonymous) {
        _showLoginRequired();
      } else {
        _openSettings();
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _accountSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(title, onTap: open),
            FutureBuilder<ApiPage>(
              key: ValueKey(
                '$title:${widget.api.localAccount.publicIdentity?['uid'] ?? widget.api.currentUid}',
              ),
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
                if (!canReadAnonymous &&
                    (!widget.api.hasCookie || _login == null)) {
                  return InkWell(
                    onTap: open,
                    child: _cardMessage('登录后查看$title'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting ||
                    (canReadAnonymous && future == null)) {
                  return const Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
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
                  return _cardMessage(_emptyLabel(title));
                }
                if (title == '我关注的话题' || title == '我的常去') {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in items.take(4))
                          Expanded(child: _accountMiniCard(item)),
                        for (var index = items.length; index < 4; index++)
                          const Spacer(),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in items.take(
                      title == '浏览历史'
                          ? 5
                          : title == '我的收藏单'
                          ? 3
                          : 4,
                    ))
                      if (title == '浏览历史' || title == '我的收藏单')
                        _accountRow(item, collection: title == '我的收藏单')
                      else
                        ApiEntityCard(api: widget.api, entity: item),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardMessage(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 20, 12, 26),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );

  bool _canReadAnonymousPublic(
    Map<String, dynamic> query,
    bool allowAnonymousPublicRead,
  ) {
    if (!allowAnonymousPublicRead || !widget.api.isAnonymous) return false;
    final uid = widget.api.localAccount.publicIdentity?['uid'];
    return uid is String && uid.isNotEmpty && query['uid'] == uid;
  }

  String _emptyLabel(String title) => switch (title) {
    '我的关注' => '还没有关注其他用户',
    '我的问答' => '你还没有发布过问答',
    '我的收藏单' => '还没有创建收藏单',
    '我关注的话题' => '还没有关注话题',
    '浏览历史' => '暂无浏览记录',
    _ => '暂无最近访问内容',
  };

  Widget _accountMiniCard(Map<String, dynamic> item) {
    final type = _first(item, ['entityType', 'entity_type']).toLowerCase();
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
        : _first(item, ['typeName', 'subTitle', 'description']);
    return InkWell(
      onTap: () => _openAccountItem(item, type),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            _accountThumbnail(item, size: 56),
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
    );
  }

  Widget _accountThumbnail(
    Map<String, dynamic> item, {
    required double size,
    bool collection = false,
  }) {
    final image = normalizeCoolapkImageUrl(
      _first(item, [
        'logo',
        'pic',
        'cover_pic',
        'cover',
        'userAvatar',
        'avatar',
        'icon',
      ]),
    );
    Widget fallback() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: collection
            ? null
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        gradient: collection
            ? const LinearGradient(
                colors: [Color(0xFF10B8C5), Color(0xFF24C4A0)],
              )
            : null,
      ),
      child: Icon(
        collection ? Icons.folder_outlined : Icons.image_outlined,
        color: collection
            ? Colors.white
            : Theme.of(context).colorScheme.onSurfaceVariant,
        size: collection ? size * 0.6 : size * 0.45,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image.isEmpty
          ? fallback()
          : CachedNetworkImage(
              image,
              headers: coolapkImageHeaders(image, api: widget.api),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            ),
    );
  }

  Widget _accountRow(Map<String, dynamic> item, {required bool collection}) {
    final type = _first(item, ['entityType', 'entity_type']).toLowerCase();
    final title = _first(item, ['title', 'username', 'name']);
    var subtitle = _first(item, ['subTitle', 'description', 'message']);
    if (collection && subtitle.isEmpty) {
      final follows = _first(item, ['follownum', 'followNum']);
      final feeds = _first(item, ['feednum', 'feedNum', 'itemnum']);
      subtitle = [
        if (follows.isNotEmpty) '$follows人关注',
        if (feeds.isNotEmpty) '$feeds个内容',
      ].join('  ');
    }
    final time = collection
        ? ''
        : formatRelativeTime(_first(item, ['dateline', 'time']));
    final typeName = collection ? '' : _first(item, ['typeName']);
    return InkWell(
      onTap: () => _openAccountItem(item, collection ? 'collection' : type),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            _accountThumbnail(
              item,
              size: collection ? 60 : 48,
              collection: collection,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title.isEmpty ? '酷安内容' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (typeName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            typeName,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                time,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openAccountItem(Map<String, dynamic> item, String type) {
    final url = _first(item, ['url']);
    if (type.contains('history') && url.isNotEmpty) {
      unawaited(CoolapkUrlHandler.handleUrl(context, widget.api, url));
      return;
    }
    final linkedFeedId = feedIdFromCoolapkUrl(url);
    if (type.contains('feed') && linkedFeedId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeedDetailPage(
            api: widget.api,
            feed: CoolapkFeed.fromJson({...item, 'id': linkedFeedId}),
          ),
        ),
      );
      return;
    }
    var id = type.contains('feed')
        ? _first(item, ['id', 'feedId', 'feed_id', 'entityId'])
        : type.contains('collection')
        ? _first(item, ['id', 'collectionId', 'collection_id'])
        : _first(item, [
            'uid',
            'id',
            'entityId',
            'entity_id',
            'tag',
            'tagName',
            'packageName',
            'productId',
          ]);
    if (type.contains('history') || id.isEmpty) {
      final url = _first(item, ['url']);
      final uri = Uri.tryParse(url.startsWith('#/') ? url.substring(1) : url);
      final parts = uri?.pathSegments ?? const <String>[];
      if (uri != null &&
          (!uri.hasAuthority ||
              uri.host == 'coolapk.com' ||
              uri.host.endsWith('.coolapk.com')) &&
          parts.length >= 2) {
        final targetType = switch (parts.first) {
          'u' => 'user',
          't' => 'topic',
          'feed' => 'feed',
          'product' => 'product',
          'collection' => 'collection',
          _ => '',
        };
        if (targetType.isNotEmpty) {
          type = targetType;
          id = parts[1];
        }
      }
    }
    if (id.isEmpty) return;
    final Widget page;
    if (type.contains('feed')) {
      page = FeedDetailPage(
        api: widget.api,
        feed: CoolapkFeed.fromJson({...item, 'id': id}),
      );
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
    } else if (type == 'collection') {
      page = CommunityDetailPage(
        api: widget.api,
        id: id,
        kind: CommunityKind.collection,
        initial: item,
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
        builder: (_) => path.contains('hitHistoryList')
            ? CommunityLibraryPage(
                api: widget.api,
                library: CommunityLibrary.history,
              )
            : path.toLowerCase().contains('followlist') ||
                  path.toLowerCase().contains('fanslist')
            ? CommunityLibraryPage(
                api: widget.api,
                uid: '${query['uid'] ?? ''}',
                library: path.toLowerCase().contains('fans')
                    ? CommunityLibrary.fans
                    : CommunityLibrary.following,
              )
            : ApiListPage(
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
    '/v6/user/recentHistoryList' => '最近访问',
    '/v6/user/hitHistoryList' => '浏览历史',
    '/v6/collection/myCollectionList' => '我的收藏单',
    '/v6/collection/list' => '我的收藏单',
    '/v6/user/questionAndAnswerList' => '我的问答',
    '/v6/user/feedList' => '我的动态',
    '/v6/user/myFollowList' => '我的关注',
    '/v6/user/followList' => '我的关注',
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
            for (final entry in const [
              (CommunityLibrary.anylist, '万物清单'),
              (CommunityLibrary.dyh, '我的看看号'),
              (CommunityLibrary.albums, '我的应用集'),
            ])
              ListTile(
                leading: const Icon(Icons.view_list_outlined),
                title: Text(entry.$2),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CommunityLibraryPage(
                        api: widget.api,
                        library: entry.$1,
                      ),
                    ),
                  );
                },
              ),
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
                _openFollowingList();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('我的粉丝'),
              onTap: () {
                Navigator.pop(context);
                if (widget.api.isAnonymous) {
                  final uid = widget.api.localAccount.publicIdentity?['uid'];
                  if (uid is String && uid.isNotEmpty) {
                    _openRoute('/v6/user/userFansList', {'uid': uid});
                  } else {
                    _showLoginRequired();
                  }
                } else {
                  _openRoute('/v6/user/myFansList', const {});
                }
              },
            ),
            if (widget.api.isAnonymous)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑本地匿名资料'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => LocalProfilePage(api: widget.api),
                    ),
                  );
                },
              ),
            if (widget.api.localAccount.publicIdentity != null)
              ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('取消公开主页身份'),
                onTap: () {
                  Navigator.pop(context);
                  widget.api.localAccount
                      .clearPublicIdentity()
                      .then((_) {
                        if (mounted) _snack(this.context, '已恢复本地匿名资料显示');
                      })
                      .catchError((Object error) {
                        if (mounted) _snack(this.context, error.toString());
                      });
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
            _accountSurface(
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
    this.onTap,
    this.color,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color ?? Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
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
          maxLines: 1,
          autocorrect: false,
          enableSuggestions: false,
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

class CoolapkPublishPickerSheet extends StatelessWidget {
  const CoolapkPublishPickerSheet({
    required this.api,
    this.onSelectType,
    super.key,
  });

  final CoolapkApi api;
  final ValueChanged<String>? onSelectType;

  void _open(BuildContext context, String type) {
    Navigator.of(context).pop();
    if (onSelectType != null) {
      onSelectType!(type);
    } else {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ComposeFeedPage(api: api, initialType: type),
        ),
      );
    }
  }

  Widget _buildItem(
    BuildContext context, {
    required String label,
    required List<Color> gradient,
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.light();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: -5,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF202023) : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? const Color(0xFFE2E2E6) : const Color(0xFF333333),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202023) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildItem(
                context,
                label: '动态',
                gradient: const [Color(0xFF6DC83E), Color(0xFF7CD84C)],
                icon: Icons.chat_bubble_rounded,
                onTap: () => _open(context, 'feed'),
              ),
              _buildItem(
                context,
                label: '图文',
                gradient: const [Color(0xFF2B9DF4), Color(0xFF43B6FC)],
                icon: Icons.article_rounded,
                onTap: () => _open(context, 'article'),
              ),
              _buildItem(
                context,
                label: '点评广场',
                gradient: const [Color(0xFF2C6CE8), Color(0xFF4488FA)],
                icon: Icons.forum_rounded,
                badge: 'NEW',
                onTap: () => _open(context, 'rating'),
              ),
              _buildItem(
                context,
                label: '二手',
                gradient: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                icon: Icons.swap_horiz_rounded,
                onTap: () => _open(context, 'ershou'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildItem(
                context,
                label: '酷图',
                gradient: const [Color(0xFFF97316), Color(0xFFFB923C)],
                icon: Icons.landscape_rounded,
                onTap: () => _open(context, 'picture'),
              ),
              _buildItem(
                context,
                label: '清单',
                gradient: const [Color(0xFF9333EA), Color(0xFFB066FC)],
                icon: Icons.bookmark_rounded,
                badge: 'NEW',
                onTap: () => _open(context, 'collection'),
              ),
              _buildItem(
                context,
                label: '天梯榜',
                gradient: const [Color(0xFFDC2626), Color(0xFFF04B4B)],
                icon: Icons.military_tech_rounded,
                badge: 'NEW',
                onTap: () => _open(context, 'rank'),
              ),
              _buildItem(
                context,
                label: '投票',
                gradient: const [Color(0xFFE11D48), Color(0xFFF84F75)],
                icon: Icons.how_to_vote_rounded,
                onTap: () => _open(context, 'vote'),
              ),
            ],
          ),
          const SizedBox(height: 26),
          InkWell(
            onTap: () {
              HapticFeedbackUtil.light();
              Navigator.of(context).pop();
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2E2E32) : const Color(0xFFF1F1F3),
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF444444),
                ),
              ),
            ),
          ),
          SizedBox(height: bottomInset + 4),
        ],
      ),
    );
  }
}

class _ComposePictureItem {
  _ComposePictureItem({this.bytes});

  final Uint8List? bytes;
  String? url;
}

class ComposeFeedPage extends StatefulWidget {
  const ComposeFeedPage({
    required this.api,
    this.initialTag,
    this.initialProductId,
    this.initialMessage,
    this.initialType,
    super.key,
  });

  final CoolapkApi api;
  final String? initialTag;
  final String? initialProductId;
  final String? initialMessage;
  final String? initialType;

  @override
  State<ComposeFeedPage> createState() => _ComposeFeedPageState();
}

class _ComposeFeedPageState extends State<ComposeFeedPage> {
  late final TextEditingController _message = TextEditingController(
    text: widget.initialMessage ?? '',
  );
  final FocusNode _focusNode = FocusNode();
  final List<_ComposePictureItem> _pictures = [];
  bool _isCoverMode = true; // 大封面 (true) vs 九宫格 (false)
  String? _selectedTopic;
  String _visibility = 'public'; // public, private, friends
  late String _type;
  String? _extraTitle;
  String? _location;
  String? _productId;
  String? _voteId;
  bool _showEmojiPicker = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'feed';
    if (_type == 'picture') {
      _isCoverMode = false;
    }
    _selectedTopic = widget.initialTag;
    _productId = widget.initialProductId;
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit => _message.text.trim().isNotEmpty || _pictures.isNotEmpty;
  bool get _hasDraft => _message.text.trim().isNotEmpty || _pictures.isNotEmpty;

  String get _visibilityLabel {
    switch (_visibility) {
      case 'private':
        return '仅自己可见';
      case 'friends':
        return '好友圈';
      case 'public':
      default:
        return '公开';
    }
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if ((text.isEmpty && _pictures.isEmpty) || _busy) return;
    HapticFeedbackUtil.light();
    setState(() => _busy = true);
    try {
      final uploadedUrls = <String>[];
      for (final pic in _pictures) {
        if (pic.url != null && pic.url!.isNotEmpty) {
          uploadedUrls.add(pic.url!);
        } else if (pic.bytes != null) {
          final url = await widget.api.uploadFeedImage(pic.bytes!);
          pic.url = url;
          uploadedUrls.add(url);
        }
      }

      await widget.api.createFeed(
        text.isNotEmpty ? text : '分享图片',
        pic: uploadedUrls.isNotEmpty ? uploadedUrls.join(',') : null,
        type: _type,
        extraTitle: _extraTitle,
        tag: _selectedTopic,
        location: _location,
        productId: _productId,
        voteId: _voteId,
      );
      if (mounted) {
        HapticFeedbackUtil.medium();
        AppToast.show(context, '发布成功');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleClose() async {
    if (_hasDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确定放弃编辑吗？'),
          content: const Text('退出后已输入的内容将不会被保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickImage() async {
    HapticFeedbackUtil.light();
    final maxCount = _isCoverMode ? 1 : 9;
    if (_pictures.length >= maxCount) {
      AppToast.show(
        context,
        _isCoverMode ? '大封面模式只能添加 1 张图片' : '九宫格模式最多添加 9 张图片',
      );
      return;
    }
    try {
      final bytes = await const MethodChannel('com.green.note/avatar')
          .invokeMethod<Uint8List>('pickImage');
      if (bytes != null && mounted) {
        setState(() {
          if (_isCoverMode) {
            _pictures.clear();
          }
          _pictures.add(_ComposePictureItem(bytes: bytes));
        });
      }
    } catch (_) {
      if (mounted) AppToast.show(context, '无法打开相册，请检查相册访问权限');
    }
  }

  Future<void> _showTopicPicker() async {
    HapticFeedbackUtil.light();
    const defaultTopics = [
      '数码日常',
      '玩机技巧',
      '酷安日常',
      '今日份日常',
      '好物推荐',
      '手机摄影',
      '电脑讨论',
      '搞机日记',
      '开箱体验',
      '每日打卡',
      '123云盘',
      'VibeCoding',
      '魅族PA',
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = defaultTopics
                .where((t) => t.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return Material(
              color: isDark ? const Color(0xFF222226) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.65,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选择发布的板块 / 话题',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: '搜索或输入自定义话题…',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF0F0F2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onChanged: (val) => setModalState(() => query = val),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        HapticFeedbackUtil.selection();
                        Navigator.of(ctx).pop(val.trim());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length + (query.trim().isNotEmpty && !filtered.contains(query.trim()) ? 1 : 0),
                      separatorBuilder: (_, _) => Divider(
                        height: 0.5,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      itemBuilder: (ctx, index) {
                        if (index == filtered.length) {
                          return ListTile(
                            leading: const Icon(Icons.add_rounded, color: Color(0xFF34D399)),
                            title: Text('使用自定义话题 "#${query.trim()}#"'),
                            onTap: () {
                              HapticFeedbackUtil.selection();
                              Navigator.of(ctx).pop(query.trim());
                            },
                          );
                        }
                        final topic = filtered[index];
                        final isChosen = _selectedTopic == topic;
                        return ListTile(
                          leading: Icon(
                            Icons.tag_rounded,
                            color: isChosen ? const Color(0xFF34D399) : (isDark ? Colors.white54 : Colors.black54),
                          ),
                          title: Text(
                            topic,
                            style: TextStyle(
                              color: isChosen ? const Color(0xFF34D399) : (isDark ? Colors.white : Colors.black87),
                              fontWeight: isChosen ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isChosen
                              ? const Icon(Icons.check_rounded, color: Color(0xFF34D399))
                              : null,
                          onTap: () {
                            HapticFeedbackUtil.selection();
                            Navigator.of(ctx).pop(topic);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
          },
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _selectedTopic = selected);
    }
  }

  Future<void> _showVisibilityPicker() async {
    HapticFeedbackUtil.light();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Material(
          color: isDark ? const Color(0xFF222226) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '谁可以看',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('公开'),
                subtitle: const Text('所有人可见（默认）'),
                trailing: _visibility == 'public'
                    ? const Icon(Icons.check_rounded, color: Color(0xFF34D399))
                    : null,
                onTap: () {
                  HapticFeedbackUtil.selection();
                  Navigator.of(ctx).pop('public');
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('仅自己可见'),
                subtitle: const Text('私密动态，仅本人可查阅'),
                trailing: _visibility == 'private'
                    ? const Icon(Icons.check_rounded, color: Color(0xFF34D399))
                    : null,
                onTap: () {
                  HapticFeedbackUtil.selection();
                  Navigator.of(ctx).pop('private');
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline_rounded),
                title: const Text('好友圈'),
                subtitle: const Text('仅互相关注的酷友好友可见'),
                trailing: _visibility == 'friends'
                    ? const Icon(Icons.check_rounded, color: Color(0xFF34D399))
                    : null,
                onTap: () {
                  HapticFeedbackUtil.selection();
                  Navigator.of(ctx).pop('friends');
                },
              ),
            ],
          ),
        ),
      );
      },
    );
    if (selected != null && mounted) {
      setState(() => _visibility = selected);
    }
  }

  void _insertTopic(String topic) {
    HapticFeedbackUtil.selection();
    final text = _message.text;
    final selection = _message.selection;
    final insertText = '#$topic# ';
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, insertText);
    _message.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );
    if (_selectedTopic == null || _selectedTopic!.isEmpty) {
      setState(() => _selectedTopic = topic);
    }
  }

  void _insertEmoji(String emojiName) {
    HapticFeedbackUtil.selection();
    final text = _message.text;
    final selection = _message.selection;
    final insertText = '[$emojiName]';
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, insertText);
    _message.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );
  }

  void _insertTagSymbol() {
    HapticFeedbackUtil.light();
    final text = _message.text;
    final selection = _message.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, '##');
    _message.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    _focusNode.requestFocus();
  }

  void _insertAtSymbol() {
    HapticFeedbackUtil.light();
    final text = _message.text;
    final selection = _message.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, '@');
    _message.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    _focusNode.requestFocus();
  }

  Future<void> _showMoreOptions() async {
    final titleController = TextEditingController(text: _extraTitle ?? '');
    final locationController = TextEditingController(text: _location ?? '');
    final productController = TextEditingController(text: _productId ?? '');
    final voteController = TextEditingController(text: _voteId ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222226) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '扩展信息与设置',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '文章标题（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: '发布位置（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: productController,
                  decoration: const InputDecoration(
                    labelText: '关联产品 ID（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: voteController,
                  decoration: const InputDecoration(
                    labelText: '关联投票 ID（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedbackUtil.light();
                      setState(() {
                        _extraTitle = titleController.text.trim().isEmpty ? null : titleController.text.trim();
                        _location = locationController.text.trim().isEmpty ? null : locationController.text.trim();
                        _productId = productController.text.trim().isEmpty ? null : productController.text.trim();
                        _voteId = voteController.text.trim().isEmpty ? null : voteController.text.trim();
                      });
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('保存设置'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaArea(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxCount = _isCoverMode ? 1 : 9;

    if (_pictures.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            key: const ValueKey('compose-media-add-box'),
            onTap: _pickImage,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262629) : const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 38,
                color: isDark ? const Color(0xFF6E6E73) : const Color(0xFFAAAAAA),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '长按图片可拖动排序',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    height: 1.5,
                  ),
                ),
                Text(
                  '发无关图、色情图将会被禁言',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _pictures.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: _pictures[i].bytes != null
                      ? Image.memory(
                          _pictures[i].bytes!,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          _pictures[i].url ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE5E5E5),
                            child: const Icon(Icons.image_outlined, color: Colors.grey),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.light();
                    setState(() => _pictures.removeAt(i));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (_pictures.length < maxCount)
          GestureDetector(
            key: const ValueKey('compose-media-add-box'),
            onTap: _pickImage,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262629) : const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 38,
                color: isDark ? const Color(0xFF6E6E73) : const Color(0xFFAAAAAA),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopicChip(
    BuildContext context,
    String title, {
    bool isFeatured = false,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isFeatured
              ? (isDark ? const Color(0xFF1B2A22) : const Color(0xFFE8F5E9))
              : (isDark ? const Color(0xFF222225) : const Color(0xFFF0F0F2)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFeatured) ...[
              Icon(
                Icons.campaign_rounded,
                size: 15,
                color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isFeatured ? FontWeight.w600 : FontWeight.normal,
                color: isFeatured
                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32))
                    : (isDark ? const Color(0xFFCCCCCC) : const Color(0xFF555555)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiKeyboard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const commonEmojis = [
      '滑稽', 'doge', '笑哭', '捂脸', '点赞', '妙啊', '机智', '吃瓜',
      '微笑', '思考', '流泪', '白眼', '发怒', '疑问', '酷', '偷笑',
      '爱心', 'OK', '强', '抱拳', '握手', '胜利', '二哈', '黑线',
      '委屈', '再见', '可怜', '亲亲', '坏笑', '阴险', '傲慢', '害羞',
    ];

    return Container(
      height: 220,
      color: isDark ? const Color(0xFF1B1B1E) : const Color(0xFFF6F6F8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: commonEmojis.length,
        itemBuilder: (ctx, index) {
          final emojiName = commonEmojis[index];
          return InkWell(
            onTap: () => _insertEmoji(emojiName),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              alignment: Alignment.center,
              child: Tooltip(
                message: emojiName,
                child: Text(
                  '[$emojiName]',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;

    final hasDraft = _hasDraft;

    return PopScope(
      canPop: !hasDraft,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && hasDraft) _handleClose();
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF141416) : Colors.white,
        body: Column(
          children: [
            // Top Bar
            SizedBox(height: topPadding),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 24,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    onPressed: _handleClose,
                  ),
                  const Spacer(),
                  // Center Segmented Capsule: 大封面 | 九宫格
                  Container(
                    height: 34,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF222225) : const Color(0xFFEAEAEA),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedbackUtil.selection();
                            setState(() => _isCoverMode = true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: _isCoverMode
                                  ? (isDark ? const Color(0xFF1B382B) : const Color(0xFFE8F5E9))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              '大封面',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _isCoverMode ? FontWeight.bold : FontWeight.normal,
                                color: _isCoverMode
                                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32))
                                  : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666)),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedbackUtil.selection();
                            setState(() => _isCoverMode = false);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: !_isCoverMode
                                  ? (isDark ? const Color(0xFF1B382B) : const Color(0xFFE8F5E9))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              '九宫格',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: !_isCoverMode ? FontWeight.bold : FontWeight.normal,
                                color: !_isCoverMode
                                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32))
                                    : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Right "发布" Button
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: (_canSubmit && !_busy) ? _submit : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(60, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        side: BorderSide(
                          color: _canSubmit
                              ? (isDark ? const Color(0xFF34D399) : scheme.primary)
                              : (isDark ? const Color(0xFF48484C) : const Color(0xFFCCCCCC)),
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '发布',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: _canSubmit
                                    ? (isDark ? const Color(0xFF34D399) : scheme.primary)
                                    : (isDark ? const Color(0xFFC0C0C4) : const Color(0xFF999999)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            // Middle Scrollable Area
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // "发布到" Row
                  InkWell(
                    onTap: _showTopicPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF163324) : const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '发布到',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (_selectedTopic != null && _selectedTopic!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1B382B) : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '# $_selectedTopic',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _selectedTopic == null || _selectedTopic!.isEmpty
                                ? '选择合适的板块会有更多的赞'
                                : '更换板块',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? const Color(0xFF7C7C82) : const Color(0xFF888888),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: isDark ? const Color(0xFF7C7C82) : const Color(0xFF888888),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Media Box Area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: _buildMediaArea(context),
                  ),
                  // Text Input Field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: TextField(
                      controller: _message,
                      focusNode: _focusNode,
                      minLines: 5,
                      maxLines: 15,
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.45,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: '分享你此刻的想法…',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: isDark ? const Color(0xFF5A5A60) : const Color(0xFF999999),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  // Divider & "谁可以看" Row
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: isDark ? const Color(0xFF2C2C30) : const Color(0xFFE5E5E5),
                  ),
                  InkWell(
                    onTap: _showVisibilityPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 20,
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '谁可以看',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF333333),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _visibilityLabel,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF777777),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF777777),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Recommended Topics Chips Strip
            Container(
              height: 36,
              color: isDark ? const Color(0xFF141416) : Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildTopicChip(
                    context,
                    '# 数码日常',
                    isFeatured: true,
                    onTap: () => _insertTopic('数码日常'),
                  ),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# 123云盘', onTap: () => _insertTopic('123云盘')),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# VibeCoding', onTap: () => _insertTopic('VibeCoding')),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# 魅族PA...', onTap: () => _insertTopic('魅族PA')),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# 今日份日常', onTap: () => _insertTopic('今日份日常')),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# 玩机日记', onTap: () => _insertTopic('玩机日记')),
                  const SizedBox(width: 8),
                  _buildTopicChip(context, '# 手机摄影', onTap: () => _insertTopic('手机摄影')),
                ],
              ),
            ),
            // Bottom Dock Toolbar
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: isDark ? const Color(0xFF141416) : Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      size: 24,
                      color: _showEmojiPicker
                          ? const Color(0xFF34D399)
                          : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666)),
                    ),
                    onPressed: () {
                      HapticFeedbackUtil.light();
                      setState(() {
                        _showEmojiPicker = !_showEmojiPicker;
                        if (_showEmojiPicker) {
                          _focusNode.unfocus();
                        } else {
                          _focusNode.requestFocus();
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.image_outlined,
                      size: 24,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    ),
                    onPressed: _pickImage,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.alternate_email_rounded,
                      size: 24,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    ),
                    onPressed: _insertAtSymbol,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.tag_rounded,
                      size: 24,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    ),
                    onPressed: _insertTagSymbol,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      size: 24,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    ),
                    onPressed: _showMoreOptions,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.language_rounded,
                      size: 24,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF666666),
                    ),
                    onPressed: _showVisibilityPicker,
                  ),
                ],
              ),
            ),
            if (_showEmojiPicker) _buildEmojiKeyboard(context),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
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
  const _FeatureRow({required this.api, required this.item});
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

String _messageKey(Map<String, dynamic> row) => chatRowKey(row);

void _snack(BuildContext context, String message) =>
    AppToast.show(context, message);
