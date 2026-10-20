import 'dart:async';
import 'dart:math' as math;

import 'package:easy_refresh/easy_refresh.dart';

import '../../core/widgets/review_refresh_header.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/design_system/components/review_navigation_bar.dart'
    show ReviewNavigationBar;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/product_price.dart';
import '../../core/network/coolapk_image.dart';
import '../feed/feed_pages.dart';
import '../feed/image_gallery_page.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/utils/spring_page_route.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/theme/app_theme.dart';
import '../digital/utils/digital_system_helper.dart';
import 'app_detail_page.dart';
import 'activity_pages.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../shell/main_pages.dart' show ComposeFeedPage, MessageChatPage;
import '../settings/official_profile_page.dart';
import '../account/local_account_page.dart';
import 'package:flutter/services.dart';

import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import 'product_comparison_page.dart';
import 'community_routes.dart';
import 'community_library_page.dart';
import 'community_detail_page.dart';
import 'reply_notifications_page.dart';

class ApiListPage extends StatefulWidget {
  const ApiListPage({
    required this.api,
    required this.title,
    required this.path,
    this.query = const {},
    this.showAppBar = true,
    this.nested = false,
    this.header,
    this.overlapHandle,
    this.itemBuilder,
    this.showAccessErrors = true,
    this.itemBuilderWithIndex,
    this.itemFilter,
    this.onPageItemsLoaded,
    this.onPageLoaded,
    this.initialItems = const [],
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String path;
  final Map<String, dynamic> query;
  final bool showAppBar;
  final bool showAccessErrors;
  final bool nested;
  final Widget? header;
  final SliverOverlapAbsorberHandle? overlapHandle;
  final Widget Function(BuildContext, Map<String, dynamic>)? itemBuilder;
  final Widget Function(BuildContext, Map<String, dynamic>, int)?
  itemBuilderWithIndex;
  final bool Function(Map<String, dynamic>)? itemFilter;
  final void Function(List<Map<String, dynamic>>)? onPageItemsLoaded;
  final void Function(ApiPage)? onPageLoaded;
  final List<Map<String, dynamic>> initialItems;

  @override
  State<ApiListPage> createState() => _ApiListPageState();
}

class _ApiListPageState extends State<ApiListPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  final _bufferedItems = <Map<String, dynamic>>[];
  String? _error;
  String _first = '';
  String _last = '';
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  bool _pendingRefresh = false;
  int _requestVersion = 0;
  static bool _isFeedEntity(Map<String, dynamic> item) {
    final type = (item['entityType'] ?? item['entity_type'] ?? '')
        .toString()
        .toLowerCase();
    if (type == 'card') return false;
    final feedType = (item['feedType'] ?? item['feed_type'] ?? '')
        .toString()
        .toLowerCase();
    final template = (item['entityTemplate'] ?? item['entity_template'] ?? '')
        .toString()
        .toLowerCase();
    return (type.contains('feed') && !type.contains('reply')) ||
        type.contains('article') ||
        feedType.contains('article') ||
        template.contains('article') ||
        (type.isEmpty && item.containsKey('message'));
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialItems.isNotEmpty) {
      _items.addAll(widget.initialItems);
    }
    _scroll.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ApiListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path ||
        !mapEquals(widget.query, oldWidget.query)) {
      _requestVersion++;
      if (_loading) {
        _pendingRefresh = true;
      } else {
        unawaited(_load(refresh: true));
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (_bufferedItems.isNotEmpty) {
      if (pos.extentAfter < 900 || pos.pixels >= pos.maxScrollExtent * 0.45) {
        setState(() {
          _items.addAll(_bufferedItems);
          _bufferedItems.clear();
        });
      }
    }
    if (_bufferedItems.isEmpty && pos.extentAfter < 520) {
      _load(refresh: false);
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (_loading) {
      if (refresh) _pendingRefresh = true;
      return;
    }
    if (!refresh && _bufferedItems.isNotEmpty) {
      setState(() {
        _items.addAll(_bufferedItems);
        _bufferedItems.clear();
      });
      return;
    }
    if (!refresh && (!_more || _error != null)) return;
    final requestVersion = ++_requestVersion;
    final path = widget.path;
    final query = Map<String, dynamic>.of(widget.query);
    setState(() {
      _loading = true;
      _error = null;
      if (refresh) {
        _bufferedItems.clear();
      }
    });
    final next = refresh ? 1 : _page + 1;
    try {
      final requestPath =
          (path.startsWith('/v6/feed/replyList') ||
              path.startsWith('/v6/feed/hotReplyList'))
          ? 'https://api2.coolapk.com$path'
          : path;
      ApiPage page;
      try {
        page = await widget.api.getList(
          requestPath,
          query: {
            ...query,
            'page': next,
            if (!refresh && _first.isNotEmpty) 'firstItem': _first,
            if (!refresh && _last.isNotEmpty) 'lastItem': _last,
          },
        );
      } catch (_) {
        if (requestPath != path) {
          page = await widget.api.getList(
            path,
            query: {
              ...query,
              'page': next,
              if (!refresh && _first.isNotEmpty) 'firstItem': _first,
              if (!refresh && _last.isNotEmpty) 'lastItem': _last,
            },
          );
        } else {
          rethrow;
        }
      }
      if (!mounted || requestVersion != _requestVersion) return;
      widget.onPageItemsLoaded?.call(page.items);
      widget.onPageLoaded?.call(page);
      setState(() {
        if (refresh) {
          _items.clear();
          _bufferedItems.clear();
          if (widget.initialItems.isNotEmpty) {
            _items.addAll(widget.initialItems);
          }
          _first = '';
          _last = '';
        }
        final known = {
          ..._items.map(_entityKey),
          ..._bufferedItems.map(_entityKey),
        };
        final newItems = page.items
            .where(
              (item) =>
                  (widget.itemFilter?.call(item) ?? true) &&
                  known.add(_entityKey(item)),
            )
            .toList();

        if (newItems.length <= 4) {
          _items.addAll(newItems);
        } else {
          final stage1Count = (newItems.length * 0.6).round().clamp(
            1,
            newItems.length,
          );
          _items.addAll(newItems.take(stage1Count));
          _bufferedItems.addAll(newItems.skip(stage1Count));
        }

        _page = next;
        if (page.firstItem.isNotEmpty) _first = page.firstItem;
        if (page.lastItem.isNotEmpty) _last = page.lastItem;
        _more =
            page.hasMore &&
            (page.items.isNotEmpty || _bufferedItems.isNotEmpty);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _bufferedItems.isEmpty) return;
        if (_scroll.hasClients &&
            (_scroll.position.maxScrollExtent <= 0 ||
                _scroll.position.extentAfter < 500)) {
          setState(() {
            _items.addAll(_bufferedItems);
            _bufferedItems.clear();
          });
        }
      });
      final isSearchAll = path.contains('/v6/search') && query['type'] == 'all';
      final hasNoFeedsInSearchAll = isSearchAll && !_items.any(_isFeedEntity);
      final shouldPreloadNext =
          refresh &&
          page.hasMore &&
          (_items.length <= 4 || hasNoFeedsInSearchAll);
      if (shouldPreloadNext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loading && _more) {
            _load(refresh: false);
          }
        });
      }
    } catch (error) {
      final errorStr = error.toString();
      if (path.contains('/feed/replyList') && query['id'] != null) {
        if (mounted) {
          try {
            final parentId = query['id'].toString();
            final detailRes = await widget.api.getReplyDetail(parentId);
            final data = detailRes['data'];
            if (data is Map) {
              final rawRows =
                  data['replyRows'] ??
                  data['subReplyRows'] ??
                  data['replyList'] ??
                  data['subReplyList'];
              final existingIds = _items.map(_entityKey).toSet();
              if (rawRows is List && rawRows.isNotEmpty) {
                for (final row in rawRows.whereType<Map>()) {
                  final mapRow = Map<String, dynamic>.from(row);
                  if (existingIds.add(_entityKey(mapRow))) {
                    _items.add(mapRow);
                  }
                }
              }
              final recentIds =
                  (data['recent_reply_ids'] ?? data['recentReplyIds'])
                      ?.toString() ??
                  '';
              if (recentIds.isNotEmpty) {
                final ids = recentIds
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                final fetchedSubReplies = await Future.wait(
                  ids.take(15).map((subId) async {
                    if (existingIds.contains(subId)) return null;
                    try {
                      final subDetail = await widget.api.getReplyDetail(subId);
                      final subData = subDetail['data'];
                      if (subData is Map) {
                        return Map<String, dynamic>.from(subData);
                      }
                    } catch (_) {}
                    return null;
                  }),
                );
                for (final item in fetchedSubReplies) {
                  if (item != null && existingIds.add(_entityKey(item))) {
                    _items.add(item);
                  }
                }
              }
              _more = false;
            }
          } catch (_) {}
        }
      }
      if (mounted && requestVersion == _requestVersion) {
        setState(() {
          _error = path.contains('/feed/replyList') && _items.isNotEmpty
              ? null
              : errorStr;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_pendingRefresh) {
          _pendingRefresh = false;
          unawaited(_load(refresh: true));
        }
      }
    }
  }

  Future<void> _retry({required bool refresh}) async {
    if (_loading) return;
    setState(() => _error = null);
    await _load(refresh: refresh);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isTodayHeadline =
        widget.title.trim().startsWith('今日酷安') ||
        widget.path == '/v6/main/headline' ||
        widget.path == '/main/headline';
    final isCollectionList =
        widget.path.contains('/collection/myCollectionList') ||
        widget.path.contains('/collection/list') ||
        (widget.title.contains('收藏单') &&
            !widget.path.contains('/collection/itemlist'));
    final isArticleList =
        widget.path == '/v6/user/htmlFeedList' ||
        widget.path.contains('htmlFeedList') ||
        widget.path.contains('articleList') ||
        (widget.path.contains('/search') &&
            (widget.query['type'] == 'feedArticle' ||
                widget.query['feedType'] == 'feedArticle'));
    final now = DateTime.now();
    final pageTitle = isTodayHeadline
        ? '今日酷安:${now.year}年${now.month}月${now.day}日'
        : widget.title;
    final listPadding = _items.isEmpty
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.fromLTRB(
            0,
            widget.header != null || isTodayHeadline || isCollectionList
                ? 0
                : 10,
            0,
            24 + MediaQuery.paddingOf(context).bottom,
          );
    final delegate = _items.isEmpty
        ? SliverChildListDelegate([
            if (widget.header != null) widget.header!,
            SizedBox(
              height:
                  MediaQuery.sizeOf(context).height *
                  (widget.itemBuilder == null ? 0.55 : 0.2),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.showAccessErrors && _error != null
                                ? _error!
                                : _error == null ||
                                      _error!.contains('验证码') ||
                                      _error!.contains('受限') ||
                                      _error!.contains('限制') ||
                                      _error!.toLowerCase().contains(
                                        'captcha',
                                      ) ||
                                      _error!.contains('403')
                                ? '暂无内容'
                                : _error!,
                          ),
                          if ((widget.showAccessErrors && _error != null) ||
                              (_error != null &&
                                  !_error!.contains('验证码') &&
                                  !_error!.contains('受限') &&
                                  !_error!.contains('限制') &&
                                  !_error!.toLowerCase().contains('captcha') &&
                                  !_error!.contains('403')))
                            TextButton(
                              onPressed: () => _retry(refresh: true),
                              child: const Text('重试'),
                            ),
                        ],
                      ),
              ),
            ),
          ])
        : isCollectionList
        ? SliverChildListDelegate([
            if (widget.header != null) widget.header!,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E1E22)
                      : Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 114,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Theme.of(context).dividerColor
                                    .withValues(alpha: 0.25),
                        ),
                      _CollectionTile(api: widget.api, entity: _items[i]),
                    ],
                  ],
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null &&
                !_error!.contains('验证码') &&
                !_error!.contains('受限') &&
                !_error!.contains('限制') &&
                !_error!.toLowerCase().contains('captcha') &&
                !_error!.contains('403'))
              TextButton(
                onPressed: () => _retry(refresh: false),
                child: Text('加载失败，点击重试：$_error'),
              ),
          ])
        : SliverChildBuilderDelegate(
            (context, index) {
              if (widget.header != null) {
                if (index == 0) return widget.header!;
              }
              final itemIndex = widget.header != null ? index - 1 : index;
              if (itemIndex == _items.length) {
                if (_loading) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_error != null &&
                    (_error!.contains('验证码') ||
                        _error!.contains('受限') ||
                        _error!.contains('限制') ||
                        _error!.toLowerCase().contains('captcha') ||
                        _error!.contains('403'))) {
                  return const SizedBox.shrink();
                }
                return TextButton(
                  onPressed: () => _retry(refresh: false),
                  child: Text('加载失败，点击重试：$_error'),
                );
              }
              final item = _items[itemIndex];
              final searchScope = SearchResultsScope.of(context);
              final isSearchAll =
                  searchScope != null &&
                  widget.header == null &&
                  widget.path.contains('/v6/search') &&
                  widget.query['type'] == 'all';

              final cardWidget =
                  widget.itemBuilderWithIndex?.call(context, item, itemIndex) ??
                  widget.itemBuilder?.call(context, item) ??
                  (isTodayHeadline
                      ? _TodayCoolapkCard(
                          key: ValueKey(_entityKey(item)),
                          api: widget.api,
                          entity: item,
                        )
                      : ApiEntityCard(
                          key: ValueKey(_entityKey(item)),
                          api: widget.api,
                          entity: item,
                          articleLayout: isArticleList,
                        ));

              if (isSearchAll) {
                final firstFeedIndex = _items.indexWhere(_isFeedEntity);
                final isFirstFeed =
                    firstFeedIndex != -1 && itemIndex == firstFeedIndex;
                final isLastCardWithoutFeed =
                    firstFeedIndex == -1 && itemIndex == _items.length - 1;

                if (isFirstFeed) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SearchFeedSectionHeader(
                        currentSort: searchScope.allSortType,
                        onSortChanged: searchScope.onAllSortChanged,
                      ),
                      cardWidget,
                    ],
                  );
                } else if (isLastCardWithoutFeed) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      cardWidget,
                      SearchFeedSectionHeader(
                        currentSort: searchScope.allSortType,
                        onSortChanged: searchScope.onAllSortChanged,
                        isLoading: _more,
                      ),
                    ],
                  );
                }
              }

              return cardWidget;
            },
            childCount:
                _items.length +
                (widget.header != null ? 1 : 0) +
                (_loading || _error != null ? 1 : 0),
          );
    final scrollable = widget.overlapHandle == null
        ? ListView.custom(
            controller: widget.nested ? null : _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
            padding: listPadding,
            childrenDelegate: delegate,
          )
        : CustomScrollView(
            key: PageStorageKey(widget.key),
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(800.0),
            slivers: [
              SliverOverlapInjector(handle: widget.overlapHandle!),
              SliverPadding(
                padding: listPadding,
                sliver: SliverList(delegate: delegate),
              ),
            ],
          );
    final list = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < 520) {
          _load(refresh: false);
        }
        return false;
      },
      child: EasyRefresh(
        header: reviewDefaultRefreshHeader,
        triggerAxis: Axis.vertical,
        onRefresh: () => _load(refresh: true),
        child: filterHorizontalScrollNotifications(scrollable),
      ),
    );
    if (!widget.showAppBar) return list;
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        toolbarHeight: isTodayHeadline ? 56 : 52,
        titleSpacing: isTodayHeadline ? 4 : null,
        title: Text(pageTitle),
        actions: isTodayHeadline
            ? [
                IconButton(
                  tooltip: '刷新',
                  onPressed: () => unawaited(_load(refresh: true)),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ]
            : isCollectionList
            ? [
                IconButton(
                  tooltip: '新建收藏单',
                  onPressed: _showCreateCollectionDialog,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]
            : null,
      ),
      body: list,
    );
  }

  Future<void> _showCreateCollectionDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    var isOpen = true;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建收藏单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '请输入收藏单名称',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '说明（选填）',
                  hintText: '请输入收藏单说明',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('公开收藏单'),
                subtitle: Text(
                  isOpen ? '所有人可见' : '仅自己可见',
                  style: const TextStyle(fontSize: 12),
                ),
                value: isOpen,
                onChanged: (val) => setDialogState(() => isOpen = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    final name = titleController.text.trim();
    final desc = descController.text.trim();
    titleController.dispose();
    descController.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      await widget.api.createCollection(
        name,
        description: desc,
        isOpen: isOpen,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('创建收藏单成功')));
        _load(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }
}

class SearchResultsScope extends InheritedWidget {
  const SearchResultsScope({
    required this.query,
    required this.allSortType,
    required this.onAllSortChanged,
    required this.onSwitchToUserTab,
    required super.child,
    super.key,
  });

  final String query;
  final String allSortType;
  final ValueChanged<String> onAllSortChanged;
  final VoidCallback onSwitchToUserTab;

  static SearchResultsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchResultsScope>();

  @override
  bool updateShouldNotify(SearchResultsScope oldWidget) =>
      query != oldWidget.query || allSortType != oldWidget.allSortType;
}

class SearchSortCapsule extends StatelessWidget {
  const SearchSortCapsule({
    required this.currentSort,
    required this.onSortChanged,
    super.key,
  });

  final String currentSort;
  final ValueChanged<String> onSortChanged;

