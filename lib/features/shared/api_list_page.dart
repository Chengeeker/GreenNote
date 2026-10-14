import 'package:easy_refresh/easy_refresh.dart';

import '../../core/widgets/review_refresh_header.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../feed/feed_pages.dart';
import '../feed/image_gallery_page.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/utils/spring_page_route.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/theme/app_theme.dart';
import '../digital/utils/digital_system_helper.dart';
import 'app_detail_page.dart';
import '../shell/main_pages.dart' show ComposeFeedPage;

class ApiListPage extends StatefulWidget {
  const ApiListPage({
    required this.api,
    required this.title,
    required this.path,
    this.query = const {},
    this.showAppBar = true,
    this.nested = false,
    this.header,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String path;
  final Map<String, dynamic> query;
  final bool showAppBar;
  final bool nested;
  final Widget? header;

  @override
  State<ApiListPage> createState() => _ApiListPageState();
}

class _ApiListPageState extends State<ApiListPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  String? _error;
  String _first = '';
  String _last = '';
  int _page = 0;
  bool _loading = false;
  bool _more = true;

  @override
  void initState() {
    super.initState();
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
      _load(refresh: true);
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 520) {
      _load(refresh: false);
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (_loading || (!refresh && !_more)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final next = refresh ? 1 : _page + 1;
    try {
      final page = await widget.api.getList(
        widget.path,
        query: {
          ...widget.query,
          'page': next,
          if (!refresh && _first.isNotEmpty) 'firstItem': _first,
          if (!refresh && _last.isNotEmpty) 'lastItem': _last,
        },
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items.clear();
          _first = '';
          _last = '';
        }
        final known = _items.map(_entityKey).toSet();
        _items.addAll(page.items.where((item) => known.add(_entityKey(item))));
        _page = next;
        if (page.firstItem.isNotEmpty) _first = page.firstItem;
        if (page.lastItem.isNotEmpty) _last = page.lastItem;
        _more = page.hasMore && page.items.isNotEmpty;
      });
      precacheFeedImages(page.items, context, api: widget.api);
      if (refresh && page.hasMore && _items.length <= 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loading && _more) {
            _load(refresh: false);
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
        onRefresh: () => _load(refresh: true),
        child: _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (widget.header != null) widget.header!,
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error ?? '暂无内容'),
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
                controller: widget.nested ? null : _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  0,
                  widget.header != null ? 0 : 10,
                  0,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount:
                    _items.length +
                    (widget.header != null ? 1 : 0) +
                    (_loading || _error != null ? 1 : 0),
                itemBuilder: (context, index) {
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
                    return TextButton(
                      onPressed: () => _load(refresh: false),
                      child: Text('加载失败，点击重试：$_error'),
                    );
                  }
                  return ApiEntityCard(
                    api: widget.api,
                    entity: _items[itemIndex],
                  );
                },
              ),
      ),
    );
    if (!widget.showAppBar) return list;
    return Scaffold(
      appBar: ReviewFrostedAppBar(title: Text(widget.title)),
      body: list,
    );
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
  const ApiEntityCard({required this.api, required this.entity, super.key});

  final CoolapkApi api;
  final Map<String, dynamic> entity;

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
      try {
        final decoded = Uri.decodeComponent(sub).replaceAll('#', '').trim();
        if (decoded.isNotEmpty && int.tryParse(decoded) == null) {
          return decoded;
        }
      } catch (_) {}
    }
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
    if (type == 'card') return _buildTemplate(context);
    if ((type.contains('feed') && !type.contains('reply')) ||
        (type.isEmpty && entity.containsKey('message'))) {
      final feed = CoolapkFeed.fromJson(entity);
      if (feed.id.isNotEmpty) return FeedCard(api: api, feed: feed);
    }
    final isTopic = type.contains('topic') || type.contains('tag');
    final isApk = type.contains('apk') || type.contains('app');
    final topicTag = isTopic ? extractTopicTag(entity) : '';
    final id = isTopic && topicTag.isNotEmpty
        ? topicTag
        : _value(
            isApk
                ? ['packageName', 'package_name', 'apkname', 'apk_name', 'id']
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
    return InkWell(
      onTap: id.isEmpty ? null : () => _open(context, type, id, entity),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(image),
                  headers: coolapkImageHeaders(image, api: api),
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _icon(context, type),
                ),
              )
            else
              _icon(context, type),
            const SizedBox(width: 12),
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
                    const SizedBox(height: 5),
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
                child: ListView.separated(
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

        if (searchScope != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              userCard,
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
                      currentSort: searchScope.allSortType,
                      onSortChanged: searchScope.onAllSortChanged,
                    ),
                  ],
                ),
              ),
            ],
          );
        }
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
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              itemCount: entities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) => SizedBox(
                width: 92,
                child: _TemplateItem(api: api, item: entities[index]),
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
          builder: (_) => ApiDetailPage(
            api: api,
            title: '评论详情',
            path: '/v6/feed/replyDetail',
            query: {'id': id},
          ),
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
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RawEntityPage(api: api, entity: entity),
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
      'title',
      'name',
      'username',
      'productName',
      'tag',
    ]);
    final image = card._value(['logo', 'icon', 'pic', 'cover', 'avatar']);
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
              child: ListView(
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
    );
  }
}

