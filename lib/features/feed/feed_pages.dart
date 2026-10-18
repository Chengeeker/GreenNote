import 'dart:async';
import 'dart:convert';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'video_player_page.dart';

import '../../core/widgets/review_refresh_header.dart';
import '../../core/design_system/components/review_card.dart';
import '../../core/design_system/components/review_navigation_bar.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

import 'image_gallery_page.dart';
import '../shared/activity_pages.dart';
import 'nine_grid_view.dart';
import 'feed_vote.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/network/product_price.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../digital/utils/digital_system_helper.dart';
import '../shared/api_list_page.dart';
import '../shared/home_destination_page.dart';
import '../shell/main_pages.dart' show ComposeFeedPage;

class _HomeChannel {
  const _HomeChannel(this.id, this.title, this.route);

  final String id;
  final String title;
  final String route;

  static const defaults = <_HomeChannel>[
    _HomeChannel('topic', '话题', '/page?url=V11_VERTICAL_TOPIC&title=话题'),
    _HomeChannel('follow', '关注', '/page?url=V15_HOME_TAB_FOLLOW'),
    _HomeChannel('headline', '头条', '/v6/main/headline'),
    _HomeChannel('hot', '热榜', '/page?url=V9_HOME_TAB_RANKING'),
    _HomeChannel('tutorial', '教程', '/page?url=V11_HOME_TAB_JC'),
    _HomeChannel('video', '视频', '/page?url=V9_HOME_TAB_SHIPIN'),
  ];

  static const more = <_HomeChannel>[
    _HomeChannel('news', '快讯', '/page?url=V11_HOME_TAB_NEWS'),
    _HomeChannel('new_device', '新机', '/page?url=V11_HOME_NEW'),
    _HomeChannel('car', '汽车', '/page?url=V11_HOME_CAR'),
    _HomeChannel('unboxing', '开箱', '/page?url=V13_IOSHOME_OPENSHOW'),
    _HomeChannel('photo', '摄影', '/page?url=V13_HOME_SHEYING'),
    _HomeChannel('game', '游戏', '/page?url=V15_YOUXI'),
    _HomeChannel('peripherals', '外设', '/page?url=V14_WAISHE'),
    _HomeChannel('theme', '美化', '/page?url=V11_HOME_MEIHUA'),
    _HomeChannel('live', '直播', '/page?url=V9_HOME_TAB_LIVE'),
    _HomeChannel('qa', '问答', '/page?url=V9_HOME_TAB_WENDA'),
    _HomeChannel('coupons', '神券', '/page?url=V11_FIND_GOODS'),
    // Backward compatibility aliases
    _HomeChannel('latest', '最新', '#/feed/newestList'),
    _HomeChannel('digest', '精选', '#/feed/digestList?type=1'),
    _HomeChannel('picture', '酷图', '#/feed/coolPictureRankList'),
    _HomeChannel('editor', '编辑精选', '#/feed/editorChoiceList'),
    _HomeChannel('questions', '问答', '#/feed/myQaFeedList'),
  ];

  static final byId = {
    for (final item in [...defaults, ...more]) item.id: item,
  };
}

class FeedHomePage extends StatefulWidget {
  const FeedHomePage({
    required this.api,
    required this.onLoginRequested,
    this.onTopBarChanged,
    super.key,
  });

  final CoolapkApi api;
  final Future<void> Function() onLoginRequested;
  final ValueChanged<PreferredSizeWidget?>? onTopBarChanged;

  @override
  State<FeedHomePage> createState() => _FeedHomePageState();
}

class _FeedHomePageState extends State<FeedHomePage>
    with TickerProviderStateMixin {
  static const _channelsKey = 'home_channels_v2';
  late List<_HomeChannel> _channels = [..._HomeChannel.defaults];
  late TabController _tabs = _newController();
  bool _editingChannels = false;
  bool _showChannels = false;
  String _selectedId = 'headline';
  Map<String, String> _serverRoutes = const {};

  TabController _newController() => TabController(
    length: _channels.length,
    initialIndex: _channels
        .indexWhere((item) => item.id == _selectedId)
        .clamp(0, _channels.length - 1)
        .toInt(),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTopBar();
    });
    unawaited(_restoreChannels());
    unawaited(
      widget.api
          .loadHomeTabRoutes()
          .then((routes) {
            if (mounted) setState(() => _serverRoutes = routes);
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _restoreChannels() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_channelsKey);
    if (!mounted || stored == null || stored.isEmpty) return;
    final restored = stored
        .map((id) => _HomeChannel.byId[id])
        .whereType<_HomeChannel>()
        .toList();
    if (restored.isNotEmpty) _replaceChannels(restored);
  }

  void _replaceChannels(List<_HomeChannel> channels) {
    if (channels.isEmpty) return;
    _selectedId = channels.any((item) => item.id == _selectedId)
        ? _selectedId
        : channels.first.id;
    final oldTabs = _tabs;
    _channels = channels;
    _tabs = _newController();
    oldTabs.dispose();
    setState(() {});
    _syncTopBar();
  }

  void _syncTopBar() => widget.onTopBarChanged?.call(
    _showChannels ? null : _buildChannelTabBar(),
  );

  void _closeChannelOverlay() {
    setState(() => _showChannels = false);
    _syncTopBar();
  }

  PreferredSizeWidget _buildChannelTabBar() => PreferredSize(
    preferredSize: const Size.fromHeight(kTextTabBarHeight),
    child: Builder(
      builder: (context) => Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              onTap: (index) => _selectedId = _channels[index].id,
              tabs: [for (final channel in _channels) Tab(text: channel.title)],
            ),
          ),
          IconButton(
            tooltip: '自定义频道',
            onPressed: () {
              setState(() {
                _showChannels = true;
                _editingChannels = false;
              });
              _syncTopBar();
            },
            icon: const Icon(Icons.menu_rounded),
          ),
        ],
      ),
    ),
  );

  Future<void> _saveChannels() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _channelsKey,
      _channels.map((item) => item.id).toList(),
    );
  }

  void _selectChannel(_HomeChannel channel) {
    if (_editingChannels) {
      if (_channels.length > 1) {
        _replaceChannels([..._channels]..remove(channel));
      }
    } else {
      _selectedId = channel.id;
      _tabs.animateTo(_channels.indexOf(channel));
      _closeChannelOverlay();
    }
    unawaited(_saveChannels());
  }

  void _addChannel(_HomeChannel channel) {
    _replaceChannels([..._channels, channel]);
    unawaited(_saveChannels());
  }

  void _resetChannels() {
    _replaceChannels([..._HomeChannel.defaults]);
    _selectedId = 'headline';
    _tabs.animateTo(2);
    unawaited(_saveChannels());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TabBarView(
          controller: _tabs,
          children: [
            for (final channel in _channels)
              RepaintBoundary(
                child: _FeedListPage(
                  key: ValueKey(channel.id),
                  api: widget.api,
                  channel: channel,
                  route: channel.id == 'topic'
                      ? channel.route
                      : _serverRoutes[channel.id] ?? channel.route,
                  onLoginRequested: widget.onLoginRequested,
                ),
              ),
          ],
        ),
        if (_showChannels) _buildChannelOverlay(context),
      ],
    );
  }

  Widget _buildChannelOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = _HomeChannel.more
        .where((item) => !_channels.any((selected) => selected.id == item.id))
        .toList();
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: _closeChannelOverlay,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.56)),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              child: Material(
                color:
                    Theme.of(context).appBarTheme.backgroundColor ??
                    Theme.of(context).scaffoldBackgroundColor,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '我的频道',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '点击进入频道',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(
                                () => _editingChannels = !_editingChannels,
                              ),
                              child: Text(_editingChannels ? '完成' : '编辑'),
                            ),
                            IconButton(
                              tooltip: '收起',
                              onPressed: _closeChannelOverlay,
                              icon: const Icon(Icons.expand_less_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _channelGrid(context, _channels, selected: true),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Text(
                              '更多频道',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '点击添加新频道',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _resetChannels,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('恢复默认'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _channelGrid(context, available, selected: false),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelGrid(
    BuildContext context,
    List<_HomeChannel> channels, {
    required bool selected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: channels.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isActive = selected && channel.id == _selectedId;
        return InkWell(
          onTap: () {
            if (selected) {
              _selectChannel(channel);
            } else {
              _addChannel(channel);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.25),
                    width: isActive ? 1.2 : 0.8,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  channel.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
                    color: isActive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (selected && _editingChannels)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Icon(
                    Icons.remove_circle,
                    size: 16,
                    color: scheme.error,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FeedListPage extends StatefulWidget {
  const _FeedListPage({
    required this.api,
    required this.channel,
    required this.route,
    required this.onLoginRequested,
    super.key,
  });

  final CoolapkApi api;
  final _HomeChannel channel;
  final String route;
  final Future<void> Function() onLoginRequested;

  @override
  State<_FeedListPage> createState() => _FeedListPageState();
}

class _FeedListPageState extends State<_FeedListPage>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _feeds = <CoolapkFeed>[];
  final _bufferedFeeds = <CoolapkFeed>[];
  List<Map<String, dynamic>> _banners = const [];
  String? _error;
  String _firstItem = '';
  String _lastItem = '';
  int _page = 0;
  bool _busy = false;
  bool _hasMore = true;
  bool _reloadAfterRouteChange = false;
  String? _activeCategoryUrl;
  int _activeCategoryIndex = 0;

  static List<CoolapkFeed>? _cachedHeadlineFeeds;
  static List<Map<String, dynamic>>? _cachedHeadlineBanners;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.channel.id == 'headline') {
      if (_cachedHeadlineFeeds != null && _cachedHeadlineFeeds!.isNotEmpty) {
        _feeds.addAll(_cachedHeadlineFeeds!);
        _banners = _cachedHeadlineBanners ?? const [];
      } else {
        unawaited(_loadInitialHeadlineCache());
      }
    }
    if (widget.channel.id != 'topic' &&
        (widget.channel.id != 'follow' || widget.api.hasCookie)) {
      _load(refresh: true);
    }
  }

  Future<void> _loadInitialHeadlineCache() async {
    if (_feeds.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedRaw = prefs.getString('cached_home_headline_v1');
      if (cachedRaw != null && cachedRaw.isNotEmpty && mounted && _feeds.isEmpty) {
        final decoded = jsonDecode(cachedRaw);
        if (decoded is Map) {
          final rawFeeds = decoded['feeds'];
          final rawBanners = decoded['banners'];
          if (rawFeeds is List && rawFeeds.isNotEmpty) {
            final feeds = rawFeeds
                .whereType<Map>()
                .map((m) => CoolapkFeed.fromJson(Map<String, dynamic>.from(m)))
                .toList();
            final banners = rawBanners is List
                ? rawBanners.whereType<Map>().map(Map<String, dynamic>.from).toList()
                : <Map<String, dynamic>>[];
            if (mounted && _feeds.isEmpty && feeds.isNotEmpty) {
              setState(() {
                _cachedHeadlineFeeds = feeds;
                _cachedHeadlineBanners = banners;
                _feeds.addAll(feeds);
                _banners = banners;
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _FeedListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channel.id == 'topic' ||
        widget.channel.id == 'follow' && !widget.api.hasCookie) {
      return;
    }
    if (oldWidget.route == widget.route) return;
    _activeCategoryUrl = null;
    _activeCategoryIndex = 0;
    if (_busy) {
      if (_feeds.isEmpty) {
        _reloadAfterRouteChange = true;
      }
    } else {
      unawaited(_load(refresh: true));
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // 渐进式线性加载：当用户滑动消耗掉当前批次的一半（约 45% 或剩余未展示区域有限）时，无缝释放内存缓冲区
    if (_bufferedFeeds.isNotEmpty) {
      if (pos.extentAfter < 900 || pos.pixels >= pos.maxScrollExtent * 0.45) {
        setState(() {
          _feeds.addAll(_bufferedFeeds);
          _bufferedFeeds.clear();
        });
      }
    }
    // 缓冲区清空后，当接近底部时，无缝触发下一页网络请求
    if (_bufferedFeeds.isEmpty && pos.extentAfter < 520) {
      _loadMore();
    }
  }

  void _onSelectCategory(Map<String, dynamic> item, int index) {
    if (_activeCategoryIndex == index && _activeCategoryUrl != null) return;
    final url = (item['url'] ?? '').toString().trim();
    if (url.isEmpty) return;
    setState(() {
      _activeCategoryIndex = index;
      _activeCategoryUrl = url;
    });
    unawaited(_load(refresh: true));
  }

  Future<void> _load({required bool refresh}) async {
    if (_busy || (!refresh && !_hasMore && _bufferedFeeds.isEmpty)) return;
    if (!refresh && _bufferedFeeds.isNotEmpty) {
      setState(() {
        _feeds.addAll(_bufferedFeeds);
        _bufferedFeeds.clear();
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (refresh) {
        _page = 0;
        _firstItem = '';
        _lastItem = '';
        _hasMore = true;
        _bufferedFeeds.clear();
      }
    });
    try {
      final nextPage = refresh ? 1 : _page + 1;
      final targetRoute = _activeCategoryUrl ?? widget.route;
      final result = await widget.api.getHomeChannelPage(
        targetRoute,
        nextPage,
        firstItem: _firstItem,
        lastItem: _lastItem,
      );
      final existingIds = <String>{
        ..._feeds.map((feed) => feed.id),
        ..._bufferedFeeds.map((feed) => feed.id),
      };
      final newItems = result.items.where((feed) => existingIds.add(feed.id)).toList();

      setState(() {
        if (refresh) {
          _feeds.clear();
          _bufferedFeeds.clear();
        }
        if (refresh && (_banners.isEmpty || _activeCategoryUrl == null)) {
          _banners = result.cards;
        }

        // 渐进式加载模型：先呈现 ~60%（50%~70%区间），剩余 ~40% 暂存内存缓冲
        if (newItems.length <= 4) {
          _feeds.addAll(newItems);
        } else {
          final stage1Count = (newItems.length * 0.6).round().clamp(1, newItems.length);
          _feeds.addAll(newItems.take(stage1Count));
          _bufferedFeeds.addAll(newItems.skip(stage1Count));
        }

        _page = nextPage;
        _firstItem = result.firstItem.isEmpty ? _firstItem : result.firstItem;
        _lastItem = result.lastItem.isEmpty ? _lastItem : result.lastItem;
        _hasMore = result.hasMore;
        if (_feeds.isEmpty && _bufferedFeeds.isEmpty) _hasMore = false;
      });

      if (widget.channel.id == 'headline' && refresh && newItems.isNotEmpty) {
        _cachedHeadlineFeeds = List.from(_feeds);
        _cachedHeadlineBanners = List.from(_banners);
        unawaited(() async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final jsonPayload = jsonEncode({
              'feeds': newItems.take(20).map((f) => f.raw).toList(),
              'banners': _banners.take(5).toList(),
            });
            await prefs.setString('cached_home_headline_v1', jsonPayload);
          } catch (_) {}
        }());
      }

      // 若当前视口无法滚动（高度不足一屏），自动平滑释放缓冲区填满视口
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _bufferedFeeds.isEmpty) return;
        if (_scrollController.hasClients &&
            (_scrollController.position.maxScrollExtent <= 0 ||
             _scrollController.position.extentAfter < 500)) {
          setState(() {
            _feeds.addAll(_bufferedFeeds);
            _bufferedFeeds.clear();
          });
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_reloadAfterRouteChange) {
          _reloadAfterRouteChange = false;
          unawaited(_load(refresh: true));
        }
      }
    }
  }

  Future<void> _loadMore() => _load(refresh: false);

  Future<void> _login() async {
    await widget.onLoginRequested();
    if (mounted && widget.api.hasCookie) await _load(refresh: true);
  }

  Widget _buildFeedSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 4,
      itemBuilder: (context, _) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: barColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 90,
                      height: 12,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: 9,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              height: 13,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 220,
              height: 13,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.channel.id == 'topic') return _HomeTopicPage(api: widget.api);
    if (widget.channel.id == 'follow' && widget.api.isAnonymous) {
      return _LocalFollowTimeline(api: widget.api);
    }
    if (widget.channel.id == 'follow' && !widget.api.hasCookie) {
      return _FollowLoginPrompt(onLogin: _login);
    }
    if (_feeds.isEmpty && _banners.isEmpty && _busy) {
      return _buildFeedSkeleton(context);
    }
    if (_feeds.isEmpty && _banners.isEmpty && _error != null) {
      if (_isCaptchaError(_error!)) {
        return EasyRefresh(
          header: reviewDefaultRefreshHeader,
          onRefresh: () => _load(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 320)],
          ),
        );
      }
      return _LoadError(message: _error!, onRetry: () => _load(refresh: true));
    }
    if (_feeds.isEmpty && _banners.isEmpty) {
      return _LoadError(
        message: '酷安暂时没有返回动态',
        onRetry: () => _load(refresh: true),
      );
    }
    final isRankChannel =
        widget.channel.id == 'hot' ||
        widget.route.contains('RANKING') ||
        (_activeCategoryUrl != null && _activeCategoryUrl!.contains('RANKING'));
    final showHeader =
        widget.channel.id == 'headline' ||
        widget.channel.id == 'hot' ||
        widget.channel.id == 'tutorial' ||
        widget.channel.id == 'video' ||
        _banners.isNotEmpty;
    return EasyRefresh(
      header: reviewDefaultRefreshHeader,
      triggerAxis: Axis.vertical,
      onRefresh: () => _load(refresh: true),
      child: filterHorizontalScrollNotifications(
        ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
          padding: EdgeInsets.fromLTRB(
            0,
            6,
            0,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: _feeds.length + (showHeader ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            if (showHeader && index == 0) {
              return HomeChannelCardsHeader(
                api: widget.api,
                cards: _banners,
                channelId: widget.channel.id,
                activeCategoryIndex: _activeCategoryIndex,
                onSelectCategory: _onSelectCategory,
              );
            }
            final feedIndex = index - (showHeader ? 1 : 0);
            if (feedIndex == _feeds.length) {
              if (_error != null) {
                if (_isCaptchaError(_error!)) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('加载失败，点击重试：$_error'),
                );
              }
              if (_busy) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return const SizedBox(height: 12);
            }
            final rankNumber = (isRankChannel && feedIndex < 20)
                ? (feedIndex + 1)
                : null;
            return FeedCard(
              key: ValueKey('feed-${_feeds[feedIndex].id}'),
              api: widget.api,
              feed: _feeds[feedIndex],
              rankNumber: rankNumber,
              isHeadline: widget.channel.id == 'headline',
            );
          },
        ),
      ),
    );
  }
}

class _LocalFollowTimeline extends StatefulWidget {
  const _LocalFollowTimeline({required this.api});
  final CoolapkApi api;

  @override
  State<_LocalFollowTimeline> createState() => _LocalFollowTimelineState();
}

class _LocalFollowTimelineState extends State<_LocalFollowTimeline> {
  static const _requestConcurrency = 3;
  static const _followCacheDuration = Duration(minutes: 5);
  final _scrollController = ScrollController();
  final _feedsById = <String, CoolapkFeed>{};
  final _loadedPages = <String, int>{};
  final _hasMoreByUser = <String, bool>{};
  final _firstItemsByUser = <String, String>{};
  final _lastItemsByUser = <String, String>{};
  List<CoolapkFeed> _feeds = [];
  List<String> _userIds = [];
  String _sourcePublicUid = '';
  String _cachedFollowUid = '';
  List<String> _cachedFollowIds = const [];
  DateTime? _followCacheTime;
  String? _sourceError;
  int _generation = 0;
  int _progress = 0;
  int _total = 0;
  int _failed = 0;
  bool _loading = false;
  bool _readingFollowing = false;
  bool _loadingMore = false;
  bool _refreshPending = false;
  bool get _hasMore => _hasMoreByUser.values.any((hasMore) => hasMore);

  @override
  void initState() {
    super.initState();
    _sourcePublicUid = _activePublicUid();
    _userIds = _sourcePublicUid.isEmpty ? _followedUserIds() : [];
    widget.api.localAccount.addListener(_onAccountChanged);
    _scrollController.addListener(_onScroll);
    unawaited(_refresh(force: true));
  }

  @override
  void didUpdateWidget(covariant _LocalFollowTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.localAccount.removeListener(_onAccountChanged);
      widget.api.localAccount.addListener(_onAccountChanged);
      _sourcePublicUid = _activePublicUid();
      unawaited(_refresh(force: true));
    }
  }

  @override
  void dispose() {
    widget.api.localAccount.removeListener(_onAccountChanged);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  List<String> _followedUserIds() =>
      widget.api.localAccount.follows.keys.toList(growable: false);

  String _activePublicUid() {
    if (!widget.api.isAnonymous) return '';
    final uid = widget.api.localAccount.publicIdentity?['uid'];
    return uid is String ? uid : '';
  }

  void _onAccountChanged() {
    final publicUid = _activePublicUid();
    if (publicUid != _sourcePublicUid) {
      _sourcePublicUid = publicUid;
      _userIds = publicUid.isEmpty ? _followedUserIds() : [];
      unawaited(_refresh(force: true));
      return;
    }
    if (publicUid.isNotEmpty) return;
    final next = _followedUserIds();
    var unchanged = next.length == _userIds.length;
    for (var index = 0; unchanged && index < next.length; index++) {
      unchanged = next[index] == _userIds[index];
    }
    if (unchanged) {
      return;
    }
    _userIds = next;
    unawaited(_refresh(force: true));
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 650) {
      unawaited(_loadMore());
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (force) {
      _followCacheTime = null;
      // Source changes must never leave another identity's timeline visible.
      setState(() => _feeds = []);
    }
    if (_loading || _loadingMore) {
      if (force) _refreshPending = true;
      return;
    }
    final generation = ++_generation;
    final publicUid = _activePublicUid();
    setState(() {
      _sourcePublicUid = publicUid;
      _userIds = publicUid.isEmpty ? _followedUserIds() : [];
      _feedsById.clear();
      _loadedPages.clear();
      _hasMoreByUser.clear();
      _firstItemsByUser.clear();
      _lastItemsByUser.clear();
      _progress = 0;
      _total = _userIds.length;
      _failed = 0;
      _sourceError = null;
      _loading = true;
      _readingFollowing = publicUid.isNotEmpty;
      _loadingMore = false;
    });
    try {
      final userIds = publicUid.isEmpty
          ? _userIds
          : await _loadPublicFollowIds(publicUid);
      if (!mounted ||
          generation != _generation ||
          publicUid != _activePublicUid()) {
        return;
      }
      setState(() {
        _userIds = userIds;
        _total = userIds.length;
        _readingFollowing = false;
        if (userIds.isEmpty) _feeds = [];
      });
      await _loadUserPages(
        {for (final uid in userIds) uid: 1},
        generation: generation,
        sourcePublicUid: publicUid,
        countProgress: true,
      );
      if (!mounted ||
          generation != _generation ||
          publicUid != _activePublicUid()) {
        return;
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _sourceError = error.toString();
        _readingFollowing = false;
        _loading = false;
      });
    } finally {
      if (mounted && generation == _generation && _loading) {
        setState(() {
          _loading = false;
          _readingFollowing = false;
        });
      }
      if (mounted && generation == _generation && _refreshPending) {
        _refreshPending = false;
        unawaited(_refresh(force: true));
      }
    }
  }

  Future<List<String>> _loadPublicFollowIds(String uid) async {
    final cachedAt = _followCacheTime;
    // shortcut: remote follow changes can take five minutes to appear.
    if (_cachedFollowUid == uid &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _followCacheDuration) {
      return _cachedFollowIds;
    }
    final userIds = <String>{};
    var pageNumber = 1;
    var firstItem = '';
    var lastItem = '';
    while (true) {
      final page = await widget.api.getUserPage(
        '/v6/user/followList',
        uid,
        pageNumber,
        firstItem: firstItem,
        lastItem: lastItem,
      );
      if (uid != _activePublicUid()) return const [];
      final previousCount = userIds.length;
      for (final user in page.items) {
        final followedUid = '${user['uid'] ?? user['userId'] ?? ''}'.trim();
        if (followedUid.isNotEmpty) userIds.add(followedUid);
      }
      if (page.items.isNotEmpty &&
          pageNumber == 1 &&
          userIds.length == previousCount) {
        throw const CoolapkApiException('无法从公开关注列表中读取用户 UID');
      }
      if (!page.hasMore ||
          page.items.isEmpty ||
          userIds.length == previousCount) {
        break;
      }
      firstItem = page.firstItem;
      lastItem = page.lastItem;
      pageNumber++;
    }
    _cachedFollowUid = uid;
    _cachedFollowIds = userIds.toList(growable: false);
    _followCacheTime = DateTime.now();
    return _cachedFollowIds;
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore) return;
    final nextPages = <String, int>{
      for (final uid in _userIds)
        if (_hasMoreByUser[uid] == true) uid: (_loadedPages[uid] ?? 1) + 1,
    };
    if (nextPages.isEmpty) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    await _loadUserPages(
      nextPages,
      generation: generation,
      sourcePublicUid: _sourcePublicUid,
    );
    if (mounted && generation == _generation) {
      setState(() => _loadingMore = false);
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(_refresh(force: true));
      }
    }
  }

  Future<void> _loadUserPages(
    Map<String, int> pages, {
    required int generation,
    required String sourcePublicUid,
    bool countProgress = false,
  }) async {
    final entries = pages.entries.toList(growable: false);
    final hadFeeds = _feeds.isNotEmpty;
    for (
      var offset = 0;
      offset < entries.length;
      offset += _requestConcurrency
    ) {
      final batch = entries.skip(offset).take(_requestConcurrency).toList();
      final results = <(String, int, FeedPage?, Object?)>[];
      await Future.wait(
        batch.map((entry) async {
          try {
            final page = await widget.api.getUserFeedPage(
              entry.key,
              entry.value,
              firstItem: _firstItemsByUser[entry.key] ?? '',
              lastItem: _lastItemsByUser[entry.key] ?? '',
            );
            results.add((entry.key, entry.value, page, null));
          } catch (error) {
            results.add((entry.key, entry.value, null, error));
          }
        }),
      );
      if (!mounted ||
          generation != _generation ||
          sourcePublicUid != _activePublicUid()) {
        return;
      }
      setState(() {
        for (final (uid, pageNumber, page, _) in results) {
          if (page == null) {
            _failed++;
            _hasMoreByUser[uid] = false;
            continue;
          }
          _loadedPages[uid] = pageNumber;
          _hasMoreByUser[uid] = page.hasMore;
          _firstItemsByUser[uid] = page.firstItem;
          _lastItemsByUser[uid] = page.lastItem;
          for (final feed in page.items) {
            if (feed.id.isEmpty) continue;
            _feedsById[feed.id] = feed;
          }
        }
        if (countProgress) _progress += batch.length;
        // Keep the visible list stable while refreshing; sort once at completion.
        if ((!hadFeeds && _feeds.isEmpty) ||
            offset + batch.length == entries.length) {
          final timestamps = {
            for (final feed in _feedsById.values) feed.id: _timestamp(feed),
          };
          if (_feedsById.isNotEmpty || _failed == 0) {
            _feeds = _feedsById.values.toList()
              ..sort((left, right) {
                final byDate = timestamps[right.id]!.compareTo(
                  timestamps[left.id]!,
                );
                return byDate != 0 ? byDate : right.id.compareTo(left.id);
              });
          }
        }
      });
    }
  }

  int _timestamp(CoolapkFeed feed) {
    final value =
        feed.raw['dateline'] ??
        feed.raw['createTime'] ??
        feed.raw['create_time'];
    if (value is num) return value.toInt();
    final text = value?.toString() ?? '';
    return int.tryParse(text) ??
        DateTime.tryParse(text)?.millisecondsSinceEpoch ??
        0;
  }

  Widget _status(String text, {bool progress = false}) => SizedBox(
    height: 260,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          if (progress) const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(text, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => EasyRefresh(
    header: reviewDefaultRefreshHeader,
    onRefresh: () => _refresh(),
    child: filterHorizontalScrollNotifications(
      ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
        padding: EdgeInsets.only(
          bottom: 20 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: _feeds.length + 1,
        itemBuilder: (context, index) {
          if (index < _feeds.length) {
            final feed = _feeds[index];
            return FeedCard(
              key: ValueKey(feed.id),
              api: widget.api,
              feed: feed,
            );
          }
          if (_feeds.isEmpty) {
            if (_loading) {
              return _status(
                _readingFollowing
                    ? '正在读取 UID 对应的关注列表'
                    : '正在汇总关注动态 $_progress/$_total',
                progress: true,
              );
            }
            if (_sourceError != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status('读取 UID 对应的关注列表失败：$_sourceError'),
                  TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              );
            }
            if (_userIds.isEmpty) {
              return _status(
                _sourcePublicUid.isNotEmpty
                    ? '该 UID 暂时没有关注用户'
                    : '在博主主页点击关注，最新动态会显示在这里',
              );
            }
            if (_hasMore) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status(
                    _failed > 0 ? '$_failed 位用户暂时无法读取，可下拉重试' : '暂时没有较新的动态',
                  ),
                  TextButton(onPressed: _loadMore, child: const Text('加载更早动态')),
                ],
              );
            }
            if (_failed > 0) {
              return _status('获取关注动态失败，向下拉动重试');
            }
            return _status('你关注的用户暂时没有发布动态');
          }
          if (_loading || _loadingMore) {
            return ListTile(
              leading: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(
                _loading ? '正在汇总关注动态 $_progress/$_total' : '正在加载更早动态',
              ),
            );
          }
          if (_sourceError != null) {
            return ListTile(title: Text('刷新关注列表失败，已保留现有动态：$_sourceError'));
          }
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: Text(
                    _failed > 0 ? '继续加载（$_failed 位用户暂时不可用）' : '加载更早动态',
                  ),
                ),
              ),
            );
          }
          if (_failed > 0) {
            return ListTile(title: Text('$_failed 位用户的动态加载失败，下拉可重试'));
          }
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: Text('没有更多动态')),
          );
        },
      ),
    ),
  );
}