  static const _sortItems = [
    (label: '综合', value: 'default'),
    (label: '实时', value: 'dateline'),
    (label: '热度', value: 'hot'),
    (label: '评论', value: 'reply'),
    (label: '精确', value: 'exact'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _sortItems)
            _buildItem(context, item.label, item.value),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, String label, String value) {
    final isSelected = currentSort == value;
    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.selection();
        onSortChanged(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2C313A) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF00B075) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class SearchFeedSectionHeader extends StatelessWidget {
  const SearchFeedSectionHeader({
    required this.currentSort,
    required this.onSortChanged,
    this.isLoading = false,
    super.key,
  });

  final String currentSort;
  final ValueChanged<String> onSortChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '动态',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SearchSortCapsule(
                currentSort: currentSort,
                onSortChanged: onSortChanged,
              ),
            ],
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class SearchFilterDropdown extends StatelessWidget {
  const SearchFilterDropdown({
    required this.currentFilter,
    required this.onFilterChanged,
    super.key,
  });

  final String currentFilter;
  final ValueChanged<String> onFilterChanged;

  static const _filterItems = [
    (label: '全部', value: 'all'),
    (label: '图文', value: 'feedArticle'),
    (label: '纯文字', value: 'feed'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentLabel = _filterItems
        .firstWhere(
          (e) => e.value == currentFilter,
          orElse: () => _filterItems.first,
        )
        .label;

    return PopupMenuButton<String>(
      onSelected: (val) {
        HapticFeedbackUtil.selection();
        onFilterChanged(val);
      },
      color: const Color(0xFF22252C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final item in _filterItems)
          PopupMenuItem<String>(
            value: item.value,
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: currentFilter == item.value
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: currentFilter == item.value
                    ? const Color(0xFF00B075)
                    : Colors.white,
              ),
            ),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentLabel,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}

class SearchFeedHeaderBar extends StatelessWidget {
  const SearchFeedHeaderBar({
    required this.currentSort,
    required this.onSortChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    super.key,
  });

  final String currentSort;
  final ValueChanged<String> onSortChanged;
  final String currentFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SearchSortCapsule(
            currentSort: currentSort,
            onSortChanged: onSortChanged,
          ),
          SearchFilterDropdown(
            currentFilter: currentFilter,
            onFilterChanged: onFilterChanged,
          ),
        ],
      ),
    );
  }
}

class ApiEntityCard extends StatelessWidget {
  const ApiEntityCard({
    required this.api,
    required this.entity,
    this.articleLayout = false,
    super.key,
  });

  final CoolapkApi api;
  final Map<String, dynamic> entity;
  final bool articleLayout;