class CoolPicPage extends StatefulWidget {
  const CoolPicPage({required this.api, super.key});

  final CoolapkApi api;

  @override
  State<CoolPicPage> createState() => _CoolPicPageState();
}

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({required this.api, required this.id, super.key});

  final CoolapkApi api;
  final String id;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  Map<String, dynamic>? _event;
  String? _error;
  bool _loading = true;

  String _text(List<String> keys) => _first(_event ?? const {}, keys);

  int? _time(List<String> keys) {
    final value = int.tryParse(_text(keys));
    return value != null && value > 0 ? value : null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/v6/event/detail',
        query: {'id': widget.id},
      );
      final root = response is Map ? response : const <String, dynamic>{};
      final data = root['data'];
      if (data is! Map) throw const CoolapkApiException('活动详情数据为空');
      if (mounted) setState(() => _event = Map<String, dynamic>.from(data));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final start = _time(['registrationStart', 'registration_start']);
    final end = _time(['registrationEnd', 'registration_end']);
    final eventEnd = _time(['eventEnd', 'event_end']);
    final stage = int.tryParse(_text(['stageStatus', 'stage_status']));
    final action = _text(['actionUrl', 'action_url']);
    final canRegister =
        action.isNotEmpty &&
        stage != 2 &&
        stage != 3 &&
        (start == null || now >= start) &&
        (end == null || now <= end);
    final status = stage == 3 || (eventEnd != null && now > eventEnd)
        ? '活动已结束'
        : start != null && now < start
        ? '报名未开始'
        : stage == 2
        ? '活动进行中'
        : end != null && now > end
        ? '报名已结束'
        : canRegister
        ? '立即报名'
        : '暂不可报名';
    final logo = _text(['logo', 'pic', 'cover']);
    final title = _text(['title', 'name']);

    return Scaffold(
      appBar: ReviewFrostedAppBar(title: const Text('酷安活动')),
      body: _loading && event == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && event == null
          ? _RetryView(message: _error!, onRetry: _load)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                if (logo.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 1080 / 608,
                    child: CachedNetworkImage(
                      logo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '报名时间：${_formatEventTime(start)} 至 ${_formatEventTime(end)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: canRegister
                            ? () => _openAction(action)
                            : null,
                        child: Text(status),
                      ),
                      if (_text(['noticeRule', 'notice_rule']).isNotEmpty) ...[
                        const Divider(height: 28),
                        Text(
                          '报名须知',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(_text(['noticeRule', 'notice_rule'])),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _load,
                          child: Text('刷新失败：$_error'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openAction(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      _snack(context, '活动报名地址无效');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _snack(context, '无法打开活动报名地址');
    }
  }
}

String _formatEventTime(int? seconds) {
  if (seconds == null) return '待定';
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
                      builder: (_) => TopicPage(api: widget.api, tag: tag),
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

class DyhPage extends StatefulWidget {
  const DyhPage({
    required this.api,
    required this.id,
    required this.title,
    super.key,
  });

  final CoolapkApi api;
  final String id;
  final String title;

  @override
  State<DyhPage> createState() => _DyhPageState();
}

class _DyhPageState extends State<DyhPage> with SingleTickerProviderStateMixin {
  static const _types = ['all', 'square'];
  late final _tabs = TabController(length: _types.length, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: Text(widget.title),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '精选'),
          Tab(text: '广场'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [
        for (final type in _types)
          ApiListPage(
            key: ValueKey('dyh-${widget.id}-$type'),
            api: widget.api,
            title: widget.title,
            path: '/v6/dyhArticle/list',
            query: {'dyhId': widget.id, 'type': type},
            showAppBar: false,
            nested: true,
          ),
      ],
    ),
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
        _following = _flag(_space, ['isFollow', 'is_follow', 'followed']);
        _blocked = _flag(_space, ['isBlackList', 'is_blocked', 'blocked']);
        _apiBlocked = _flag(_space, ['isBlocked', 'is_block']);
        _special = _flag(_space, ['isSpecialFollow', 'is_special_follow']);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    Map<String, dynamic> body = const {},
  }) async {
    if (_working) return false;
    setState(() => _working = true);
    try {
      await widget.api.request(
        path,
        method: 'POST',
        query: {'uid': widget.uid},
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
    await _userAction('/v6/user/updateRemark', body: {'remark': value});
  }

  List<(String, String)> get _profileTabs => [
    ('主页', ''),
    ('动态', '/v6/user/feedList'),
    ('回复', '/v6/user/replyList'),
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
    ('关注列表', '/v6/user/userFollowList'),
    ('酷图流', '/v6/page/dataList:userCoolPictureFeedList'),
    ('数码评分', '/v6/page/dataList:nodeRatingList'),
    ('好物动态', '/v6/page/dataList:goodsFeedList'),
    ('二手', '/v6/page/dataList:userErshouList'),
    if (widget.uid == widget.api.currentUid)
      ('回收站', '/v6/page/dataList:userDeleteFeedList'),
  ];

  Widget _profileStat(String label, String value, {VoidCallback? onTap}) {
    final count = int.tryParse(value);
    final countStr = count == null
        ? (value.isEmpty ? '0' : value)
        : count > 10000
        ? '${(count / 10000).toStringAsFixed(1)}万'
        : '$count';
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          countStr,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: '$label列表',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: content,
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
          builder: (_) => ApiListPage(
            api: widget.api,
            title: title,
            path: path,
            query: {'uid': widget.uid},
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final data = _space ?? const <String, dynamic>{};
    final name = _first(data, ['username', 'userName', 'name']);
    final avatar = _first(data, ['userAvatar', 'avatar']);
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
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: Text(name.isEmpty ? '酷友主页' : name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'block':
                  _toggleBlock();
                  break;
                case 'apiBlock':
                  _userAction(
                    _apiBlocked ? '/v6/user/unblock' : '/v6/user/block',
                  ).then((changed) {
                    if (mounted && changed) {
                      setState(() => _apiBlocked = !_apiBlocked);
                    }
                  });
                  break;
                case 'special':
                  _userAction(
                    _special
                        ? '/v6/user/cancelFollower'
                        : '/v6/user/specialFollowUser',
                  ).then((changed) {
                    if (mounted && changed) {
                      setState(() => _special = !_special);
                    }
                  });
                  break;
                case 'remark':
                  _updateRemark();
                  break;
              }
            },
            itemBuilder: (context) => [
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
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cover.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  _openImage(cover, tag: 'cover_${widget.uid}'),
                              child: SizedBox(
                                height: 128,
                                width: double.infinity,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      cover,
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
                                    GestureDetector(
                                      onTap: () => _openImage(
                                        avatar,
                                        tag: 'avatar_${widget.uid}',
                                      ),
                                      child: AppAvatar(
                                        api: widget.api,
                                        url: avatar,
                                        size: 64,
                                        name: name,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  name.isEmpty ? '酷安用户' : name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: context
                                                        .adjustWeight(
                                                          FontWeight.bold,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              if (_first(data, [
                                                'level',
                                              ]).isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Lv.${_first(data, ['level'])}',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'UID: ${widget.uid}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (widget.uid != widget.api.currentUid)
                                      if (_working)
                                        const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else if (_following)
                                        OutlinedButton.icon(
                                          onPressed: _follow,
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                          ),
                                          label: const Text('已关注'),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                          ),
                                        )
                                      else
                                        FilledButton.icon(
                                          onPressed: _follow,
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('关注'),
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                          ),
                                        ),
                                  ],
                                ),
                                if (bio.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    bio,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                const Divider(height: 1, thickness: 0.5),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _profileStat('获赞', likeCount),
                                    ),
                                    Expanded(
                                      child: _profileStat(
                                        '关注',
                                        followCount,
                                        onTap: () => _openRelations(
                                          '关注',
                                          widget.uid == widget.api.currentUid
                                              ? '/v6/user/myFollowList'
                                              : '/v6/user/userFollowList',
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _profileStat(
                                        '粉丝',
                                        fansCount,
                                        onTap: () => _openRelations(
                                          '粉丝',
                                          widget.uid == widget.api.currentUid
                                              ? '/v6/user/myFansList'
                                              : '/v6/user/userFansList',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                      TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                        unselectedLabelColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        dividerColor: Colors.transparent,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final tab in _profileTabs) Tab(text: tab.$1),
                        ],
                      ),
                      Theme.of(context).colorScheme.surface,
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
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ApiEntityCard(
                                      api: widget.api,
                                      entity: Map<String, dynamic>.from(item),
                                    ),
                                  ),
                            if (_space?['homeTabCardRows'] is! List ||
                                (_space!['homeTabCardRows'] as List).isEmpty)
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
                            if (tab.$2.contains(':'))
                              'url': tab.$2.split(':').last,
                          },
                          showAppBar: false,
                          nested: true,
                        ),
                  ],
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

class TopicPage extends StatefulWidget {
  const TopicPage({
    required this.api,
    required this.tag,
    this.initialTitle,
    this.initialLogo,
    super.key,
  });

  final CoolapkApi api;
  final String tag;
  final String? initialTitle;
  final String? initialLogo;

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
  String _sortMode = 'default';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: 1, // '讨论'
      vsync: this,
    );
    _loadDetail();
  }

  @override
  void dispose() {
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
    return tabs.isEmpty ? _defaultTabs : tabs;
  }

  bool _hasTabDiff(List<_ProductTab> a, List<_ProductTab> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title ||
          a[i].type != b[i].type ||
          a[i].subId != b[i].subId) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadDetail() async {
    try {
      final res = await widget.api.getProductDetail(widget.id);
      if (mounted) {
        final serverTabs = _parseServerTabs(res['tabList'], widget.id);
        if (_hasTabDiff(_tabs, serverTabs)) {
          final currentType = _tabs[_tabController.index].type;
          var nextIndex = serverTabs.indexWhere((t) => t.type == currentType);
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
            final isFollow = res['is_follow'] ?? res['isFollow'];
            _following = isFollow == 1 || isFollow == true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            oldController.dispose();
          });
        } else {
          setState(() {
            _detail = res;
            final isFollow = res['is_follow'] ?? res['isFollow'];
            _following = isFollow == 1 || isFollow == true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final next = !_following;
    setState(() => _following = next);
    try {
      await widget.api.followProduct(widget.id, following: !next);
    } catch (_) {
      if (mounted) setState(() => _following = !next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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

    final scoreStr = (raw['score'] ?? raw['star_average_score'] ?? '7.7')
        .toString();
    final scoreVal = double.tryParse(scoreStr) ?? 7.7;
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
        (raw['comment_num_txt'] ??
                '${raw['owner_comment_num'] ?? '3550'}机主点评 ${raw['detail_comment_num'] ?? '3327'}详细点评')
            .toString();

    final specsTags = <String>[
      if ((raw['release_time_txt'] ?? raw['release_time'] ?? '')
          .toString()
          .isNotEmpty)
        '${raw['release_time_txt'] ?? raw['release_time']} 上市'
      else
        '2025-10-13 上市',
      if ((raw['chip'] ?? raw['soc'] ?? raw['processor'] ?? '')
          .toString()
          .isNotEmpty)
        (raw['chip'] ?? raw['soc'] ?? raw['processor']).toString()
      else
        '天玑 9500',
      if ((raw['screen_size'] ?? raw['screen'] ?? '').toString().isNotEmpty)
        (raw['screen_size'] ?? raw['screen']).toString()
      else
        '6.78 英寸',
      if ((raw['screen_type'] ?? '').toString().isNotEmpty)
        raw['screen_type'].toString()
      else
        '直屏',
      if ((raw['battery'] ?? '').toString().isNotEmpty)
        raw['battery'].toString(),
      if ((raw['charging'] ?? '').toString().isNotEmpty)
        raw['charging'].toString(),
    ];

    return Scaffold(
      extendBody: true,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            backgroundColor: theme.scaffoldBackgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: innerBoxIsScrolled
                ? Text(
                    productTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
            actions: [
              IconButton(
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
                                      color: scheme.onSurfaceVariant.withValues(
                                        alpha: 0.7,
                                      ),
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
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: primaryGreen,
                indicatorWeight: 3,
                labelColor: primaryGreen,
                labelStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelColor: scheme.onSurfaceVariant,
                unselectedLabelStyle: const TextStyle(fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: [for (final tab in _tabs) Tab(text: tab.title)],
              ),
              color: theme.scaffoldBackgroundColor,
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final currentIndex = _tabController.index;
                if (currentIndex >= _tabs.length) {
                  return const SizedBox.shrink();
                }
                final currentTab = _tabs[currentIndex];
                if (currentTab.type != 'feed' && currentTab.type != 'rating') {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentTab.type == 'feed' ? '全部讨论' : '全部点评',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.sort_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF222222)
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSortChip(
                              '默认',
                              'default',
                              primaryGreen,
                              scheme,
                              isDark,
                            ),
                            _buildSortChip(
                              '最新',
                              'latest',
                              primaryGreen,
                              scheme,
                              isDark,
                            ),
                            _buildSortChip(
                              '热度',
                              'hot',
                              primaryGreen,
                              scheme,
                              isDark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [for (final tab in _tabs) _buildTabContent(tab, raw)],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 208,
                child: Material(
                  color: isDark
                      ? const Color(0xFF262626)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.94),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(
                          alpha: isDark ? 0.2 : 0.35,
                        ),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildBottomAction(
                          'PK',
                          '对比',
                          Icons.compare_arrows_rounded,
                          scheme.onSurfaceVariant,
                          () => AppToast.show(context, '已加入机型对比库'),
                        ),
                        _buildBottomAction(
                          'heart',
                          _following ? '已关注' : '关注',
                          _following
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          _following ? primaryGreen : scheme.onSurfaceVariant,
                          _toggleFollow,
                        ),
                        _buildBottomAction(
                          'star',
                          '打分',
                          Icons.star_border_rounded,
                          scheme.onSurfaceVariant,
                          () => AppToast.show(context, '请登录后打分'),
                        ),
                        _buildBottomAction(
                          'buy',
                          '购买',
                          Icons.shopping_bag_outlined,
                          scheme.onSurfaceVariant,
                          () => AppToast.show(context, '正在跳转官方购买渠道'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: primaryGreen,
                elevation: 3,
                shadowColor: primaryGreen.withValues(alpha: 0.4),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedbackUtil.light();
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ComposeFeedPage(api: widget.api),
                      ),
                    );
                  },
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
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
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
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
    Color primaryGreen,
    ColorScheme scheme,
    bool isDark,
  ) {
    final selected = _sortMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_sortMode == mode) return;
        HapticFeedbackUtil.selection();
        setState(() => _sortMode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF2E2E2E) : scheme.surface)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? primaryGreen : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomAction(
    String type,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(_ProductTab tab, Map<String, dynamic> raw) {
    if (tab.type == 'main') {
      return _ProductSpecsFullView(api: widget.api, id: widget.id, raw: raw);
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
      );
    }
    return ApiListPage(
      key: ValueKey(
        'prod-${tab.type}-${tab.subId ?? ""}-${widget.id}-$_sortMode',
      ),
      api: widget.api,
      title: tab.title,
      path: '/v6/page/dataList',
      query: {
        'url': '/page?url=/product/feedList',
        'id': widget.id,
        'type': tab.type,
        if (tab.subId != null && tab.subId!.isNotEmpty) 'subId': tab.subId!,
        if (tab.type == 'feed')
          'listType': _sortMode == 'latest'
              ? 'dateline_desc'
              : (_sortMode == 'hot' ? 'hot_desc' : 'lastupdate_desc'),
        if (tab.type == 'rating')
          'listType': _sortMode == 'latest' ? 'dateline_desc' : 'hot_desc',
        if (tab.type == 'trade') 'listType': 'dateline_desc',
      },
      showAppBar: false,
      nested: true,
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

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar, {required this.color});

  final TabBar _tabBar;
  final Color color;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: color, child: _tabBar);
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
  });

  final CoolapkApi api;
  final String id;
  final Map<String, dynamic> raw;

  @override
  State<_ProductSpecsFullView> createState() => _ProductSpecsFullViewState();
}

class _ProductSpecsFullViewState extends State<_ProductSpecsFullView> {
  List<Map<String, dynamic>> _params = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  Future<void> _loadParams() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.request(
        '/v6/product/paramList',
        query: {'id': widget.id},
      );
      final data = res['data'];
      if (data is List && mounted) {
        setState(() {
          _params = data
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading && _params.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayParams = _params.isNotEmpty
        ? _params
        : [
            {
              'title': '处理器',
              'value':
                  widget.raw['chip'] ??
                  widget.raw['processor'] ??
                  '天玑 9500 / 骁龙 8 至尊版',
            },
            {
              'title': '屏幕尺寸',
              'value': widget.raw['screen_size'] ?? '6.78 英寸 AMOLED',
            },
            {
              'title': '屏幕分辨率',
              'value': widget.raw['screen_resolution'] ?? '2800 × 1260 像素',
            },
            {
              'title': '刷新率',
              'value': widget.raw['screen_refresh_rate'] ?? '1-120Hz 8T LTPO',
            },
            {'title': '电池容量', 'value': widget.raw['battery'] ?? '6000mAh 蓝海电池'},
            {
              'title': '充电功率',
              'value': widget.raw['charging'] ?? '90W 超快闪充 + 30W 无线闪充',
            },
            {
              'title': '后置主摄',
              'value': widget.raw['camera_main'] ?? '5000万像素 索尼定制超大底 OIS',
            },
            {
              'title': '潜望长焦',
              'value': widget.raw['camera_tele'] ?? '2亿像素 蔡司 APO 超级长焦',
            },
            {
              'title': '前置镜头',
              'value': widget.raw['camera_front'] ?? '5000万像素 超感光前置',
            },
            {
              'title': '机身尺寸与重量',
              'value':
                  widget.raw['dimensions'] ?? '164.0 × 75.3 × 8.2mm, 约 223g',
            },
            {
              'title': '操作系统',
              'value': widget.raw['os'] ?? 'OriginOS 5 / Android 15',
            },
            {
              'title': '防水等级',
              'value': widget.raw['waterproof'] ?? 'IP68 & IP69 防尘抗水',
            },
          ];

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: displayParams.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 0.5,
        color: scheme.outlineVariant.withValues(alpha: 0.2),
      ),
      itemBuilder: (context, index) {
        final item = displayParams[index];
        final name = (item['title'] ?? item['name'] ?? item['key'] ?? '')
            .toString();
        final value = (item['value'] ?? item['val'] ?? '').toString();
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
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
      final isFollow = _flag(detailMap, ['isFollow', 'is_follow', 'followed']);

      final title = _first(detailMap, ['title', 'tag', 'name']);
      final displayTitle = title.isNotEmpty
          ? title
          : (widget.initialTitle != null && widget.initialTitle!.isNotEmpty
                ? widget.initialTitle!
                : _cleanTag);

      final productInfo = await DigitalSystemHelper.resolveSystemProduct(
        widget.api,
        displayTitle,
      );

      if (!mounted) return;
      setState(() {
        _detail = detailMap;
        _following = isFollow;
        if (productInfo.productId != null) {
          _productId = productInfo.productId;
        }
        _profile = _resolveWithDynamicData(
          resolveSystemProfile(_cleanTag, displayTitle),
          detailMap,
          productInfo,
        );
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
      hasRating: base.hasRating || score > 0,
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
    final resolvedLogo = logoUrl.isNotEmpty
        ? logoUrl
        : (DigitalSystemHelper.getSystemPresetLogo(displayTitle) ?? '');

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
                _buildFallbackLogo(displayTitle, accentColor),
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
    final title = _first(_detail, ['title', 'tag', 'name']);
    final displayTitle = title.isNotEmpty
        ? title
        : (widget.initialTitle != null && widget.initialTitle!.isNotEmpty
              ? widget.initialTitle!
              : _cleanTag);
    final cover = _first(_detail, [
      'cover',
      'banner',
      'background',
      'bg_pic',
      'background_url',
    ]);
    var logo = _first(_detail, ['logo', 'icon', 'pic', 'avatar']);
    if (logo.isEmpty &&
        widget.initialLogo != null &&
        widget.initialLogo!.isNotEmpty) {
      logo = widget.initialLogo!;
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
        floatingActionButton: FloatingActionButton(
          heroTag: 'topic_fab_${widget.tag}',
          backgroundColor: const Color(0xFF00B075),
          elevation: 4,
          shape: const CircleBorder(),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ComposeFeedPage(api: widget.api, initialTag: displayTitle),
              ),
            );
          },
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
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
                      if (cover.isNotEmpty)
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'topic_fab_${widget.tag}',
        backgroundColor: const Color(0xFF00B075),
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ComposeFeedPage(api: widget.api, initialTag: displayTitle),
            ),
          );
        },
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
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
                        key: PageStorageKey('$_cleanTag:digest:$_sortMode'),
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
                        key: PageStorageKey('$_cleanTag:discuss:$_sortMode'),
                        api: widget.api,
                        title: '讨论',
                        path: '/v6/topic/tagFeedList',
                        query: {'tag': _cleanTag, 'listType': _apiSortKey},
                        showAppBar: false,
                        nested: true,
                      ),
                      // 2: 机型区
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:devices:$_sortMode'),
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
                        key: PageStorageKey('$_cleanTag:rating:$_sortMode'),
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
                        key: PageStorageKey('$_cleanTag:discuss:$_sortMode'),
                        api: widget.api,
                        title: '讨论',
                        path: '/v6/topic/tagFeedList',
                        query: {'tag': _cleanTag, 'listType': _apiSortKey},
                        showAppBar: false,
                        nested: true,
                      ),
                      // 1: 点评
                      ApiListPage(
                        key: PageStorageKey('$_cleanTag:rating:$_sortMode'),
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
  Widget build(BuildContext context) => Center(
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

Widget _avatar(String value, double size, {required CoolapkApi api}) =>
    AppAvatar(api: api, url: value, size: size);

String _entityKey(Map<String, dynamic> value) =>
    '${value['entityType'] ?? value['entity_type']}:${value['id'] ?? value['uid'] ?? value['url']}:${value['title']}';

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