class _FollowLoginPrompt extends StatelessWidget {
  const _FollowLoginPrompt({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_add_alt_1_rounded, size: 42),
          const SizedBox(height: 12),
          Text('登录后查看关注动态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('未登录时酷安可能返回推荐内容，不能代表你的关注列表。', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onLogin, child: const Text('登录酷安')),
        ],
      ),
    ),
  );
}

class _HomeTopicPage extends StatefulWidget {
  const _HomeTopicPage({required this.api});
  final CoolapkApi api;

  @override
  State<_HomeTopicPage> createState() => _HomeTopicPageState();
}

class _HomeTopicPageState extends State<_HomeTopicPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  int _selected = 1;

  Future<List<Map<String, dynamic>>> _load() async {
    final page = await widget.api.getList(
      '/v6/page/dataList',
      query: {'url': 'V11_VERTICAL_TOPIC', 'title': '话题', 'page': 1},
    );
    final topics = <Map<String, dynamic>>[];
    for (final item in page.items) {
      final children = item['entities'];
      if (children is! List) continue;
      for (final child in children.whereType<Map>()) {
        final topic = Map<String, dynamic>.from(child);
        if (topic['title'] != null && topic['url'] != null) topics.add(topic);
      }
    }
    return topics;
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final topics = snapshot.data;
          if (topics == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (topics.isEmpty) {
            return _LoadError(
              message: '酷安没有返回话题分区',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final selected = _selected.clamp(0, topics.length - 1);
          final topic = topics[selected];
          final target = _topicTarget(
            topic['url'].toString(),
            topic['title']?.toString() ?? '',
          );
          return Row(
            children: [
              SizedBox(
                width: 92,
                child: ListView.builder(
                  itemCount: topics.length,
                  itemBuilder: (context, index) {
                    final item = topics[index];
                    return InkWell(
                      onTap: () => setState(() => _selected = index),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        decoration: BoxDecoration(
                          color: index == selected
                              ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHigh
                              : null,
                          border: Border(
                            left: BorderSide(
                              color: index == selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 10,
                        ),
                        child: Text(
                          item['title'].toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: index == selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: ApiListPage(
                  key: ValueKey(target.toString()),
                  api: widget.api,
                  title: topic['title'].toString(),
                  path: target.$1,
                  query: target.$2,
                  showAppBar: false,
                  nested: true,
                ),
              ),
            ],
          );
        },
      );

  (String, Map<String, dynamic>) _topicTarget(String value, String title) {
    var raw = value.trim();
    if (raw.startsWith('/page?url=')) {
      raw = raw.substring('/page?url='.length);
    }
    try {
      if (raw.contains('%')) {
        raw = Uri.decodeComponent(raw);
      }
    } catch (_) {}

    // Coolapk's /v6/topic/tagList directly ignores the keywords query parameter
    // and returns default trending tags. Sub-topic hashtags like
    // #/topic/tagList?keywords=... must be requested via /v6/page/dataList.
    final query = <String, dynamic>{
      'url': raw,
      if (title.isNotEmpty) 'title': title,
    };
    return ('/v6/page/dataList', query);
  }
}

class _HeadlineCarousel extends StatefulWidget {
  const _HeadlineCarousel({required this.api, required this.cards});
  final CoolapkApi api;
  final List<Map<String, dynamic>> cards;

  @override
  State<_HeadlineCarousel> createState() => _HeadlineCarouselState();
}

class _HeadlineCarouselState extends State<_HeadlineCarousel> {
  static const int _loopFactor = 10000;
  static const double _fixedAspectRatio = 4.35;
  PageController? _controller;
  Timer? _timer;
  late List<Map<String, dynamic>> _items = _resolveItems(widget.cards);
  int _page = 0;

  static const List<Map<String, dynamic>> _defaultCarouselEntities = [
    {
      'title': '年轻人的第一辆车',
      'pic': 'https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg',
      'url': '/page?url=V9_CAR_CENTER',
    },
    {
      'title': '今日酷安',
      'pic': 'https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg',
      'url': '/feed/headline',
    },
  ];

  static List<Map<String, dynamic>> _resolveItems(
    List<Map<String, dynamic>> cards,
  ) {
    final list = _flatten(cards);
    return list.isNotEmpty ? list : _defaultCarouselEntities;
  }

  static List<Map<String, dynamic>> _flatten(
    List<Map<String, dynamic>> cards,
  ) => [
    for (final card in cards)
      if (card['entities'] is List)
        ...(card['entities'] as List).whereType<Map>().map(
          Map<String, dynamic>.from,
        )
      else if (_image(card).isNotEmpty)
        card,
  ].where((item) => _image(item).isNotEmpty).toList(growable: false);

  static String _image(Map<String, dynamic> item) =>
      (item['pic'] ?? item['image'] ?? item['cover'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _initController();
    _startTimer();
  }

  void _initController() {
    if (_items.isEmpty) return;
    final initialPage = _items.length > 1
        ? (_items.length * (_loopFactor ~/ 2))
        : 0;
    _controller = PageController(initialPage: initialPage);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_controller != null && _controller!.hasClients) {
          _controller!.nextPage(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _HeadlineCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cards, widget.cards)) {
      final newItems = _resolveItems(widget.cards);
      final changed =
          newItems.length != _items.length || !_areItemsEqual(_items, newItems);
      if (changed) {
        _items = newItems;
        _controller?.dispose();
        _page = 0;
        _initController();
        _startTimer();
      }
    }
  }

  static bool _areItemsEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_image(a[i]) != _image(b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final isLoop = _items.length > 1;
    final totalCount = isLoop ? _items.length * _loopFactor : 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: AspectRatio(
        aspectRatio: _fixedAspectRatio,
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  _timer?.cancel();
                } else if (notification is ScrollEndNotification) {
                  _startTimer();
                }
                return false;
              },
              child: protectHorizontalDragFromVerticalRefresh(
                PageView.builder(
                  controller: _controller,
                  physics: const PageScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemCount: totalCount,
                  onPageChanged: (index) {
                    final newPage = index % _items.length;
                    if (newPage != _page) {
                      setState(() => _page = newPage);
                    }
                  },
                  itemBuilder: (context, index) {
                    final item = _items[index % _items.length];
                    final image = _image(item);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          HapticFeedbackUtil.selection();
                          openHeadlineTarget(context, widget.api, item);
                        },
                        child: CachedNetworkImage(
                          normalizeCoolapkImageUrl(image),
                          headers: coolapkImageHeaders(image, api: widget.api),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (isLoop)
              Positioned(
                right: 12,
                bottom: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Container(
                        width: 5.5,
                        height: 5.5,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: i == _page ? 1.0 : 0.45,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const List<Map<String, dynamic>> _defaultHeadlineCards = [
  {
    'entityTemplate': 'imageCarouselCard_1',
    'entityType': 'card',
    'entities': [
      {
        'title': '年轻人的第一辆车',
        'pic': 'https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg',
        'url': '/page?url=V9_CAR_CENTER',
      },
      {
        'title': '今日酷安',
        'pic': 'https://image.coolapk.com/feed/2024/0905/15/456889_1725522515_8218.jpg',
        'url': '/feed/headline',
      },
    ],
  },
  {
    'entityTemplate': 'iconLinkGridCard',
    'entityType': 'card',
    'entities': [
      {'title': '值得看', 'url': '/page?url=V8_ZHUANTI_20180327'},
      {'title': '热闻', 'url': '/page?url=V8_JINRI_NEWS'},
      {'title': '活动', 'url': '/page?url=V11_ACTIVITIES'},
      {'title': 'AI', 'url': '/page?url=V9_AI_ZONE'},
      {'title': '人像摄影', 'url': '/t/人像摄影'},
      {
        'title': '选机中心',
        'url': 'https://m.coolapk.com/mp/productSelector/configSearch?callFunction=indexSearch',
      },
      {'title': '玩机大神', 'url': '/page?url=V8_RECOMMEND_USER'},
      {'title': '投票', 'url': '#/feed/digestList?type=16&message_status=all'},
      {'title': '头条榜', 'url': '/page?url=V9_LISHITOUTIAO_NEW'},
      {
        'title': '官方频道',
        'url': '/page?url=V11_ZHUANTI_EDITORIALDEPARTMENT_20211117',
      },
    ],
  },
  {
    'entityTemplate': 'iconMiniScrollCard',
    'entityType': 'card',
    'entities': [
      {
        'title': 'vivo X300 Pro',
        'url': '/page?url=V9_SEARCH_PHONE&key=vivo+X300+Pro',
      },
      {'title': '真我Neo8', 'url': '/page?url=V9_SEARCH_PHONE&key=真我Neo8'},
      {'title': '小米17 Max', 'url': '/page?url=V9_SEARCH_PHONE&key=小米17+Max'},
      {
        'title': 'iPhone 16 Pro',
        'url': '/page?url=V9_SEARCH_PHONE&key=iPhone+16+Pro',
      },
      {'title': '一加13', 'url': '/page?url=V9_SEARCH_PHONE&key=一加13'},
      {
        'title': 'OPPO Find X8',
        'url': '/page?url=V9_SEARCH_PHONE&key=OPPO+Find+X8',
      },
    ],
  },
];

const List<Map<String, dynamic>> _defaultHotCards = [
  {
    'entityTemplate': 'iconLinkGridCard',
    'entityType': 'card',
    'entities': [
      {'title': '周榜', 'url': '#/feed/rankList?type=weekly'},
      {'title': '月榜', 'url': '#/feed/rankList?type=monthly'},
      {'title': '收藏榜', 'url': '#/feed/rankList?type=favorite'},
      {'title': '酷安指数', 'url': '/t/酷安指数'},
      {'title': '酷图榜', 'url': '#/feed/coolPictureRankList'},
    ],
  },
  {
    'entityTemplate': 'iconMiniGridCard',
    'entityType': 'card',
    'entities': [
      {
        'title': '荣耀Magic7',
        'tag': '荣耀Magic7',
        'pic': '',
        'url': '/t/荣耀Magic7',
        'targetType': 'topic',
      },
      {
        'title': '周鸿祎',
        'tag': '周鸿祎',
        'pic': '',
        'url': '/t/周鸿祎',
        'targetType': 'topic',
      },
      {
        'title': '华为Mate70',
        'tag': '华为Mate70',
        'pic': '',
        'url': '/t/华为Mate70',
        'targetType': 'topic',
      },
      {
        'title': '百瓦快充',
        'tag': '百瓦快充',
        'pic': '',
        'url': '/t/百瓦快充',
        'targetType': 'topic',
      },
      {
        'title': '苹果优惠',
        'tag': '苹果',
        'pic': '',
        'url': '/t/苹果',
        'targetType': 'topic',
      },
      {
        'title': '鸿蒙NEXT',
        'tag': '鸿蒙NEXT',
        'pic': '',
        'url': '/t/鸿蒙NEXT',
        'targetType': 'topic',
      },
    ],
  },
  {
    'entityTemplate': 'capsuleListCard',
    'entityType': 'card',
    'entities': [
      {'title': '薅羊毛'},
      {'title': '酷安小编'},
      {'title': '二手'},
      {'title': '微信'},
      {'title': '徕卡一瞬'},
      {'title': '一加13'},
      {'title': 'shizuku'},
      {'title': '临时root'},
      {'title': '一加'},
      {'title': 'iqoo15'},
    ],
  },
  {
    'entityTemplate': 'selectorLinkCard',
    'entityType': 'card',
    'entities': [
      {'title': '今日热门', 'url': '/page?url=V9_HOME_TAB_HOT'},
      {'title': '手机', 'url': '/page?url=V9_HOME_TAB_HOT_PHONE'},
      {'title': '系统', 'url': '/page?url=V9_HOME_TAB_HOT_SYSTEM'},
      {'title': '平板', 'url': '/page?url=V9_HOME_TAB_HOT_PAD'},
      {'title': '耳机', 'url': '/page?url=V9_HOME_TAB_HOT_EARPHONE'},
      {'title': '穿戴', 'url': '/page?url=V9_HOME_TAB_HOT_WEAR'},
    ],
  },
];

const List<Map<String, dynamic>> _defaultTutorialCards = [
  {
    'entityTemplate': 'image_1',
    'entityType': 'card',
    'title': '全站教程精选',
    'description': '酷安教程中心，收录各类玩机技巧。欢迎各位@全站教程精选 投送优质教程。',
    'pic': '',
  },
  {
    'entityTemplate': 'selectorLinkCard',
    'entityType': 'card',
    'entities': [
      {'title': '全部', 'url': '/page?url=V9_TUTORIAL_ALL'},
      {'title': '进阶', 'url': '/page?url=V9_TUTORIAL_ADVANCED'},
      {'title': '苹果', 'url': '/page?url=V9_TUTORIAL_APPLE'},
      {'title': 'PC', 'url': '/page?url=V9_TUTORIAL_PC'},
      {'title': '数码生活', 'url': '/page?url=V9_TUTORIAL_DIGITAL'},
    ],
  },
];

const List<Map<String, dynamic>> _defaultVideoCards = [
  {
    'entityTemplate': 'iconMiniLinkGridCard',
    'entityType': 'card',
    'entities': [
      {'title': '最新发布', 'url': '/page?url=V9_HOME_TAB_SHIPIN_LATEST'},
      {'title': '热门视频', 'url': '/page?url=V9_HOME_TAB_SHIPIN_HOT'},
      {'title': '发视频', 'url': '#/feed/create'},
    ],
  },
];

class HomeChannelCardsHeader extends StatelessWidget {
  const HomeChannelCardsHeader({
    required this.api,
    required this.cards,
    required this.channelId,
    required this.activeCategoryIndex,
    required this.onSelectCategory,
    super.key,
  });

  final CoolapkApi api;
  final List<Map<String, dynamic>> cards;
  final String channelId;
  final int activeCategoryIndex;
  final void Function(Map<String, dynamic> item, int index) onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final processedCards = <Map<String, dynamic>>[];

    for (final card in cards) {
      final template = (card['entityTemplate'] ?? card['entity_template'] ?? '')
          .toString();
      final entityType =
          (card['entityType'] ?? card['entity_type'] ?? card['type'] ?? '')
              .toString();
      final type = template.isNotEmpty ? template : entityType;
      if (type == 'feed' ||
          (card['entities'] is List &&
              (card['entities'] as List).isEmpty &&
              !type.contains('banner') &&
              type != 'image_1')) {
        continue;
      }
      processedCards.add(card);
    }

    if (channelId == 'headline') {
      final carouselCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t.startsWith('imageCarousel') ||
            t.startsWith('imageSquare') ||
            t == 'image_1' ||
            t == 'banner';
      }).toList();
      widgets.add(
        _HeadlineCarousel(
          api: api,
          cards: carouselCards.isNotEmpty
              ? carouselCards
              : _defaultHeadlineCards
                    .where((c) => c['entityTemplate'] == 'imageCarouselCard_1')
                    .toList(),
        ),
      );

      final gridCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'iconLinkGridCard' || t == 'iconGridCard';
      }).toList();
      final gridCard = gridCards.isNotEmpty
          ? gridCards.first
          : _defaultHeadlineCards.firstWhere(
              (c) => c['entityTemplate'] == 'iconLinkGridCard',
            );
      widgets.add(_ChannelIconGridCardTwoPage(api: api, card: gridCard));

      final scrollCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'iconMiniScrollCard' || t == 'miniScrollCard';
      }).toList();
      final scrollCard = scrollCards.isNotEmpty
          ? scrollCards.first
          : _defaultHeadlineCards.firstWhere(
              (c) => c['entityTemplate'] == 'iconMiniScrollCard',
            );
      widgets.add(_ChannelMiniScrollCard(api: api, card: scrollCard));
    } else if (channelId == 'hot') {
      final rankCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'iconLinkGridCard' || t == 'rankCard';
      }).toList();
      final rankCard = rankCards.isNotEmpty
          ? rankCards.first
          : _defaultHotCards.firstWhere(
              (c) => c['entityTemplate'] == 'iconLinkGridCard',
            );
      widgets.add(_ChannelIconGridCardSingleRow(api: api, card: rankCard));

      final newsCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'iconMiniGridCard' || t == 'miniGridCard';
      }).toList();
      final newsCard = newsCards.isNotEmpty
          ? newsCards.first
          : _defaultHotCards.firstWhere(
              (c) => c['entityTemplate'] == 'iconMiniGridCard',
            );
      widgets.add(_HotNewsMiniGridCard(api: api, card: newsCard));

      final capsuleCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'capsuleListCard' || t == 'capsuleCard';
      }).toList();
      final capsuleCard = capsuleCards.isNotEmpty
          ? capsuleCards.first
          : _defaultHotCards.firstWhere(
              (c) => c['entityTemplate'] == 'capsuleListCard',
            );
      widgets.add(_HotSearchCapsuleCard(api: api, card: capsuleCard));

      final selectorCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'selectorLinkCard' || t == 'tabLinkCard';
      }).toList();
      final selectorCard = selectorCards.isNotEmpty
          ? selectorCards.first
          : _defaultHotCards.firstWhere(
              (c) => c['entityTemplate'] == 'selectorLinkCard',
            );
      widgets.add(
        _ChannelSelectorLinkCard(
          card: selectorCard,
          activeIndex: activeCategoryIndex,
          onSelect: onSelectCategory,
        ),
      );
    } else if (channelId == 'tutorial') {
      final bannerCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'image_1' ||
            t.startsWith('imageCarousel') ||
            t == 'tutorialBanner';
      }).toList();
      final bannerCard = bannerCards.isNotEmpty
          ? bannerCards.first
          : _defaultTutorialCards.firstWhere(
              (c) => c['entityTemplate'] == 'image_1',
            );
      widgets.add(_TutorialBannerCard(api: api, card: bannerCard));

      final selectorCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'selectorLinkCard' || t == 'tabLinkCard';
      }).toList();
      final selectorCard = selectorCards.isNotEmpty
          ? selectorCards.first
          : _defaultTutorialCards.firstWhere(
              (c) => c['entityTemplate'] == 'selectorLinkCard',
            );
      widgets.add(
        _ChannelSelectorLinkCard(
          card: selectorCard,
          activeIndex: activeCategoryIndex,
          onSelect: onSelectCategory,
        ),
      );
    } else if (channelId == 'video') {
      final videoCards = processedCards.where((c) {
        final t = (c['entityTemplate'] ?? c['entityType'] ?? '').toString();
        return t == 'iconMiniLinkGridCard' || t == 'videoFilterBar';
      }).toList();
      final videoCard = videoCards.isNotEmpty
          ? videoCards.first
          : _defaultVideoCards.firstWhere(
              (c) => c['entityTemplate'] == 'iconMiniLinkGridCard',
            );
      widgets.add(
        _VideoFilterBar(
          api: api,
          card: videoCard,
          onFilterSelect: (url) {
            onSelectCategory({'url': url, 'title': '视频筛选'}, 0);
          },
        ),
      );
    } else {
      for (final card in processedCards) {
        final template =
            (card['entityTemplate'] ?? card['entity_template'] ?? '')
                .toString();
        final entityType =
            (card['entityType'] ?? card['entity_type'] ?? card['type'] ?? '')
                .toString();
        final type = template.isNotEmpty ? template : entityType;

        if (type.startsWith('imageCarouselCard') || type == 'image_1') {
          widgets.add(_HeadlineCarousel(api: api, cards: [card]));
        } else if (type == 'iconLinkGridCard') {
          widgets.add(_ChannelIconGridCardSingleRow(api: api, card: card));
        } else if (type == 'iconMiniScrollCard') {
          widgets.add(_ChannelMiniScrollCard(api: api, card: card));
        } else if (type == 'iconMiniGridCard') {
          widgets.add(_HotNewsMiniGridCard(api: api, card: card));
        } else if (type == 'capsuleListCard') {
          widgets.add(_HotSearchCapsuleCard(api: api, card: card));
        } else if (type == 'selectorLinkCard') {
          widgets.add(
            _ChannelSelectorLinkCard(
              card: card,
              activeIndex: activeCategoryIndex,
              onSelect: onSelectCategory,
            ),
          );
        } else if (type == 'iconMiniLinkGridCard') {
          widgets.add(
            _VideoFilterBar(
              api: api,
              card: card,
              onFilterSelect: (url) =>
                  onSelectCategory({'url': url, 'title': '筛选'}, 0),
            ),
          );
        }
      }
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}