  String _value(Iterable<String> keys) {
    for (final key in keys) {
      final value = entity[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  static String extractTopicTag(Map<String, dynamic> entity) {
    final url = (entity['url'] ?? '').toString();
    if (url.contains('/t/')) {
      var sub = url.substring(url.indexOf('/t/') + 3);
      if (sub.contains('?')) sub = sub.substring(0, sub.indexOf('?'));
      if (sub.contains('/')) sub = sub.substring(0, sub.indexOf('/'));
      // A /t/ URL may contain raw Chinese, which decodeComponent rejects.
      var decoded = sub;
      try {
        decoded = Uri.decodeComponent(sub);
      } catch (_) {}
      decoded = decoded.replaceAll('#', '').trim();
      if (decoded.isNotEmpty && int.tryParse(decoded) == null) return decoded;
    }
    final uri = Uri.tryParse(
      url.startsWith('/') ? 'https://coolapk.com$url' : url,
    );
    final queryTag =
        uri?.queryParameters['tag']?.replaceAll('#', '').trim() ?? '';
    if (queryTag.isNotEmpty) return queryTag;
    for (final key in ['tag', 'tagName', 'title', 'name']) {
      final val = entity[key]?.toString().trim() ?? '';
      if (val.isNotEmpty && int.tryParse(val) == null) {
        return val.replaceAll('#', '').trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final type = _value(['entityType', 'entity_type']).toLowerCase();
    final template = _value(['entityTemplate', 'entity_template'])
        .toLowerCase();
    final feedType = _value(['feedType', 'feed_type']).toLowerCase();
    final isArticle =
        articleLayout ||
        type == 'article' ||
        type == 'feedarticle' ||
        type == 'feed_article' ||
        type == 'dyharticle' ||
        template == 'feedarticle' ||
        template == 'feed_article' ||
        template == 'article' ||
        template == 'dyharticle' ||
        feedType == 'feedarticle' ||
        feedType == 'feed_article' ||
        feedType == 'article' ||
        feedType == 'dyharticle';

    if (type == 'card') return _buildTemplate(context);
    if ((type.contains('feed') && !type.contains('reply')) ||
        type.contains('article') ||
        isArticle ||
        (type.isEmpty && entity.containsKey('message'))) {
      CoolapkFeed feed;
      final cachedFeed = entity['_cached_feed_model'];
      if (cachedFeed is CoolapkFeed) {
        feed = cachedFeed;
      } else {
        feed = CoolapkFeed.fromJson(entity);
        try {
          entity['_cached_feed_model'] = feed;
        } catch (_) {}
      }
      if (feed.id.isNotEmpty) {
        return FeedCard(
          key: ValueKey('feed-${feed.id}'),
          api: api,
          feed: feed,
          articleLayout: isArticle,
        );
      }
    }
    final isTopic = type.contains('topic') || type.contains('tag');
    final isApk = type.contains('apk') || type.contains('app');
    final isCollection = type.contains('collection');
    if (isCollection) {
      return _CollectionTile(api: api, entity: entity);
    }
    final topicTag = isTopic ? extractTopicTag(entity) : '';
    final id = isTopic && topicTag.isNotEmpty
        ? topicTag
        : _value(
            isApk
                ? ['packageName', 'package_name', 'apkname', 'apk_name', 'id']
                : isCollection
                ? ['id', 'collectionId', 'collection_id']
                : [
                    'uid',
                    'id',
                    'packageName',
                    'package_name',
                    'tag',
                    'tagName',
                    'productId',
                  ],
          );
    final title = _value([
      'goods_title',
      'title',
      'username',
      'userName',
      'apkName',
      'apk_name',
      'productName',
      'tag',
    ]);
    final subtitleValue = _value([
      'description',
      'message',
      'subTitle',
      'apkVersion',
      'brief',
    ]);
    final subtitle = subtitleValue.isNotEmpty
        ? subtitleValue
        : _entitySummary(type);
    var image = _value([
      'goods_pic',
      'userAvatar',
      'avatar',
      'logo',
      'icon',
      'pic',
      'cover',
      'tagLogo',
      'tag_logo',
      'img',
    ]);
    if (image.isEmpty) {
      final preset = DigitalSystemHelper.getSystemPresetLogo(title);
      if (preset != null && preset.isNotEmpty) {
        image = preset;
      }
    }
    return RepaintBoundary(
      child: InkWell(
        onTap: id.isEmpty ? null : () => _open(context, type, id, entity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    normalizeCoolapkImageUrl(image),
                    headers: coolapkImageHeaders(image, api: api),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _icon(context, type),
                  ),
                )
              else
                _icon(context, type),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '酷安内容' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _plain(subtitle),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  String _entitySummary(String type) {
    String field(List<String> keys) => _value(keys);
    switch (type) {
      case 'user':
      case 'contacts':
        return [
          if (field(['follow', 'followNum']).isNotEmpty)
            '${field(['follow', 'followNum'])}关注',
          if (field(['fans', 'fansNum']).isNotEmpty)
            '${field(['fans', 'fansNum'])}粉丝',
        ].join(' · ');
      case 'product':
        return [
          if (field(['hotNumTxt', 'hot_num_txt', 'hot_num']).isNotEmpty)
            '${field(['hotNumTxt', 'hot_num_txt', 'hot_num'])}热度',
          if (field(['feedCommentNumTxt', 'commentnum']).isNotEmpty)
            '${field(['feedCommentNumTxt', 'commentnum'])}讨论',
        ].join(' · ');
      case 'apk':
        return [
          if (field(['commentnum', 'commentNum']).isNotEmpty)
            '${field(['commentnum', 'commentNum'])}讨论',
          if (field(['downCount', 'apkDownCount']).isNotEmpty)
            '${field(['downCount', 'apkDownCount'])}下载',
        ].join(' · ');
      case 'topic':
      case 'tag':
        return [
          if (field(['hotNumTxt', 'hot_num_txt']).isNotEmpty)
            '${field(['hotNumTxt', 'hot_num_txt'])}热度',
          if (field(['commentnumTxt', 'commentnum']).isNotEmpty)
            '${field(['commentnumTxt', 'commentnum'])}讨论',
        ].join(' · ');
      default:
        return '';
    }
  }

  Widget _buildTemplate(BuildContext context) {
    final template = _value(['entityTemplate', 'entity_template']);
    final title = _value(['title', 'subTitle']);
    final rawEntities = entity['entities'];
    final entities = (rawEntities is List ? rawEntities : const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (template == 'textCard') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (_value(['description']).isNotEmpty) ...[
              const SizedBox(height: 8),
              CoolapkRichText(
                api: api,
                text: _value(['description']),
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(height: 1.6),
              ),
            ],
          ],
        ),
      );
    }
    if (template == 'imageScaleCard') {
      final picture = _value(['pic']).isNotEmpty
          ? _value(['pic'])
          : (entities.isEmpty ? '' : _first(entities.first, ['pic']));
      final dimensions = RegExp(r'@(\d+)x(\d+)').firstMatch(picture);
      final width = double.tryParse(dimensions?.group(1) ?? '');
      final height = double.tryParse(dimensions?.group(2) ?? '');
      if (picture.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio:
                width != null && height != null && width > 0 && height > 0
                ? width / height
                : 4.5,
            child: CachedNetworkImage(
              normalizeCoolapkImageUrl(picture),
              headers: coolapkImageHeaders(picture, api: api),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }
    if (template == 'refreshCard' && _value(['url']).isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => openHeadlineTarget(context, api, entity),
          child: Text(title),
        ),
      );
    }
    if (template == 'noMoreDataCard' || entities.isEmpty && title.isEmpty) {
      return const SizedBox.shrink();
    }
    if (template == 'headCard' || template == 'titleCard') {
      final description = _value(['description', 'subTitle']);
      if (title.isEmpty && description.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (description.isNotEmpty)
              Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    final isGrid = const {
      'iconLinkGridCard',
      'iconMiniGridCard',
      'imageTextGridCard',
    }.contains(template);
    final isHorizontal = const {
      'imageCarouselCard_1',
      'iconMiniScrollCard',
      'iconLargeScrollCard',
      'imageSquareScrollCard',
      'iconScrollCard',
      'imageTextScrollCard',
    }.contains(template);
    final children = entities
        .map((item) => ApiEntityCard(api: api, entity: item))
        .toList(growable: false);
    if (isGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            childAspectRatio: 0.82,
            children: [
              for (final item in entities)
                _TemplateItem(api: api, item: item, compact: true),
            ],
          ),
        ],
      );
    }
    if (isHorizontal) {
      final isUserCard =
          title == '用户' ||
          entities.any(
            (e) =>
                (e['entityType'] ?? e['entity_type'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains('user') ||
                e.containsKey('uid'),
          );
      if (isUserCard) {
        final searchScope = SearchResultsScope.of(context);
        final userCard = Container(
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  '用户',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 104,
                child: protectHorizontalDragFromVerticalRefresh(
                  ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: entities.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, index) => SizedBox(
                      width: 72,
                      child: _TemplateItem(api: api, item: entities[index]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedbackUtil.light();
                    if (searchScope != null) {
                      searchScope.onSwitchToUserTab();
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      '更多相关用户',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF00B075),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return userCard;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          SizedBox(
            height: 116,
            child: protectHorizontalDragFromVerticalRefresh(
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                itemCount: entities.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) => SizedBox(
                  width: 92,
                  child: _TemplateItem(api: api, item: entities[index]),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ...children,
      ],
    );
  }

  Widget _icon(BuildContext context, String type) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(_iconFor(type)),
  );

  IconData _iconFor(String type) {
    if (type.contains('user')) return Icons.person_outline_rounded;
    if (type.contains('apk') || type.contains('app')) {
      return Icons.apps_rounded;
    }
    if (type.contains('topic') || type.contains('tag')) {
      return Icons.tag_rounded;
    }
    if (type.contains('product') || type.contains('rating')) {
      return Icons.devices_rounded;
    }
    return Icons.article_outlined;
  }

  void _open(
    BuildContext context,
    String type,
    String id, [
    Map<String, dynamic>? item,
  ]) {
    final data = item ?? entity;
    final specialized = communityPageForEntity(api, data);
    if (specialized != null) {
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => specialized));
      return;
    }
    final activity = activityGoodsUrl(data);
    if (activity != null) {
      openActivityDocument(
        context,
        api,
        activity,
        title: _first(data, ['goods_title', 'title', 'name']),
      );
      return;
    }
    if (type.contains('dyh')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DyhPage(
            api: api,
            id: id,
            title: _value(['title', 'name']).isEmpty
                ? '看看号'
                : _value(['title', 'name']),
          ),
        ),
      );
      return;
    }
    if (type.contains('event')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailPage(api: api, id: id),
        ),
      );
      return;
    }
    if (type.contains('reply')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReplyThreadPage(api: api, id: id, initial: data),
        ),
      );
      return;
    }
    if (type.contains('category')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RawEntityPage(api: api, entity: entity),
        ),
      );
      return;
    }
    if (type.contains('user')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UserSpacePage(api: api, uid: id),
        ),
      );
      return;
    }
    if (type.contains('product') || type.contains('rating')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductPage(api: api, id: id, title: _value(['title', 'name'])),
        ),
      );
      return;
    }
    if (type.contains('apk') || type.contains('app')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AppDetailPage(api: api, id: id, initialEntity: item),
        ),
      );
      return;
    }
    if (type.contains('topic') || type.contains('tag')) {
      final topicTag = extractTopicTag(data);
      final tag = topicTag.isNotEmpty ? topicTag : id;
      final title = _first(data, ['title', 'name', 'tag', 'tagName']);
      final logo = _first(data, ['logo', 'icon', 'pic', 'avatar']);
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(
            api: api,
            tag: tag,
            initialTitle: title.isNotEmpty ? title : null,
            initialLogo: logo.isNotEmpty ? logo : null,
          ),
        ),
      );
      return;
    }
    if (type.contains('collection')) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ApiListPage(
            api: api,
            title: _value(['title', 'name']),
            path: '/v6/collection/itemlist',
            query: {'id': id},
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RawEntityPage(api: api, entity: entity),
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.api, required this.entity});

  final CoolapkApi api;
  final Map<String, dynamic> entity;

  String _val(List<String> keys) {
    for (final k in keys) {
      final v = entity[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final id = _val(['id', 'collectionId', 'collection_id']);
    final title = _val(['title', 'name']);

    final isOpenVal = _val(['is_open', 'isOpen', 'status']);
    final isPrivate = isOpenVal == '0' || isOpenVal == 'private';
    final privacy = isPrivate ? '私密' : '公开';

    final followNum = _val(['follow_num', 'followNum', 'follownum']);
    final followText = '${followNum.isEmpty ? '1' : followNum}人关注';

    final contentNum = _val([
      'content_num',
      'contentNum',
      'item_num',
      'itemNum',
      'feed_num',
      'feednum',
      'num',
      'count',
    ]);
    final contentText = '${contentNum.isEmpty ? '0' : contentNum}个内容';

    final subtitle = '$privacy  $followText  $contentText';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: id.isEmpty
          ? null
          : () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CommunityDetailPage(
                    api: api,
                    id: id,
                    kind: CommunityKind.collection,
                    initial: entity,
                  ),
                ),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 84,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1FD5D2), Color(0xFF20D4A0)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF20D4A0).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.folder_outlined,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty ? '收藏单' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white38 : Colors.black38,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCoolapkCard extends StatelessWidget {
  const _TodayCoolapkCard({required this.api, required this.entity, super.key});

  final CoolapkApi api;
  final Map<String, dynamic> entity;

  List<Map<String, dynamic>> get _entities => (entity['entities'] is List)
      ? (entity['entities'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false)
      : const [];

  String get _title =>
      (entity['title'] ?? entity['subTitle'] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final template =
        (entity['entityTemplate'] ?? entity['entity_template'] ?? '')
            .toString();
    final notice = _plain(
      '$_title ${entity['description'] ?? entity['subTitle'] ?? ''}',
    );
    if (notice.contains('爆料信息不一定准确')) {
      return _TodayCoolapkNotice(text: notice.trim());
    }
    if (_plain(_title).contains('今日话题') && _entities.isNotEmpty) {
      return _TodayCoolapkTopics(api: api, title: _title, items: _entities);
    }
    final imageGrid =
        template == 'imageTextGridCard' ||
        (const {
              'iconGridCard',
              'iconMiniGridCard',
              'iconLinkGridCard',
            }.contains(template) &&
            _entities.any((item) {
              final image =
                  item['pic'] ??
                  item['image'] ??
                  item['cover'] ??
                  item['coverPic'] ??
                  item['img'] ??
                  item['goods_pic'] ??
                  item['feedPic'] ??
                  item['feed_pic'] ??
                  item['logo'] ??
                  item['icon'];
              return image != null && image.toString().trim().isNotEmpty;
            }));
    if (imageGrid && _entities.isNotEmpty) {
      return _TodayCoolapkFeatures(api: api, items: _entities);
    }
    return ApiEntityCard(api: api, entity: entity);
  }
}

class _TodayCoolapkFeatures extends StatelessWidget {
  const _TodayCoolapkFeatures({required this.api, required this.items});

  final CoolapkApi api;
  final List<Map<String, dynamic>> items;

  static const _fallbackColors = [
    Color(0xFF344768),
    Color(0xFF496236),
    Color(0xFF595959),
    Color(0xFF858585),
  ];

  Color _background(Map<String, dynamic> item, int index) {
    final raw =
        item['bgColor'] ??
        item['bg_color'] ??
        item['backgroundColor'] ??
        item['background_color'] ??
        item['color'];
    if (raw is num) {
      final value = raw.toInt();
      return Color(value <= 0xFFFFFF ? 0xFF000000 | value : value);
    }
    final value = raw?.toString().trim().replaceFirst('#', '') ?? '';
    if (value.length == 6 || value.length == 8) {
      final parsed = int.tryParse(value, radix: 16);
      if (parsed != null) {
        return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
      }
    }
    return _fallbackColors[index % _fallbackColors.length];
  }

  String _text(Map<String, dynamic> item) =>
      (item['title'] ?? item['goods_title'] ?? item['name'] ?? '').toString();

  String _image(Map<String, dynamic> item) =>
      (item['pic'] ??
              item['image'] ??
              item['cover'] ??
              item['coverPic'] ??
              item['img'] ??
              item['goods_pic'] ??
              item['feedPic'] ??
              item['feed_pic'] ??
              item['logo'] ??
              item['icon'] ??
              '')
          .toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          final background = _background(item, index);
          final image = _image(item);
          return Material(
            color: background,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openHeadlineTarget(context, api, item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: image.isEmpty
                        ? const SizedBox.shrink()
                        : CachedNetworkImage(
                            normalizeCoolapkImageUrl(image),
                            headers: coolapkImageHeaders(image, api: api),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                  ),
                  SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _text(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
                      ),
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

class _TodayCoolapkTopics extends StatelessWidget {
  const _TodayCoolapkTopics({
    required this.api,
    required this.title,
    required this.items,
  });

  final CoolapkApi api;
  final String title;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = title.replaceFirst('🔥', '').trim();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Color(0xFFFF633D),
                size: 22,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  heading.isEmpty ? '今日话题' : heading,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < (items.length.clamp(0, 4) / 2).ceil(); row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 6),
              child: Row(
                children: [
                  for (final item in items.skip(row * 2).take(2))
                    Expanded(
                      child: _TodayCoolapkTopicItem(api: api, item: item),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayCoolapkTopicItem extends StatelessWidget {
  const _TodayCoolapkTopicItem({required this.api, required this.item});

  final CoolapkApi api;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final card = ApiEntityCard(api: api, entity: item);
    final title = card._value(['title', 'name', 'tag']);
    final image = card._value(['pic', 'image', 'cover', 'logo', 'icon']);
    final tag = ApiEntityCard.extractTopicTag(item);
    return InkWell(
      onTap: () => openHeadlineTarget(context, api, item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: image.isEmpty
                  ? Container(
                      width: 34,
                      height: 34,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Text(
                        tag.isEmpty
                            ? '#'
                            : String.fromCharCode(tag.runes.first),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                  : CachedNetworkImage(
                      normalizeCoolapkImageUrl(image),
                      headers: coolapkImageHeaders(image, api: api),
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 34, height: 34),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCoolapkNotice extends StatelessWidget {
  const _TodayCoolapkNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TemplateItem extends StatelessWidget {
  const _TemplateItem({
    required this.api,
    required this.item,
    this.compact = false,
  });

  final CoolapkApi api;
  final Map<String, dynamic> item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = ApiEntityCard(api: api, entity: item);
    final title = card._value([
      'goods_title',
      'title',
      'name',
      'username',
      'productName',
      'tag',
    ]);
    final image = card._value([
      'goods_pic',
      'logo',
      'icon',
      'pic',
      'cover',
      'avatar',
    ]);
    final type = card._value(['entityType', 'entity_type']).toLowerCase();
    final isUser =
        type.contains('user') ||
        item.containsKey('uid') ||
        (item.containsKey('username') && !type.contains('feed'));
    final url = card._value(['url']);
    final isTopic =
        type.contains('topic') || type.contains('tag') || url.contains('/t/');
    final topicTag = isTopic ? ApiEntityCard.extractTopicTag(item) : '';
    final id = isTopic && topicTag.isNotEmpty
        ? topicTag
        : card._value(['uid', 'id', 'productId', 'tag']);
    return InkWell(
      onTap: isTopic
          ? () => card._open(
              context,
              'topic',
              id.isNotEmpty ? id : topicTag,
              item,
            )
          : id.isNotEmpty
          ? () => card._open(context, type, id, item)
          : url.isEmpty
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ApiListPage(
                  api: api,
                  title: title.isEmpty ? '酷安内容' : title,
                  path: '/v6/page/dataList',
                  query: {'url': url},
                ),
              ),
            ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(isUser ? 100 : 10),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(image),
                  headers: coolapkImageHeaders(image, api: api),
                  width: isUser ? 52 : (compact ? 42 : 64),
                  height: isUser ? 52 : (compact ? 42 : 64),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    isUser
                        ? Icons.person_outline_rounded
                        : Icons.widgets_outlined,
                    size: compact ? 30 : 40,
                  ),
                ),
              )
            else
              Icon(
                isUser ? Icons.person_outline_rounded : Icons.widgets_outlined,
                size: compact ? 30 : 40,
              ),
            const SizedBox(height: 6),
            Text(
              title.isEmpty ? '更多' : title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: isUser
                  ? const TextStyle(fontSize: 12, color: Colors.white70)
                  : Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class RawEntityPage extends StatelessWidget {
  const RawEntityPage({required this.api, required this.entity, super.key});
  final CoolapkApi api;
  final Map<String, dynamic> entity;

  @override
  Widget build(BuildContext context) {
    final title = _first(entity, ['title', 'name', 'username', 'tag']);
    return Scaffold(
      appBar: ReviewFrostedAppBar(title: Text(title.isEmpty ? '酷安内容' : title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ObjectHeader(api: api, data: entity),
          for (final entry in entity.entries)
            if (!_isComplex(entry.value))
              ListTile(
                title: Text(_humanize(entry.key)),
                subtitle: SelectableText(entry.value.toString()),
              ),
        ],
      ),
    );
  }
}

class ApiDetailPage extends StatefulWidget {
  const ApiDetailPage({
    required this.api,
    required this.title,
    required this.path,
    required this.query,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String path;
  final Map<String, dynamic> query;

  @override
  State<ApiDetailPage> createState() => _ApiDetailPageState();
}

class _ApiDetailPageState extends State<ApiDetailPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        widget.path,
        query: widget.query,
      );
      if (!mounted) return;
      final root = response is Map<String, dynamic>
          ? response
          : <String, dynamic>{};
      final data = root['data'];
      setState(() {
        _data = data is Map ? Map<String, dynamic>.from(data) : root;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data ?? const <String, dynamic>{};
    return Scaffold(
      appBar: ReviewFrostedAppBar(title: Text(widget.title)),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
          ? _RetryView(message: _error!, onRetry: _load)
          : EasyRefresh(
              header: reviewDefaultRefreshHeader,
              onRefresh: _load,
              child: filterHorizontalScrollNotifications(
                ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ObjectHeader(api: widget.api, data: data),
                    const SizedBox(height: 12),
                    for (final entry in data.entries)
                      if (!_isComplex(entry.value))
                        ListTile(
                          title: Text(_humanize(entry.key)),
                          subtitle: Text(entry.value.toString()),
                          isThreeLine: entry.value.toString().length > 60,
                        ),
                    if (_error != null)
                      TextButton(onPressed: _load, child: Text('刷新失败：$_error')),
                  ],
                ),
              ),
            ),
    );
  }
}

class CoolPicPage extends StatefulWidget {
  const CoolPicPage({required this.api, super.key});

  final CoolapkApi api;

  @override
  State<CoolPicPage> createState() => _CoolPicPageState();
}

class EventDetailPage extends StatelessWidget {
  const EventDetailPage({required this.api, required this.id, super.key});
  final CoolapkApi api;
  final String id;
  @override
  Widget build(BuildContext context) => CrowdTestPage(api: api, id: id);
}

class _CoolPicPageState extends State<CoolPicPage> {
  int _selectedShortcutIndex = 0; // 0: 热门, 1: 2K, 2: 全面屏, 3: 平板, 4: 最新

  static const List<Map<String, String>> _topicCards = [
    {
      'title': '#风景#',
      'tag': '风景',
      'pic': 'https://image.coolapk.com/feed_tag/2024/0118/16/20240118-164741-943015-o_1hki865j51p1m131n1g9k165i1uon1a-uid-453007@1080x1080.png',
    },
    {
      'title': '#二次元#',
      'tag': '二次元',
      'pic': 'https://img.coolapk.com/picture/2021/0122/10/1032338_1611283624_5739.png',
    },
    {
      'title': '#生活#',
      'tag': '生活',
      'pic': 'http://image.coolapk.com/product_logo/2019/1226/10/0_8718_7917@182x90.jpg',
    },
    {
      'title': '#艺术#',
      'tag': '艺术',
      'pic': 'http://image.coolapk.com/product_logo/2025/0427/16/0_3140_2957_310@1000x500.png',
    },
    {
      'title': '#运动#',
      'tag': '运动',
      'pic': 'http://image.coolapk.com/product_logo/2019/1226/10/0_6008_4842@160x80.jpg',
    },
    {
      'title': '#美女#',
      'tag': '美女',
      'pic': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269382_1688.png',
    },
    {
      'title': '#手机壁纸#',
      'tag': '手机壁纸',
      'pic': 'http://image.coolapk.com/product_logo/2019/1226/10/0_9017_754@160x80.jpg',
    },
    {
      'title': '#插画#',
      'tag': '插画',
      'pic': 'https://img.coolapk.com/picture/2021/0401/17/1032338_1617269527_5239.png',
    },
    {
      'title': '#汽车#',
      'tag': '汽车',
      'pic': 'http://image.coolapk.com/product_logo/2019/1226/10/0_7890_1234@160x80.jpg',
    },
  ];

  Map<String, dynamic> _computeQuery() {
    switch (_selectedShortcutIndex) {
      case 0:
        return {'type': 'hot', 'tag': ''};
      case 1:
        return {'type': 'hot', 'tag': '2K'};
      case 2:
        return {'type': 'hot', 'tag': '全面屏'};
      case 3:
        return {'type': 'hot', 'tag': '平板'};
      case 4:
        return {'type': 'newest', 'tag': ''};
      default:
        return {'type': 'hot', 'tag': ''};
    }
  }

  Widget _buildCoolPicHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 第一行：圆角话题卡横滑列表（#风景#、#二次元#、#生活#等）
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _topicCards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final topic = _topicCards[index];
              final title = topic['title']!;
              final tag = topic['tag']!;
              final pic = topic['pic']!;

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedbackUtil.selection();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => TopicPage(
                        api: widget.api,
                        tag: tag,
                        initialTitle: title,
                        initialLogo: pic.isNotEmpty ? pic : null,
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 78,
                    height: 78,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          normalizeCoolapkImageUrl(pic),
                          headers: coolapkImageHeaders(pic, api: widget.api),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.25),
                                Colors.black.withValues(alpha: 0.65),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // 2. 第二行：5 项彩色快捷操作按钮（🔥热门、2K、📱全面屏、💻平板、🔖最新）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildShortcutButton(
                context: context,
                index: 0,
                icon: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 28,
                  color: Color(0xFFFF3B30),
                ),
                label: '热门',
              ),
              _buildShortcutButton(
                context: context,
                index: 1,
                icon: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C7BE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '2K',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                label: '2K',
              ),
              _buildShortcutButton(
                context: context,
                index: 2,
                icon: const Icon(
                  Icons.stay_current_portrait_rounded,
                  size: 28,
                  color: Color(0xFF007AFF),
                ),
                label: '全面屏',
              ),
              _buildShortcutButton(
                context: context,
                index: 3,
                icon: const Icon(
                  Icons.tablet_mac_rounded,
                  size: 28,
                  color: Color(0xFFFF9500),
                ),
                label: '平板',
              ),
              _buildShortcutButton(
                context: context,
                index: 4,
                icon: const Icon(
                  Icons.bookmark_rounded,
                  size: 28,
                  color: Color(0xFFFF2D55),
                ),
                label: '最新',
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildShortcutButton({
    required BuildContext context,
    required int index,
    required Widget icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedShortcutIndex == index;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isSelected) return;
          HapticFeedbackUtil.selection();
          setState(() {
            _selectedShortcutIndex = index;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 32, width: 32, child: Center(child: icon)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ApiListPage(
      key: ValueKey('coolpic-$_selectedShortcutIndex'),
      api: widget.api,
      title: '酷图',
      path: '/v6/picture/list',
      query: _computeQuery(),
      showAppBar: false,
      nested: true,
      header: _buildCoolPicHeader(context),
    );
  }
}

class DyhPage extends StatelessWidget {
  const DyhPage({
    super.key,
    required this.api,
    required this.id,
    required this.title,
  });
  final CoolapkApi api;
  final String id;
  final String title;
  @override
  Widget build(BuildContext context) => CommunityDetailPage(
    api: api,
    id: id,
    kind: CommunityKind.dyh,
    initial: {'title': title},
  );
}

class UserSpacePage extends StatefulWidget {
  const UserSpacePage({required this.api, required this.uid, super.key});

  final CoolapkApi api;
  final String uid;

  @override
  State<UserSpacePage> createState() => _UserSpacePageState();
}

class _UserSpacePageState extends State<UserSpacePage> {
  Map<String, dynamic>? _space;
  String? _error;
  bool _loading = true;
  bool _following = false;
  bool _blocked = false;
  bool _apiBlocked = false;
  bool _special = false;
  bool _working = false;
  bool _profileScrolled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        widget.api.getUserSpace(widget.uid),
        widget.api
            .getUserProfile(widget.uid)
            .catchError((_) => <String, dynamic>{}),
      ]);
      final response = responses.first;
      final profile = responses.last;
      final data = response['data'];
      final profileData = profile['data'];
      final spaceMap = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      final profileMap = profileData is Map
          ? Map<String, dynamic>.from(profileData)
          : <String, dynamic>{};
      final nestedUser = spaceMap['userInfo'] ?? spaceMap['user_info'];
      final nestedProfile = profileMap['userInfo'] ?? profileMap['user_info'];
      if (!mounted) return;
      setState(() {
        _space = {
          if (nestedUser is Map) ...Map<String, dynamic>.from(nestedUser),
          if (nestedProfile is Map) ...Map<String, dynamic>.from(nestedProfile),
          ...profileMap,
          ...spaceMap,
          ...response,
        };
        _following = widget.api.isAnonymous
            ? widget.api.localAccount.follows.containsKey(widget.uid)
            : _flag(_space, ['isFollow', 'is_follow', 'followed']);
        _blocked = _flag(_space, ['isBlackList', 'is_blocked', 'blocked']);
        _apiBlocked = _flag(_space, [
          'isIgnore',
          'isIgnored',
          'isBlocked',
          'is_block',
        ]);
        _special = _flag(_space, ['isSpecialFollow', 'is_special_follow']);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _onProfileScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification is ScrollUpdateNotification) {
      final scrolled = notification.metrics.pixels > 0;
      if (scrolled != _profileScrolled && mounted) {
        setState(() => _profileScrolled = scrolled);
      }
    }
    return false;
  }

  Future<void> _follow() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.api.followUser(widget.uid, following: _following);
      if (mounted) setState(() => _following = !_following);
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _userAction(
    String path, {
    String method = 'POST',
    Map<String, dynamic> query = const {},
    Map<String, dynamic> body = const {},
  }) async {
    if (_working) return false;
    setState(() => _working = true);
    try {
      if (!widget.api.hasCookie) {
        throw CoolapkApiException(widget.api.loginRequiredMessage);
      }
      await widget.api.request(
        path,
        method: method,
        query: {'uid': widget.uid, ...query},
        body: body,
      );
      if (mounted) _snack(context, '操作已提交');
      return true;
    } catch (error) {
      if (mounted) _snack(context, error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleBlock() async {
    final block = !_blocked;
    if (block) {
      final sure = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('拉黑这位用户？'),
          content: const Text('拉黑会影响你在酷安看到的相关内容。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('拉黑'),
            ),
          ],
        ),
      );
      if (!mounted || sure != true) return;
    }
    final changed = await _userAction(
      block ? '/v6/user/addToBlackList' : '/v6/user/removeFromBlackList',
      method: 'GET',
    );
    if (mounted && changed) setState(() => _blocked = block);
  }

  Future<void> _updateRemark() async {
    final controller = TextEditingController(
      text: _first(_space, ['remark', 'userRemark']),
    );
    final value = await showAppDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改备注'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await _userAction(
      '/v6/user/updateRemark',
      body: {'uid': widget.uid, 'name': value},
    );
  }

  Future<void> _setPublicIdentity() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设为我的公开资料？'),
        content: const Text(
          '只会在本机及匿名账户备份中保存这个公开主页的 UID、名称和头像。'
          '酷安不会验证你是否拥有该账号；这不会建立 Cookie 登录，也不会开放发帖、评论等操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认这是我'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_space == null) await _load();
    final data = _space;
    final username = _first(data, ['username', 'userName', 'name']);
    if (data == null || username.isEmpty) {
      if (mounted) _snack(context, '公开主页资料暂时不可用，请稍后重试');
      return;
    }
    try {
      await widget.api.localAccount.setPublicIdentity(
        uid: widget.uid,
        username: username,
        userAvatar: _first(data, ['userAvatar', 'avatar', 'user_avatar']),
      );
      if (mounted) _snack(context, '已将公开主页用于匿名账户显示');
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    }
  }

  void _handleMenuAction(String value) {
    switch (value) {
      case 'block':
        _toggleBlock();
        break;
      case 'apiBlock':
        _userAction(
          _apiBlocked
              ? '/v6/user/removeFromIgnoreList'
              : '/v6/user/addToIgnoreList',
          method: 'GET',
        ).then((changed) {
          if (mounted && changed) {
            setState(() => _apiBlocked = !_apiBlocked);
          }
        });
        break;
      case 'special':
        _userAction(
          '/v6/user/specialFollowUser',
          query: {'special': _special ? 0 : 1},
        ).then((changed) {
          if (mounted && changed) {
            setState(() => _special = !_special);
          }
        });
        break;
      case 'remark':
        _updateRemark();
        break;
      case 'setIdentity':
        _setPublicIdentity();
        break;
      case 'copyUid':
        Clipboard.setData(ClipboardData(text: widget.uid));
        AppToast.show(context, '已复制 UID: ${widget.uid}');
        break;
      case 'copyLink':
        final link = 'https://www.coolapk.com/u/${widget.uid}';
        Clipboard.setData(ClipboardData(text: link));
        AppToast.show(context, '已复制主页链接');
        break;
    }
  }

  Future<void> _showProfileActionsSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.api.isAnonymous)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  widget.api.localAccount.publicIdentity?['uid'] == widget.uid
                      ? '已设为我的公开资料'
                      : '设为我的公开资料',
                ),
                enabled:
                    widget.api.localAccount.publicIdentity?['uid'] != widget.uid,
                onTap: () => Navigator.pop(context, 'setIdentity'),
              ),
            ListTile(
              leading: Icon(
                _special ? Icons.star_rounded : Icons.star_outline_rounded,
              ),
              title: Text(_special ? '取消特别关注' : '特别关注'),
              onTap: () => Navigator.pop(context, 'special'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('设置备注'),
              onTap: () => Navigator.pop(context, 'remark'),
            ),
            ListTile(
              leading: Icon(
                _apiBlocked
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_outlined,
              ),
              title: Text(_apiBlocked ? '取消屏蔽' : '屏蔽用户'),
              onTap: () => Navigator.pop(context, 'apiBlock'),
            ),
            ListTile(
              leading: Icon(
                _blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: Colors.redAccent,
              ),
              title: Text(
                _blocked ? '取消拉黑' : '拉黑用户',
                style: const TextStyle(color: Colors.redAccent),
              ),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制 UID'),
              onTap: () => Navigator.pop(context, 'copyUid'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制主页链接'),
              onTap: () => Navigator.pop(context, 'copyLink'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    _handleMenuAction(choice);
  }

  List<(String, String)> get _profileTabs => [
    ('主页', ''),
    ('动态', '/v6/user/feedList'),
    ('回复', '/v6/user/replyList'),
    (
      '点评',
      '/v6/page/dataList:#/feed/nodeRatingList?uid=${widget.uid}&targetType=all&parseRatingToFeed=1',
    ),
    ('图文', '/v6/user/htmlFeedList'),
    ('问答', '/v6/user/questionAndAnswerList'),
    ('酷图', '/v6/user/pictureList'),
    ('图集', '/v6/user/albumList'),
    ('收藏', '/v6/collection/list'),
    ('好物榜', '/v6/goodsList/list'),
    ('店铺', '/v6/goods/goodsStoreItemList'),
    ('开发者应用', '/v6/apk/developerAppList'),
    ('关注应用', '/v6/user/apkFollowList'),
    ('发现', '/v6/user/discoveryList'),
    ('关注列表', '/v6/user/followList'),
    (
      '酷图流',
      '/v6/page/dataList:#/feed/userCoolPictureFeedList?fragmentTemplate=flex',
    ),
    (
      '好物动态',
      '/v6/page/dataList:#/goods/goodsFeedList?type=default&fragmentTemplate=flex',
    ),
    (
      '二手',
      '/v6/page/dataList:#/feed/userErshouList?fragmentTemplate=flex&ershouStatus=userAll',
    ),
    if (widget.uid == widget.api.currentUid)
      ('回收站', '/v6/page/dataList:#/feed/userDeleteFeedList'),
  ];

  Widget _profileStatInline(String label, String value, {VoidCallback? onTap}) {
    final count = int.tryParse(value);
    final countStr = count == null
        ? (value.isEmpty ? '0' : value)
        : count > 10000
        ? '${(count / 10000).toStringAsFixed(1)}万'
        : '$count';
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          countStr,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12.5,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: '$label列表',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: content,
        ),
      ),
    );
  }

  String _genderText(Map<String, dynamic> data) {
    final raw = data['gender'] ?? data['sex'];
    if (raw == 1 || raw == '1' || raw == '男') return '♂';
    if (raw == 2 || raw == '2' || raw == '女') return '♀';
    return '';
  }

  String _formatEra(Map<String, dynamic> data) {
    final era = _first(data, ['era', 'age_group', 'generation']).trim();
    if (era.isNotEmpty) return era;
    final birthYear = int.tryParse(_first(data, ['birth_year', 'birthYear']));
    if (birthYear != null && birthYear > 1940 && birthYear <= DateTime.now().year) {
      if (birthYear >= 2000) {
        final decade = ((birthYear % 100) ~/ 10) * 10;
        return '${decade.toString().padLeft(2, '0')}后';
      } else {
        final decade = ((birthYear % 100) ~/ 10) * 10;
        return '$decade后';
      }
    }
    final birth = _first(data, ['birth', 'birthday']).trim();
    if (birth.length >= 4) {
      final year = int.tryParse(birth.substring(0, 4));
      if (year != null && year > 1940 && year <= DateTime.now().year) {
        if (year >= 2000) {
          final decade = ((year % 100) ~/ 10) * 10;
          return '${decade.toString().padLeft(2, '0')}后';
        } else {
          final decade = ((year % 100) ~/ 10) * 10;
          return '$decade后';
        }
      }
    }
    return '';
  }

  String _formatActiveTime(dynamic raw) {
    if (raw == null) return '';
    final str = raw.toString().trim();
    if (str.isEmpty || str == '0') return '';
    final ts = int.tryParse(str);
    if (ts != null) {
      final millis = ts > 10000000000 ? ts : ts * 1000;
      final date = DateTime.fromMillisecondsSinceEpoch(millis);
      final diff = DateTime.now().difference(date);
      if (diff.isNegative || diff.inMinutes < 5) return '刚刚活跃';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前活跃';
      if (diff.inDays < 1) return '${diff.inHours}小时前活跃';
      if (diff.inDays < 30) return '${diff.inDays}天前活跃';
      final months = (diff.inDays / 30).floor();
      if (months < 12) return '$months个月前活跃';
      return '${(diff.inDays / 365).floor()}年前活跃';
    }
    if (str.contains('活跃')) return str;
    return '$str活跃';
  }

  Widget _buildChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _buildEquipmentCard({required bool isMe, required String count}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApiListPage(
              api: widget.api,
              title: isMe ? '我的装备' : 'TA的装备',
              path: '/v6/page/dataList',
              query: {
                'url':
                    '/feed/nodeRatingList?uid=${widget.uid}&targetType=all&parseRatingToFeed=1',
                'title': isMe ? '我的装备' : 'TA的装备',
                'pageContext': 'user_space',
              },
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.devices_other_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              isMe ? '我的装备' : 'TA的装备',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              count.isNotEmpty && count != '0'
                  ? '$count个装备'
                  : (isMe ? '添加装备' : '查看装备'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(String url, {String? tag}) {
    if (url.isEmpty) return;
    HapticFeedbackUtil.light();
    Navigator.of(context).push<void>(
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          api: widget.api,
          pics: [GalleryImage(url)],
          initialIndex: 0,
          statusId: tag ?? url,
          isDetail: true,
          authorName: _first(_space, ['username', 'userName', 'name']),
        ),
      ),
    );
  }

  void _openRelations(String title, String path) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CommunityLibraryPage(
            api: widget.api,
            uid: widget.uid,
            library: path.toLowerCase().contains('fans')
                ? CommunityLibrary.fans
                : CommunityLibrary.following,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final data = _space ?? const <String, dynamic>{};
    final name = _first(data, ['username', 'userName', 'name']);
    final avatar = _first(data, ['userAvatar', 'avatar']);
    final avatarFrame = _first(data, [
      'avatarFrame',
      'avatar_frame',
      'userAvatarFrame',
      'user_avatar_frame',
    ]);
    final cover = _first(data, [
      'userCover',
      'cover',
      'background',
      'background_url',
    ]);
    final bio = _first(data, [
      'bio',
      'subTitle',
      'sign',
      'signature',
      'description',
    ]);
    final level = _first(data, ['level']);
    final likeCount = _first(data, [
      'be_like_num',
      'feed_like_num',
      'beLikeNum',
      'feedLikeNum',
      'like_num',
      'likeNum',
      'likenum',
    ]);
    final followCount = _first(data, [
      'follow_num',
      'followNum',
      'follownum',
      'follow',
    ]);
    final fansCount = _first(data, ['fans_num', 'fansNum', 'fansnum', 'fans']);
    final feedCount = _first(data, ['feed_num', 'feedNum', 'feednum', 'feeds']);
    final equipmentCount = _first(data, [
      'buy_num',
      'buyNum',
      'device_num',
      'deviceNum',
      'my_device_num',
      'equipment_num',
      'feed_rating_num',
      'rating_num',
    ]);
    final isMe = widget.uid == widget.api.currentUid ||
        (widget.api.isAnonymous &&
            widget.api.localAccount.publicIdentity?['uid'] == widget.uid);

    final chips = <Widget>[];
    final genderText = _genderText(data);
    final eraText = _formatEra(data);
    if (genderText.isNotEmpty || eraText.isNotEmpty) {
      final label = [
        if (genderText.isNotEmpty) genderText,
        if (eraText.isNotEmpty) eraText,
      ].join(' ');
      chips.add(_buildChip(label));
    }
    final province = _first(data, ['province', 'user_province']).trim();
    final city = _first(data, ['city', 'user_city']).trim();
    final location = (province.isNotEmpty && city.isNotEmpty && province != city)
        ? '$province $city'
        : (province.isNotEmpty ? province : city);
    if (location.isNotEmpty) {
      chips.add(_buildChip(location));
    }
    final astro = _first(data, ['astro', 'constellation']).trim();
    if (astro.isNotEmpty) {
      chips.add(_buildChip(astro));
    }
    final activeStr = _formatActiveTime(
      data['logintime'] ??
          data['login_time'] ??
          data['last_login_time'] ??
          data['active_time'],
    );
    if (activeStr.isNotEmpty) {
      chips.add(_buildChip(activeStr));
    }

    final theme = Theme.of(context);
    final pageBackground = theme.scaffoldBackgroundColor;
    final feedCardColor = theme.cardTheme.color ?? theme.cardColor;
    final profileTopInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ReviewFrostedAppBar(
        title: _profileScrolled ? Text(name.isEmpty ? '酷友主页' : name) : null,
        backgroundColor: _profileScrolled || _space == null
            ? pageBackground
            : Colors.transparent,
        showBottomBorder: _profileScrolled || _space == null,
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SearchPage(api: widget.api),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              if (widget.api.isAnonymous)
                PopupMenuItem(
                  value: 'setIdentity',
                  enabled:
                      widget.api.localAccount.publicIdentity?['uid'] !=
                      widget.uid,
                  child: Text(
                    widget.api.localAccount.publicIdentity?['uid'] == widget.uid
                        ? '已设为我的公开资料'
                        : '这是我',
                  ),
                ),
              PopupMenuItem(
                value: 'block',
                child: Text(_blocked ? '取消拉黑' : '拉黑用户'),
              ),
              PopupMenuItem(
                value: 'apiBlock',
                child: Text(_apiBlocked ? '取消屏蔽' : '屏蔽用户'),
              ),
              PopupMenuItem(
                value: 'special',
                child: Text(_special ? '取消特别关注' : '特别关注'),
              ),
              const PopupMenuItem(value: 'remark', child: Text('设置备注')),
              const PopupMenuItem(value: 'copyUid', child: Text('复制 UID')),
              const PopupMenuItem(value: 'copyLink', child: Text('复制主页链接')),
            ],
          ),
        ],
      ),
      body: _loading && _space == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _space == null
          ? _RetryView(message: _error!, onRetry: _load)
          : DefaultTabController(
              length: _profileTabs.length,
              initialIndex: 1,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onProfileScroll,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (cover.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _openImage(
                                        cover,
                                        tag: 'cover_${widget.uid}',
                                      ),
                                      child: CachedNetworkImage(
                                        cover,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    )
                                  else
                                    Container(
                                      color: const Color(0xFF1F2B26),
                                    ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(
                                            alpha: cover.isNotEmpty ? 0.35 : 0.65,
                                          ),
                                          Colors.black.withValues(
                                            alpha: cover.isNotEmpty ? 0.65 : 0.85,
                                          ),
                                          pageBackground,
                                        ],
                                        stops: const [0, 0.65, 1],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    16,
                                    profileTopInset + 52 + 10,
                                    16,
                                    14,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _openImage(
                                              avatar,
                                              tag: 'avatar_${widget.uid}',
                                            ),
                                            child: AppAvatar(
                                              api: widget.api,
                                              url: avatar,
                                              size: 76,
                                              name: name,
                                              avatarFrame: avatarFrame,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (isMe) ...[
                                            InkWell(
                                              onTap: () {
                                                if (widget.api.hasCookie) {
                                                  Navigator.of(context)
                                                      .push(
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              OfficialProfilePage(
                                                                api: widget.api,
                                                              ),
                                                        ),
                                                      )
                                                      .then((_) => _load());
                                                } else {
                                                  Navigator.of(context)
                                                      .push(
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              LocalProfilePage(
                                                                api: widget.api,
                                                                activate: true,
                                                              ),
                                                        ),
                                                      )
                                                      .then((_) => _load());
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 6.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.38),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Text(
                                                  '编辑资料',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: _showProfileActionsSheet,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.16),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.38),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.grid_view_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            if (_working)
                                              const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                            Color
                                                          >(Colors.white),
                                                    ),
                                              )
                                            else
                                              InkWell(
                                                onTap: _follow,
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 6.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: _following
                                                        ? Colors.white
                                                            .withValues(
                                                              alpha: 0.16,
                                                            )
                                                        : const Color(
                                                          0xFF00B075,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                    border: _following
                                                        ? Border.all(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.38,
                                                              ),
                                                          width: 0.8,
                                                        )
                                                        : null,
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        _following
                                                            ? Icons.check_rounded
                                                            : Icons.add_rounded,
                                                        size: 14,
                                                        color: Colors.white,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        _following
                                                            ? '已关注'
                                                            : '关注',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () {
                                                if (!widget.api.hasCookie) {
                                                  AppToast.show(
                                                    context,
                                                    '请先使用酷安账号登录',
                                                  );
                                                } else {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          MessageChatPage(
                                                            api: widget.api,
                                                            uid: widget.uid,
                                                            ukey: '',
                                                            username: name,
                                                            avatar: avatar,
                                                          ),
                                                    ),
                                                  );
                                                }
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 6.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.38),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Text(
                                                  '私信',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: _showProfileActionsSheet,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Container(
                                                width: 32,
                                                height: 32,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.16),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.38),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.more_horiz_rounded,
                                                  size: 18,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name.isEmpty ? '酷安用户' : name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 21,
                                                fontWeight: context.adjustWeight(
                                                  FontWeight.bold,
                                                ),
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (level.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1.5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2CB76A),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Lv.$level',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (bio.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                                right: 6,
                                              ),
                                              child: Icon(
                                                Icons.local_offer_outlined,
                                                size: 14,
                                                color: Colors.white.withValues(
                                                  alpha: 0.72,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                bio,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.white.withValues(
                                                    alpha: 0.88,
                                                  ),
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          _profileStatInline(
                                            '获赞',
                                            likeCount,
                                          ),
                                          const SizedBox(width: 20),
                                          _profileStatInline(
                                            '关注',
                                            followCount,
                                            onTap: () => _openRelations(
                                              '关注',
                                              widget.uid ==
                                                      widget.api.currentUid
                                                  ? '/v6/user/myFollowList'
                                                  : '/v6/user/followList',
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          _profileStatInline(
                                            '粉丝',
                                            fansCount,
                                            onTap: () => _openRelations(
                                              '粉丝',
                                              widget.uid ==
                                                      widget.api.currentUid
                                                  ? '/v6/user/myFansList'
                                                  : '/v6/user/userFansList',
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (chips.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: chips,
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      _buildEquipmentCard(
                                        isMe: isMe,
                                        count: equipmentCount,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _ProfileTabHeader(
                          TabBar(
                            indicatorSize: TabBarIndicatorSize.label,
                            indicator: UnderlineTabIndicator(
                              borderSide: const BorderSide(
                                color: Color(0xFF2CB76A),
                                width: 3,
                              ),
                              insets: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            labelColor: const Color(0xFF2CB76A),
                            unselectedLabelColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.normal,
                              fontSize: 14,
                            ),
                            dividerColor: Colors.transparent,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              for (final tab in _profileTabs)
                                Tab(height: 46, text: tab.$1),
                            ],
                          ),
                          feedCardColor,
                        ),
                      ),
                    ],
                    body: TabBarView(
                      children: [
                        for (final tab in _profileTabs)
                          if (tab.$2.isEmpty)
                            ListView(
                              padding: const EdgeInsets.fromLTRB(8, 10, 8, 24),
                              children: [
                                if (_space?['homeTabCardRows'] is List)
                                  for (final item
                                      in (_space!['homeTabCardRows'] as List)
                                          .whereType<Map>())
                                    if (!((item['title'] ?? item['name'] ?? '')
                                            .toString()
                                            .contains('关注的人') ||
                                        (item['title'] ?? item['name'] ?? '')
                                            .toString()
                                            .contains('关注的板块') ||
                                        (item['title'] ?? item['name'] ?? '')
                                            .toString()
                                            .contains('热门动态')))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: ApiEntityCard(
                                          api: widget.api,
                                          entity: Map<String, dynamic>.from(
                                            item,
                                          ),
                                        ),
                                      ),
                                if (_space?['homeTabCardRows'] is! List ||
                                    (_space!['homeTabCardRows'] as List)
                                        .isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('暂无主页内容，可切换分栏查看动态和收藏'),
                                  ),
                              ],
                            )
                          else
                            ApiListPage(
                              key: PageStorageKey('${widget.uid}:${tab.$2}'),
                              api: widget.api,
                              title: tab.$1,
                              path: tab.$2.split(':').first,
                              query: {
                                'uid': widget.uid,
                                if (tab.$2.contains(':')) ...{
                                  'url': tab.$2.split(':').last,
                                  'title': tab.$1,
                                  'subTitle': '',
                                  'pageContext': 'user_space',
                                },
                                if (tab.$1 == '收藏') 'showDefault': 1,
                              },
                              showAppBar: false,
                              nested: true,
                              header: tab.$1 == '动态' &&
                                      feedCount.isNotEmpty &&
                                      feedCount != '0'
                                  ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        10,
                                        16,
                                        6,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '全部动态 ($feedCount)',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.8),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}


class _ProfileTabHeader extends SliverPersistentHeaderDelegate {
  const _ProfileTabHeader(this.tabs, this.color);
  final TabBar tabs;
  final Color color;
  @override
  double get minExtent => tabs.preferredSize.height;
  @override
  double get maxExtent => minExtent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(color: color, child: tabs);
  @override
  bool shouldRebuild(covariant _ProfileTabHeader oldDelegate) =>
      tabs != oldDelegate.tabs || color != oldDelegate.color;
}

Widget greenComposeFab({
  required BuildContext context,
  required Object heroTag,
  required VoidCallback onPressed,
  bool useLiquidGlass = true,
}) {
  final size = useLiquidGlass ? 48.0 : 48.0;
  final button = Theme(
    data: Theme.of(context).copyWith(
      floatingActionButtonTheme: Theme.of(context).floatingActionButtonTheme
          .copyWith(
            sizeConstraints: BoxConstraints.tightFor(width: size, height: size),
          ),
    ),
    child: FloatingActionButton(
      tooltip: '发布动态',
      heroTag: heroTag,
      backgroundColor: useLiquidGlass
          ? Colors.transparent
          : const Color(0xFF00B075),
      elevation: useLiquidGlass ? 0 : 4,
      shape: const CircleBorder(
        side: BorderSide(color: Color(0x33FFFFFF), width: 1.5),
      ),
      onPressed: onPressed,
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );
  if (!useLiquidGlass) return button;
  return GlassContainer(
    width: size,
    height: size,
    shape: const LiquidOval(),
    settings: ReviewNavigationBar.liquidGlassSettings.copyWith(
      glassColor: const Color(0xCC00B075),
    ),
    quality: ReviewNavigationBar.liquidGlassQuality,
    useOwnLayer: true,
    clipBehavior: Clip.antiAlias,
    child: button,
  );
}

class TopicPage extends StatefulWidget {
  const TopicPage({
    required this.api,
    required this.tag,
    this.initialTitle,
    this.initialLogo,
    this.initialCover,
    super.key,
  });

  final CoolapkApi api;
  final String tag;
  final String? initialTitle;
  final String? initialLogo;
  final String? initialCover;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class ProductPage extends StatefulWidget {
  const ProductPage({
    required this.api,
    required this.id,
    this.title = '',
    super.key,
  });

  final CoolapkApi api;
  final String id;
  final String title;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductTab {
  const _ProductTab({
    required this.title,
    required this.type,
    this.subId,
    this.url,
  });

  final String title;
  final String type;
  final String? subId;
  final String? url;
}

class _ProductPageState extends State<ProductPage>
    with TickerProviderStateMixin {
  static const _defaultTabs = [
    _ProductTab(title: '参数', type: 'main'),
    _ProductTab(title: '讨论', type: 'feed'),
    _ProductTab(title: '点评', type: 'rating'),
    _ProductTab(title: '图文', type: 'article'),
    _ProductTab(title: '问答', type: 'answer'),
    _ProductTab(title: '视频', type: 'video'),
    _ProductTab(title: '二手', type: 'trade'),
  ];

  late TabController _tabController;
  late List<_ProductTab> _tabs = _defaultTabs;
  Map<String, dynamic>? _detail;
  bool _following = false;
  bool _followWorking = false;
  String _sortMode = 'default';
  final _outerScroll = ScrollController();
  final _compactHeader = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: 1, // '讨论'
      vsync: this,
    );
    _outerScroll.addListener(_updateCompactHeader);
    _loadDetail();
  }

  void _updateCompactHeader() {
    if (!_outerScroll.hasClients) return;
    final position = _outerScroll.position;
    final collapsed =
        position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1;
    if (_compactHeader.value != collapsed) _compactHeader.value = collapsed;
  }

  @override
  void dispose() {
    _outerScroll.dispose();
    _compactHeader.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<_ProductTab> _parseServerTabs(dynamic tabListRaw, String productId) {
    if (tabListRaw is! List || tabListRaw.isEmpty) return _defaultTabs;
    final tabs = <_ProductTab>[];
    for (final item in tabListRaw) {
      if (item is! Map) continue;
      if (item['is_open'] == 0 || item['is_open'] == '0') continue;
      final title = (item['title'] ?? '').toString().trim();
      final url = (item['url'] ?? '').toString().trim();
      if (title.isEmpty || url.isEmpty) continue;

      try {
        final uri = Uri.parse(url);
        final innerUrl = uri.queryParameters['url'] ?? url;
        final innerUri = Uri.parse(innerUrl);
        final feedType =
            innerUri.queryParameters['type'] ??
            uri.queryParameters['type'] ??
            '';
        final targetId =
            innerUri.queryParameters['id'] ?? uri.queryParameters['id'] ?? '';
        final subId =
            innerUri.queryParameters['subId'] ?? uri.queryParameters['subId'];

        if (innerUri.path == '/product/feedList' ||
            uri.path == '/product/feedList' ||
            innerUrl.contains('/product/feedList')) {
          if (targetId.isNotEmpty && targetId != productId) continue;
          if (feedType == 'main') {
            tabs.add(_ProductTab(title: title, type: 'main', url: url));
          } else if (feedType == 'subTabFeed') {
            tabs.add(
              _ProductTab(
                title: title,
                type: 'subTabFeed',
                subId: subId,
                url: url,
              ),
            );
          } else if (feedType.isNotEmpty) {
            tabs.add(_ProductTab(title: title, type: feedType, url: url));
          }
        } else if (url.startsWith('/')) {
          tabs.add(_ProductTab(title: title, type: 'external', url: url));
        }
      } catch (_) {}
    }
    if (tabs.isNotEmpty && !tabs.any((t) => t.type == 'main')) {
      tabs.insert(0, const _ProductTab(title: '参数', type: 'main'));
    }
    return tabs.isEmpty ? _defaultTabs : tabs;
  }

  bool _hasTabDiff(List<_ProductTab> a, List<_ProductTab> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title ||
          a[i].type != b[i].type ||
          a[i].subId != b[i].subId ||
          a[i].url != b[i].url) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadDetail() async {
    try {
      final res = await widget.api.getProductDetail(widget.id);
      final action = res['userAction'];
      final isFollow =
          res['is_follow'] ??
          res['isFollow'] ??
          (action is Map ? action['follow'] : null);
      final following = widget.api.isAnonymous
          ? widget.api.localAccount.productFollows.containsKey(widget.id)
          : isFollow == true || '$isFollow' == '1';
      if (mounted) {
        final serverTabs = _parseServerTabs(res['tabList'], widget.id);
        if (_hasTabDiff(_tabs, serverTabs)) {
          final currentTab = _tabs[_tabController.index];
          var nextIndex = serverTabs.indexWhere(
            (t) => t.type == currentTab.type && t.subId == currentTab.subId,
          );
          if (nextIndex < 0) {
            nextIndex = serverTabs.indexWhere((t) => t.type == 'feed');
          }
          if (nextIndex < 0) nextIndex = 0;

          final oldController = _tabController;
          final newController = TabController(
            length: serverTabs.length,
            initialIndex: nextIndex,
            vsync: this,
          );
          setState(() {
            _detail = res;
            _tabs = serverTabs;
            _tabController = newController;
            _following = following;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            oldController.dispose();
          });
        } else {
          setState(() {
            _detail = res;
            _following = following;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_followWorking) return;
    if (!widget.api.hasAccount) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    final next = !_following;
    setState(() {
      _following = next;
      _followWorking = true;
    });
    try {
      await widget.api.followProduct(
        widget.id,
        following: !next,
        product: _detail,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _following = !next);
        AppToast.show(context, '$error');
      }
    } finally {
      if (mounted) setState(() => _followWorking = false);
    }
  }

  void _openComparison() {
    HapticFeedbackUtil.light();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProductComparisonPage(
          api: widget.api,
          initialProductId: widget.id,
          initialDetail: _detail,
        ),
      ),
    );
  }

  Future<void> _handleBuy() async {
    HapticFeedbackUtil.light();
    final raw = _detail ?? const <String, dynamic>{};
    final explicitUrl =
        (raw['buy_url'] ??
                raw['goods_buy_url'] ??
                raw['jd_url'] ??
                raw['mall_url'] ??
                raw['shop_url'] ??
                '')
            .toString()
            .trim();

    final productTitle = (raw['title'] ?? widget.title).toString().trim();
    final searchTitle = productTitle.isNotEmpty ? productTitle : '手机';

    if (explicitUrl.isNotEmpty &&
        (explicitUrl.startsWith('http://') ||
            explicitUrl.startsWith('https://') ||
            explicitUrl.startsWith('openapp.jdmobile://'))) {
      try {
        final uri = Uri.parse(explicitUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // Construct JD app scheme & mobile web search url
    final jdParams = jsonEncode({
      'category': 'jump',
      'des': 'search',
      'keyWord': searchTitle,
    });
    final jdAppUri = Uri.parse(
      'openapp.jdmobile://virtual?params=${Uri.encodeComponent(jdParams)}',
    );
    final jdWebUri = Uri.parse(
      'https://so.m.jd.com/ware/search.action?keyword=${Uri.encodeComponent(searchTitle)}',
    );

    try {
      if (await canLaunchUrl(jdAppUri)) {
        final launched = await launchUrl(
          jdAppUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      }
    } catch (_) {}

    // Fallback to JD web
    try {
      await launchUrl(jdWebUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '无法打开购买链接: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final actionBarHeight = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(12) * 1.4 + 22,
    );
    const primaryGreen = Color(0xFF00B074);

    final raw = _detail ?? const <String, dynamic>{};
    final productTitle =
        (raw['title'] ?? widget.title).toString().trim().isEmpty
        ? '数码产品'
        : (raw['title'] ?? widget.title).toString().trim();
    final logo = (raw['logo'] ?? raw['cover'] ?? raw['pic'] ?? '')
        .toString()
        .trim();

    final hotNumRaw = raw['hot_num_txt'] ?? raw['hot_num'] ?? '58.4万';
    final hotStr = hotNumRaw.toString().endsWith('万')
        ? hotNumRaw.toString()
        : (int.tryParse('$hotNumRaw') != null
              ? '${(int.parse('$hotNumRaw') / 10000).toStringAsFixed(1)}万'
              : '$hotNumRaw');
    final feedNumRaw = raw['feed_num_txt'] ?? raw['feed_num'] ?? '3.7万';
    final feedStr = feedNumRaw.toString().endsWith('万')
        ? feedNumRaw.toString()
        : (int.tryParse('$feedNumRaw') != null
              ? '${(int.parse('$feedNumRaw') / 10000).toStringAsFixed(1)}万'
              : '$feedNumRaw');
    final followNumRaw = raw['follow_num_txt'] ?? raw['follow_num'] ?? '1.5万';
    final followStr = followNumRaw.toString().endsWith('万')
        ? followNumRaw.toString()
        : (int.tryParse('$followNumRaw') != null
              ? '${(int.parse('$followNumRaw') / 10000).toStringAsFixed(1)}万'
              : '$followNumRaw');

    final isUnreleased =
        raw['release_status'] == 0 || raw['release_status']?.toString() == '0';
    final releaseTime = (raw['release_time_txt'] ?? raw['release_time'] ?? '')
        .toString();
    final wishCount = num.tryParse('${raw['wish_count'] ?? 0}')?.toInt() ?? 0;
    final wishCountText = wishCount >= 10000
        ? '${(wishCount / 10000).toStringAsFixed(1)}万'
        : '$wishCount';

    final scoreStr =
        (raw['score'] ??
                raw['star_average_score'] ??
                raw['rating_average_score'] ??
                '0')
            .toString();
    final scoreVal = double.tryParse(scoreStr) ?? 0;
    final starCount = (scoreVal / 2).clamp(1.0, 5.0).round();

    final batteryScore =
        double.tryParse('${raw['score_battery'] ?? raw['score_1'] ?? '7.3'}') ??
        7.3;
    final cameraScore =
        double.tryParse('${raw['score_camera'] ?? raw['score_2'] ?? '8.2'}') ??
        8.2;
    final perfScore =
        double.tryParse(
          '${raw['score_performance'] ?? raw['score_3'] ?? '7.8'}',
        ) ??
        7.8;
    final screenScore =
        double.tryParse('${raw['score_screen'] ?? raw['score_4'] ?? '7.6'}') ??
        7.6;
    final designScore =
        double.tryParse(
          '${raw['score_appearance'] ?? raw['score_5'] ?? '8.0'}',
        ) ??
        8.0;
    final valueScore =
        double.tryParse('${raw['score_cost'] ?? raw['score_6'] ?? '7.1'}') ??
        7.1;

    final commentSummary =
        raw['comment_num_txt']?.toString().trim().isNotEmpty == true
        ? raw['comment_num_txt'].toString()
        : isUnreleased
        ? '${raw['owner_star_total_count'] ?? 0}机主点评 ${raw['rating_total_num'] ?? 0}详细点评'
        : '${raw['owner_comment_num'] ?? '3550'}机主点评 ${raw['detail_comment_num'] ?? '3327'}详细点评';

    final specsTags = <String>[
      if (releaseTime.isNotEmpty)
        '$releaseTime 上市'
      else if (!isUnreleased)
        '2025-10-13 上市',
      if ((raw['chip'] ?? raw['soc'] ?? raw['processor'] ?? '')
          .toString()
          .isNotEmpty)
        (raw['chip'] ?? raw['soc'] ?? raw['processor']).toString()
      else if (!isUnreleased)
        '天玑 9500',
      if ((raw['screen_size'] ?? raw['screen'] ?? '').toString().isNotEmpty)
        (raw['screen_size'] ?? raw['screen']).toString()
      else if (!isUnreleased)
        '6.78 英寸',
      if ((raw['screen_type'] ?? '').toString().isNotEmpty)
        raw['screen_type'].toString()
      else if (!isUnreleased)
        '直屏',
      if ((raw['battery'] ?? '').toString().isNotEmpty)
        raw['battery'].toString(),
      if ((raw['charging'] ?? '').toString().isNotEmpty)
        raw['charging'].toString(),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 4,
        title: ValueListenableBuilder<bool>(
          valueListenable: _compactHeader,
          builder: (context, compact, _) => compact
              ? Row(
                  key: const ValueKey('product-compact-header'),
                  children: [
                    if (logo.isNotEmpty) ...[
                      SizedBox(
                        width: 28,
                        height: 34,
                        child: CachedNetworkImage(
                          normalizeCoolapkImageUrl(logo),
                          headers: coolapkImageHeaders(logo, api: widget.api),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            productTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                          if (!isUnreleased && scoreVal > 0)
                            Semantics(
                              label: '机型评分 $scoreStr 分',
                              child: ExcludeSemantics(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < 5; i++)
                                        Icon(
                                          scoreVal / 2 >= i + 1
                                              ? Icons.star_rounded
                                              : scoreVal / 2 > i
                                              ? Icons.star_half_rounded
                                              : Icons.star_outline_rounded,
                                          size: 12,
                                          color: const Color(0xFFFFA000),
                                        ),
                                      const SizedBox(width: 4),
                                      Text(
                                        scoreStr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFFFA000),
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
                )
              : const SizedBox.shrink(),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _compactHeader,
            builder: (context, compact, _) => compact
                ? TextButton(
                    key: const ValueKey('product-compact-follow'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      backgroundColor: scheme.surfaceContainerHighest,
                      minimumSize: const Size(64, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _followWorking ? null : _toggleFollow,
                    child: Text(_following ? '已关注' : '关注'),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: '搜索机型',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SearchPage(api: widget.api, initialQuery: productTitle),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: NestedScrollView(
        key: const ValueKey('product-nested-scroll'),
        controller: _outerScroll,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF282828)
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: logo.isNotEmpty
                              ? CachedNetworkImage(
                                  normalizeCoolapkImageUrl(logo),
                                  headers: coolapkImageHeaders(
                                    logo,
                                    api: widget.api,
                                  ),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.phone_android_rounded,
                                    size: 36,
                                    color: primaryGreen,
                                  ),
                                )
                              : const Icon(
                                  Icons.phone_android_rounded,
                                  size: 36,
                                  color: primaryGreen,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    productTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: _toggleFollow,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _following
                                          ? Colors.transparent
                                          : primaryGreen,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: _following
                                            ? scheme.outlineVariant.withValues(
                                                alpha: 0.6,
                                              )
                                            : primaryGreen,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      _following ? '已关注' : '关注',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: _following
                                            ? scheme.onSurfaceVariant
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$hotStr热度  $feedStr讨论',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _buildOverlappingAvatars(),
                                const SizedBox(width: 6),
                                Text(
                                  '$followStr关注 >',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF222222)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.45,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(
                          alpha: isDark ? 0.2 : 0.3,
                        ),
                        width: 0.6,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '酷安评分',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isUnreleased)
                              Text(
                                releaseTime.isEmpty ? '未发布' : '$releaseTime上市',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              )
                            else
                              InkWell(
                                onTap: () {},
                                child: Text(
                                  '详细数据 >',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (isUnreleased)
                          SizedBox(
                            height: 112,
                            child: Center(
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: wishCountText,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: ' 人想买',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 108,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      scoreVal.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var s = 0; s < 5; s++)
                                          Icon(
                                            s < starCount
                                                ? Icons.star_rounded
                                                : Icons.star_outline_rounded,
                                            size: 15,
                                            color: s < starCount
                                                ? const Color(0xFFFFA000)
                                                : scheme.outlineVariant,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '机主评分',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: 90,
                                width: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildScoreBar('续航', batteryScore, scheme),
                                    _buildScoreBar('影像', cameraScore, scheme),
                                    _buildScoreBar('性能', perfScore, scheme),
                                    _buildScoreBar('屏幕', screenScore, scheme),
                                    _buildScoreBar('外观质感', designScore, scheme),
                                    _buildScoreBar('性价比', valueScore, scheme),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: scheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                commentSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCapsuleAction(
                              '想买',
                              scheme,
                              () => AppToast.show(context, '已加入想买清单'),
                            ),
                            const SizedBox(width: 8),
                            if (isUnreleased)
                              _buildCapsuleAction(
                                '未发布',
                                scheme,
                                null,
                                outlined: true,
                              )
                            else
                              _buildCapsuleAction(
                                '打分',
                                scheme,
                                () => AppToast.show(context, '评分功能需登录机主账号'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: specsTags.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF262626)
                                : scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.5,
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.2,
                              ),
                              width: 0.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            specsTags[idx],
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: primaryGreen,
                  indicatorWeight: 3,
                  indicator: const _ProductTabIndicator(),
                  labelColor: primaryGreen,
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  unselectedLabelStyle: const TextStyle(fontSize: 16),
                  dividerColor: Colors.transparent,
                  tabs: [for (final tab in _tabs) Tab(text: tab.title)],
                ),
                color: theme.scaffoldBackgroundColor,
              ),
            ),
          ),
        ],
        body: Builder(
          builder: (context) => TabBarView(
            controller: _tabController,
            children: [
              for (final tab in _tabs)
                _buildTabContent(
                  tab,
                  raw,
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: math.min(176.0, MediaQuery.sizeOf(context).width - 82.0),
                height: actionBarHeight,
                child: GlassContainer(
                  height: actionBarHeight,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 9999),
                  settings: ReviewNavigationBar.liquidGlassSettings,
                  quality: ReviewNavigationBar.liquidGlassQuality,
                  useOwnLayer: true,
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildBottomAction(
                            '对比',
                            Icons.compare_arrows_rounded,
                            Colors.white,
                            _openComparison,
                          ),
                        ),
                        Expanded(
                          child: _buildBottomAction(
                            _following ? '已关注' : '关注',
                            _following
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            _following ? primaryGreen : Colors.white,
                            _toggleFollow,
                          ),
                        ),
                        if (isUnreleased)
                          Expanded(
                            child: _buildBottomAction(
                              '未发布',
                              Icons.star_border_rounded,
                              scheme.onSurfaceVariant,
                              null,
                            ),
                          )
                        else ...[
                          Expanded(
                            child: _buildBottomAction(
                              '打分',
                              Icons.star_border_rounded,
                              Colors.white,
                              () => AppToast.show(
                                context,
                                widget.api.loginRequiredMessage,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _buildBottomAction(
                              '购买',
                              Icons.shopping_bag_outlined,
                              Colors.white,
                              _handleBuy,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              greenComposeFab(
                context: context,
                heroTag: 'product_fab_${widget.id}',
                useLiquidGlass: true,
                onPressed: () {
                  HapticFeedbackUtil.light();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ComposeFeedPage(api: widget.api),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlappingAvatars() {
    return const SizedBox(
      width: 44,
      height: 20,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Color(0xFF64B5F6),
              child: Icon(Icons.person, size: 12, color: Colors.white),
            ),
          ),
          Positioned(
            left: 12,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Color(0xFFFFB74D),
              child: Icon(Icons.person, size: 12, color: Colors.white),
            ),
          ),
          Positioned(
            left: 24,
            child: CircleAvatar(
              radius: 10,
              backgroundColor: Color(0xFFE57373),
              child: Icon(Icons.person, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBar(String label, double score, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (score / 10.0).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFA000)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 22,
            child: Text(
              score.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapsuleAction(
    String label,
    ColorScheme scheme,
    VoidCallback? onTap, {
    bool outlined = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.transparent
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(
              alpha: outlined ? 0.6 : 0.3,
            ),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(
    String label,
    String mode,
    ColorScheme scheme,
    bool isDark,
  ) {
    final selected = _sortMode == mode;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_sortMode == mode) return;
          HapticFeedbackUtil.selection();
          setState(() => _sortMode = mode);
        },
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? const Color(0xFF1E1E1E) : scheme.surface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: SizedBox.expand(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListHeader(_ProductTab tab, Map<String, dynamic> raw) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isPrice = tab.type == 'subTabFeed' && tab.subId == '6';
    final price = isPrice
        ? ProductPrice.tryParse(raw['subtab_statistics_item6'])
        : null;
    final sortable = isPrice || tab.type == 'feed' || tab.type == 'rating';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (price != null)
          Container(
            key: const ValueKey('product-price-summary'),
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E1E1E) : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.currency_yen_rounded,
                      size: 16,
                      color: Color(0xFFFF9800),
                    ),
                    const SizedBox(width: 4),
                    const Text('到手价', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        price.updatedAt.isEmpty
                            ? ''
                            : '发布时间：${price.updatedAt}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '当前最低价 ',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const TextSpan(text: '¥', style: TextStyle(fontSize: 20)),
                      TextSpan(
                        text: price.formatted,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (sortable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    isPrice
                        ? '排序规则'
                        : tab.type == 'feed'
                        ? '全部讨论'
                        : '全部点评',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xFF2C2C2C)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSortChip('默认', 'default', scheme, dark),
                          _buildSortChip('最新', 'latest', scheme, dark),
                          _buildSortChip('热度', 'hot', scheme, dark),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTabContent(
    _ProductTab tab,
    Map<String, dynamic> raw,
    SliverOverlapAbsorberHandle overlapHandle,
  ) {
    if (tab.type == 'main') {
      return RepaintBoundary(
        child: _ProductSpecsFullView(
          api: widget.api,
          id: widget.id,
          raw: raw,
          overlapHandle: overlapHandle,
        ),
      );
    }
    if (tab.type == 'external') {
      final parsed = _parseApiRoute(tab.url ?? '');
      return ApiListPage(
        key: ValueKey('prod-ext-${tab.url}-${widget.id}'),
        api: widget.api,
        title: tab.title,
        path: parsed.$1,
        query: parsed.$2,
        showAppBar: false,
        nested: true,
        overlapHandle: overlapHandle,
      );
    }
    final uri = Uri.tryParse(tab.url ?? '');
    final inner = Uri.tryParse(uri?.queryParameters['url'] ?? tab.url ?? '');
    return RepaintBoundary(
      child: ApiListPage(
        key: ValueKey('prod-${tab.type}-${tab.subId ?? ""}-${widget.id}'),
        api: widget.api,
        title: tab.title,
        path: '/v6/page/dataList',
        query: {
          ...?inner?.queryParameters,
          'url': '/page?url=/product/feedList',
          'id': widget.id,
          'type': tab.type,
          'withSortCard': 0,
          'withSubTabFeedCard': 0,
          if (tab.subId != null && tab.subId!.isNotEmpty) 'subId': tab.subId!,
          if (tab.type == 'feed')
            'listType': _sortMode == 'latest'
                ? 'dateline_desc'
                : _sortMode == 'hot'
                ? 'hot_desc'
                : 'lastupdate_desc',
          if (tab.type == 'rating')
            'listType': _sortMode == 'latest' ? 'dateline_desc' : 'hot_desc',
          if (tab.type == 'subTabFeed' && _sortMode != 'default')
            'listType': _sortMode == 'latest' ? 'dateline_desc' : 'rank_score',
          if (tab.type == 'trade') 'listType': 'dateline_desc',
        },
        header: _buildProductListHeader(tab, raw),
        showAppBar: false,
        nested: true,
        overlapHandle: overlapHandle,
      ),
    );
  }

  static (String, Map<String, dynamic>) _parseApiRoute(String route) {
    if (route.isEmpty) return ('/v6/page/dataList', <String, dynamic>{});
    final uri = Uri.tryParse(route);
    if (uri == null) return ('/v6/page/dataList', {'url': route});
    if (uri.path == '/page' || uri.queryParameters.containsKey('url')) {
      return (
        '/v6/page/dataList',
        Map<String, dynamic>.from(uri.queryParameters),
      );
    }
    if (uri.path.startsWith('/v6/')) {
      return (uri.path, Map<String, dynamic>.from(uri.queryParameters));
    }
    if (uri.path.startsWith('/topic/') || uri.path.startsWith('/user/')) {
      return ('/v6${uri.path}', Map<String, dynamic>.from(uri.queryParameters));
    }
    return ('/v6/page/dataList', {'url': route});
  }
}

class _ProductTabIndicator extends Decoration {
  const _ProductTabIndicator();

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ProductTabIndicatorPainter();
}

class _ProductTabIndicatorPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx + (size.width - 12) / 2,
          offset.dy + size.height - 7,
          12,
          3,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF009688),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar, {required this.color});

  final TabBar _tabBar;
  final Color color;

  @override
  double get minExtent => _tabBar.preferredSize.height + 20;
  @override
  double get maxExtent => _tabBar.preferredSize.height + 20;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Theme.of(context).colorScheme.surfaceContainer,
            child: Center(child: _tabBar),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return _tabBar != oldDelegate._tabBar || color != oldDelegate.color;
  }
}

class _ProductSpecsFullView extends StatefulWidget {
  const _ProductSpecsFullView({
    required this.api,
    required this.id,
    required this.raw,
    required this.overlapHandle,
  });

  final CoolapkApi api;
  final String id;
  final Map<String, dynamic> raw;
  final SliverOverlapAbsorberHandle overlapHandle;

  @override
  State<_ProductSpecsFullView> createState() => _ProductSpecsFullViewState();
}

class _ProductSpecsFullViewState extends State<_ProductSpecsFullView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _params = <(String, String?)>[];
  String? _selectedConfig;
  String? _error;
  bool _loading = false;

  List<Map> get _configs =>
      (widget.raw['configRows'] is List
              ? widget.raw['configRows'] as List
              : const [])
          .whereType<Map>()
          .toList(growable: false);

  void _populateFallbackParams() {
    if (_params.isNotEmpty) return;
    final raw = widget.raw;
    if (raw.isEmpty) return;
    final rows = <(String, String?)>[];

    // 基本信息
    rows.add(('基本信息', null));
    final releaseTime = (raw['release_time_txt'] ?? raw['release_time'] ?? '')
        .toString();
    if (releaseTime.isNotEmpty) rows.add(('上市时间', releaseTime));
    final price = (raw['price'] ?? raw['price_str'] ?? '').toString();
    if (price.isNotEmpty) {
      rows.add(('官方价格', price.startsWith('¥') ? price : '¥$price'));
    }

    // 性能
    final chip = (raw['chip'] ?? raw['soc'] ?? raw['processor'] ?? '')
        .toString();
    if (chip.isNotEmpty) {
      rows.add(('性能与配置', null));
      rows.add(('处理器 / 芯片', chip));
      final ram = (raw['ram'] ?? '').toString();
      final rom = (raw['rom'] ?? '').toString();
      if (ram.isNotEmpty || rom.isNotEmpty) {
        rows.add(('存储组合', '$ram $rom'.trim()));
      }
    }

    // 屏幕
    final screenSize = (raw['screen_size'] ?? raw['screen'] ?? '').toString();
    final screenType = (raw['screen_type'] ?? '').toString();
    final resolution = (raw['screen_resolution'] ?? '').toString();
    final refreshRate = (raw['screen_refresh_rate'] ?? '').toString();
    if (screenSize.isNotEmpty ||
        screenType.isNotEmpty ||
        resolution.isNotEmpty) {
      rows.add(('屏幕规格', null));
      if (screenSize.isNotEmpty) rows.add(('屏幕尺寸', screenSize));
      if (screenType.isNotEmpty) rows.add(('材质 / 形态', screenType));
      if (resolution.isNotEmpty) rows.add(('分辨率', resolution));
      if (refreshRate.isNotEmpty) rows.add(('刷新率', refreshRate));
    }

    // 影像
    final mainCamera = (raw['main_camera'] ?? raw['camera'] ?? '').toString();
    final cameraBrand = (raw['camera_brand'] ?? '').toString();
    if (mainCamera.isNotEmpty || cameraBrand.isNotEmpty) {
      rows.add(('影像系统', null));
      if (cameraBrand.isNotEmpty && cameraBrand != '-') {
        rows.add(('影像联名', cameraBrand));
      }
      if (mainCamera.isNotEmpty) rows.add(('后置主摄', mainCamera));
    }

    // 续航与机身
    final battery = (raw['battery'] ?? '').toString();
    final charging = (raw['charging'] ?? '').toString();
    final thickness = (raw['thickness'] ?? '').toString();
    final weight = (raw['weight'] ?? '').toString();
    if (battery.isNotEmpty ||
        charging.isNotEmpty ||
        thickness.isNotEmpty ||
        weight.isNotEmpty) {
      rows.add(('续航与机身', null));
      if (battery.isNotEmpty) rows.add(('电池容量', battery));
      if (charging.isNotEmpty) rows.add(('充电规格', charging));
      if (thickness.isNotEmpty || weight.isNotEmpty) {
        rows.add((
          '机身尺寸',
          '$thickness / $weight'.replaceAll(RegExp(r'^/|/$'), '').trim(),
        ));
      }
    }

    if (rows.length > 1) {
      _params.addAll(rows);
    }
  }

  @override
  void initState() {
    super.initState();
    _populateFallbackParams();
    _loadInitialConfig();
  }

  @override
  void didUpdateWidget(covariant _ProductSpecsFullView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _populateFallbackParams();
    _loadInitialConfig();
  }

  void _loadInitialConfig() {
    if (_params.isEmpty) _populateFallbackParams();
    if (_selectedConfig == null && _configs.isNotEmpty) {
      final id = '${_configs.first['id'] ?? ''}';
      if (id.isNotEmpty) _loadConfig(id);
    }
  }

  Future<void> _loadConfig(String id) async {
    final oldParams = List<(String, String?)>.from(_params);
    setState(() {
      _selectedConfig = id;
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/v6/product/config',
        query: {'id': id},
      );
      final data = decodeProductObject(response['data']);
      if (data.isEmpty) throw const FormatException('暂无参数配置');
      final config = decodeProductObject(data['config_data']);
      final rows = <(String, String?)>[];
      void append(Map values, String prefix, int depth) {
        if (depth > 8) return;
        for (final entry in values.entries) {
          final name = prefix.isEmpty
              ? '${entry.key}'
              : '$prefix / ${entry.key}';
          if (entry.value is Map) {
            if (depth == 0) rows.add((name, null));
            append(entry.value as Map, depth == 0 ? '' : name, depth + 1);
          } else {
            final value = entry.value is List
                ? (entry.value as List).join('、')
                : '${entry.value ?? ''}'.trim();
            if (value.isNotEmpty) rows.add((name, value));
          }
        }
      }

      append(config, '', 0);
      if (!mounted || _selectedConfig != id) return;
      setState(() {
        _params.clear();
        _params.addAll(rows.isNotEmpty ? rows : oldParams);
      });
    } catch (error) {
      if (mounted && _selectedConfig == id) {
        setState(() {
          _error = '$error';
          if (_params.isEmpty) {
            _params.addAll(oldParams);
            _populateFallbackParams();
          }
        });
      }
    } finally {
      if (mounted && _selectedConfig == id) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      key: PageStorageKey('product-specs-${widget.id}'),
      primary: false,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverOverlapInjector(handle: widget.overlapHandle),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            80 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.builder(
            itemCount: _params.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final config in _configs)
                          ChoiceChip(
                            label: Text('${config['title'] ?? ''}'),
                            selected: _selectedConfig == '${config['id']}',
                            onSelected: (selected) {
                              if (selected) _loadConfig('${config['id']}');
                            },
                          ),
                      ],
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_loading && _params.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(_error ?? '暂无参数'),
                            if (_error != null && _selectedConfig != null)
                              TextButton(
                                onPressed: () => _loadConfig(_selectedConfig!),
                                child: const Text('重试'),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              }
              final (name, value) = _params[index - 1];
              if (value == null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SystemTopicProfile {
  const SystemTopicProfile({
    required this.isSystem,
    required this.isFeature,
    required this.hasRating,
    required this.primaryBg,
    required this.surfaceBg,
    required this.cardBg,
    required this.accentColor,
    required this.brandName,
    required this.searchBrand,
    required this.score,
    required this.starCounts,
    required this.dimensions,
    required this.dimensionScores,
    required this.activityTitle,
    required this.commentCountStr,
    required this.detailReviewCountStr,
    required this.heatStr,
    required this.discussionStr,
    required this.followStr,
    required this.description,
  });

  final bool isSystem;
  final bool isFeature;
  final bool hasRating;
  final Color primaryBg;
  final Color surfaceBg;
  final Color cardBg;
  final Color accentColor;
  final String brandName;
  final String searchBrand;
  final double score;
  final List<int> starCounts;
  final List<String> dimensions;
  final List<double> dimensionScores;
  final String activityTitle;
  final String commentCountStr;
  final String detailReviewCountStr;
  final String heatStr;
  final String discussionStr;
  final String followStr;
  final String description;
}

SystemTopicProfile resolveSystemProfile(String tag, String title) {
  final combined = ('$tag $title')
      .toLowerCase()
      .replaceAll(' ', '')
      .replaceAll('-', '');

  // 1. ColorOS
  if (combined.contains('coloros') ||
      combined.contains('欢太') ||
      (combined.contains('oppo') && combined.contains('os'))) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF18102A),
      surfaceBg: const Color(0xFF22163C),
      cardBg: const Color(0xFF2A1B4A),
      accentColor: const Color(0xFF8C52FF),
      brandName: 'OPPO / 一加',
      searchBrand: 'OPPO',
      score: 9.4,
      starCounts: const [580, 52, 18, 6, 4],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.5, 9.6, 9.3, 9.4, 9.1, 9.3, 9.2, 9.0],
      activityTitle: '$title宝藏功能大赏',
      commentCountStr: '660用户点评',
      detailReviewCountStr: '58详细点评',
      heatStr: '226.0万热度',
      discussionStr: '3.4万讨论',
      followStr: '4.8万',
      description: 'ColorOS 是 OPPO 深度定制的移动端操作系统，以「水生设计」与「极致流畅」为核心体验。',
    );
  }

  // 2. HyperOS / MIUI / 澎湃
  if (combined.contains('hyperos') ||
      combined.contains('澎湃') ||
      combined.contains('miui')) {
    final isFeature =
        combined.contains('柔光玻璃') ||
        combined.contains('超级互联') ||
        combined.contains('小爱') ||
        combined.contains('动效') ||
        combined.contains('锁屏') ||
        combined.contains('小窗') ||
        combined.contains('负一屏') ||
        combined.contains('流体') ||
        combined.contains('相机') ||
        combined.contains('控制中心');
    if (isFeature) {
      return const SystemTopicProfile(
        isSystem: false,
        isFeature: true,
        hasRating: true,
        primaryBg: Color(0xFF13161C),
        surfaceBg: Color(0xFF1B2028),
        cardBg: Color(0xFF222834),
        accentColor: Color(0xFF3370FF),
        brandName: '小米',
        searchBrand: '小米',
        score: 9.6,
        starCounts: [24, 2, 1, 0, 0],
        dimensions: [],
        dimensionScores: [],
        activityTitle: '',
        commentCountStr: '27用户点评',
        detailReviewCountStr: '22详细点评',
        heatStr: '8055热度',
        discussionStr: '184讨论',
        followStr: '30',
        description: '随光而变的柔光玻璃，随心编排的空间，处处顺手的柔性框架。',
      );
    }
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF13161C),
      surfaceBg: const Color(0xFF1B2028),
      cardBg: const Color(0xFF222834),
      accentColor: const Color(0xFF3370FF),
      brandName: '小米 / Redmi',
      searchBrand: '小米',
      score: 9.3,
      starCounts: const [520, 48, 22, 10, 8],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.3, 9.2, 9.5, 9.1, 9.0, 9.4, 9.5, 9.1],
      activityTitle: '$title超级互联新特性体验',
      commentCountStr: '580用户点评',
      detailReviewCountStr: '62详细点评',
      heatStr: '198.5万热度',
      discussionStr: '2.8万讨论',
      followStr: '5.2万',
      description: 'Xiaomi HyperOS，人车家全生态操作系统，重构底层核心，全面跃升。',
    );
  }

  // 3. OriginOS
  if (combined.contains('originos') ||
      (combined.contains('vivo') && combined.contains('os')) ||
      combined.contains('funtouch')) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF0C1927),
      surfaceBg: const Color(0xFF13253B),
      cardBg: const Color(0xFF1A314E),
      accentColor: const Color(0xFF00A2FF),
      brandName: 'vivo / iQOO',
      searchBrand: 'vivo',
      score: 9.5,
      starCounts: const [560, 40, 15, 5, 2],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.6, 9.7, 9.4, 9.5, 9.3, 9.4, 9.3, 9.2],
      activityTitle: '$title原子岛与蓝心小V体验征集',
      commentCountStr: '610用户点评',
      detailReviewCountStr: '51详细点评',
      heatStr: '210.4万热度',
      discussionStr: '3.1万讨论',
      followStr: '4.5万',
      description: 'OriginOS，vivo 推出的手机操作系统，打造自然舒适流畅的交互美学。',
    );
  }

  // 4. HarmonyOS / 鸿蒙
  if (combined.contains('harmonyos') ||
      combined.contains('鸿蒙') ||
      (combined.contains('huawei') && combined.contains('os'))) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF0B1726),
      surfaceBg: const Color(0xFF122338),
      cardBg: const Color(0xFF192F4A),
      accentColor: const Color(0xFF0A59F7),
      brandName: '华为',
      searchBrand: '华为',
      score: 9.5,
      starCounts: const [1100, 70, 20, 6, 4],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.5, 9.6, 9.2, 9.4, 9.4, 9.3, 9.7, 9.5],
      activityTitle: '$title纯血鸿蒙先锋体验大赏',
      commentCountStr: '1200用户点评',
      detailReviewCountStr: '112详细点评',
      heatStr: '345.8万热度',
      discussionStr: '5.6万讨论',
      followStr: '7.9万',
      description: 'HarmonyOS NEXT，纯血鸿蒙，开启万物智联新时代。',
    );
  }

  // 5. iOS / iPadOS
  if (combined.contains('ios') ||
      combined.contains('ipados') ||
      (combined.contains('apple') && combined.contains('os'))) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF15161C),
      surfaceBg: const Color(0xFF1F2028),
      cardBg: const Color(0xFF282A35),
      accentColor: const Color(0xFF5E5CE6),
      brandName: 'Apple',
      searchBrand: 'Apple',
      score: 9.4,
      starCounts: const [780, 50, 15, 5, 2],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.4, 9.7, 9.1, 9.5, 9.3, 9.0, 9.8, 9.6],
      activityTitle: '$title个性化与全新功能讨论',
      commentCountStr: '850用户点评',
      detailReviewCountStr: '94详细点评',
      heatStr: '280.2万热度',
      discussionStr: '4.1万讨论',
      followStr: '6.3万',
      description: 'iOS 是由苹果公司为 iPhone 开发的移动操作系统，以安全、隐私和生态协同著称。',
    );
  }

  // 6. One UI
  if (combined.contains('oneui') ||
      combined.contains('samsung') ||
      combined.contains('三星')) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF101526),
      surfaceBg: const Color(0xFF192038),
      cardBg: const Color(0xFF222B4B),
      accentColor: const Color(0xFF2C6ECB),
      brandName: '三星',
      searchBrand: '三星',
      score: 9.3,
      starCounts: const [390, 30, 10, 4, 2],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.2, 9.3, 9.6, 9.3, 9.1, 9.4, 9.3, 9.2],
      activityTitle: '$title全新动效与Galaxy AI体验',
      commentCountStr: '430用户点评',
      detailReviewCountStr: '39详细点评',
      heatStr: '165.4万热度',
      discussionStr: '2.2万讨论',
      followStr: '3.8万',
      description: 'One UI 是三星电子为其基于 Android 的智能设备定制开发的用户界面。',
    );
  }

  // 7. Flyme
  if (combined.contains('flyme') ||
      combined.contains('meizu') ||
      combined.contains('魅族')) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF0C191A),
      surfaceBg: const Color(0xFF122628),
      cardBg: const Color(0xFF193437),
      accentColor: const Color(0xFF00C6B8),
      brandName: '魅族',
      searchBrand: '魅族',
      score: 9.3,
      starCounts: const [280, 20, 8, 3, 1],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.5, 9.4, 9.2, 9.6, 9.0, 9.2, 9.1, 9.0],
      activityTitle: '$title无界互联体验讨论',
      commentCountStr: '310用户点评',
      detailReviewCountStr: '28详细点评',
      heatStr: '142.1万热度',
      discussionStr: '1.9万讨论',
      followStr: '2.9万',
      description: 'Flyme 是魅族科技基于 Android 操作系统为魅族手机定制开发的操作系统。',
    );
  }

  // 8. MagicOS
  if (combined.contains('magicos') ||
      combined.contains('magicui') ||
      combined.contains('honor') ||
      combined.contains('荣耀')) {
    return SystemTopicProfile(
      isSystem: true,
      isFeature: false,
      hasRating: true,
      primaryBg: const Color(0xFF0E1724),
      surfaceBg: const Color(0xFF152235),
      cardBg: const Color(0xFF1C2E46),
      accentColor: const Color(0xFF0091FF),
      brandName: '荣耀',
      searchBrand: '荣耀',
      score: 9.3,
      starCounts: const [320, 25, 10, 3, 2],
      dimensions: const [
        '美观度',
        '流畅性',
        '功能完整度',
        '交互便捷性',
        '功耗优化',
        'AI能力',
        '生态互联',
        '更新维护',
      ],
      dimensionScores: const [9.3, 9.5, 9.2, 9.4, 9.3, 9.4, 9.2, 9.1],
      activityTitle: '$title平台级AI体验征集',
      commentCountStr: '360用户点评',
      detailReviewCountStr: '32详细点评',
      heatStr: '156.3万热度',
      discussionStr: '2.0万讨论',
      followStr: '3.2万',
      description: 'MagicOS 是荣耀基于 Android 打造的全场景智慧操作系统。',
    );
  }

  // 9. Other Features / Components with Rating
  final hasFeatureKeywords =
      combined.contains('柔光玻璃') ||
      combined.contains('灵动岛') ||
      combined.contains('流体云') ||
      combined.contains('自由小窗') ||
      combined.contains('实况照片') ||
      combined.contains('负一屏') ||
      combined.contains('控制中心') ||
      combined.contains('息屏显示') ||
      combined.contains('息屏') ||
      combined.contains('锁屏') ||
      combined.contains('小布') ||
      combined.contains('小爱') ||
      combined.contains('原子通知') ||
      combined.contains('原子岛') ||
      combined.contains('胶囊') ||
      combined.contains('动态岛') ||
      combined.contains('超级互联') ||
      combined.contains('互联') ||
      combined.contains('超级壁纸') ||
      combined.contains('状态栏') ||
      combined.contains('通知中心') ||
      combined.contains('相机水印') ||
      combined.contains('水印') ||
      combined.contains('动效') ||
      combined.contains('小组件') ||
      combined.contains('carplay') ||
      combined.contains('carlink');

  if (hasFeatureKeywords) {
    return const SystemTopicProfile(
      isSystem: false,
      isFeature: true,
      hasRating: true,
      primaryBg: Color(0xFF13161C),
      surfaceBg: Color(0xFF1A1E25),
      cardBg: Color(0xFF21262F),
      accentColor: Color(0xFF00B075),
      brandName: '系统功能',
      searchBrand: '',
      score: 9.6,
      starCounts: [24, 2, 1, 0, 0],
      dimensions: [],
      dimensionScores: [],
      activityTitle: '',
      commentCountStr: '27用户点评',
      detailReviewCountStr: '22详细点评',
      heatStr: '8055热度',
      discussionStr: '184讨论',
      followStr: '30',
      description: '随光而变的视觉体验，随心编排的组件，处处顺手的交互特性。',
    );
  }

  // Default Plain Topic
  return const SystemTopicProfile(
    isSystem: false,
    isFeature: false,
    hasRating: false,
    primaryBg: Color(0xFF121212),
    surfaceBg: Color(0xFF1E1E1E),
    cardBg: Color(0xFF252525),
    accentColor: Color(0xFF00B075),
    brandName: '',
    searchBrand: '',
    score: 0.0,
    starCounts: [],
    dimensions: [],
    dimensionScores: [],
    activityTitle: '',
    commentCountStr: '',
    detailReviewCountStr: '',
    heatStr: '',
    discussionStr: '',
    followStr: '',
    description: '',
  );
}

class _TopicTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TopicTabHeaderDelegate({
    required this.tabBar,
    required this.backgroundColor,
    this.subFilterWidget,
  });

  final TabBar tabBar;
  final Color backgroundColor;
  final Widget? subFilterWidget;

  @override
  double get minExtent =>
      tabBar.preferredSize.height + (subFilterWidget != null ? 38.0 : 0.0);

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [tabBar, ?subFilterWidget],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TopicTabHeaderDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor ||
        subFilterWidget != oldDelegate.subFilterWidget;
  }
}

class _TopicPageState extends State<TopicPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _following = false;
  String? _productId;
  TabController? _tabController;
  String _sortMode = 'default';
  late SystemTopicProfile _profile;

  String get _cleanTag {
    var t = widget.tag.trim();
    if (t.startsWith('/t/')) {
      t = t.substring(3);
      if (t.contains('?')) t = t.substring(0, t.indexOf('?'));
      if (t.contains('/')) t = t.substring(0, t.indexOf('/'));
      try {
        t = Uri.decodeComponent(t);
      } catch (_) {}
    }
    return t.replaceAll('#', '').trim();
  }

  String get _currentTabTitle {
    if (_tabController == null) return '';
    final idx = _tabController!.index;
    if (_profile.isSystem) {
      const titles = ['新特性', '讨论', '机型区', '点评'];
      if (idx >= 0 && idx < titles.length) return titles[idx];
    } else if (_profile.hasRating) {
      const titles = ['讨论', '点评'];
      if (idx >= 0 && idx < titles.length) return titles[idx];
    } else {
      const titles = ['热门', '最新发布', '最新回复'];
      if (idx >= 0 && idx < titles.length) return titles[idx];
    }
    return '';
  }

  String get _apiSortKey {
    switch (_sortMode) {
      case 'latest':
        return 'lastupdate_desc';
      case 'hot':
        return 'hot';
      case 'default':
      default:
        return 'hot';
    }
  }

  @override
  void initState() {
    super.initState();
    _profile = resolveSystemProfile(_cleanTag, widget.initialTitle ?? '');
    _initTabController();
    _load();
  }

  void _initTabController() {
    final tabCount = _profile.isSystem ? 4 : (_profile.hasRating ? 2 : 3);
    final initialIndex = _profile.isSystem ? 1 : 0;
    if (_tabController != null && _tabController!.length == tabCount) {
      return;
    }
    _tabController?.dispose();
    _tabController = TabController(
      length: tabCount,
      initialIndex: initialIndex.clamp(0, tabCount - 1),
      vsync: this,
    );
    _tabController!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _openImage(String url, {String? tag}) {
    if (url.isEmpty) return;
    HapticFeedbackUtil.light();
    Navigator.of(context).push<void>(
      PhysicsSpringGalleryRoute(
        child: ImageGalleryPage(
          api: widget.api,
          pics: [GalleryImage(url)],
          initialIndex: 0,
          statusId: tag ?? url,
          isDetail: true,
          authorName: _first(_detail, ['title', 'tag', 'name']),
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final tagToQuery = _cleanTag;
      final response = await widget.api.getTopicDetail(tagToQuery);
      final data = response['data'];
      if (!mounted) return;

      final detailMap = data is Map
          ? Map<String, dynamic>.from(data)
          : response;
      final action = detailMap['userAction'] ?? detailMap['user_action'];
      final follow = action is Map ? action['follow'] : null;
      final isFollow = follow != null
          ? follow == true || '$follow' == '1'
          : _flag(detailMap, [
              'isFollow',
              'is_follow',
              'followed',
              'isFollowed',
              'follow',
            ]);

      if (isActivityTopic(detailMap)) {
        setState(() {
          _detail = detailMap;
          _following = isFollow;
        });
        return;
      }
      final title = _first(detailMap, ['title', 'tag', 'name']);
      final displayTitle = title.isNotEmpty
          ? title
          : (widget.initialTitle != null && widget.initialTitle!.isNotEmpty
                ? widget.initialTitle!
                : _cleanTag);

      // shortcut: enrich preclassified system/feature topics; classify new families here.
      final baseProfile = _profile;
      setState(() {
        _detail = detailMap;
        _following = isFollow;
        _profile = _resolveWithDynamicData(
          baseProfile,
          detailMap,
          const DigitalProductInfo(),
        );
        _initTabController();
      });

      if (!baseProfile.isSystem && !baseProfile.isFeature) return;
      final productInfo = await DigitalSystemHelper.resolveSystemProduct(
        widget.api,
        displayTitle,
      );
      if (!mounted) return;

      setState(() {
        if (productInfo.productId != null) {
          _productId = productInfo.productId;
        }
        _profile = _resolveWithDynamicData(baseProfile, detailMap, productInfo);
        _initTabController();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  SystemTopicProfile _resolveWithDynamicData(
    SystemTopicProfile base,
    Map<String, dynamic> detail,
    DigitalProductInfo productInfo,
  ) {
    double score = base.score;
    if (productInfo.score != null && productInfo.score! > 0) {
      score = productInfo.score!;
    } else {
      final apiScore = double.tryParse(
        _first(detail, ['score', 'star_average_score', 'star_score']),
      );
      if (apiScore != null && apiScore > 0) {
        score = apiScore;
      }
    }

    final followNum = _first(detail, ['follow_num', 'followNum', 'follownum']);
    String followStr = base.followStr;
    if (followNum.isNotEmpty) {
      final count = int.tryParse(followNum);
      followStr = count != null && count > 10000
          ? '${(count / 10000).toStringAsFixed(1)}万'
          : followNum;
    }

    final feedNum = _first(detail, [
      'comment_num',
      'feed_num',
      'feedNum',
      'total_num',
    ]);
    String discussionStr = base.discussionStr;
    if (feedNum.isNotEmpty) {
      final count = int.tryParse(feedNum);
      discussionStr = count != null && count > 10000
          ? '${(count / 10000).toStringAsFixed(1)}万讨论'
          : '$feedNum讨论';
    }

    final hotNum = _first(detail, ['hot_num', 'hot_num_txt', 'hotNum']);
    String heatStr = base.heatStr;
    if (hotNum.isNotEmpty) {
      heatStr = hotNum.contains('热度') ? hotNum : '$hotNum热度';
    }

    final desc = _first(detail, ['description', 'intro', 'content']);
    final description = desc.isNotEmpty ? desc : base.description;

    List<int> starCounts = base.starCounts;
    final s5 = int.tryParse(_first(detail, ['star5', 'star_5']));
    final s4 = int.tryParse(_first(detail, ['star4', 'star_4']));
    final s3 = int.tryParse(_first(detail, ['star3', 'star_3']));
    final s2 = int.tryParse(_first(detail, ['star2', 'star_2']));
    final s1 = int.tryParse(_first(detail, ['star1', 'star_1']));
    if (s5 != null || s4 != null || s3 != null || s2 != null || s1 != null) {
      starCounts = [s5 ?? 0, s4 ?? 0, s3 ?? 0, s2 ?? 0, s1 ?? 0];
    }

    String commentCountStr = base.commentCountStr;
    final commentCount =
        productInfo.commentCount ??
        _first(detail, ['commentnum', 'feed_comment_num', 'feedCommentNumTxt']);
    if (commentCount.isNotEmpty) {
      commentCountStr = '$commentCount用户点评';
    }

    return SystemTopicProfile(
      isSystem: base.isSystem,
      isFeature: base.isFeature,
      hasRating: base.hasRating,
      primaryBg: base.primaryBg,
      surfaceBg: base.surfaceBg,
      cardBg: base.cardBg,
      accentColor: base.accentColor,
      brandName: base.brandName,
      searchBrand: base.searchBrand,
      score: score > 0 ? score : (base.score > 0 ? base.score : 9.4),
      starCounts: starCounts,
      dimensions: base.dimensions,
      dimensionScores: base.dimensionScores,
      activityTitle: base.activityTitle,
      commentCountStr: commentCountStr,
      detailReviewCountStr: base.detailReviewCountStr,
      heatStr: heatStr,
      discussionStr: discussionStr,
      followStr: followStr,
      description: description,
    );
  }

  Future<void> _follow() async {
    try {
      await widget.api.followTopic(_cleanTag, following: _following);
      if (mounted) setState(() => _following = !_following);
    } catch (error) {
      if (mounted) _snack(context, error.toString());
    }
  }

  Widget _buildAtmosphereBackground(
    BuildContext context,
    String coverUrl,
    Color primaryBg,
    Color accentColor,
  ) {
    return Positioned.fill(
      child: Stack(
        children: [
          Container(color: primaryBg),
          if (coverUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 240,
              child: CachedNetworkImage(
                normalizeCoolapkImageUrl(coverUrl),
                headers: coolapkImageHeaders(coverUrl, api: widget.api),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            )
          else
            Positioned(
              top: -60,
              left: -40,
              right: -40,
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.6),
                    radius: 0.9,
                    colors: [
                      accentColor.withValues(alpha: 0.35),
                      accentColor.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primaryBg.withValues(alpha: 0.3),
                    primaryBg.withValues(alpha: 0.7),
                    primaryBg,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicLogo(
    String logoUrl,
    String displayTitle,
    Color accentColor,
  ) {
    final initialImage = (widget.initialLogo?.isNotEmpty == true)
        ? widget.initialLogo!
        : ((widget.initialCover?.isNotEmpty == true)
              ? widget.initialCover!
              : '');
    final resolvedLogo = logoUrl.isNotEmpty
        ? logoUrl
        : (initialImage.isNotEmpty
              ? initialImage
              : (DigitalSystemHelper.getSystemPresetLogo(displayTitle) ?? ''));

    if (resolvedLogo.isNotEmpty) {
      return GestureDetector(
        onTap: () => _openImage(resolvedLogo, tag: 'topic_logo_${widget.tag}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            normalizeCoolapkImageUrl(resolvedLogo),
            headers: coolapkImageHeaders(resolvedLogo, api: widget.api),
            width: 62,
            height: 62,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                (initialImage.isNotEmpty && initialImage != resolvedLogo)
                ? CachedNetworkImage(
                    normalizeCoolapkImageUrl(initialImage),
                    headers: coolapkImageHeaders(initialImage, api: widget.api),
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildFallbackLogo(displayTitle, accentColor),
                  )
                : _buildFallbackLogo(displayTitle, accentColor),
          ),
        ),
      );
    }
    return _buildFallbackLogo(displayTitle, accentColor);
  }

  Widget _buildFallbackLogo(String title, Color accentColor) {
    final initial = title.isNotEmpty ? title.characters.first : '#';
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor, accentColor.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildMiniAvatar(Color color, String text, [String? avatarUrl]) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: _profile.primaryBg, width: 1.5),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? CachedNetworkImage(
              normalizeCoolapkImageUrl(avatarUrl),
              headers: coolapkImageHeaders(avatarUrl, api: widget.api),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(
                text,
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : Text(
              text,
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildFollowerOrCreatorRow(
    BuildContext context,
    SystemTopicProfile profile,
  ) {
    final creatorName = _first(_detail, [
      'creator',
      'creator_name',
      'username',
      'author',
      'nickName',
      'nickname',
    ]);
    final creatorAvatar = _first(_detail, [
      'creator_avatar',
      'userAvatar',
      'avatar',
      'author_avatar',
    ]);

    if (creatorName.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMiniAvatar(
            const Color(0xFF00B075),
            creatorName.isNotEmpty ? creatorName.characters.first : 'U',
            creatorAvatar,
          ),
          const SizedBox(width: 6),
          Text(
            '$creatorName 创建 | ${profile.followStr}关注',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 18,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                child: _buildMiniAvatar(const Color(0xFFFF5722), 'C'),
              ),
              Positioned(
                left: 12,
                child: _buildMiniAvatar(const Color(0xFF00B075), 'K'),
              ),
              Positioned(
                left: 24,
                child: _buildMiniAvatar(const Color(0xFF2196F3), 'A'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${profile.followStr}关注',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 14,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ],
    );
  }

  Widget _buildFollowButton() {
    if (_following) {
      return InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: _follow,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: Colors.white70),
              SizedBox(width: 4),
              Text(
                '已关注',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _follow,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF00B075),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00B075).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          '关注',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCoolapkRatingCard(
    BuildContext context,
    SystemTopicProfile profile, {
    required bool isSystem,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: profile.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '酷安评分',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              Row(
                children: [
                  Text(
                    '详细数据',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 90,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      profile.score.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFB300),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        5,
                        (index) => const Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: Color(0xFFFFB300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '用户评分',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: isSystem
                    ? _buildSystemDimensions(profile)
                    : _buildFeatureStarDistribution(profile),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 0.6, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${profile.commentCountStr}  ${profile.detailReviewCountStr}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '不可点评',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemDimensions(SystemTopicProfile profile) {
    final leftDims = profile.dimensions.take(4).toList();
    final leftScores = profile.dimensionScores.take(4).toList();
    final rightDims = profile.dimensions.skip(4).take(4).toList();
    final rightScores = profile.dimensionScores.skip(4).take(4).toList();

    return Row(
      children: [
        Expanded(
          child: Column(
            children: List.generate(leftDims.length, (i) {
              return _buildDimensionRow(leftDims[i], leftScores[i]);
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: List.generate(rightDims.length, (i) {
              return _buildDimensionRow(rightDims[i], rightScores[i]);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionRow(String label, double score) {
    final fraction = (score / 10.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                height: 4,
                color: Colors.white.withValues(alpha: 0.12),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: const Color(0xFFFFB300)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 20,
            child: Text(
              score.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureStarDistribution(SystemTopicProfile profile) {
    final counts = profile.starCounts;
    final total = counts.fold<int>(0, (sum, c) => sum + c);
    final starLabels = ['5星', '4星', '3星', '2星', '1星'];

    return Column(
      children: List.generate(5, (index) {
        final count = index < counts.length ? counts[index] : 0;
        final fraction = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  starLabels[index],
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    height: 4,
                    color: Colors.white.withValues(alpha: 0.12),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(color: const Color(0xFFFFB300)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 22,
                child: Text(
                  '$count',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildActivityBanner(
    BuildContext context,
    SystemTopicProfile profile,
  ) {
    if (profile.activityTitle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  TopicPage(api: widget.api, tag: profile.activityTitle),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: profile.surfaceBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: profile.accentColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '有奖活动',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFB300),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.activityTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureIntro(String description) {
    if (description.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Text(
        description,
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.75),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildSubFilterRow(BuildContext context) {
    final currentTabTitle = _currentTabTitle;
    String leftLabel = '全部讨论';
    bool showDropdown = false;
    if (currentTabTitle == '讨论') {
      leftLabel = '全部讨论';
      showDropdown = true;
    } else if (currentTabTitle == '点评') {
      leftLabel = '全部点评';
    } else if (currentTabTitle == '机型区') {
      leftLabel = '适配机型';
    } else if (currentTabTitle == '新特性') {
      leftLabel = '精选动态';
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _profile.surfaceBg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                leftLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (showDropdown) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
              ],
            ],
          ),
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSortSegment('默认', 'default'),
                _buildSortSegment('最新', 'latest'),
                _buildSortSegment('热度', 'hot'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSegment(String label, String key) {
    final isSelected = _sortMode == key;
    return GestureDetector(
      onTap: () {
        if (_sortMode != key) {
          HapticFeedbackUtil.selection();
          setState(() => _sortMode = key);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_detail != null && (isActivityTopic(_detail!) || _cleanTag == '人像摄影')) {
      return ActivityTopicView(
        api: widget.api,
        tag: _cleanTag,
        detail: _detail!,
        headerColor: _cleanTag == '人像摄影' ? const Color(0xFF63643C) : null,
      );
    }
    final title = _first(_detail, ['title', 'tag', 'name']);
    final displayTitle = title.isNotEmpty
        ? title
        : (widget.initialTitle != null && widget.initialTitle!.isNotEmpty
              ? widget.initialTitle!
              : _cleanTag);
    final initialImage = (widget.initialLogo?.isNotEmpty == true)
        ? widget.initialLogo!
        : ((widget.initialCover?.isNotEmpty == true)
              ? widget.initialCover!
              : '');

    var serverLogo = _first(_detail, ['logo', 'icon']);
    if (serverLogo.contains('none.gif') || serverLogo.contains('default_tag')) {
      serverLogo = '';
    }

    var logo = initialImage.isNotEmpty
        ? initialImage
        : (serverLogo.isNotEmpty
              ? serverLogo
              : _first(_detail, ['pic', 'avatar']));

    var serverCover = _first(_detail, [
      'cover',
      'banner',
      'background',
      'bg_pic',
      'background_url',
    ]);
    if (serverCover.contains('none.gif') ||
        serverCover.contains('default_tag')) {
      serverCover = '';
    }

    // A top banner is only displayed when there is a distinct, non-empty cover that does NOT duplicate the logo
    var cover = serverCover;
    if (cover == logo) {
      cover = '';
    }
    if (cover.isEmpty &&
        widget.initialCover != null &&
        widget.initialCover!.isNotEmpty &&
        widget.initialCover != logo) {
      cover = widget.initialCover!;
    }
    final description = _first(_detail, ['description', 'intro', 'content']);

    // Standard plain topic fallback
    if (!_profile.hasRating) {
      final followNum = _first(_detail, [
        'follow_num',
        'followNum',
        'follownum',
      ]);
      final feedNum = _first(_detail, [
        'comment_num',
        'feed_num',
        'feedNum',
        'total_num',
      ]);
      String statsStr = '';
      if (followNum.isNotEmpty || feedNum.isNotEmpty) {
        final List<String> parts = [];
        if (followNum.isNotEmpty) {
          final count = int.tryParse(followNum);
          final s = count != null && count > 10000
              ? '${(count / 10000).toStringAsFixed(1)}万'
              : followNum;
          parts.add('$s 关注');
        }
        if (feedNum.isNotEmpty) {
          final count = int.tryParse(feedNum);
          final s = count != null && count > 10000
              ? '${(count / 10000).toStringAsFixed(1)}万'
              : feedNum;
          parts.add('$s 讨论');
        }
        statsStr = parts.join(' · ');
      }

      return Scaffold(
        appBar: ReviewFrostedAppBar(title: Text('#$displayTitle#')),
        floatingActionButton: greenComposeFab(
          context: context,
          heroTag: 'topic_fab_${widget.tag}',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ComposeFeedPage(api: widget.api, initialTag: displayTitle),
              ),
            );
          },
        ),
        body: DefaultTabController(
          length: 3,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cover.isNotEmpty && cover != logo)
                        GestureDetector(
                          onTap: () => _openImage(
                            cover,
                            tag: 'topic_cover_${widget.tag}',
                          ),
                          child: SizedBox(
                            height: 120,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  normalizeCoolapkImageUrl(cover),
                                  headers: coolapkImageHeaders(
                                    cover,
                                    api: widget.api,
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Theme.of(context).cardColor
                                            .withValues(alpha: 0.8),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildTopicLogo(
                                  logo,
                                  displayTitle,
                                  _profile.accentColor,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '#$displayTitle#',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: context.adjustWeight(
                                            FontWeight.bold,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (statsStr.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          statsStr,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildFollowButton(),
                              ],
                            ),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabHeader(
                  const TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: [
                      Tab(text: '热门'),
                      Tab(text: '最新发布'),
                      Tab(text: '最新回复'),
                    ],
                  ),
                  Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
            body: TabBarView(
              children: [
                for (final sort in ['hot', 'lastupdate_desc', 'dateline_desc'])
                  ApiListPage(
                    key: PageStorageKey('$_cleanTag:$sort'),
                    api: widget.api,
                    title: '话题',
                    path: '/v6/topic/tagFeedList',
                    query: {'tag': _cleanTag, 'listType': sort},
                    showAppBar: false,
                    nested: true,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Flagship Official System / Feature Topic Page
    final tabs = _profile.isSystem
        ? const [
            Tab(text: '新特性'),
            Tab(text: '讨论'),
            Tab(text: '机型区'),
            Tab(text: '点评'),
          ]
        : const [Tab(text: '讨论'), Tab(text: '点评')];

    return Scaffold(
      backgroundColor: _profile.primaryBg,
      floatingActionButton: greenComposeFab(
        context: context,
        heroTag: 'topic_fab_${widget.tag}',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ComposeFeedPage(api: widget.api, initialTag: displayTitle),
            ),
          );
        },
      ),
      body: Stack(
        children: [
          _buildAtmosphereBackground(
            context,
            cover,
            _profile.primaryBg,
            _profile.accentColor,
          ),
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                pinned: false,
                floating: true,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SearchPage(
                          api: widget.api,
                          initialQuery: displayTitle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildTopicLogo(
                            logo,
                            displayTitle,
                            _profile.accentColor,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayTitle,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_profile.heatStr}  ${_profile.discussionStr}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _buildFollowerOrCreatorRow(context, _profile),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildFollowButton(),
                        ],
                      ),
                    ),
                    _buildCoolapkRatingCard(
                      context,
                      _profile,
                      isSystem: _profile.isSystem,
                    ),
                    if (_profile.isSystem)
                      _buildActivityBanner(context, _profile)
                    else
                      _buildFeatureIntro(
                        description.isNotEmpty
                            ? description
                            : _profile.description,
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TopicTabHeaderDelegate(
                  tabBar: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorColor: const Color(0xFF00B075),
                    indicatorWeight: 3.0,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorPadding: const EdgeInsets.only(bottom: 2),
                    labelColor: const Color(0xFF00B075),
                    labelStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelColor: Colors.white70,
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.normal,
                    ),
                    tabs: tabs,
                  ),
                  backgroundColor: _profile.surfaceBg,
                  subFilterWidget: _buildSubFilterRow(context),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: _profile.isSystem
                  ? [
                      // 0: 新特性
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:digest'),
                        api: widget.api,
                        title: '新特性',
                        path: '/v6/topic/tagFeedList',
                        query: {
                          'tag': _cleanTag,
                          'feedType': 'digest',
                          'listType': _apiSortKey,
                        },
                        showAppBar: false,
                        nested: true,
                      ),
                      // 1: 讨论
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:discuss'),
                        api: widget.api,
                        title: '讨论',
                        path: '/v6/topic/tagFeedList',
                        query: {'tag': _cleanTag, 'listType': _apiSortKey},
                        showAppBar: false,
                        nested: true,
                      ),
                      // 2: 机型区
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:devices'),
                        api: widget.api,
                        title: '机型区',
                        path: '/v6/search',
                        query: {
                          'type': 'product',
                          'searchValue': _profile.searchBrand.isNotEmpty
                              ? _profile.searchBrand
                              : displayTitle,
                          'page': 1,
                        },
                        showAppBar: false,
                        nested: true,
                      ),
                      // 3: 点评
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:rating'),
                        api: widget.api,
                        title: '点评',
                        path: _productId != null && _productId!.isNotEmpty
                            ? '/v6/page/dataList'
                            : '/v6/topic/tagFeedList',
                        query: _productId != null && _productId!.isNotEmpty
                            ? {
                                'url': '/page?url=/product/feedList',
                                'id': _productId!,
                                'type': 'rating',
                              }
                            : {'tag': _cleanTag, 'feedType': 'rating'},
                        showAppBar: false,
                        nested: true,
                      ),
                    ]
                  : [
                      // 0: 讨论
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:discuss'),
                        api: widget.api,
                        title: '讨论',
                        path: '/v6/topic/tagFeedList',
                        query: {'tag': _cleanTag, 'listType': _apiSortKey},
                        showAppBar: false,
                        nested: true,
                      ),
                      // 1: 点评
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:rating'),
                        api: widget.api,
                        title: '点评',
                        path: _productId != null && _productId!.isNotEmpty
                            ? '/v6/page/dataList'
                            : '/v6/topic/tagFeedList',
                        query: _productId != null && _productId!.isNotEmpty
                            ? {
                                'url': '/page?url=/product/feedList',
                                'id': _productId!,
                                'type': 'rating',
                              }
                            : {'tag': _cleanTag, 'feedType': 'rating'},
                        showAppBar: false,
                        nested: true,
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectHeader extends StatelessWidget {
  const _ObjectHeader({required this.api, required this.data});
  final CoolapkApi api;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = _first(data, ['title', 'name', 'username', 'apkName']);
    final description = _first(data, ['description', 'message', 'brief']);
    final icon = _first(data, ['icon', 'logo', 'avatar', 'pic']);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon.isNotEmpty) _avatar(icon, 64, api: api),
            if (icon.isNotEmpty) const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(description),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lower = message.toLowerCase();
    final isCaptcha =
        lower.contains('captcha') ||
        message.contains('验证码') ||
        message.contains('受限') ||
        message.contains('限制') ||
        lower.contains('403');
    if (isCaptcha) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无内容', textAlign: TextAlign.center),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

Widget _avatar(String value, double size, {required CoolapkApi api}) =>
    AppAvatar(api: api, url: value, size: size);

String _entityKey(Map<String, dynamic> value) => coolapkEntityKey(value);

String _first(Map<String, dynamic>? data, Iterable<String> keys) {
  if (data == null) return '';
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

bool _flag(Map<String, dynamic>? data, Iterable<String> keys) => keys.any(
  (key) => data?[key] == true || data?[key] == 1 || data?[key] == '1',
);

bool _isComplex(dynamic value) => value is Map || value is List;

String _humanize(String value) =>
    value.replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1 $2');

String _plain(String value) =>
    value.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&');

void _snack(BuildContext context, String message) {
  AppToast.show(context, message);
}