class _ChannelIconGridCardTwoPage extends StatefulWidget {
  const _ChannelIconGridCardTwoPage({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  State<_ChannelIconGridCardTwoPage> createState() =>
      _ChannelIconGridCardTwoPageState();
}

class _ChannelIconGridCardTwoPageState
    extends State<_ChannelIconGridCardTwoPage> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final rawEntities = widget.card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final items = entities.isNotEmpty
        ? entities
        : _defaultHeadlineCards[1]['entities'] as List<Map<String, dynamic>>;

    final pageCount = (items.length / 5).ceil().clamp(1, 4);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 78,
            child: protectHorizontalDragFromVerticalRefresh(
              filterHorizontalScrollNotifications(
                PageView.builder(
                  itemCount: pageCount,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemBuilder: (context, pageIndex) {
                    final start = pageIndex * 5;
                    final end = (start + 5).clamp(0, items.length);
                    final pageItems = items.sublist(start, end);

                    return Row(
                      children: [
                        for (final item in pageItems)
                          Expanded(child: _buildGridItem(context, item)),
                        for (var i = 0; i < 5 - pageItems.length; i++)
                          const Expanded(child: SizedBox.shrink()),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (pageCount > 1) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: _currentPage == 0 ? 14 : 6,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: _currentPage == 0
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: _currentPage == 1 ? 14 : 6,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: _currentPage == 1
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final pic = (item['pic'] ?? item['icon'] ?? item['logo'] ?? '').toString();
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedbackUtil.selection();
        openHeadlineTarget(context, widget.api, item);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pic.isNotEmpty && !pic.endsWith('.gif'))
              CachedNetworkImage(
                normalizeCoolapkImageUrl(pic),
                headers: coolapkImageHeaders(pic, api: widget.api),
                width: 44,
                height: 44,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _solidIcon(title, scheme),
              )
            else
              _solidIcon(title, scheme),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _solidIcon(String title, ColorScheme scheme) {
    IconData icon = Icons.apps_rounded;
    Color bg = scheme.primary;
    if (title.contains('值得看')) {
      icon = Icons.verified_rounded;
      bg = const Color(0xFF2979FF);
    } else if (title.contains('热闻') || title.contains('新闻')) {
      icon = Icons.article_rounded;
      bg = const Color(0xFFFF9800);
    } else if (title.contains('活动')) {
      icon = Icons.local_activity_rounded;
      bg = const Color(0xFFFF4D4D);
    } else if (title.contains('AI')) {
      icon = Icons.smart_toy_rounded;
      bg = const Color(0xFF00B0FF);
    } else if (title.contains('摄影')) {
      icon = Icons.face_rounded;
      bg = const Color(0xFF00E5FF);
    } else if (title.contains('选机')) {
      icon = Icons.phone_android_rounded;
      bg = const Color(0xFF7C4DFF);
    } else if (title.contains('玩机') || title.contains('大神')) {
      icon = Icons.psychology_rounded;
      bg = const Color(0xFFFF4081);
    } else if (title.contains('投票')) {
      icon = Icons.how_to_vote_rounded;
      bg = const Color(0xFF536DFE);
    } else if (title.contains('榜')) {
      icon = Icons.leaderboard_rounded;
      bg = const Color(0xFFFF6D00);
    } else if (title.contains('频道')) {
      icon = Icons.campaign_rounded;
      bg = const Color(0xFF00C853);
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _ChannelIconGridCardSingleRow extends StatelessWidget {
  const _ChannelIconGridCardSingleRow({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final rawEntities = card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final items = entities.isNotEmpty
        ? entities
        : [
            {'title': '周榜', 'url': '/page?url=V9_WEEK_RANK'},
            {'title': '月榜', 'url': '/page?url=V9_MONTH_RANK'},
            {'title': '收藏榜', 'url': '/page?url=V9_FAV_RANK'},
            {'title': '酷安指数', 'url': '/page?url=V9_COOL_INDEX'},
            {'title': '酷图榜', 'url': '/page?url=V9_COOL_PICTURE_RANK'},
          ];

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ReviewCard(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              for (final item in items.take(5))
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedbackUtil.selection();
                      openHeadlineTarget(context, api, item);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildRankIcon(item, scheme),
                        const SizedBox(height: 6),
                        Text(
                          (item['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankIcon(Map<String, dynamic> item, ColorScheme scheme) {
    final title = (item['title'] ?? '').toString();
    final pic = (item['pic'] ?? item['icon'] ?? item['logo'] ?? '').toString();

    if (pic.isNotEmpty && !pic.endsWith('.gif')) {
      return CachedNetworkImage(
        normalizeCoolapkImageUrl(pic),
        headers: coolapkImageHeaders(pic, api: api),
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallbackRankIcon(title),
      );
    }
    return _fallbackRankIcon(title);
  }

  Widget _fallbackRankIcon(String title) {
    IconData icon = Icons.bar_chart_rounded;
    Color color = Colors.orange;
    if (title.contains('周榜')) {
      icon = Icons.thumb_up_rounded;
      color = const Color(0xFFFF5252);
    } else if (title.contains('月榜')) {
      icon = Icons.chat_bubble_rounded;
      color = const Color(0xFF00E5FF);
    } else if (title.contains('收藏')) {
      icon = Icons.star_rounded;
      color = const Color(0xFFFFB300);
    } else if (title.contains('指数')) {
      icon = Icons.show_chart_rounded;
      color = const Color(0xFF7C4DFF);
    } else if (title.contains('图')) {
      icon = Icons.bar_chart_rounded;
      color = const Color(0xFFFF6D00);
    }
    return Icon(icon, color: color, size: 36);
  }
}

class _ChannelMiniScrollCard extends StatelessWidget {
  const _ChannelMiniScrollCard({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final rawEntities = card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final items = entities.isNotEmpty
        ? entities
        : (_defaultHeadlineCards[2]['entities'] as List<Map<String, dynamic>>);

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 36,
        child: protectHorizontalDragFromVerticalRefresh(
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final title = (item['title'] ?? '').toString();
              final pic = (item['pic'] ?? item['icon'] ?? item['logo'] ?? '')
                  .toString();

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  HapticFeedbackUtil.selection();
                  openHeadlineTarget(context, api, item);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pic.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            normalizeCoolapkImageUrl(pic),
                            headers: coolapkImageHeaders(pic, api: api),
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.phone_android_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.phone_android_rounded,
                          size: 14,
                          color: scheme.primary,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HotNewsMiniGridCard extends StatefulWidget {
  const _HotNewsMiniGridCard({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  State<_HotNewsMiniGridCard> createState() => _HotNewsMiniGridCardState();
}

class _HotNewsMiniGridCardState extends State<_HotNewsMiniGridCard> {
  static final Map<String, String> _topicLogoCache = {};
  static final Set<String> _pendingTags = {};

  @override
  void initState() {
    super.initState();
    _fetchMissingLogos();
  }

  @override
  void didUpdateWidget(covariant _HotNewsMiniGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fetchMissingLogos();
  }

  List<Map<String, dynamic>> _getItems() {
    final rawEntities = widget.card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    return entities.isNotEmpty
        ? entities
        : (_defaultHotCards[1]['entities'] as List<Map<String, dynamic>>);
  }

  void _fetchMissingLogos() {
    final items = _getItems();
    for (var i = 0; i < items.length && i < 8; i++) {
      final item = items[i];
      final title = _extractItemTitle(item, i);
      final tag = _extractTopicTag(item, title);
      final pic = _extractItemPic(item);
      if (pic.isNotEmpty) {
        _topicLogoCache[tag] = pic;
        continue;
      }
      if (tag.isNotEmpty &&
          !_topicLogoCache.containsKey(tag) &&
          !_pendingTags.contains(tag)) {
        _pendingTags.add(tag);
        _resolveTopicLogo(tag);
      }
    }
  }

  Future<void> _resolveTopicLogo(String tag) async {
    try {
      final response = await widget.api.getTopicDetail(tag);
      final data = response['data'];
      final detail = data is Map ? Map<String, dynamic>.from(data) : response;
      var logo =
          (detail['logo'] ??
                  detail['icon'] ??
                  detail['pic'] ??
                  detail['avatar'] ??
                  '')
              .toString()
              .trim();
      if (logo.isEmpty) {
        final searchRes = await widget.api.search(tag, 'topic', 1);
        if (searchRes.items.isNotEmpty) {
          final first = searchRes.items.first;
          logo =
              (first['logo'] ??
                      first['icon'] ??
                      first['pic'] ??
                      first['avatar'] ??
                      '')
                  .toString()
                  .trim();
        }
      }
      if (logo.isNotEmpty) {
        _topicLogoCache[tag] = logo;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Graceful fallback
    } finally {
      _pendingTags.remove(tag);
    }
  }

  static String _extractItemPic(Map<String, dynamic> item) {
    for (final key in [
      'pic',
      'logo',
      'icon',
      'image',
      'cover',
      'tagLogo',
      'tag_logo',
      'tagPic',
      'tag_pic',
      'subPic',
      'sub_pic',
      'userAvatar',
      'user_avatar',
      'userSmallAvatar',
    ]) {
      final val = (item[key] ?? '').toString().trim();
      if (val.isNotEmpty && !val.endsWith('.gif')) return val;
    }
    final targetRow = item['target_row'] ?? item['targetRow'];
    if (targetRow is Map) {
      for (final key in ['pic', 'logo', 'icon', 'image', 'cover', 'tagLogo']) {
        final val = (targetRow[key] ?? '').toString().trim();
        if (val.isNotEmpty && !val.endsWith('.gif')) return val;
      }
    }
    final extraData = item['extraData'] ?? item['extra_data'];
    if (extraData is Map) {
      for (final key in ['pic', 'logo', 'icon', 'image', 'cover', 'tagLogo']) {
        final val = (extraData[key] ?? '').toString().trim();
        if (val.isNotEmpty && !val.endsWith('.gif')) return val;
      }
    }
    return '';
  }

  static String _extractItemTitle(Map<String, dynamic> item, int index) {
    var title =
        (item['title'] ??
                item['entityTitle'] ??
                item['tag'] ??
                item['name'] ??
                item['text'] ??
                item['subTitle'] ??
                '')
            .toString()
            .trim();
    if (title.isEmpty) {
      final url = (item['url'] ?? item['href'] ?? '').toString();
      if (url.contains('/t/')) {
        final sub = url
            .substring(url.indexOf('/t/') + 3)
            .split('?')
            .first
            .split('/')
            .first;
        try {
          title = Uri.decodeComponent(sub);
        } catch (_) {
          title = sub;
        }
      } else if (url.contains('tag=')) {
        final parsed = Uri.tryParse(url);
        title = parsed?.queryParameters['tag'] ?? '';
      }
    }
    final defaultList =
        _defaultHotCards[1]['entities'] as List<Map<String, dynamic>>;
    if (title.isEmpty && index >= 0 && index < defaultList.length) {
      title = (defaultList[index]['title'] ?? '').toString();
    }
    return title;
  }

  static String _extractTopicTag(Map<String, dynamic> item, String title) {
    var tag = (item['tag'] ?? item['target_tag'] ?? item['topic'] ?? '')
        .toString()
        .trim();
    if (tag.isNotEmpty) return tag.replaceAll('#', '').trim();

    final url = (item['url'] ?? item['href'] ?? item['target_url'] ?? '')
        .toString()
        .trim();
    if (url.contains('/t/')) {
      var sub = url.substring(url.indexOf('/t/') + 3);
      if (sub.contains('?')) sub = sub.substring(0, sub.indexOf('?'));
      if (sub.contains('/')) sub = sub.substring(0, sub.indexOf('/'));
      try {
        tag = Uri.decodeComponent(sub);
      } catch (_) {
        tag = sub;
      }
      if (tag.isNotEmpty) return tag.replaceAll('#', '').trim();
    }
    if (url.contains('tag=')) {
      final parsed = Uri.tryParse(
        url.startsWith('/') ? 'https://coolapk.com$url' : url,
      );
      final qTag = parsed?.queryParameters['tag'] ?? '';
      if (qTag.isNotEmpty) return qTag.replaceAll('#', '').trim();
    }

    final targetRow = item['target_row'] ?? item['targetRow'];
    if (targetRow is Map) {
      final rTag = (targetRow['tag'] ?? targetRow['title'] ?? '')
          .toString()
          .trim();
      if (rTag.isNotEmpty) return rTag.replaceAll('#', '').trim();
    }

    if (title.contains('#')) {
      final match = RegExp(r'#([^#]+)#').firstMatch(title);
      if (match != null && match.group(1) != null) {
        return match.group(1)!.trim();
      }
    }

    final cleanTitle = title.replaceAll('#', '').trim();
    for (final keyword in [
      '荣耀WIN2',
      '荣耀Magic',
      '荣耀',
      '华为Mate',
      '华为',
      '苹果',
      'iPhone',
      'iPad',
      '小米',
      'Redmi',
      '红米',
      'OPPO',
      'vivo',
      'iQOO',
      '一加',
      '魅族',
      '三星',
      '周鸿祎',
      '鸿蒙',
      '快充',
      '芯片',
      '高通',
      '联发科',
      '英伟达',
      'AI',
      '手机',
      '数码',
    ]) {
      if (cleanTitle.toLowerCase().contains(keyword.toLowerCase())) {
        return keyword;
      }
    }

    if (cleanTitle.length > 6) {
      return cleanTitle.substring(0, 4);
    }
    return cleanTitle;
  }

  static Widget _buildFallbackTopicIcon(String title, ColorScheme scheme) {
    final hash = title.hashCode.abs();
    final colors = [
      const Color(0xFF00B0FF),
      const Color(0xFF00E676),
      const Color(0xFFFF5252),
      const Color(0xFFFF9100),
      const Color(0xFF7C4DFF),
      const Color(0xFFFF4081),
      const Color(0xFF00BFA5),
      const Color(0xFFFFAB00),
    ];
    final accentColor = colors[hash % colors.length];

    String char = '#';
    final clean = title.replaceAll('#', '').trim();
    if (clean.isNotEmpty) {
      final first = clean.substring(0, 1);
      if (RegExp(r'[a-zA-Z0-9]').hasMatch(first)) {
        char = first.toUpperCase();
      } else {
        char = first;
      }
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        char,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: accentColor,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItems();
    final scheme = Theme.of(context).colorScheme;
    final rowCount = ((items.length) / 2).ceil().clamp(1, 4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ReviewCard(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rowCount; r++) ...[
                if (r > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    if (r * 2 < items.length)
                      Expanded(
                        child: _buildCell(context, items[r * 2], scheme, r * 2),
                      ),
                    const SizedBox(width: 12),
                    if (r * 2 + 1 < items.length)
                      Expanded(
                        child: _buildCell(
                          context,
                          items[r * 2 + 1],
                          scheme,
                          r * 2 + 1,
                        ),
                      )
                    else
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context,
    Map<String, dynamic> item,
    ColorScheme scheme,
    int index,
  ) {
    final title = _extractItemTitle(item, index);
    final tag = _extractTopicTag(item, title);
    var pic = _extractItemPic(item);
    if (pic.isEmpty && _topicLogoCache.containsKey(tag)) {
      pic = _topicLogoCache[tag] ?? '';
    }

    final targetItem = Map<String, dynamic>.from(item);
    if ((targetItem['title'] ?? '').toString().isEmpty) {
      targetItem['title'] = title;
    }
    if ((targetItem['tag'] ?? '').toString().isEmpty) {
      targetItem['tag'] = tag.isNotEmpty ? tag : title;
    }
    if (pic.isNotEmpty && (targetItem['pic'] ?? '').toString().isEmpty) {
      targetItem['pic'] = pic;
      targetItem['logo'] = pic;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedbackUtil.selection();
        openHeadlineTarget(context, widget.api, targetItem);
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: pic.isNotEmpty
                ? CachedNetworkImage(
                    normalizeCoolapkImageUrl(pic),
                    headers: coolapkImageHeaders(pic, api: widget.api),
                    width: 26,
                    height: 26,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildFallbackTopicIcon(title, scheme),
                  )
                : _buildFallbackTopicIcon(title, scheme),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HotSearchCapsuleCard extends StatelessWidget {
  const _HotSearchCapsuleCard({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final rawEntities = card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final items = entities.isNotEmpty
        ? entities
        : (_defaultHotCards[2]['entities'] as List<Map<String, dynamic>>);

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ReviewCard(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: protectHorizontalDragFromVerticalRefresh(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedbackUtil.selection();
                      final query = (item['title'] ?? '').toString();
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SearchPage(api: api, initialQuery: query),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        (item['title'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
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

class _ChannelSelectorLinkCard extends StatelessWidget {
  const _ChannelSelectorLinkCard({
    required this.card,
    required this.activeIndex,
    required this.onSelect,
  });

  final Map<String, dynamic> card;
  final int activeIndex;
  final void Function(Map<String, dynamic> item, int index) onSelect;

  @override
  Widget build(BuildContext context) {
    final rawEntities = card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    if (entities.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 38,
        child: protectHorizontalDragFromVerticalRefresh(
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: entities.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = entities[index];
              final title = (item['title'] ?? '').toString();
              final isSelected = index == activeIndex;

              return InkWell(
                borderRadius: BorderRadius.circular(19),
                onTap: () {
                  HapticFeedbackUtil.selection();
                  onSelect(item, index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary
                        : scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                    borderRadius: BorderRadius.circular(19),
                    border: isSelected
                        ? null
                        : Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.2),
                            width: 0.6,
                          ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? scheme.onPrimary : scheme.onSurface,
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
}

class _TutorialBannerCard extends StatelessWidget {
  const _TutorialBannerCard({required this.api, required this.card});

  final CoolapkApi api;
  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final pic = (card['pic'] ?? card['image'] ?? card['cover'] ?? '')
        .toString();
    final entities = (card['entities'] is List)
        ? (card['entities'] as List)
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList()
        : <Map<String, dynamic>>[];
    final image = pic.isNotEmpty
        ? pic
        : (entities.isNotEmpty
              ? (entities.first['pic'] ?? entities.first['image'] ?? '')
                    .toString()
              : '');
    final description =
        (card['description'] ??
                card['subTitle'] ??
                '酷安教程中心，收录各类玩机技巧。欢迎各位@全站教程精选 投送优质教程。')
            .toString();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ReviewCard(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 3.2,
                child: image.isNotEmpty
                    ? CachedNetworkImage(
                        normalizeCoolapkImageUrl(image),
                        headers: coolapkImageHeaders(image, api: api),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _defaultTutorialGraphic(scheme),
                      )
                    : _defaultTutorialGraphic(scheme),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultTutorialGraphic(ColorScheme scheme) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00B4D8), Color(0xFF48CAE4), Color(0xFF90E0EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '全站教程精选',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0077B6),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0077B6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '收获玩机乐趣',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoFilterBar extends StatelessWidget {
  const _VideoFilterBar({
    required this.api,
    required this.card,
    required this.onFilterSelect,
  });

  final CoolapkApi api;
  final Map<String, dynamic> card;
  final void Function(String url) onFilterSelect;

  @override
  Widget build(BuildContext context) {
    final rawEntities = card['entities'];
    final entities = (rawEntities is List)
        ? rawEntities.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];

    final items = entities.isNotEmpty
        ? entities
        : _defaultVideoCards.first['entities'] as List<Map<String, dynamic>>;

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ReviewCard(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final item in items.take(3))
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    HapticFeedbackUtil.selection();
                    final title = (item['title'] ?? '').toString();
                    if (title.contains('发视频')) {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ComposeFeedPage(api: api),
                        ),
                      );
                    } else {
                      final url = (item['url'] ?? '').toString();
                      if (url.isNotEmpty) {
                        onFilterSelect(url);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilterIcon(item),
                        const SizedBox(width: 6),
                        Text(
                          (item['title'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterIcon(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    if (title.contains('最新')) {
      return const Icon(
        Icons.explore_rounded,
        color: Color(0xFF7C4DFF),
        size: 18,
      );
    } else if (title.contains('热门')) {
      return const Icon(
        Icons.local_fire_department_rounded,
        color: Color(0xFFFF9100),
        size: 18,
      );
    } else if (title.contains('发视频') || title.contains('发布')) {
      return const Icon(
        Icons.videocam_rounded,
        color: Color(0xFFFF5252),
        size: 18,
      );
    }
    return const Icon(Icons.play_circle_outline_rounded, size: 18);
  }
}

void openHeadlineTarget(
  BuildContext context,
  CoolapkApi api,
  Map<String, dynamic> item,
) {
  var title =
      (item['title'] ??
              item['entityTitle'] ??
              item['tag'] ??
              item['name'] ??
              item['text'] ??
              item['subTitle'] ??
              '')
          .toString()
          .trim();
  final value =
      (item['url'] ??
              item['href'] ??
              item['goods_url'] ??
              item['goods_buy_url'] ??
              '')
          .toString()
          .trim();
  if (title.isEmpty && value.contains('/t/')) {
    final sub = value
        .substring(value.indexOf('/t/') + 3)
        .split('?')
        .first
        .split('/')
        .first;
    try {
      title = Uri.decodeComponent(sub);
    } catch (_) {
      title = sub;
    }
  } else if (title.isEmpty && value.contains('tag=')) {
    final parsed = Uri.tryParse(value);
    title = parsed?.queryParameters['tag'] ?? '';
  }
  final entityType = (item['entityType'] ?? item['entity_type'] ?? '')
      .toString()
      .toLowerCase();
  final targetType = (item['targetType'] ?? item['target_type'] ?? '')
      .toString()
      .toLowerCase();
  final pic =
      (item['pic'] ??
              item['image'] ??
              item['cover'] ??
              item['logo'] ??
              item['icon'] ??
              '')
          .toString()
          .trim();

  if (openHomeDestination(context, api, title, value)) return;
  if (title == '人像摄影' || value.contains('V9_PORTRAIT_PHOTO')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TopicPage(api: api, tag: '人像摄影', initialTitle: '人像摄影'),
      ),
    );
    return;
  }

  final activityUri = activityGoodsUrl(item) ?? Uri.tryParse(value);
  if (activityUri != null && isOfficialActivityDocument(activityUri)) {
    openActivityDocument(
      context,
      api,
      activityUri,
      title: title.isEmpty ? '活动详情' : title,
    );
    return;
  }

  if (value.isEmpty) {
    if (title.isNotEmpty) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(
            api: api,
            tag: title.replaceAll('#', '').trim(),
            initialTitle: title,
            initialLogo: pic.isNotEmpty ? pic : null,
            initialCover: pic.isNotEmpty ? pic : null,
          ),
        ),
      );
    }
    return;
  }

  if (title == '发视频' ||
      value.contains('feed/create') ||
      value.contains('feed/compose')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ComposeFeedPage(api: api)),
    );
    return;
  }

  var route = value;
  if (route.startsWith('#')) {
    route = route.substring(1);
  }

  // 1. Topic tag recognition (User: "热榜点进去是空的，正常来说，热榜它其实就是一个话题，点进去应该是对应话题的内容")
  final isTopic =
      entityType == 'topic' ||
      entityType == 'tag' ||
      targetType == 'topic' ||
      route.contains('/t/') ||
      route.contains('/topic/') ||
      route.contains('tag=') ||
      route.contains('V9_NEWS_');

  if (isTopic) {
    var tag = ApiEntityCard.extractTopicTag({...item, 'url': route});
    if (tag.isEmpty) {
      tag = title.replaceAll('#', '').trim();
    }
    tag = tag.replaceAll('#', '').trim();
    if (tag.isNotEmpty) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(
            api: api,
            tag: tag,
            initialTitle: tag,
            initialLogo: pic.isNotEmpty ? pic : null,
            initialCover: pic.isNotEmpty ? pic : null,
          ),
        ),
      );
      return;
    }
  }

  if (value.startsWith('#/') &&
      !value.contains('/rankList') &&
      !value.contains('coolPictureRankList')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isEmpty ? '酷安内容' : title,
          path: '/v6/page/dataList',
          query: {'url': value},
        ),
      ),
    );
    return;
  }

  // 2. Rank List routes
  if (route.contains('coolPictureRankList') || title.contains('酷图')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isNotEmpty ? title : '酷图榜',
          path: '/v6/feed/coolPictureRankList',
        ),
      ),
    );
    return;
  }

  if (route.contains('rankList') || route.contains('RANK')) {
    final parsed = Uri.tryParse(
      route.startsWith('/') ? 'https://coolapk.com$route' : route,
    );
    final type =
        parsed?.queryParameters['type'] ??
        (title.contains('月')
            ? 'monthly'
            : (title.contains('收藏') ? 'favorite' : 'weekly'));
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isNotEmpty ? title : '榜单',
          path: '/v6/feed/rankList',
          query: {'type': type},
        ),
      ),
    );
    return;
  }

  // 3. Search routes
  if (route.startsWith('searchTab://') ||
      route.contains('search?key=') ||
      route.contains('search?keywords=') ||
      route.contains('search?searchValue=')) {
    final uri = Uri.tryParse(route);
    final query =
        uri?.queryParameters['key'] ??
        uri?.queryParameters['keywords'] ??
        uri?.queryParameters['searchValue'] ??
        title;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SearchPage(api: api, initialQuery: query),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(route);
  if (uri == null) return;

  final path = uri.path;

  if (path.startsWith('/clickUrl/')) {
    launchUrl(
      uri.replace(scheme: 'https', host: 'api.coolapk.com'),
      mode: LaunchMode.externalApplication,
    );
    return;
  }

  if (path.startsWith('/event/')) {
    final id = path.substring('/event/'.length).split('/').first;
    if (int.tryParse(id) != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EventDetailPage(api: api, id: id),
        ),
      );
      return;
    }
  }

  if (path == '/feed/headline' || path == '/v6/main/headline') {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isNotEmpty ? title : '今日酷安',
          path: '/v6/main/headline',
          query: uri.queryParameters,
        ),
      ),
    );
    return;
  }

  if (path.startsWith('/feed/')) {
    final segments = path.substring('/feed/'.length).split('/');
    final feedId = segments.first.split('?').first;
    if (feedId.isNotEmpty && int.tryParse(feedId) != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FeedDetailPage(
            api: api,
            feed: CoolapkFeed(
              id: feedId,
              username: (item['username'] ?? title).toString(),
              avatar: (item['userAvatar'] ?? pic).toString(),
              message: (item['message'] ?? title).toString(),
              date: '',
              likeCount: '0',
              replyCount: '0',
              pictures: const [],
              raw: item,
            ),
          ),
        ),
      );
      return;
    }
  }

  if (path.startsWith('/product/') || targetType == 'product') {
    var productId = (item['id'] ?? '').toString();
    if (productId.isEmpty && path.startsWith('/product/')) {
      productId = path.substring('/product/'.length).split('?').first;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProductPage(api: api, id: productId, title: title),
      ),
    );
    return;
  }

  if (path.startsWith('/dyh/') || targetType.contains('dyh')) {
    var dyhId = (item['id'] ?? '').toString();
    if (dyhId.isEmpty && path.startsWith('/dyh/')) {
      dyhId = path.substring('/dyh/'.length).split('?').first;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DyhPage(api: api, id: dyhId, title: title),
      ),
    );
    return;
  }

  if (path.startsWith('/u/') || path.startsWith('/user/')) {
    final uid = path.replaceFirst(RegExp(r'^/u(?:ser)?/'), '').split('/').first;
    if (uid.isNotEmpty) {
      _openUserSpace(context, api, uid);
      return;
    }
  }

  if (path.startsWith('/page?') ||
      path == '/page' ||
      path == '/page/dataList') {
    final pageUrl = uri.queryParameters['url'] ?? '';
    if (pageUrl.startsWith('V9_NEWS_') ||
        pageUrl.contains('tag=') ||
        pageUrl.contains('/t/')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(
            api: api,
            tag: title.replaceAll('#', '').trim(),
            initialTitle: title,
            initialLogo: pic.isNotEmpty ? pic : null,
            initialCover: pic.isNotEmpty ? pic : null,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isNotEmpty ? title : '酷安内容',
          path: '/v6/page/dataList',
          query: uri.queryParameters,
        ),
      ),
    );
    return;
  }

  if (path.startsWith('/v6/')) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiListPage(
          api: api,
          title: title.isNotEmpty ? title : '酷安内容',
          path: path,
          query: uri.queryParameters,
        ),
      ),
    );
    return;
  }

  if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }

  // Fallback: If title exists, open topic or search instead of dead end
  if (title.isNotEmpty) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TopicPage(
          api: api,
          tag: title.replaceAll('#', '').trim(),
          initialTitle: title,
          initialLogo: pic.isNotEmpty ? pic : null,
          initialCover: pic.isNotEmpty ? pic : null,
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({required this.api, this.initialQuery, super.key});

  final CoolapkApi api;
  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  final _feeds = <CoolapkFeed>[];
  final _bufferedFeeds = <CoolapkFeed>[];
  String _query = '';
  String? _error;
  int _page = 0;
  bool _busy = false;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      final q = widget.initialQuery!.trim();
      _queryController.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(q);
      });
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (_bufferedFeeds.isNotEmpty) {
      if (pos.extentAfter < 900 || pos.pixels >= pos.maxScrollExtent * 0.45) {
        setState(() {
          _feeds.addAll(_bufferedFeeds);
          _bufferedFeeds.clear();
        });
      }
    }
    if (_bufferedFeeds.isEmpty && pos.extentAfter < 520) {
      _loadMore();
    }
  }

  Future<void> _submit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _query = query;
      _page = 0;
      _hasMore = true;
      _error = null;
      _feeds.clear();
      _bufferedFeeds.clear();
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_busy || _query.isEmpty) return;
    if (_bufferedFeeds.isNotEmpty) {
      setState(() {
        _feeds.addAll(_bufferedFeeds);
        _bufferedFeeds.clear();
      });
      return;
    }
    if (!_hasMore) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextPage = _page + 1;
      final result = await widget.api.searchFeeds(_query, nextPage);
      if (!mounted) return;
      setState(() {
        final existingIds = <String>{
          ..._feeds.map((feed) => feed.id),
          ..._bufferedFeeds.map((feed) => feed.id),
        };
        final newItems = result.items.where((feed) => existingIds.add(feed.id)).toList();
        if (newItems.length <= 4) {
          _feeds.addAll(newItems);
        } else {
          final stage1Count = (newItems.length * 0.6).round().clamp(1, newItems.length);
          _feeds.addAll(newItems.take(stage1Count));
          _bufferedFeeds.addAll(newItems.skip(stage1Count));
        }
        _page = nextPage;
        _hasMore = result.hasMore;
        if (result.items.isEmpty && _bufferedFeeds.isEmpty) _hasMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _bufferedFeeds.isEmpty) return;
        if (_scrollController.hasClients &&
            (_scrollController.position.maxScrollExtent <= 0 ||
             _scrollController.position.extentAfter < 500)) {
          setState(() {
            _feeds.addAll(_bufferedFeeds);
            _bufferedFeeds.clear();
          });
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canPop = Navigator.of(context).canPop();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              Expanded(
                child: SearchBar(
                  controller: _queryController,
                  hintText: '搜索酷安动态',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_queryController.text.isNotEmpty)
                      IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          _queryController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                  onSubmitted: _submit,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildResults()),
      ],
    );
    if (canPop) {
      return Scaffold(body: SafeArea(child: content));
    }
    return content;
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return const Center(child: Text('输入关键词，搜索酷安动态'));
    }
    if (_feeds.isEmpty && _busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_feeds.isEmpty && _error != null) {
      return _LoadError(message: _error!, onRetry: _loadMore);
    }
    if (_feeds.isEmpty) {
      return const Center(child: Text('没有找到相关动态'));
    }
    return EasyRefresh(
      header: reviewDefaultRefreshHeader,
      onRefresh: () => _submit(_query),
      child: filterHorizontalScrollNotifications(
        ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
          padding: EdgeInsets.fromLTRB(
            0,
            6,
            0,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: _feeds.length + 1,
          itemBuilder: (context, index) {
            if (index == _feeds.length) {
              if (_error != null) {
                return TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('加载失败，点击重试：$_error'),
                );
              }
              if (_busy) {
                return const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return const SizedBox(height: 12);
            }
            return FeedCard(
              key: ValueKey('feed-${_feeds[index].id}'),
              api: widget.api,
              feed: _feeds[index],
            );
          },
        ),
      ),
    );
  }
}

class _OfficialFeedMessage extends StatelessWidget {
  const _OfficialFeedMessage({
    required this.api,
    required this.text,
    required this.style,
    required this.lines,
    required this.onMore,
  });
  final CoolapkApi api;
  final String text;
  final TextStyle style;
  final int lines;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: lines,
      )..layout(maxWidth: constraints.maxWidth);
      if (!painter.didExceedMaxLines) {
        painter.dispose();
        return CoolapkRichText(api: api, text: text, style: style);
      }
      final linkStyle = style.copyWith(color: const Color(0xFF009688));
      final link = TextPainter(
        text: TextSpan(text: '…查看更多', style: linkStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      final last = painter.computeLineMetrics().last;
      final end = painter
          .getPositionForOffset(
            Offset(
              (constraints.maxWidth - link.width).clamp(
                0,
                constraints.maxWidth,
              ),
              last.baseline - last.ascent / 2,
            ),
          )
          .offset
          .clamp(0, text.length);
      painter.dispose();
      link.dispose();
      return CoolapkRichText(
        api: api,
        text: text.substring(0, end).trimRight(),
        style: style,
        suffixSpans: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              onTap: onMore,
              child: Text('…查看更多', style: linkStyle),
            ),
          ),
        ],
      );
    },
  );
}

class FeedCard extends StatefulWidget {
  const FeedCard({
    required this.api,
    required this.feed,
    this.isDetail = false,
    this.rankNumber,
    this.isHeadline = false,
    this.officialLayout = false,
    this.articleLayout = false,
    this.editorialCover = false,
    this.picturesBeforeText = false,
    this.authorHeader,
    this.body,
    super.key,
  });
  final CoolapkApi api;
  final CoolapkFeed feed;
  final bool isDetail;
  final int? rankNumber;
  final bool isHeadline;
  final bool officialLayout;
  final bool articleLayout;
  final bool editorialCover;
  final bool picturesBeforeText;
  final Widget? authorHeader;
  final Widget? body;
  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> with AutomaticKeepAliveClientMixin {
  late bool _liked = widget.feed.liked;
  late int _likes = int.tryParse(widget.feed.likeCount) ?? 0;
  late bool _favorited = _extractFavorited(widget.api, widget.feed);
  late String _articleCover = _extractArticleCover(widget.feed);
  late String _articleSummary = _extractArticleSummary(widget.feed);
  late _FeedVideoInfo? _videoInfo = _extractFeedVideo(widget.feed);
  bool _working = false;

  @override
  bool get wantKeepAlive => true;

  static bool _extractFavorited(CoolapkApi api, CoolapkFeed feed) {
    try {
      if (api.isAnonymous) {
        return api.localAccount.favorites.containsKey(feed.id);
      }
    } catch (_) {}
    return feed.favorited;
  }

  static String _extractArticleCover(CoolapkFeed feed) {
    for (final key in [
      'message_cover',
      'cover',
      'coverPic',
      'cover_pic',
      'extra_pic',
      'header_image',
      'pic',
    ]) {
      final rawVal = feed.raw[key];
      if (rawVal != null) {
        final s = rawVal.toString().trim();
        if (s.isNotEmpty) {
          final first = s.split(',').first.trim();
          if (first.isNotEmpty &&
              (first.startsWith('http://') ||
                  first.startsWith('https://') ||
                  first.startsWith('//') ||
                  first.startsWith('/'))) {
            return first;
          }
        }
      }
    }
    if (feed.pictures.isNotEmpty) {
      return feed.pictures.first;
    }
    return '';
  }

  static String _extractArticleSummary(CoolapkFeed feed) {
    final feedTitle = (feed.raw['title'] ?? '').toString().trim();
    for (final key in ['description', 'subTitle', 'intro', 'summary']) {
      final val = feed.raw[key];
      if (val != null) {
        var s = val.toString().trim();
        if (s.isNotEmpty && s != feedTitle) {
          s = html.parse(s).body?.text.trim() ?? s;
          if (feedTitle.isNotEmpty && s.startsWith(feedTitle)) {
            s = s.substring(feedTitle.length).trim();
          }
          if (s.isNotEmpty) return s;
        }
      }
    }
    var msg = feed.message.trim();
    if (feedTitle.isNotEmpty && msg.startsWith(feedTitle)) {
      msg = msg.substring(feedTitle.length).trim();
    }
    msg = msg.replaceAll(RegExp(r'^#+\s*.*?\n'), '').trim();
    return msg;
  }

  @override
  void didUpdateWidget(covariant FeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed != widget.feed) {
      _liked = widget.feed.liked;
      _likes = int.tryParse(widget.feed.likeCount) ?? 0;
      _favorited = _extractFavorited(widget.api, widget.feed);
      _articleCover = _extractArticleCover(widget.feed);
      _articleSummary = _extractArticleSummary(widget.feed);
      _videoInfo = _extractFeedVideo(widget.feed);
    }
  }

  Future<void> _openDetail() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => FeedDetailPage(api: widget.api, feed: widget.feed),
    ),
  );
  Future<void> _like() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.api.likeFeed(widget.feed.id, liked: _liked);
      if (mounted) {
        setState(() {
          _likes = (_likes + (_liked ? -1 : 1)).clamp(0, 1 << 31);
          _liked = !_liked;
        });
      }
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _forward() async {
    if (_working) return;
    var draft = '';
    final message = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转发动态'),
        content: TextField(
          onChanged: (value) => draft = value,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '说点什么…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('转发'),
          ),
        ],
      ),
    );
    if (!mounted || message == null) return;
    setState(() => _working = true);
    try {
      await widget.api.forwardFeed(widget.feed.id, message.trim());
      if (mounted) AppToast.show(context, '已提交转发');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.api.favoriteFeed(
        widget.feed.id,
        favorited: _favorited,
        feed: widget.feed,
      );
      if (mounted) {
        setState(() => _favorited = !_favorited);
        AppToast.show(context, _favorited ? '已添加至收藏' : '已取消收藏');
      }
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showFeedMoreActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final feedId = widget.feed.id;
    final shareUrl = 'https://www.coolapk.com/feed/$feedId';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 第一行：灰底圆形按钮 [收藏, 屏蔽, 举报]
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildSheetCircleAction(
                            key: const ValueKey('action-favorite'),
                            isDark: isDark,
                            isGreen: false,
                            icon: _favorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            iconColor: _favorited
                                ? Colors.amber
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : const Color(0xFF333333)),
                            label: _favorited ? '已收藏' : '收藏',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _toggleFavorite();
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-block'),
                            isDark: isDark,
                            isGreen: false,
                            icon: Icons.visibility_off_outlined,
                            label: '屏蔽',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '已屏蔽该动态，减少类似推荐');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-report'),
                            isDark: isDark,
                            isGreen: false,
                            icon: Icons.crisis_alert_outlined,
                            label: '举报',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '已收到举报，我们将尽快核实处理');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 第二行：绿底圆形按钮 [推荐上头条]
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildSheetCircleAction(
                            key: const ValueKey('action-recommend-headline'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.military_tech_outlined,
                            iconSize: 26,
                            label: '推荐上头条',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '已推荐上头条');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 第三行：绿底横向滑动 [动态, 私信, 生成分享图, 看看号, 微信, 朋友圈, QQ, 复制链接, 更多]
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-feed'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.edit_note_rounded,
                            iconSize: 26,
                            label: '动态',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _forward();
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-message'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.mail_outline_rounded,
                            label: '私信',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '请在消息列表中选择要分享的好友');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-poster'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.image_outlined,
                            label: '生成分享图',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '正在生成卡片分享图...');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-kankan'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.podcasts_outlined,
                            label: '看看号',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              AppToast.show(context, '已分享至看看号');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-wechat'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.chat_bubble_rounded,
                            label: '微信',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: shareUrl),
                                ),
                              );
                              AppToast.show(context, '已复制动态链接，可前往微信粘贴分享');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-moments'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.motion_photos_on_outlined,
                            label: '朋友圈',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: shareUrl),
                                ),
                              );
                              AppToast.show(context, '已复制动态链接，可前往朋友圈粘贴分享');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-qq'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.forum_outlined,
                            label: 'QQ',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: shareUrl),
                                ),
                              );
                              AppToast.show(context, '已复制动态链接，可前往QQ粘贴分享');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-copy-link'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.link_rounded,
                            label: '复制链接',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: shareUrl),
                                ),
                              );
                              AppToast.show(context, '动态链接已复制到剪贴板');
                            },
                          ),
                          const SizedBox(width: 20),
                          _buildSheetCircleAction(
                            key: const ValueKey('action-share-more'),
                            isDark: isDark,
                            isGreen: true,
                            icon: Icons.more_horiz_rounded,
                            label: '更多',
                            onTap: () {
                              Navigator.pop(sheetContext);
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: shareUrl),
                                ),
                              );
                              AppToast.show(context, '已复制动态链接');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 底部取消按钮
                    InkWell(
                      key: const ValueKey('action-sheet-cancel'),
                      onTap: () => Navigator.pop(sheetContext),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        alignment: Alignment.center,
                        child: Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.85)
                                : const Color(0xFF333333),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetCircleAction({
    Key? key,
    required bool isDark,
    required bool isGreen,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    double iconSize = 24,
  }) {
    final bgColor = isGreen
        ? (isDark ? const Color(0xFF1B3D2F) : const Color(0xFFE2F7EB))
        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2));
    final defaultIconColor = isGreen
        ? const Color(0xFF00C06D)
        : (isDark
            ? Colors.white.withValues(alpha: 0.85)
            : const Color(0xFF333333));
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF555555);

    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor ?? defaultIconColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCommentBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _openQuickReply,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Builder(
                builder: (_) {
                  String avatarUrl = '';
                  try {
                    avatarUrl = widget.api.currentUserAvatar;
                  } catch (_) {}
                  return AppAvatar(api: widget.api, url: avatarUrl, size: 22);
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '说点儿什么吧',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQuickReply() async {
    if (!widget.api.hasCookie) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    var replyText = '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '回复 @${widget.feed.username}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: '说点儿什么吧…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (val) => replyText = val,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(replyText),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      try {
        await widget.api.reply(widget.feed.id, result.trim());
        if (mounted) {
          AppToast.show(context, '回复发送成功');
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(context, '回复失败: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final feed = widget.feed;
    final scheme = Theme.of(context).colorScheme;
    final isDetail = widget.isDetail;
    final rawEntityType =
        (feed.raw['entityType'] ?? feed.raw['entity_type'] ?? '')
            .toString()
            .toLowerCase();
    final rawFeedType = (feed.raw['feedType'] ?? feed.raw['feed_type'] ?? '')
        .toString()
        .toLowerCase();
    final rawEntityTemplate =
        (feed.raw['entityTemplate'] ?? feed.raw['entity_template'] ?? '')
            .toString()
            .toLowerCase();
    final articleCover = _articleCover;
    final feedTitle = (feed.raw['title'] ?? '').toString().trim();
    final isGenericFeedTitle =
        feedTitle.contains('动态') ||
        feedTitle.contains('图文') ||
        feedTitle == feed.username ||
        feedTitle.startsWith('${feed.username}的');

    final productPrice = '${feed.raw['tsubid']}' == '6'
        ? ProductPrice.tryParse(feed.raw['tsubdata'])
        : null;

    final isArticle = widget.articleLayout ||
        feed.isArticle ||
        rawEntityType == 'article' ||
        rawEntityType == 'feedarticle' ||
        rawEntityType == 'feed_article' ||
        rawEntityType == 'dyharticle' ||
        rawEntityType == 'news' ||
        rawFeedType == 'feedarticle' ||
        rawFeedType == 'feed_article' ||
        rawFeedType == 'article' ||
        rawFeedType == 'dyharticle' ||
        rawEntityTemplate == 'feedarticle' ||
        rawEntityTemplate == 'feed_article' ||
        rawEntityTemplate == 'article' ||
        rawEntityTemplate == 'dyharticle' ||
        (feedTitle.isNotEmpty &&
            !isGenericFeedTitle &&
            articleCover.isNotEmpty &&
            productPrice == null &&
            feed.raw['vote'] == null);

    final compactLayout =
        widget.officialLayout || widget.articleLayout || isArticle;
    final rawLevel = (feed.raw['user_level'] ??
            feed.raw['userInfo']?['level'] ??
            feed.raw['user_info']?['level'] ??
            feed.raw['level'] ??
            '')
        .toString()
        .trim();
    final device = (feed.raw['device_title'] ?? feed.raw['device_name'] ?? '')
        .toString()
        .trim();
    final innerContent = Padding(
      padding: isDetail
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
          : EdgeInsets.fromLTRB(
              productPrice == null ? 12 : 14,
              12,
              productPrice == null ? 12 : 14,
              8,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDetail) ...[
            if (widget.authorHeader != null)
              widget.authorHeader!
            else
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: feed.uid.isEmpty
                        ? null
                        : () => _openUserSpace(context, widget.api, feed.uid),
                    child: AppAvatar(
                      api: widget.api,
                      url: feed.avatar,
                      size: (widget.articleLayout || isArticle)
                          ? 38
                          : widget.officialLayout
                          ? 32
                          : productPrice != null
                          ? 38
                          : 42,
                      name: feed.username,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          key: const ValueKey('feed-author-link'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: feed.uid.isEmpty
                              ? null
                              : () => _openUserSpace(
                                  context,
                                  widget.api,
                                  feed.uid,
                                ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  feed.username.isEmpty
                                      ? '酷安用户'
                                      : feed.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: productPrice != null ? 16 : 15,
                                    fontWeight: context.adjustWeight(
                                      FontWeight.bold,
                                    ),
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              if (rawLevel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    rawLevel.toLowerCase().startsWith('lv.')
                                        ? rawLevel
                                        : 'Lv.$rawLevel',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              feed.date,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (device.isNotEmpty)
                              Flexible(
                                child: InkWell(
                                  key: const ValueKey('feed-device-link'),
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _openDeviceDiscussion(
                                    context,
                                    widget.api,
                                    device,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.smartphone_rounded,
                                          size: 12,
                                          color: scheme.onSurfaceVariant
                                              .withValues(alpha: 0.8),
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            device,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: scheme.onSurfaceVariant,
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
                  if (widget.rankNumber != null && widget.rankNumber! > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.rankNumber! <= 3
                            ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.6,
                              ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            size: 15,
                            color: widget.rankNumber! <= 3
                                ? const Color(0xFFFF5252)
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            widget.rankNumber! < 10
                                ? '0${widget.rankNumber}'
                                : '${widget.rankNumber}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: widget.rankNumber! <= 3
                                  ? const Color(0xFFFF5252)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  InkWell(
                    key: const ValueKey('feed-more-actions-btn'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: _showFeedMoreActions,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
          if (widget.body != null)
            widget.body!
          else if (isArticle && !isDetail) ...[
            if (feedTitle.isNotEmpty && !isGenericFeedTitle)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  feedTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: context.adjustWeight(FontWeight.bold),
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ),
            if (articleCover.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 2.0,
                    child: CachedNetworkImage(
                      normalizeCoolapkImageUrl(articleCover),
                      headers: coolapkImageHeaders(
                        articleCover,
                        api: widget.api,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.4,
                        ),
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Builder(
              builder: (context) {
                final summary = _articleSummary;
                if (summary.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CoolapkRichText(
                    api: widget.api,
                    text: summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      letterSpacing: 0.1,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
            _FeedTargetOrTagRow(
              api: widget.api,
              feed: feed,
              isDetail: isDetail,
            ),
          ] else ...[
            Builder(
              builder: (context) {
                final feedTitle = (feed.raw['title'] ?? '').toString().trim();
                final isGenericFeedTitle =
                    feedTitle.contains('动态') ||
                    feedTitle.contains('图文') ||
                    feedTitle == feed.username ||
                    feedTitle.startsWith('${feed.username}的');
                if (feedTitle.isNotEmpty &&
                    feedTitle != feed.message &&
                    !isGenericFeedTitle) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (feed.raw['vote'] is Map)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    '投票',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          TextSpan(text: feedTitle),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: widget.articleLayout
                            ? 18
                            : widget.officialLayout
                            ? 16
                            : 17,
                        fontWeight: widget.articleLayout
                            ? FontWeight.bold
                            : widget.officialLayout
                            ? FontWeight.w500
                            : FontWeight.bold,
                        color: scheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            if (isArticle && isDetail && articleCover.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 2.0,
                    child: CachedNetworkImage(
                      normalizeCoolapkImageUrl(articleCover),
                      headers: coolapkImageHeaders(
                        articleCover,
                        api: widget.api,
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            if (productPrice != null)
              Padding(
                key: const ValueKey('feed-product-price'),
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFF9800)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            color: const Color(0xFFFF9800),
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              width: 13,
                              height: 13,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white),
                              ),
                              child: const Text(
                                '¥',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              '到手价',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFF9800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '¥${productPrice.formatted}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF9800),
                      ),
                    ),
                    if (productPrice.config.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2C2C2C)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          productPrice.config,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (widget.picturesBeforeText && feed.pictures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: _PictureGrid(
                  api: widget.api,
                  urls: feed.pictures,
                  metadata: feed.pictureMetadata,
                  isDetail: isDetail,
                  joinedImages: true,
                ),
              ),
            if (feed.message.isNotEmpty && !widget.editorialCover)
              if (isDetail)
                SelectionArea(
                  child: CoolapkRichText(
                    api: widget.api,
                    text: feed.message,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.65,
                      letterSpacing: 0.15,
                      color: scheme.onSurface,
                    ),
                  ),
                )
              else if (widget.articleLayout)
                CoolapkRichText(
                  api: widget.api,
                  text: _extractArticleSummary(feed),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    letterSpacing: 0.1,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else if (widget.officialLayout)
                _OfficialFeedMessage(
                  api: widget.api,
                  text: feed.message.trimRight(),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: scheme.onSurface,
                  ),
                  lines: 6,
                  onMore: _openDetail,
                )
              else
                CoolapkRichText(
                  api: widget.api,
                  prefixSpans: productPrice == null
                      ? const []
                      : [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 15,
                              height: 15,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF009688),
                                  width: 1.5,
                                ),
                              ),
                              child: const Text(
                                '¥',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1,
                                  color: Color(0xFF009688),
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(
                            text: ' 到手价 | ',
                            style: TextStyle(color: Color(0xFF009688)),
                          ),
                        ],
                  text: feed.message.trimRight(),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: productPrice != null ? 17.5 : 16,
                    height: productPrice != null ? 1.4 : 1.3,
                    color: scheme.onSurface,
                  ),
                ),
            Builder(
              builder: (context) {
                if (widget.picturesBeforeText && feed.pictures.isNotEmpty) {
                  return const SizedBox.shrink();
                }
                if (widget.editorialCover) {
                  final cover =
                      (feed.raw['message_cover'] ??
                              feed.raw['pic'] ??
                              feed.pictures.firstOrNull ??
                              '')
                          .toString();
                  if (cover.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 20 / 9,
                              child: CachedNetworkImage(
                                normalizeCoolapkImageUrl(cover),
                                headers: coolapkImageHeaders(
                                  cover,
                                  api: widget.api,
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD84124),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '◇ 编辑精选',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }
                final video = _videoInfo;
                if (video != null) {
                  return _FeedVideoPreview(
                    api: widget.api,
                    feed: feed,
                    video: video,
                  );
                }
                final effectivePictures =
                    isArticle && isDetail && articleCover.isNotEmpty
                        ? feed.pictures
                            .where((url) => url != articleCover)
                            .toList()
                        : feed.pictures;
                if (effectivePictures.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _PictureGrid(
                      api: widget.api,
                      urls: effectivePictures,
                      metadata: feed.pictureMetadata,
                      isDetail: widget.isDetail,
                      joinedImages:
                          !isDetail && (productPrice != null || compactLayout),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            if (widget.editorialCover && feed.message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _OfficialFeedMessage(
                  api: widget.api,
                  text: feed.message,
                  lines: 3,
                  onMore: _openDetail,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (feed.raw['vote'] is Map)
              FeedVote(
                api: widget.api,
                feedId: feed.id,
                vote: Map<String, dynamic>.from(feed.raw['vote'] as Map),
              ),
            if (productPrice == null || isDetail)
              _FeedTargetOrTagRow(
                api: widget.api,
                feed: feed,
                isDetail: isDetail,
              ),
          ],
          if (widget.isHeadline && !isDetail) _buildQuickCommentBar(context),
          if (isDetail)
            Builder(
              builder: (context) {
                final ip = (feed.raw['ip_location'] ?? '').toString().trim();
                final viewNum =
                    (feed.raw['view_num'] ?? feed.raw['viewnum'] ?? '')
                        .toString()
                        .trim();
                final locationText = ip.isEmpty
                    ? ''
                    : (ip.startsWith('发布于') ? ip : '发布于$ip');
                final isMyPost =
                    widget.api.hasCookie &&
                    widget.api.currentUid.isNotEmpty &&
                    (feed.uid == widget.api.currentUid ||
                        feed.raw['uid']?.toString() == widget.api.currentUid);
                final viewsText = (isMyPost && viewNum.isNotEmpty)
                    ? '$viewNum浏览'
                    : '';
                final lastChange =
                    feed.raw['last_change_time'] ??
                    feed.raw['last_change_date'];
                String lastChangeText = '';
                if (lastChange != null &&
                    lastChange.toString().isNotEmpty &&
                    lastChange.toString() != '0') {
                  final editRel = formatRelativeTime(lastChange.toString());
                  if (editRel.isNotEmpty) {
                    lastChangeText = '编辑于 $editRel';
                  }
                }
                final infoLine = [
                  if (lastChangeText.isNotEmpty) lastChangeText,
                  if (locationText.isNotEmpty) locationText,
                  if (viewsText.isNotEmpty) viewsText,
                ].join(' · ');
                if (infoLine.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    infoLine,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                );
              },
            ),
          if (!isDetail &&
              !(widget.officialLayout && feed.raw['vote'] is Map)) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionBtn(
                  icon: _liked
                      ? Icons.thumb_up_rounded
                      : Icons.thumb_up_outlined,
                  count: _likes,
                  color: _liked ? scheme.primary : scheme.onSurfaceVariant,
                  onTap: _like,
                  label: _liked ? '取消赞' : '赞',
                ),
                _buildActionBtn(
                  icon: Icons.chat_bubble_outline_rounded,
                  count: int.tryParse(feed.replyCount) ?? 0,
                  color: scheme.onSurfaceVariant,
                  onTap: _openDetail,
                  label: '评论',
                ),
                _buildActionBtn(
                  icon: Icons.share_outlined,
                  count:
                      (int.tryParse('${feed.raw['forwardnum'] ?? 0}') ?? 0) +
                      (compactLayout
                          ? int.tryParse('${feed.raw['share_num'] ?? 0}') ?? 0
                          : 0),
                  color: scheme.onSurfaceVariant,
                  onTap: _showFeedMoreActions,
                  label: '分享',
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (isDetail) {
      return innerContent;
    }

    return RepaintBoundary(
      child: ReviewCard(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        elevation: compactLayout || productPrice != null ? 0 : 1,
        color:
            (compactLayout || productPrice != null) &&
                Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            compactLayout || productPrice != null ? 14 : 20,
          ),
          side: BorderSide.none,
        ),
        enableFeedback: false,
        splashFactory: NoSplash.splashFactory,
        onTap: () {
          HapticFeedbackUtil.light();
          _openDetail();
        },
        child: innerContent,
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback? onTap,
    required String label,
  }) {
    final text = count > 0
        ? (count > 10000 ? '${(count / 10000).toStringAsFixed(1)}w' : '$count')
        : '';
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _working ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (text.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedVideoInfo {
  const _FeedVideoInfo({
    required this.videoUrl,
    required this.coverUrl,
    required this.durationText,
    required this.requestParams,
  });

  final String videoUrl;
  final String coverUrl;
  final String durationText;
  final String requestParams;
}

_FeedVideoInfo? _extractFeedVideo(CoolapkFeed feed) {
  final raw = feed.raw;
  var videoUrl = [raw['media_url'], raw['video_url']]
      .map((value) => value?.toString().trim() ?? '')
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  var coverUrl = [raw['video_pic'], raw['pic'], raw['cover']]
      .map((value) => value?.toString().trim() ?? '')
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  var durationMs = 0;

  final mediaInfoRaw = raw['media_info'] ?? raw['mediaInfo'];
  Map<String, dynamic>? mediaInfo;
  if (mediaInfoRaw is Map<String, dynamic>) {
    mediaInfo = mediaInfoRaw;
  } else if (mediaInfoRaw is Map) {
    mediaInfo = Map<String, dynamic>.from(mediaInfoRaw);
  } else if (mediaInfoRaw is String && mediaInfoRaw.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(mediaInfoRaw);
      if (decoded is Map) mediaInfo = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }

  var requestParams = '';
  final rawRequestParams =
      [mediaInfo?['requestParams'], mediaInfo?['request_params']].firstWhere(
        (value) => value != null && value.toString().trim().isNotEmpty,
        orElse: () => null,
      );
  dynamic requestParamsValue = rawRequestParams;
  if (requestParamsValue is String && requestParamsValue.trim().isNotEmpty) {
    try {
      requestParamsValue = jsonDecode(requestParamsValue);
    } catch (_) {}
  }
  if (requestParamsValue is Map && requestParamsValue.isNotEmpty) {
    final providerParams =
        requestParamsValue.containsKey('fromType') ||
            requestParamsValue.containsKey('0')
        ? requestParamsValue
        : requestParamsValue.values.last;
    requestParams = providerParams is Map
        ? jsonEncode(providerParams)
        : providerParams is String
        ? providerParams.trim()
        : '';
  } else if (rawRequestParams is String) {
    requestParams = rawRequestParams.trim();
  }

  if (requestParams.isNotEmpty) {
    try {
      final parsedParams = jsonDecode(requestParams);
      if (parsedParams is Map && parsedParams['fromType'] == 'localVideo') {
        videoUrl = (parsedParams['0'] ?? '').toString().trim();
        requestParams = '';
      }
    } catch (_) {}
  }

  if (mediaInfo != null) {
    if (videoUrl.isEmpty) {
      videoUrl =
          (mediaInfo['url'] ??
                  mediaInfo['media_url'] ??
                  mediaInfo['stream_url'] ??
                  '')
              .toString()
              .trim();
    }
    if (coverUrl.isEmpty) {
      coverUrl =
          (mediaInfo['cover'] ??
                  mediaInfo['pic'] ??
                  mediaInfo['cover_url'] ??
                  '')
              .toString()
              .trim();
    }
    final dur =
        mediaInfo['duration'] ??
        mediaInfo['duration_ms'] ??
        mediaInfo['video_duration'];
    if (dur != null) {
      durationMs = int.tryParse(dur.toString()) ?? 0;
    }
  }

  if (videoUrl.isEmpty) {
    final extraUrl = (raw['extra_url'] ?? raw['url'] ?? raw['shareUrl'] ?? '')
        .toString()
        .trim();
    if (extraUrl.contains('video') ||
        extraUrl.endsWith('.mp4') ||
        extraUrl.contains('weibo.com') ||
        extraUrl.contains('t.cn') ||
        extraUrl.contains('bilibili.com') ||
        extraUrl.contains('b23.tv')) {
      videoUrl = extraUrl;
    }
  }

  if (videoUrl.isEmpty) {
    final weiboMatch = RegExp(
      r'https?://(?:video\.weibo\.com|h5\.video\.weibo\.com|weibo\.com/\d+/[A-Za-z0-9]+|weibo\.com/tv/show/\d+:\w+)[\w\-\.,@?^=%&:/~\+#]*',
    ).firstMatch(feed.message);
    if (weiboMatch != null) {
      videoUrl = weiboMatch.group(0)!;
    }
  }

  if (videoUrl.isEmpty) {
    final shortLinkMatch = RegExp(r'https?://t\.cn/[A-Za-z0-9]+')
        .firstMatch(feed.message);
    if (shortLinkMatch != null) {
      videoUrl = shortLinkMatch.group(0)!;
    }
  }

  if (videoUrl.isEmpty) {
    final biliMatch = RegExp(
      r'https?://(?:(?:www\.)?bilibili\.com/video/[A-Za-z0-9]+|b23\.tv/[A-Za-z0-9]+)[\w\-\.,@?^=%&:/~\+#]*',
    ).firstMatch(feed.message);
    if (biliMatch != null) {
      videoUrl = biliMatch.group(0)!;
    }
  }

  if (videoUrl.isEmpty && requestParams.isEmpty) return null;

  if (coverUrl.isEmpty && feed.pictures.isNotEmpty) {
    coverUrl = feed.pictures.first;
  }

  var durationText = '';
  if (durationMs > 0) {
    final totalSeconds = durationMs > 1000 ? (durationMs ~/ 1000) : durationMs;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    durationText =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  } else if (mediaInfo != null && mediaInfo['duration_string'] != null) {
    durationText = mediaInfo['duration_string'].toString();
  }

  return _FeedVideoInfo(
    videoUrl: videoUrl,
    coverUrl: coverUrl,
    durationText: durationText,
    requestParams: requestParams,
  );
}

class _FeedVideoPreview extends StatelessWidget {
  const _FeedVideoPreview({
    required this.api,
    required this.feed,
    required this.video,
  });

  final CoolapkApi api;
  final CoolapkFeed feed;
  final _FeedVideoInfo video;

  @override
  Widget build(BuildContext context) {
    final title = feed.message.isNotEmpty
        ? feed.message
        : (feed.raw['title'] ?? '视频播放').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            HapticFeedbackUtil.selection();
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => CoolapkVideoPlayerPage(
                  api: api,
                  videoUrl: video.videoUrl,
                  requestParams: video.requestParams,
                  coverUrl: video.coverUrl.isNotEmpty ? video.coverUrl : null,
                  title: title,
                  authorName: feed.username,
                  feedId: feed.id,
                ),
              ),
            );
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (video.coverUrl.isNotEmpty)
                  CachedNetworkImage(
                    normalizeCoolapkImageUrl(video.coverUrl),
                    headers: coolapkImageHeaders(video.coverUrl, api: api),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blueGrey.shade900, Colors.black87],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.videocam_rounded,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                Container(color: Colors.black.withValues(alpha: 0.25)),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                if (video.durationText.isNotEmpty)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        video.durationText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

class _FeedTargetOrTagRow extends StatelessWidget {
  const _FeedTargetOrTagRow({
    required this.api,
    required this.feed,
    required this.isDetail,
  });

  final CoolapkApi api;
  final CoolapkFeed feed;
  final bool isDetail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = feed.raw;

    // 1. Primary target row / topic / product
    final targetRow = raw['targetRow'] is Map
        ? Map<String, dynamic>.from(raw['targetRow'] as Map)
        : null;
    final ttitle = (targetRow?['title'] ?? raw['ttitle'] ?? '')
        .toString()
        .trim();
    final tpic = (targetRow?['logo'] ?? raw['tpic'] ?? '').toString().trim();
    final turl = (targetRow?['url'] ?? raw['turl'] ?? '').toString().trim();
    final subTitle = (targetRow?['subTitle'] ?? '').toString().trim();
    final targetType =
        (targetRow?['targetType'] ??
                (turl.contains('/product/') ? 'product' : 'topic'))
            .toString()
            .toLowerCase();

    // 2. If primary target exists:
    if (ttitle.isNotEmpty) {
      if (isDetail) {
        final productTypeName = (targetRow?['productTypeName'] ?? '')
            .toString()
            .trim();
        final starScore =
            targetRow?['star_average_score'] ??
            targetRow?['score'] ??
            raw['star_average_score'] ??
            raw['score'];
        final scoreNum = double.tryParse(starScore?.toString() ?? '') ?? 0.0;
        final isProduct =
            targetType == 'product' ||
            turl.contains('/product/') ||
            scoreNum > 0 ||
            productTypeName.isNotEmpty;

        var productId = (targetRow?['id'] ?? raw['product_id'] ?? '')
            .toString()
            .trim();
        if (productId.isEmpty && turl.startsWith('/product/')) {
          productId = turl.substring('/product/'.length);
          if (productId.contains('?')) {
            productId = productId.substring(0, productId.indexOf('?'));
          }
        }

        final isFollow =
            targetRow != null &&
            (targetRow['isFollow'] == 1 || targetRow['is_follow'] == 1);
        final displaySub = subTitle.isNotEmpty
            ? (subTitle.startsWith('🔥') ? subTitle : '🔥 $subTitle')
            : '';

        if (isProduct) {
          final scoreText = scoreNum > 0 ? scoreNum.toStringAsFixed(1) : '';
          final starRating = (scoreNum / 2).clamp(0.0, 5.0);
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    _navigateToTarget(context, ttitle, tpic, turl, targetRow),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (tpic.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                normalizeCoolapkImageUrl(tpic),
                                headers: coolapkImageHeaders(tpic, api: api),
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.devices_rounded,
                                    color: scheme.onPrimaryContainer,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ] else ...[
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.devices_rounded,
                                color: scheme.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        productTypeName.isNotEmpty
                                            ? productTypeName
                                            : '数码',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        ttitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (displaySub.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    displaySub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (scoreText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  scoreText,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: scheme.primary.withValues(
                                        alpha: (starRating >= i + 1)
                                            ? 1.0
                                            : ((starRating > i) ? 0.6 : 0.25),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _TargetFollowPill(
                              api: api,
                              productId: productId,
                              tag: ttitle,
                              isProduct: true,
                              initialFollowing: isFollow,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PostFeedPill(
                              api: api,
                              tag: ttitle,
                              productId: productId,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Topic card in detail page
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  _navigateToTarget(context, ttitle, tpic, turl, targetRow),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (tpic.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              normalizeCoolapkImageUrl(tpic),
                              headers: coolapkImageHeaders(tpic, api: api),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.tag_rounded,
                                  color: scheme.onPrimaryContainer,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ] else ...[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.tag_rounded,
                              color: scheme.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '话题',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      ttitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (displaySub.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  displaySub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TargetFollowPill(
                            api: api,
                            productId: '',
                            tag: ttitle,
                            isProduct: false,
                            initialFollowing: isFollow,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PostFeedPill(
                            api: api,
                            tag: ttitle,
                            productId: '',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        // Feed list card style: Compact capsule pill
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  _navigateToTarget(context, ttitle, tpic, turl, targetRow),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tpic.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          normalizeCoolapkImageUrl(tpic),
                          headers: coolapkImageHeaders(tpic, api: api),
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            targetType == 'product'
                                ? Icons.devices_rounded
                                : Icons.tag_rounded,
                            size: 13,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ] else ...[
                      Icon(
                        targetType == 'product'
                            ? Icons.devices_rounded
                            : Icons.tag_rounded,
                        size: 13,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      ttitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
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

    // 3. Fallback: check relationRows
    final relationRows = raw['relationRows'];
    if (relationRows is List && relationRows.isNotEmpty) {
      final firstRel = relationRows.whereType<Map>().firstOrNull;
      if (firstRel is Map && firstRel['title'] != null) {
        final relTitle = firstRel['title'].toString().trim();
        final relLogo = (firstRel['logo'] ?? '').toString().trim();
        final relUrl = (firstRel['url'] ?? '').toString().trim();
        if (relTitle.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    _navigateToTarget(context, relTitle, relLogo, relUrl, null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (relLogo.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            normalizeCoolapkImageUrl(relLogo),
                            headers: coolapkImageHeaders(relLogo, api: api),
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.bubble_chart_outlined,
                              size: 13,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        relTitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
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
    }

    // 4. Fallback: If not detail page, check if device exists to show device capsule pill
    final device = (raw['device_title'] ?? raw['device_name'] ?? '')
        .toString()
        .trim();
    if (!isDetail) {
      if (device.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smartphone_rounded,
                    size: 13,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    device,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final rawTags = raw['tags'];
    final tagRows = raw['tagRows'];
    final tagsList = <String>[];
    if (rawTags is String && rawTags.isNotEmpty) {
      for (final t in rawTags.split(',')) {
        final clean = t.replaceAll('#', '').trim();
        if (clean.isNotEmpty &&
            !clean.startsWith('http') &&
            !tagsList.contains(clean)) {
          tagsList.add(clean);
        }
      }
    } else if (rawTags is List) {
      for (final t in rawTags) {
        final clean = t.toString().replaceAll('#', '').trim();
        if (clean.isNotEmpty &&
            !clean.startsWith('http') &&
            !tagsList.contains(clean)) {
          tagsList.add(clean);
        }
      }
    }
    if (tagRows is List) {
      for (final tr in tagRows) {
        if (tr is Map && tr['title'] != null) {
          final clean = tr['title'].toString().replaceAll('#', '').trim();
          if (clean.isNotEmpty &&
              !clean.startsWith('http') &&
              !tagsList.contains(clean)) {
            tagsList.add(clean);
          }
        }
      }
    }
    if (tagsList.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (_) {},
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final tag in tagsList)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TopicPage(api: api, tag: tag),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tag_rounded, size: 13, color: scheme.primary),
                      const SizedBox(width: 2),
                      Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToTarget(
    BuildContext context,
    String title,
    String logo,
    String url,
    Map<String, dynamic>? targetRow,
  ) {
    final targetType = (targetRow?['targetType'] ?? '')
        .toString()
        .toLowerCase();
    final id = (targetRow?['id'] ?? '').toString();

    if (url.startsWith('/product/') || targetType == 'product') {
      var productId = id;
      if (productId.isEmpty && url.startsWith('/product/')) {
        productId = url.substring('/product/'.length);
        if (productId.contains('?')) {
          productId = productId.substring(0, productId.indexOf('?'));
        }
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProductPage(api: api, id: productId, title: title),
        ),
      );
      return;
    }

    if (url.startsWith('/dyh/') || targetType.contains('dyh')) {
      var dyhId = id;
      if (dyhId.isEmpty && url.startsWith('/dyh/')) {
        dyhId = url.substring('/dyh/'.length);
        if (dyhId.contains('?')) {
          dyhId = dyhId.substring(0, dyhId.indexOf('?'));
        }
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DyhPage(api: api, id: dyhId, title: title),
        ),
      );
      return;
    }

    // Topic tag fallback
    var tag = title;
    if (url.contains('/t/')) {
      var sub = url.substring(url.indexOf('/t/') + 3);
      if (sub.contains('?')) sub = sub.substring(0, sub.indexOf('?'));
      if (sub.contains('/')) sub = sub.substring(0, sub.indexOf('/'));
      try {
        final decoded = Uri.decodeComponent(sub).replaceAll('#', '').trim();
        if (decoded.isNotEmpty && int.tryParse(decoded) == null) {
          tag = decoded;
        }
      } catch (_) {}
    }
    tag = tag.replaceAll('#', '').trim();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TopicPage(
          api: api,
          tag: tag,
          initialTitle: title,
          initialLogo: logo.isNotEmpty ? logo : null,
        ),
      ),
    );
  }
}

class _TargetFollowPill extends StatefulWidget {
  const _TargetFollowPill({
    required this.api,
    required this.productId,
    required this.tag,
    required this.isProduct,
    required this.initialFollowing,
  });

  final CoolapkApi api;
  final String productId;
  final String tag;
  final bool isProduct;
  final bool initialFollowing;

  @override
  State<_TargetFollowPill> createState() => _TargetFollowPillState();
}

class _TargetFollowPillState extends State<_TargetFollowPill> {
  late bool _following = widget.api.isAnonymous && widget.isProduct
      ? widget.api.localAccount.productFollows.containsKey(widget.productId)
      : widget.initialFollowing;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    if (!(widget.isProduct ? widget.api.hasAccount : widget.api.hasCookie)) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.isProduct && widget.productId.isNotEmpty) {
        await widget.api.followProduct(
          widget.productId,
          following: _following,
          product: {'id': widget.productId, 'title': widget.tag},
        );
      } else {
        final cleanTag = widget.tag.replaceAll('#', '').trim();
        await widget.api.followTopic(cleanTag, following: _following);
      }
      if (mounted) {
        setState(() => _following = !_following);
        AppToast.show(context, _following ? '已关注' : '已取消关注');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: _following
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.3)
          : scheme.primary.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : _toggle,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _following ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
                color: _following ? scheme.onSurfaceVariant : scheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _following ? '已关注' : '关注',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _following ? scheme.onSurfaceVariant : scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostFeedPill extends StatelessWidget {
  const _PostFeedPill({
    required this.api,
    required this.tag,
    required this.productId,
  });

  final CoolapkApi api;
  final String tag;
  final String productId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!api.hasCookie) {
            AppToast.show(context, api.loginRequiredMessage);
            return;
          }
          final cleanTag = tag.replaceAll('#', '').trim();
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ComposeFeedPage(
                api: api,
                initialTag: cleanTag,
                initialProductId: productId,
              ),
            ),
          );
        },
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: scheme.onSurface),
              const SizedBox(width: 4),
              Text(
                '我也发一条',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorFollowButton extends StatefulWidget {
  const _AuthorFollowButton({
    required this.api,
    required this.uid,
    required this.initialFollowing,
  });

  final CoolapkApi api;
  final String uid;
  final bool initialFollowing;

  @override
  State<_AuthorFollowButton> createState() => _AuthorFollowButtonState();
}

class _AuthorFollowButtonState extends State<_AuthorFollowButton> {
  late bool _following = widget.api.isAnonymous
      ? widget.api.localAccount.follows.containsKey(widget.uid)
      : widget.initialFollowing;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _AuthorFollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFollowing != widget.initialFollowing) {
      _following = widget.api.isAnonymous
          ? widget.api.localAccount.follows.containsKey(widget.uid)
          : widget.initialFollowing;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (!widget.api.hasAccount) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.followUser(widget.uid, following: _following);
      if (mounted) {
        setState(() => _following = !_following);
        AppToast.show(context, _following ? '已关注' : '已取消关注');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_following) {
      return OutlinedButton(
        onPressed: _busy ? null : _toggle,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          minimumSize: const Size(0, 30),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Text(
          '已关注',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : _toggle,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        minimumSize: const Size(0, 30),
        side: BorderSide(color: scheme.primary, width: 1.2),
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: Text(
        '关注',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _TargetFollowButton extends StatefulWidget {
  const _TargetFollowButton({
    required this.api,
    required this.targetType,
    required this.title,
    required this.initialFollowing,
  });

  final CoolapkApi api;
  final String targetType;
  final String title;
  final bool initialFollowing;

  @override
  State<_TargetFollowButton> createState() => _TargetFollowButtonState();
}

class _TargetFollowButtonState extends State<_TargetFollowButton> {
  late bool _following = widget.initialFollowing;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.targetType != 'product') {
        final cleanTag = widget.title.replaceAll('#', '').trim();
        await widget.api.followTopic(cleanTag, following: _following);
      }
      if (mounted) setState(() => _following = !_following);
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: const Icon(Icons.check_rounded, size: 14),
        label: const Text('已关注'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _toggle,
      icon: const Icon(Icons.add_rounded, size: 14),
      label: const Text('关注'),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class FeedDetailPage extends ConsumerStatefulWidget {
  const FeedDetailPage({required this.api, required this.feed, super.key});

  final CoolapkApi api;
  final CoolapkFeed feed;

  @override
  ConsumerState<FeedDetailPage> createState() => _FeedDetailPageState();
}

class _FeedDetailPageState extends ConsumerState<FeedDetailPage> {
  final _scroll = ScrollController();
  final _replyController = TextEditingController();
  Map<String, dynamic>? _detail;
  final _replies = <CoolapkFeed>[];
  String? _replyError;
  bool _loadingDetail = true;
  bool _loadingReplies = false;
  bool _replyHasMore = true;
  bool _liked = false;
  bool _favorited = false;
  bool _feedActionBusy = false;
  bool _sendingReply = false;
  final _replyLikes = <String, bool>{};
  String _replyTo = '';
  final _replyPicture = TextEditingController();
  bool _replyAndForward = false;
  String _commentMode = 'hot';
  int _replyPage = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.feed.liked;
    _favorited = widget.api.isAnonymous
        ? widget.api.localAccount.favorites.containsKey(widget.feed.id)
        : widget.feed.favorited;
    final initialEmbedded = _extractEmbeddedReplies();
    if (initialEmbedded.isNotEmpty) {
      _replies.addAll(initialEmbedded);
    }
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _replyController.dispose();
    _replyPicture.dispose();
    super.dispose();
  }

  List<CoolapkFeed> _extractEmbeddedReplies() {
    final embedded = <Map<String, dynamic>>[];
    for (final source in [_detail, widget.feed.raw]) {
      if (source == null) continue;
      for (final key in [
        'topReplyRows',
        'top_reply_rows',
        'replyMeRows',
        'reply_me_rows',
        'replyRows',
        'reply_rows',
      ]) {
        final list = source[key];
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              embedded.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    }
    if (embedded.isEmpty) return const [];
    final seen = <String>{};
    return embedded.map(CoolapkFeed.fromJson).where((reply) {
      final type =
          (reply.raw['entityType'] ??
                  reply.raw['entity_type'] ??
                  reply.raw['type'] ??
                  '')
              .toString()
              .toLowerCase();
      return type != 'feed_detail_reply_sponsor_card' &&
          reply.message.trim().toUpperCase() !=
              'FEED_DETAIL_REPLY_SPONSOR_CARD' &&
          reply.id.isNotEmpty &&
          seen.add(reply.id);
    }).toList();
  }

  void _onScroll() {
    if (_replyError == null &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 420) {
      _loadReplies(refresh: false);
    }
  }

  Future<void> _load() async {
    await Future.wait([_loadDetail(), _loadReplies()]);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loadingDetail = true;
    });
    try {
      final result = await widget.api.getFeedDetail(widget.feed.id);
      if (mounted) {
        setState(() {
          _detail = result;
          if (_replies.isEmpty) {
            final embedded = _extractEmbeddedReplies();
            if (embedded.isNotEmpty) {
              _replies.addAll(embedded);
            }
          }
        });
      }
    } catch (_) {
      // 动态基本内容由 widget.feed 完整提供；详情接口若因未登录风控受限或失败，静默使用已有内容，无需中断展示或弹出多余的错误与重试
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _loadReplies({bool refresh = true}) async {
    if (_loadingReplies || (!refresh && !_replyHasMore)) {
      return;
    }
    final next = refresh ? 1 : _replyPage + 1;
    setState(() {
      _loadingReplies = true;
      _replyError = null;
    });

    final rawFeedType =
        (_detail?['feedType'] ??
                _detail?['feed_type'] ??
                widget.feed.raw['feedType'] ??
                widget.feed.raw['feed_type'] ??
                'feed')
            .toString()
            .trim();
    // Coolapk /v6/feed/replyList strictly expects 'feed' for posts and 'feed_reply' for sub-replies.
    // Unrecognized values like 'user_feed', 'feed_article' cause API restriction ("访问受限").
    final feedType = rawFeedType == 'feed_reply' ? 'feed_reply' : 'feed';

    try {
      var result = switch (_commentMode) {
        'hot' => await widget.api.getHotReplyPage(widget.feed.id, next),
        'latest' => await widget.api.getReplyPage(
          widget.feed.id,
          next,
          listType: 'dateline_desc',
          feedType: feedType,
          firstItem: refresh ? null : _replies.firstOrNull?.id,
          lastItem: refresh ? null : _replies.lastOrNull?.id,
        ),
        'author' => await widget.api.getReplyPage(
          widget.feed.id,
          next,
          fromFeedAuthor: true,
          feedType: feedType,
          firstItem: refresh ? null : _replies.firstOrNull?.id,
          lastItem: refresh ? null : _replies.lastOrNull?.id,
        ),
        _ => await widget.api.getReplyPage(
          widget.feed.id,
          next,
          listType: 'lastupdate_desc',
          feedType: feedType,
          firstItem: refresh ? null : _replies.firstOrNull?.id,
          lastItem: refresh ? null : _replies.lastOrNull?.id,
        ),
      };

      // 当热门或普通评论返回空列表时（例如个人主页自发动态、冷门动态、头条部分评论），
      // 深度提取冷门评论：尝试从 recent_reply_ids 拉取具体回复（该接口未受未登录风控限制）
      if (result.items.isEmpty && refresh) {
        if (_detail == null && _loadingDetail) {
          try {
            final res = await widget.api.getFeedDetail(widget.feed.id);
            if (mounted) _detail = res;
          } catch (_) {}
        }
        final recentIdsRaw =
            (_detail?['recent_reply_ids'] ??
                    widget.feed.raw['recent_reply_ids'])
                ?.toString() ??
            '';
        final recentIds = recentIdsRaw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (recentIds.isNotEmpty) {
          final futures = recentIds.take(15).map((rid) async {
            try {
              final res = await widget.api.getReplyDetail(rid);
              final data = res['data'];
              if (data is Map<String, dynamic> && data['id'] != null) {
                return CoolapkFeed.fromJson(data);
              }
            } catch (_) {}
            return null;
          });
          final fetched = (await Future.wait(futures))
              .whereType<CoolapkFeed>()
              .toList();
          if (fetched.isNotEmpty) {
            result = ApiPage(
              items: fetched.map((r) => r.raw).toList(),
              page: 1,
              firstItem: fetched.firstOrNull?.id ?? '',
              lastItem: fetched.lastOrNull?.id ?? '',
              hasMore: false,
            );
          }
        }

        // 如果依然为空且处于 hot 模式，尝试普通排序请求（针对登录用户或免风控节点）
        if (result.items.isEmpty && _commentMode == 'hot') {
          try {
            final regularResult = await widget.api.getReplyPage(
              widget.feed.id,
              1,
              listType: 'lastupdate_desc',
              feedType: feedType,
            );
            if (regularResult.items.isNotEmpty) {
              result = regularResult;
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        _applyReplyPage(result, refresh: refresh, page: next);
      }
    } catch (error) {
      if (mounted) {
        // 彻底去除评论区报错与重试条，非致命风控错误静默降级展示
        _replyError = null;
        if (_commentMode != 'hot') {
          try {
            final fallback = await widget.api.getHotReplyPage(
              widget.feed.id,
              1,
            );
            if (mounted && fallback.items.isNotEmpty) {
              setState(() => _commentMode = 'hot');
              _applyReplyPage(fallback, refresh: true, page: 1);
              return;
            }
          } catch (_) {}
        }

        if (_detail == null && _loadingDetail) {
          try {
            final res = await widget.api.getFeedDetail(widget.feed.id);
            if (mounted) _detail = res;
          } catch (_) {}
        }

        final recentIdsRaw =
            (_detail?['recent_reply_ids'] ??
                    widget.feed.raw['recent_reply_ids'])
                ?.toString() ??
            '';
        final recentIds = recentIdsRaw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (recentIds.isNotEmpty && _replies.isEmpty) {
          try {
            final futures = recentIds.take(15).map((rid) async {
              try {
                final res = await widget.api.getReplyDetail(rid);
                final data = res['data'];
                if (data is Map<String, dynamic> && data['id'] != null) {
                  return CoolapkFeed.fromJson(data);
                }
              } catch (_) {}
              return null;
            });
            final fetched = (await Future.wait(futures))
                .whereType<CoolapkFeed>()
                .toList();
            if (mounted && fetched.isNotEmpty) {
              setState(() {
                final ids = _replies.map((r) => r.id).toSet();
                for (final r in fetched) {
                  if (ids.add(r.id)) _replies.add(r);
                }
              });
            }
          } catch (_) {}
        }

        if (mounted && _replies.isEmpty) {
          final embedded = _extractEmbeddedReplies();
          if (embedded.isNotEmpty) {
            setState(() {
              _replies.addAll(embedded);
            });
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loadingReplies = false);
    }
  }

  void _applyReplyPage(
    ApiPage result, {
    required bool refresh,
    required int page,
  }) {
    setState(() {
      // 仅在获取到了新数据时清空旧数据，防止冷门帖子因空响应误清空已有的内嵌或保底评论
      if (refresh && result.items.isNotEmpty) {
        _replies.clear();
      }
      final ids = _replies.map((reply) => reply.id).toSet();
      _replies.addAll(
        result.items.map(CoolapkFeed.fromJson).where((reply) {
          final type =
              (reply.raw['entityType'] ??
                      reply.raw['entity_type'] ??
                      reply.raw['type'] ??
                      '')
                  .toString()
                  .toLowerCase();
          return type != 'feed_detail_reply_sponsor_card' &&
              reply.message.trim().toUpperCase() !=
                  'FEED_DETAIL_REPLY_SPONSOR_CARD' &&
              (reply.id.isEmpty || ids.add(reply.id));
        }),
      );
      if (_replies.isEmpty) {
        final embedded = _extractEmbeddedReplies();
        for (final reply in embedded) {
          if (ids.add(reply.id)) {
            _replies.add(reply);
          }
        }
      }
      _replyPage = page;
      _replyHasMore = result.hasMore && result.items.isNotEmpty;
    });
  }

  Future<void> _toggleLike() async {
    if (_feedActionBusy) return;
    setState(() => _feedActionBusy = true);
    try {
      await widget.api.likeFeed(widget.feed.id, liked: _liked);
      if (mounted) setState(() => _liked = !_liked);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _feedActionBusy = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_feedActionBusy) return;
    setState(() => _feedActionBusy = true);
    try {
      await widget.api.favoriteFeed(
        widget.feed.id,
        favorited: _favorited,
        feed: _detail == null
            ? widget.feed
            : CoolapkFeed.fromJson({
                ...widget.feed.raw,
                ..._detail!,
                'id': widget.feed.id,
              }),
      );
      if (mounted) setState(() => _favorited = !_favorited);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _feedActionBusy = false);
    }
  }

  Future<void> _toggleReplyLike(
    CoolapkFeed reply, {
    VoidCallback? onUpdated,
  }) async {
    if (reply.id.isEmpty) return;
    final liked = _replyLikes[reply.id] ?? reply.liked;
    try {
      await widget.api.likeReply(reply.id, liked: liked);
      if (mounted) {
        setState(() => _replyLikes[reply.id] = !liked);
        onUpdated?.call();
      }
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _deleteReply(CoolapkFeed reply) async {
    final sure = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条评论？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || sure != true) return;
    try {
      await widget.api.deleteReply(reply.id);
      if (mounted) await _loadReplies();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _showReplyThread(
    CoolapkFeed reply,
    String authorUid,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final rawSubReplies = reply.raw['replyRows'] ?? reply.raw['reply_rows'];
        final initialSubReplies = (rawSubReplies is List)
            ? rawSubReplies
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList()
            : <Map<String, dynamic>>[];
        final replyCount =
            int.tryParse(
              '${reply.raw['replyRowsMore'] ?? reply.raw['replynum'] ?? reply.replyCount}',
            ) ??
            initialSubReplies.length;
        return SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.64,
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Material(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : theme.colorScheme.surfaceContainerLow,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '关闭回复',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded, size: 28),
                        ),
                        Expanded(
                          child: Text(
                            '回复($replyCount)',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(sheetContext)
                                  .popUntil((route) => route is PageRoute),
                          child: const Text('查看原动态'),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
                Expanded(
                  child: ApiListPage(
                    key: ValueKey('reply-thread-${reply.id}'),
                    api: widget.api,
                    title: '',
                    path: '/v6/feed/replyList',
                    query: {
                      'id': reply.id,
                      'feedType': 'feed_reply',
                      'discussMode': 1,
                      'listType': 'lastupdate_desc',
                    },
                    initialItems: initialSubReplies,
                    showAppBar: false,
                    header: ColoredBox(
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : theme.colorScheme.surfaceContainerHigh,
                      child: _replyThreadTile(
                        sheetContext,
                        reply,
                        authorUid,
                        isThreadRoot: true,
                        onUpdated: () {
                          if (sheetContext.mounted) setSheetState(() {});
                        },
                      ),
                    ),
                    itemBuilder: (itemContext, item) {
                      final entityType =
                          (item['entityType'] ??
                                  item['entity_type'] ??
                                  item['type'] ??
                                  '')
                              .toString()
                              .toLowerCase();
                      final message = (item['message'] ?? '')
                          .toString()
                          .trim()
                          .toUpperCase();
                      if (entityType == 'feed_detail_reply_sponsor_card' ||
                          message == 'FEED_DETAIL_REPLY_SPONSOR_CARD') {
                        return const SizedBox.shrink();
                      }
                      return _replyThreadTile(
                        itemContext,
                        CoolapkFeed.fromJson(item),
                        authorUid,
                        onUpdated: () {
                          if (sheetContext.mounted) setSheetState(() {});
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _replyThreadTile(
    BuildContext context,
    CoolapkFeed reply,
    String authorUid, {
    VoidCallback? onUpdated,
    bool isThreadRoot = false,
  }) => _ReplyTile(
    api: widget.api,
    reply: reply,
    authorUid: authorUid,
    showSubReplies: !isThreadRoot,
    showThreadAction: !isThreadRoot,
    showDivider: true,
    liked: _replyLikes[reply.id] ?? reply.liked,
    onReply: () {
      Navigator.of(context).popUntil((route) => route is PageRoute);
      if (!mounted) return;
      setState(() => _replyTo = reply.id);
      _openCommentComposer();
    },
    onLike: () => _toggleReplyLike(
      reply,
      onUpdated: () {
        if (context.mounted) onUpdated?.call();
      },
    ),
    onDelete:
        widget.api.currentUid.isNotEmpty && widget.api.currentUid == reply.uid
        ? () {
            Navigator.of(context).popUntil((route) => route is PageRoute);
            unawaited(_deleteReply(reply));
          }
        : null,
    onDetails: () => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ApiDetailPage(
          api: widget.api,
          title: '评论详情',
          path: '/v6/feed/replyDetail',
          query: {'id': reply.id},
        ),
      ),
    ),
    onThread: () => _showReplyThread(reply, authorUid),
  );

  Future<void> _sendReply() async {
    final message = _replyController.text.trim();
    if (message.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      await widget.api.reply(
        widget.feed.id,
        message,
        rid: _replyTo,
        pic: _replyPicture.text.trim().isEmpty
            ? null
            : _replyPicture.text.trim(),
        replyAndForward: _replyAndForward,
      );
      _replyController.clear();
      _replyPicture.clear();
      setState(() => _replyTo = '');
      await _loadReplies();
      if (mounted) _showMessage('评论已提交');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _forward() async {
    final controller = TextEditingController();
    final message = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转发动态'),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '说点什么…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('转发'),
          ),
        ],
      ),
    );
    if (message == null) return;
    try {
      await widget.api.forwardFeed(widget.feed.id, message.trim());
      if (mounted) _showMessage('已提交转发');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _deleteFeed() async {
    final sure = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条动态？'),
        content: const Text('此操作会直接请求酷安删除动态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.api.deleteFeed(widget.feed.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final useLiquidGlass = ref.watch(
      appSettingsProvider.select(
        (settings) => settings.useLiquidGlassNavBar,
      ),
    );
    final displayUsername =
        (_detail?['username'] ??
                _detail?['user_info']?['username'] ??
                widget.feed.username)
            .toString()
            .trim();
    final displayAvatar =
        (_detail?['userAvatar'] ??
                _detail?['avatar'] ??
                _detail?['user_info']?['userAvatar'] ??
                _detail?['user_info']?['avatar'] ??
                widget.feed.avatar)
            .toString()
            .trim();
    final authorUid =
        (_detail?['uid'] ?? _detail?['user_info']?['uid'] ?? widget.feed.uid)
            .toString()
            .trim();
    final device =
        (_detail?['device_title'] ??
                _detail?['device_name'] ??
                widget.feed.raw['device_title'] ??
                widget.feed.raw['device_name'] ??
                '')
            .toString()
            .trim();
    final rawLevel =
        (_detail?['userInfo']?['level'] ??
                _detail?['user_info']?['level'] ??
                _detail?['user_level'] ??
                widget.feed.raw['user_level'] ??
                widget.feed.raw['userInfo']?['level'] ??
                '')
            .toString()
            .trim();
    final levelText = rawLevel.isNotEmpty
        ? (rawLevel.toLowerCase().startsWith('lv.') ? rawLevel : 'Lv.$rawLevel')
        : '';
    final isFollow =
        _detail?['isFollow'] ??
        _detail?['is_follow'] ??
        widget.feed.raw['isFollow'] ??
        widget.feed.raw['is_follow'];
    final isAuthorFollowed = isFollow == 1 || isFollow == true;
    final isSelf =
        widget.api.hasCookie &&
        widget.api.currentUid.isNotEmpty &&
        authorUid == widget.api.currentUid;
    final timeStr = widget.feed.date;
    final subTitleLine = [
      if (timeStr.isNotEmpty) timeStr,
      if (device.isNotEmpty) '📱 $device',
    ].join(' ');

    final scaffold = Scaffold(
      extendBody: true,
      appBar: ReviewFrostedAppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: authorUid.isEmpty
              ? null
              : () => _openUserSpace(context, widget.api, authorUid),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AppAvatar(
                  api: widget.api,
                  url: displayAvatar,
                  size: 38,
                  name: displayUsername,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              displayUsername.isEmpty
                                  ? '酷安用户'
                                  : displayUsername,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (levelText.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '($levelText)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subTitleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (authorUid.isNotEmpty && !isSelf)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _AuthorFollowButton(
                api: widget.api,
                uid: authorUid,
                initialFollowing: isAuthorFollowed,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              switch (value) {
                case 'delete':
                  await _deleteFeed();
                  break;
                case 'copy':
                  final text = widget.feed.message;
                  if (text.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) AppToast.show(context, '已复制动态内容');
                  }
                  break;
                case 'space':
                  if (authorUid.isNotEmpty) {
                    _openUserSpace(context, widget.api, authorUid);
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              if (isSelf)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('删除动态'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('复制文本'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'space',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('查看主页'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GlassBackgroundSource(
        enabled: useLiquidGlass,
        child: EasyRefresh(
          header: reviewDefaultRefreshHeader,
          onRefresh: _load,
          child: filterHorizontalScrollNotifications(
            ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                80 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _DetailContent(
                  api: widget.api,
                  feed: widget.feed,
                  detail: _detail,
                ),
                if (_loadingDetail &&
                    widget.feed.message.isEmpty &&
                    _detail == null)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: LinearProgressIndicator()),
                  ),
                Divider(
                  height: 16,
                  thickness: 0.5,
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.25),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Builder(
                        builder: (context) {
                          final replyNum =
                              int.tryParse(
                                '${_detail?['replynum'] ?? _detail?['replyNum'] ?? widget.feed.replyCount}',
                              ) ??
                              _replies.length;
                          final totalReplies = replyNum > 0
                              ? '$replyNum'
                              : (_replies.isNotEmpty
                                    ? '${_replies.length}'
                                    : '0');
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '共 $totalReplies 回复',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                              if (_loadingReplies && _replies.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1E1E1E)
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(2.5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _commentFilterChip('默认', 'default'),
                            _commentFilterChip('最新', 'latest'),
                            _commentFilterChip('热门', 'hot'),
                            _commentFilterChip('楼主', 'author'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingReplies && _replies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_replies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.35),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '还没有回复哦，快来回复一下吧~',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < _replies.length; index++)
                        _ReplyTile(
                          api: widget.api,
                          reply: _replies[index],
                          authorUid: authorUid,
                          showDivider: index + 1 < _replies.length,
                          onReply: () {
                            setState(() {
                              _replyTo = _replies[index].id;
                            });
                            _openCommentComposer();
                          },
                          liked:
                              _replyLikes[_replies[index].id] ??
                              _replies[index].liked,
                          onLike: () => _toggleReplyLike(_replies[index]),
                          onDelete:
                              widget.api.currentUid.isNotEmpty &&
                                  widget.api.currentUid == _replies[index].uid
                              ? () => _deleteReply(_replies[index])
                              : null,
                          onDetails: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ApiDetailPage(
                                api: widget.api,
                                title: '评论详情',
                                path: '/v6/feed/replyDetail',
                                query: {'id': _replies[index].id},
                              ),
                            ),
                          ),
                          onThread: () =>
                              _showReplyThread(_replies[index], authorUid),
                        ),
                    ],
                  ),
                if (_loadingReplies && _replies.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_replyHasMore && _replies.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('已经到底了')),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
          child: Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final capsuleColor = isDark
                  ? const Color(0xFF262626)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.92);
              final capsuleBorder = Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: isDark ? 0.2 : 0.35,
                ),
                width: 0.6,
              );

              final likeNum =
                  int.tryParse(
                    '${_detail?['likenum'] ?? _detail?['likeNum'] ?? widget.feed.likeCount}',
                  ) ??
                  0;
              final displayLike =
                  (likeNum +
                          (_liked && !widget.feed.liked
                              ? 1
                              : (!_liked && widget.feed.liked ? -1 : 0)))
                      .clamp(0, 1 << 31);
              final displayLikeCount = displayLike > 0 ? '$displayLike' : '赞';

              final replyNum =
                  int.tryParse(
                    '${_detail?['replynum'] ?? _detail?['replyNum'] ?? widget.feed.replyCount}',
                  ) ??
                  _replies.length;
              final displayReplyCount = replyNum > 0 ? '$replyNum' : '评论';

              final favNum =
                  int.tryParse(
                    '${_detail?['favnum'] ?? _detail?['favNum'] ?? widget.feed.raw['favnum'] ?? widget.feed.raw['favNum'] ?? '0'}',
                  ) ??
                  0;
              final displayFav =
                  (favNum +
                          (_favorited && !widget.feed.favorited
                              ? 1
                              : (!_favorited && widget.feed.favorited
                                    ? -1
                                    : 0)))
                      .clamp(0, 1 << 31);
              final displayFavCount = widget.api.isAnonymous || displayFav == 0
                  ? '收藏'
                  : '$displayFav';

              final forwardNum =
                  int.tryParse(
                    '${_detail?['forwardnum'] ?? _detail?['forwardNum'] ?? widget.feed.raw['forwardnum'] ?? widget.feed.raw['forwardNum'] ?? '0'}',
                  ) ??
                  0;
              final displayForwardCount = forwardNum > 0 ? '$forwardNum' : '转发';

              return Row(
                children: [
                  // Left floating capsule: 写评论
                  Expanded(
                    flex: 9,
                    child: Material(
                      color: useLiquidGlass ? Colors.transparent : capsuleColor,
                      elevation: useLiquidGlass ? 0 : 2,
                      shadowColor: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('feed-detail-comment-capsule'),
                        onTap: _openCommentComposer,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: useLiquidGlass ? null : capsuleBorder,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (useLiquidGlass) _detailActionGlass(),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _replyTo.isEmpty ? '写评论' : '回复中…',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
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
                  const SizedBox(width: 10),
                  // Right floating capsule: 赞、评、藏、转
                  Expanded(
                    flex: 12,
                    child: Material(
                      key: const ValueKey('feed-detail-actions-capsule'),
                      color: useLiquidGlass ? Colors.transparent : capsuleColor,
                      elevation: useLiquidGlass ? 0 : 2,
                      shadowColor: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: useLiquidGlass ? null : capsuleBorder,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (useLiquidGlass) _detailActionGlass(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _bottomActionItem(
                                    icon: _liked
                                        ? Icons.thumb_up_rounded
                                        : Icons.thumb_up_outlined,
                                    label: displayLikeCount,
                                    color: _liked
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    onTap: _toggleLike,
                                  ),
                                  _bottomActionItem(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    label: displayReplyCount,
                                    color: scheme.onSurfaceVariant,
                                    onTap: () {
                                      if (_scroll.hasClients) {
                                        _scroll.animateTo(
                                          _scroll.position.maxScrollExtent
                                              .clamp(0.0, 600.0),
                                          duration: const Duration(
                                            milliseconds: 350,
                                          ),
                                          curve: Curves.easeOut,
                                        );
                                      }
                                    },
                                  ),
                                  _bottomActionItem(
                                    icon: _favorited
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    label: displayFavCount,
                                    color: _favorited
                                        ? Colors.amber.shade700
                                        : scheme.onSurfaceVariant,
                                    onTap: _toggleFavorite,
                                  ),
                                  _bottomActionItem(
                                    icon: Icons.repeat_rounded,
                                    label: displayForwardCount,
                                    color: scheme.onSurfaceVariant,
                                    onTap: _forward,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return useLiquidGlass ? GlassPage(child: scaffold) : scaffold;
  }

  Widget _detailActionGlass() => AdaptiveGlass(
    key: const ValueKey('feed-detail-action-glass'),
    shape: const LiquidRoundedSuperellipse(borderRadius: 9999),
    settings: ReviewNavigationBar.liquidGlassSettings,
    quality: ReviewNavigationBar.liquidGlassQuality,
    child: const SizedBox.expand(),
  );

  Widget _commentFilterChip(String label, String mode) {
    final selected = _commentMode == mode;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _loadingReplies
          ? null
          : () {
              if (_commentMode == mode) return;
              setState(() {
                _commentMode = mode;
                _replyPage = 0;
                _replyHasMore = true;
              });
              _loadReplies();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF2E2E2E) : scheme.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? (isDark ? Colors.white : scheme.primary)
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _bottomActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCommentComposer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.viewInsetsOf(ctx).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _replyTo.isEmpty ? '发表评论' : '回复评论',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_replyTo.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => _replyTo = '');
                            Navigator.pop(ctx);
                            _openCommentComposer();
                          },
                          child: const Text('取消回复指定人'),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _replyController,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: _replyTo.isEmpty ? '说点什么吧…' : '回复这条评论…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: _replyPicture.text.isEmpty
                            ? '附加图片 URL'
                            : '已附加图片',
                        onPressed: () async {
                          final controller = TextEditingController(
                            text: _replyPicture.text,
                          );
                          final value = await showAppDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('附加图片'),
                              content: TextField(
                                controller: controller,
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
                                  onPressed: () => Navigator.pop(
                                    context,
                                    controller.text.trim(),
                                  ),
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          );
                          controller.dispose();
                          if (mounted && value != null) {
                            setState(() => _replyPicture.text = value);
                            setModalState(() {});
                          }
                        },
                        icon: Icon(
                          _replyPicture.text.isEmpty
                              ? Icons.attach_file_rounded
                              : Icons.image_rounded,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _replyAndForward = !_replyAndForward);
                          setModalState(() {});
                        },
                        icon: Icon(
                          _replyAndForward
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          '同时转发',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _sendingReply
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _sendReply();
                              },
                        child: const Text('发送'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.api,
    required this.feed,
    required this.detail,
  });

  final CoolapkApi api;
  final CoolapkFeed feed;
  final Map<String, dynamic>? detail;

  @override
  Widget build(BuildContext context) {
    final message = _text(detail?['message'] ?? detail?['description']);
    final nestedUser = detail?['userInfo'] ?? detail?['user_info'];
    final user = nestedUser is Map
        ? Map<String, dynamic>.from(nestedUser)
        : const <String, dynamic>{};
    final expandedFeed = message.isEmpty
        ? feed
        : CoolapkFeed(
            id: feed.id,
            uid: _text(detail?['uid'] ?? user['uid'] ?? feed.uid),
            username: _text(
              detail?['username'] ?? user['username'] ?? feed.username,
            ),
            avatar: _text(
              detail?['userAvatar'] ?? user['avatar'] ?? feed.avatar,
            ),
            message: message,
            date: feed.date,
            likeCount: _text(
              detail?['likenum'] ?? detail?['likeNum'] ?? feed.likeCount,
            ),
            replyCount: _text(
              detail?['replynum'] ?? detail?['replyNum'] ?? feed.replyCount,
            ),
            pictures: _detailImages(detail!, feed.pictures),
            pictureMetadata: {
              ...feed.pictureMetadata,
              ...CoolapkFeed.pictureMetadataFromJson(detail!),
            },
            liked: feed.liked,
            favorited: feed.favorited,
            raw: detail!,
          );
    return FeedCard(api: api, feed: expandedFeed, isDetail: true);
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.api,
    required this.reply,
    required this.showDivider,
    required this.liked,
    required this.onReply,
    required this.onLike,
    required this.onDetails,
    required this.onThread,
    this.authorUid = '',
    this.onDelete,
    this.showSubReplies = true,
    this.showThreadAction = true,
  });

  final CoolapkApi api;
  final CoolapkFeed reply;
  final bool showDivider;
  final bool liked;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onDetails;
  final VoidCallback onThread;
  final String authorUid;
  final VoidCallback? onDelete;
  final bool showSubReplies;
  final bool showThreadAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final isAuthor = authorUid.isNotEmpty && reply.uid == authorUid;
    final likeCount = int.tryParse(reply.likeCount) ?? 0;
    final replyCount = int.tryParse(reply.replyCount) ?? 0;

    final rawSubReplies = reply.raw['replyRows'] ?? reply.raw['reply_rows'];
    final subReplies = (rawSubReplies is List)
        ? rawSubReplies.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final totalSubCount =
        int.tryParse(
          '${reply.raw['replyRowsMore'] ?? reply.raw['replynum'] ?? replyCount}',
        ) ??
        subReplies.length;

    final nameColor = isDark
        ? const Color(0xFF26A69A)
        : const Color(0xFF00897B);

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: reply.uid.isEmpty
                    ? null
                    : () => _openUserSpace(context, api, reply.uid),
                borderRadius: BorderRadius.circular(18),
                child: AppAvatar(
                  api: api,
                  url: reply.avatar,
                  size: 36,
                  name: reply.username,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: InkWell(
                            onTap: reply.uid.isEmpty
                                ? null
                                : () => _openUserSpace(context, api, reply.uid),
                            child: Text(
                              reply.username.isEmpty ? '酷安用户' : reply.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: nameColor,
                              ),
                            ),
                          ),
                        ),
                        if (isAuthor) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '楼主',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (reply.message.isNotEmpty)
                      CoolapkRichText(
                        api: api,
                        text: reply.message,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          color: scheme.onSurface,
                        ),
                      ),
                    if (reply.pictures.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _PictureGrid(
                        api: api,
                        urls: reply.pictures,
                        metadata: reply.pictureMetadata,
                        isDetail: true,
                      ),
                    ],
                    if (showSubReplies &&
                        (subReplies.isNotEmpty || totalSubCount > 0))
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.45,
                                ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final sub in subReplies.take(3)) ...[
                              _buildSubReplyLine(
                                context,
                                sub,
                                nameColor,
                                scheme,
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (totalSubCount > 0)
                              InkWell(
                                onTap: onThread,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    subReplies.isEmpty
                                        ? '共 $totalSubCount 条回复 >'
                                        : (totalSubCount > 3 ||
                                              ((int.tryParse(
                                                        '${reply.raw['replyRowsMore']}',
                                                      ) ??
                                                      0) >
                                                  0))
                                        ? '共 $totalSubCount 条回复 >'
                                        : '查看对话 >',
                                    style: TextStyle(
                                      color: nameColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          reply.date,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onLike,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  liked
                                      ? Icons.thumb_up_rounded
                                      : Icons.thumb_up_outlined,
                                  size: 15,
                                  color: liked
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant.withValues(
                                          alpha: 0.8,
                                        ),
                                ),
                                if (likeCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '$likeCount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: liked
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant.withValues(
                                              alpha: 0.8,
                                            ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onReply,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 15,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                                if (replyCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '$replyCount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: '更多',
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'thread':
                                onThread();
                                break;
                              case 'details':
                                onDetails();
                                break;
                              case 'delete':
                                onDelete?.call();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (showThreadAction)
                              const PopupMenuItem(
                                value: 'thread',
                                child: Text('查看楼中楼回复'),
                              ),
                            const PopupMenuItem(
                              value: 'details',
                              child: Text('评论详情'),
                            ),
                            if (onDelete != null)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除评论'),
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
        ],
      ),
    ),
  );
}

  Widget _buildSubReplyLine(
    BuildContext context,
    Map<String, dynamic> sub,
    Color nameColor,
    ColorScheme scheme,
  ) {
    final subUser = (sub['username'] ?? '').toString();
    final subMsg = (sub['message'] ?? '').toString();
    final ruser = (sub['rusername'] ?? '').toString();
    final subFeed = CoolapkFeed.fromJson(sub);
    final userInfo = sub['userInfo'] ?? sub['user_info'];
    final subUid =
        (sub['uid'] ??
                (userInfo is Map ? userInfo['uid'] ?? userInfo['id'] : null) ??
                '')
            .toString();
    final ruserUid =
        (sub['ruid'] ?? (ruser == reply.username ? reply.uid : null) ?? '')
            .toString();

    InlineSpan userName(String name, String uid) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        onTap: uid.isEmpty ? null : () => _openUserSpace(context, api, uid),
        child: Text(
          name,
          style: TextStyle(
            color: nameColor,
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolapkRichText(
          api: api,
          text: subMsg,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 12.5,
            height: 1.35,
          ),
          prefixSpans: [
            userName(subUser, subUid),
            if (ruser.isNotEmpty) ...[
              TextSpan(
                text: ' 回复 ',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              userName(ruser, ruserUid),
            ],
            TextSpan(
              text: ': ',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        if (subFeed.pictures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PictureGrid(
              api: api,
              urls: subFeed.pictures,
              metadata: subFeed.pictureMetadata,
              isDetail: true,
            ),
          ),
      ],
    );
  }
}

void _openUserSpace(BuildContext context, CoolapkApi api, String uid) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => UserSpacePage(api: api, uid: uid),
    ),
  );
}

Future<void> _openDeviceDiscussion(
  BuildContext context,
  CoolapkApi api,
  String deviceName,
) async {
  final product = await DigitalSystemHelper.resolveDeviceProduct(
    api,
    deviceName,
  );
  if (!context.mounted) return;
  final productId = product.productId?.trim() ?? '';
  if (productId.isEmpty) {
    AppToast.show(context, '暂时无法找到“$deviceName”的机型讨论区');
    return;
  }
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProductPage(
        api: api,
        id: productId,
        title: product.title ?? deviceName,
      ),
    ),
  );
}

class _PictureGrid extends StatelessWidget {
  const _PictureGrid({
    required this.api,
    required this.urls,
    required this.metadata,
    required this.isDetail,
    this.joinedImages = false,
  });
  final CoolapkApi api;
  final List<String> urls;
  final Map<String, Map<String, dynamic>> metadata;
  final bool isDetail;
  final bool joinedImages;

  @override
  Widget build(BuildContext context) {
    int dimension(Map<String, dynamic> metadata, String name) {
      final large = metadata['large'];
      final largeMap = large is Map ? large : const <String, dynamic>{};
      final geo = metadata['geo'];
      final geoMap = geo is Map ? geo : const <String, dynamic>{};
      final largeGeo = largeMap['geo'];
      final largeGeoMap = largeGeo is Map
          ? largeGeo
          : const <String, dynamic>{};
      final value =
          metadata[name] ??
          metadata[name == 'width' ? 'w' : 'h'] ??
          geoMap[name] ??
          largeMap[name] ??
          largeGeoMap[name];
      return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    }

    final pics = urls
        .map((url) {
          final imageMetadata = metadata[url] ?? const <String, dynamic>{};
          return GalleryImage(
            url,
            width: dimension(imageMetadata, 'width'),
            height: dimension(imageMetadata, 'height'),
            raw: imageMetadata,
          );
        })
        .toList(growable: false);

    return NineGridView(
      api: api,
      pics: pics,
      statusId: '',
      isDetail: isDetail,
      joinedImages: joinedImages,
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 38,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _text(dynamic value) => value == null ? '' : value.toString().trim();

bool _isCaptchaError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('captcha') || lower.contains('验证码');
}

List<String> _detailImages(Map<String, dynamic> detail, List<String> fallback) {
  final isDetailHdr =
      detail['is_hdr'] == 1 ||
      detail['is_hdr'] == '1' ||
      detail['is_hdr'] == true ||
      detail['hdr'] == 1 ||
      detail['hdr'] == '1' ||
      detail['hdr'] == true ||
      detail['isHdr'] == 1 ||
      detail['isHdr'] == '1' ||
      detail['isHdr'] == true;
  final raw =
      detail['picArr'] ?? detail['imageUriList'] ?? detail['image_uri_list'];
  if (raw is List) {
    final urls = <String>[];
    for (final value in raw) {
      final url = value is Map
          ? _text(value['url'] ?? value['pic'])
          : _text(value);
      if (url.startsWith('http://') || url.startsWith('https://')) {
        if (!urls.contains(url)) {
          urls.add(url);
          if (isDetailHdr) {
            HdrImageDetector.markHdr(url);
          } else if (value is Map) {
            final vHdr = value['is_hdr'] ?? value['isHdr'] ?? value['hdr'];
            if (vHdr == 1 || vHdr == '1' || vHdr == true) {
              HdrImageDetector.markHdr(url);
            }
          }
        }
      }
    }
    if (urls.isNotEmpty) return urls.toList(growable: false);
  }
  return fallback;
}
