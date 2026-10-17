import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
import 'home_destination_page.dart';

String _field(Map row, String key) => '${row[key] ?? ''}'.trim();
List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : [];

bool isActivityTopic(Map<String, dynamic> detail) =>
    _rows(detail['tabList']).any((tab) => _field(tab, 'title') == '活动详情');

int? _eventTime(Map<String, dynamic> event, List<String> keys) {
  for (final key in keys) {
    final value = int.tryParse(_field(event, key));
    if (value != null && value > 0) return value;
  }
  return null;
}

({String label, bool canRegister, String actionUrl, String winnersUrl})
crowdTestAction(Map<String, dynamic> event, {int? nowSeconds}) {
  final now = nowSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final start = _eventTime(event, [
    'time_reg_start',
    'registrationStart',
    'registration_start',
  ]);
  final end = _eventTime(event, [
    'time_reg_end',
    'registrationEnd',
    'registration_end',
  ]);
  final eventEnd = _eventTime(event, ['time_end', 'eventEnd', 'event_end']);
  final stage = int.tryParse(
    _field(event, 'stage_status').isEmpty
        ? _field(event, 'stageStatus')
        : _field(event, 'stage_status'),
  );
  final action = _field(event, 'action_url').isEmpty
      ? _field(event, 'actionUrl')
      : _field(event, 'action_url');
  final uri = Uri.tryParse(action);
  final validAction =
      uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  final winners = _field(event, 'prizeUserUrl');
  final joined = _field(event, 'is_join_status') == '1';
  final canRegister =
      !joined &&
      (stage == null || stage == 1) &&
      start != null &&
      end != null &&
      now >= start &&
      now <= end &&
      validAction;
  final label = winners.isNotEmpty
      ? '查看众测名单'
      : stage == 2
      ? '暂未公布众测名单'
      : stage == 3 || (eventEnd != null && now > eventEnd)
      ? '活动已结束'
      : start != null && now < start
      ? '报名未开始'
      : end != null && now > end
      ? '暂未公布众测名单'
      : joined
      ? '已报名'
      : canRegister
      ? '立即报名'
      : '暂不可报名';
  return (
    label: label,
    canRegister: canRegister,
    actionUrl: action,
    winnersUrl: winners,
  );
}

/// Only official HTTPS activity documents are embedded. Other links use routing.
bool isOfficialActivityDocument(Uri uri) =>
    uri.scheme == 'https' &&
    const [
      'm.coolapk.com',
      'www.coolapk.com',
      'coolapk.com',
    ].contains(uri.host) &&
    (uri.path.startsWith('/activity/') ||
        uri.path.startsWith('/mp/feedLotto/'));

Uri? activityGoodsUrl(Map<String, dynamic> goods) {
  for (final key in ['goods_url', 'goods_buy_url']) {
    final uri = Uri.tryParse(_field(goods, key));
    if (uri != null && isOfficialActivityDocument(uri)) return uri;
  }
  return null;
}

void openActivityDocument(
  BuildContext context,
  CoolapkApi api,
  Uri uri, {
  String title = '活动详情',
}) {
  if (!isOfficialActivityDocument(uri)) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ActivityWebPage(api: api, uri: uri, title: title),
    ),
  );
}

class ActivityWebPage extends StatefulWidget {
  const ActivityWebPage({
    required this.api,
    required this.uri,
    required this.title,
    super.key,
  });
  final CoolapkApi api;
  final Uri uri;
  final String title;
  @override
  State<ActivityWebPage> createState() => _ActivityWebPageState();
}

class _ActivityWebPageState extends State<ActivityWebPage> {
  late String _title = widget.title;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101010),
    appBar: AppBar(
      backgroundColor: const Color(0xFF1E1E1E),
      foregroundColor: const Color(0xFFCCCCCC),
      titleSpacing: 4,
      title: Text(
        _title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20),
      ),
      actions: [
        PopupMenuButton<String>(
          onSelected: (_) =>
              launchUrl(widget.uri, mode: LaunchMode.externalApplication),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'browser', child: Text('在浏览器打开')),
          ],
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ActivityDocument(
        api: widget.api,
        uri: widget.uri,
        onTitle: (title) {
          if (mounted && title.isNotEmpty) setState(() => _title = title);
        },
      ),
    ),
  );
}

class ActivityDocument extends StatefulWidget {
  const ActivityDocument({
    required this.api,
    required this.uri,
    this.onTitle,
    super.key,
  });
  final CoolapkApi api;
  final Uri uri;
  final ValueChanged<String>? onTitle;
  @override
  State<ActivityDocument> createState() => _ActivityDocumentState();
}

class _ActivityDocumentState extends State<ActivityDocument> {
  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb ||
        !const [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    if (!isOfficialActivityDocument(widget.uri)) {
      _error = '活动地址无效';
      return;
    }
    _initialize();
  }

  Future<void> _initialize() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(
        dark ? const Color(0xFF0D1726) : Colors.white,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            try {
              // Official documents use prefers-color-scheme; honor the app's theme.
              await controller.runJavaScript('''
                for (const sheet of document.styleSheets) {
                  try {
                    for (const rule of sheet.cssRules) {
                      if (rule.media && rule.media.mediaText.includes('prefers-color-scheme')) {
                        const wanted = rule.media.mediaText.includes('${dark ? 'dark' : 'light'}');
                        rule.media.mediaText = wanted ? 'all' : 'not all';
                      }
                    }
                  } catch (_) {}
                }
              ''');
              final title = await controller.getTitle();
              if (mounted && title != null) widget.onTitle?.call(title);
            } catch (_) {
              // Navigation may have disposed the platform view.
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '活动页面加载失败：${error.description}');
            }
          },
          onHttpError: (error) {
            if (mounted && error.request?.uri == widget.uri) {
              setState(
                () => _error =
                    '活动页面暂不可用（HTTP ${error.response?.statusCode ?? ''}）',
              );
            }
          },
          onNavigationRequest: (request) {
            if (!mounted) return NavigationDecision.prevent;
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (isOfficialActivityDocument(uri)) {
              return NavigationDecision.navigate;
            }
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final official =
                uri.host == 'coolapk.com' || uri.host.endsWith('.coolapk.com');
            final path = uri.path;
            if (official &&
                path == '/feed/writer' &&
                uri.queryParameters['type'] != 'rating') {
              if (!widget.api.hasCookie) {
                AppToast.show(context, widget.api.loginRequiredMessage);
              } else {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ComposeFeedPage(
                      api: widget.api,
                      initialTag: uri.queryParameters['tag'],
                    ),
                  ),
                );
              }
              return NavigationDecision.prevent;
            }
            if (official && path == '/feed/writer') {
              // shortcut: rating submission uses the official writer until a native rating form exists.
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            if (official &&
                (path.startsWith('/t/') ||
                    path.startsWith('/feed/') ||
                    path.startsWith('/u/') ||
                    path.startsWith('/product/') ||
                    path == '/page')) {
              openHeadlineTarget(context, widget.api, {'url': uri.toString()});
            } else if (uri.scheme == 'http' || uri.scheme == 'https') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            } else if (uri.scheme == 'coolmarket') {
              final route =
                  '/${uri.host}${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
              if (const [
                '/t/',
                '/feed/',
                '/u/',
                '/product/',
                '/page',
                '/feed/create',
              ].any(route.startsWith)) {
                openHeadlineTarget(context, widget.api, {'url': route});
              }
            }
            return NavigationDecision.prevent;
          },
        ),
      );
      // No app auth headers or Cookie are forwarded to web documents.
      await controller.loadRequest(widget.uri);
      if (mounted) setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = '无法加载活动页面：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) Text(_error!),
              if (_error == null &&
                  _initialized &&
                  const [
                    TargetPlatform.android,
                    TargetPlatform.iOS,
                    TargetPlatform.macOS,
                  ].contains(defaultTargetPlatform))
                const CircularProgressIndicator(),
              TextButton(
                onPressed: () =>
                    launchUrl(widget.uri, mode: LaunchMode.externalApplication),
                child: const Text('在浏览器打开活动详情'),
              ),
              if (_error != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _progress = 0;
                    });
                    if (_controller != null) {
                      _controller!.loadRequest(widget.uri);
                    } else {
                      _initialize();
                    }
                  },
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(
          controller: _controller!,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => VerticalDragGestureRecognizer(),
            ),
          },
        ),
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
      ],
    );
  }
}

class ActivityTopicPage extends StatefulWidget {
  const ActivityTopicPage({required this.api, required this.tag, super.key});
  final CoolapkApi api;
  final String tag;
  @override
  State<ActivityTopicPage> createState() => _ActivityTopicPageState();
}

class _ActivityTopicPageState extends State<ActivityTopicPage> {
  late Future<Map<String, dynamic>> _future = _load();
  Future<Map<String, dynamic>> _load() async {
    final result = await widget.api.getTopicDetail(widget.tag);
    final data = result['data'];
    if (data is! Map) throw const CoolapkApiException('活动话题数据为空');
    return Map<String, dynamic>.from(data);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ActivityTopicView(
          api: widget.api,
          tag: widget.tag,
          detail: snapshot.data!,
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.tag)),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snapshot.error}'),
                    TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('重试'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class ActivityTopicView extends StatefulWidget {
  const ActivityTopicView({
    required this.api,
    required this.tag,
    required this.detail,
    this.headerColor,
    super.key,
  });
  final CoolapkApi api;
  final String tag;
  final Map<String, dynamic> detail;
  final Color? headerColor;
  @override
  State<ActivityTopicView> createState() => _ActivityTopicViewState();
}

class _ActivityTopicViewState extends State<ActivityTopicView>
    with SingleTickerProviderStateMixin {
  late final List<Map<String, dynamic>> _tabs = _rows(widget.detail['tabList']);
  late final TabController _tabsController;
  late bool _following = (widget.detail['userAction'] as Map?)?['follow'] == 1;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final selected = _tabs.indexWhere(
      (tab) => tab['page_name'] == widget.detail['selectedTab'],
    );
    _tabsController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: selected < 0 ? 0 : selected,
    );
  }

  @override
  void dispose() {
    _tabsController.dispose();
    super.dispose();
  }

  Future<void> _follow() async {
    if (_busy) return;
    if (!widget.api.hasAccount) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.followTopic(widget.tag, following: _following);
      if (mounted) setState(() => _following = !_following);
    } catch (error) {
      if (mounted) AppToast.show(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? widget.headerColor ?? const Color(0xFF414058)
        : widget.headerColor == null
        ? const Color(0xFFE5E3EF)
        : Color.lerp(widget.headerColor, Colors.white, .85)!;
    final foreground = dark ? const Color(0xFFDDDDDD) : const Color(0xFF252431);
    final detail = widget.detail;
    final title = _field(detail, 'title');
    final logo = normalizeCoolapkImageUrl(_field(detail, 'logo'));
    final followers = _rows(detail['recent_follow_list']);
    final recommendations = [
      for (final row in _rows(detail['recommendRows']))
        ..._rows(row['entities']),
    ];
    final bar = TabBar(
      controller: _tabsController,
      labelColor: const Color(0xFF009688),
      unselectedLabelColor: const Color(0xFFBBBBBB),
      labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      indicatorColor: const Color(0xFF009688),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: const _ShortTopicIndicator(),
      dividerHeight: 0,
      tabs: [for (final tab in _tabs) Tab(text: _field(tab, 'title'))],
    );
    return Theme(
      data: officialHomeTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          foregroundColor: foreground,
          actions: [
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      SearchPage(api: widget.api, initialQuery: title),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: greenComposeFab(
          context: context,
          heroTag: 'activity_topic_fab_${widget.tag}',
          useLiquidGlass: true,
          onPressed: () {
            if (!widget.api.hasAccount) {
              AppToast.show(context, widget.api.loginRequiredMessage);
              return;
            }
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    ComposeFeedPage(api: widget.api, initialTag: widget.tag),
              ),
            );
          },
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, inner) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (logo.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              logo,
                              headers: coolapkImageHeaders(
                                logo,
                                api: widget.api,
                              ),
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isEmpty ? widget.tag : title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 20,
                                  color: foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${detail['hot_num_txt'] ?? detail['hot_num'] ?? 0}热度  '
                                '${detail['commentnum_txt'] ?? detail['commentnum'] ?? 0}讨论',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: foreground.withValues(alpha: .65),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (final user in followers.take(3))
                                    AppAvatar(
                                      api: widget.api,
                                      url: _field(user, 'userAvatar'),
                                      size: 18,
                                      name: '',
                                    ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${detail['follownum_txt'] ?? detail['follow_num'] ?? detail['follownum'] ?? 0}关注',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: foreground.withValues(alpha: .65),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _following
                                ? Colors.transparent
                                : const Color(0xFF009688),
                            foregroundColor: _following
                                ? foreground.withValues(alpha: .65)
                                : Colors.white,
                            side: _following
                                ? BorderSide(
                                    color: foreground.withValues(alpha: .25),
                                  )
                                : null,
                            minimumSize: const Size(58, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          onPressed: _busy ? null : _follow,
                          child: Text(_following ? '已关注' : '关注'),
                        ),
                      ],
                    ),
                    if (_field(detail, 'intro').isNotEmpty ||
                        _field(detail, 'description').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: CoolapkRichText(
                          api: widget.api,
                          text: _field(detail, 'intro').isEmpty
                              ? _field(detail, 'description')
                              : _field(detail, 'intro'),
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.65,
                            color: foreground,
                          ),
                        ),
                      ),
                    for (final item in recommendations)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .17),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${item['entityTypeName'] ?? ''}  ',
                                    style: const TextStyle(
                                      color: Color(0xFF00DDCA),
                                    ),
                                  ),
                                  TextSpan(
                                    text: _field(item, 'title'),
                                    style: TextStyle(color: foreground),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: foreground,
                            ),
                            onTap: () =>
                                openHeadlineTarget(context, widget.api, item),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_tabs.isNotEmpty)
              SliverPersistentHeader(
                pinned: true,
                delegate: _ActivityTabs(
                  bar,
                  dark ? const Color(0xFF1E1E1E) : Colors.white,
                ),
              ),
          ],
          body: ColoredBox(
            color: dark ? const Color(0xFF101010) : Colors.white,
            child: _tabs.isEmpty
                ? const Center(child: Text('暂无活动内容'))
                : TabBarView(
                    controller: _tabsController,
                    children: [
                      for (final tab in _tabs)
                        _ActivityTab(api: widget.api, tab: tab),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActivityTabs extends SliverPersistentHeaderDelegate {
  _ActivityTabs(this.bar, this.color);
  final TabBar bar;
  final Color color;
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
    child: protectHorizontalDragFromVerticalRefresh(bar),
  );
  @override
  bool shouldRebuild(_ActivityTabs old) => old.bar != bar || old.color != color;
}

class _ShortTopicIndicator extends Decoration {
  const _ShortTopicIndicator();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ShortTopicPainter();
}

class _ShortTopicPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx + size.width / 2 - 5,
          offset.dy + size.height - 5,
          10,
          3,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF009688),
    );
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.api, required this.tab});
  final CoolapkApi api;
  final Map<String, dynamic> tab;
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  late String _route = _field(widget.tab, 'url');
  String _selectedSort = '默认';
  Map<String, dynamic>? _sortCard;

  void _rememberSortCard(List<Map<String, dynamic>> items) {
    if (_sortCard != null) return;
    for (final item in items) {
      if (item['entityTemplate'] == 'sortSelectCard' &&
          _rows(item['entities']).isNotEmpty) {
        setState(() => _sortCard = item);
        return;
      }
    }
  }

  bool _visibleActivityItem(Map<String, dynamic> item) =>
      visibleHomeEntity(item) &&
      (_sortCard == null || item['entityTemplate'] != 'sortSelectCard');

  Widget _buildSortCard(BuildContext context, Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('全部讨论', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final sort in _rows(item['entities']))
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              final url = _field(sort, 'url');
                              final title = _field(sort, 'title');
                              if (url.isNotEmpty && _selectedSort != title) {
                                setState(() {
                                  _sortCard = item;
                                  _route = url;
                                  _selectedSort = title;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: _selectedSort == _field(sort, 'title')
                                    ? Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: .1)
                                    : Colors.transparent,
                              ),
                              child: Text(
                                _field(sort, 'title'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
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

  @override
  Widget build(BuildContext context) {
    final route = _route;
    if (route.isEmpty) return const Center(child: Text('暂无活动内容'));
    final uri = Uri.tryParse(route);
    if (uri != null && isOfficialActivityDocument(uri)) {
      return ActivityDocument(key: ValueKey(route), api: widget.api, uri: uri);
    }
    final request = homePageRequest(route);
    return ApiListPage(
      key: ValueKey(route),
      api: widget.api,
      title: _field(widget.tab, 'title'),
      nested: true,
      showAppBar: false,
      path: request.path,
      query: request.query,
      header: _sortCard == null ? null : _buildSortCard(context, _sortCard!),
      itemFilter: _visibleActivityItem,
      onPageItemsLoaded: _rememberSortCard,
      itemBuilder: (_, item) {
        if (item['entityType'] == 'feed') {
          return FeedCard(
            api: widget.api,
            feed: CoolapkFeed.fromJson(item),
            officialLayout: true,
          );
        }
        if (item['entityTemplate'] == 'sortSelectCard') {
          return _buildSortCard(context, item);
        }
        return ApiEntityCard(api: widget.api, entity: item);
      },
    );
  }
}

class CrowdTestPage extends StatefulWidget {
  const CrowdTestPage({required this.api, required this.id, super.key});
  final CoolapkApi api;
  final String id;
  @override
  State<CrowdTestPage> createState() => _CrowdTestPageState();
}

class _CrowdTestPageState extends State<CrowdTestPage> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _expanded = false;
  Future<Map<String, dynamic>> _load() async {
    final result = await widget.api.request(
      '/v6/event/detail',
      query: {'id': widget.id},
    );
    final data = result is Map ? result['data'] : null;
    if (data is! Map) throw const CoolapkApiException('活动详情数据为空');
    return Map<String, dynamic>.from(data);
  }

  int? _time(Map<String, dynamic> event, List<String> keys) {
    return _eventTime(event, keys);
  }

  String _date(int? seconds) {
    if (seconds == null) return '待公布';
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _register(String action, int deadline) async {
    if (DateTime.now().millisecondsSinceEpoch ~/ 1000 > deadline) {
      setState(() {});
      AppToast.show(context, '报名已结束');
      return;
    }
    if (!widget.api.hasCookie) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    final uri = Uri.tryParse(action);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      AppToast.show(context, '活动报名地址无效');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.inAppWebView) && mounted) {
      AppToast.show(context, '无法打开报名页面');
    }
  }

  Widget _card(BuildContext context, Widget child) => Container(
    margin: const EdgeInsets.fromLTRB(9, 0, 9, 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('酷安众测')),
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }
      final event = snapshot.data!;
      final start = _time(event, [
        'time_reg_start',
        'registrationStart',
        'registration_start',
      ]);
      final end = _time(event, [
        'time_reg_end',
        'registrationEnd',
        'registration_end',
      ]);
      final action = crowdTestAction(event);
      final picture = normalizeCoolapkImageUrl(_field(event, 'logo'));
      final notice = _field(event, 'notice_rule').isEmpty
          ? _field(event, 'noticeRule')
          : _field(event, 'notice_rule');
      final sponsors = event['sponsorUser'] is Map
          ? [Map<String, dynamic>.from(event['sponsorUser'] as Map)]
          : _rows(event['sponsorUser']);
      final prizes = event['sponsorPrize'] is Map
          ? [Map<String, dynamic>.from(event['sponsorPrize'] as Map)]
          : _rows(event['sponsorPrize']);
      final rawTabs = event['tabList'];
      final tabs = rawTabs is Map
          ? [Map<String, dynamic>.from(rawTabs)]
          : _rows(rawTabs);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final background = dark
          ? const Color(0xFF101010)
          : Theme.of(context).colorScheme.surfaceContainerLow;
      final theme = officialHomeTheme(Theme.of(context));
      return Theme(
        data: theme,
        child: DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            backgroundColor: background,
            body: NestedScrollView(
              headerSliverBuilder: (context, inner) => [
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      if (picture.isNotEmpty)
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            picture,
                            headers: coolapkImageHeaders(
                              picture,
                              api: widget.api,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: background),
                          ),
                        ),
                      if (picture.isNotEmpty)
                        Positioned(
                          top: 110,
                          left: 0,
                          right: 0,
                          height: 94,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    background.withValues(alpha: 0),
                                    background,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 6,
                        left: 8,
                        child: const BackButton(color: Colors.white),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          top: picture.isEmpty
                              ? MediaQuery.paddingOf(context).top + 56
                              : 152,
                        ),
                        child: _card(
                          context,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _field(event, 'title'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.alarm, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '报名时间：${_date(start)}至${_date(end)}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: FilledButton(
                                  onPressed: action.winnersUrl.isNotEmpty
                                      ? () => openHeadlineTarget(
                                          context,
                                          widget.api,
                                          {
                                            'title': '众测名单',
                                            'url': action.winnersUrl,
                                          },
                                        )
                                      : action.canRegister
                                      ? () => _register(action.actionUrl, end!)
                                      : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF009688),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: Text(
                                    action.label,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              if (notice.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (context) => SafeArea(
                                      child: FractionallySizedBox(
                                        heightFactor: .75,
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '众测须知',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(notice),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.help_outline,
                                    size: 12,
                                  ),
                                  label: const Text(
                                    '众测须知',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.onSurfaceVariant,
                                    padding: EdgeInsets.zero,
                                    alignment: Alignment.centerLeft,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (notice.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _card(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '报名须知',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            notice,
                            maxLines: _expanded ? null : 5,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.fade,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                              foregroundColor: const Color(0xFF009688),
                            ),
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            child: Text(_expanded ? '收起' : '展开'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (sponsors.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _card(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '主办方',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final sponsor in sponsors)
                            _EventSponsor(api: widget.api, user: sponsor),
                        ],
                      ),
                    ),
                  ),
                if (prizes.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _card(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '活动奖品',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final prize in prizes)
                            Row(
                              children: [
                                if (_field(prize, 'logo').isNotEmpty)
                                  CachedNetworkImage(
                                    normalizeCoolapkImageUrl(
                                      _field(prize, 'logo'),
                                    ),
                                    headers: coolapkImageHeaders(
                                      _field(prize, 'logo'),
                                      api: widget.api,
                                    ),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.contain,
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _field(prize, 'title'),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (tabs.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ActivityTabs(
                      TabBar(
                        labelColor: const Color(0xFF009688),
                        indicatorColor: const Color(0xFF009688),
                        labelStyle: const TextStyle(fontSize: 18),
                        dividerHeight: 0,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: [
                          for (final tab in tabs)
                            Tab(text: _field(tab, 'title')),
                        ],
                      ),
                      dark
                          ? const Color(0xFF1E1E1E)
                          : theme.colorScheme.surface,
                    ),
                  ),
              ],
              body: tabs.isEmpty
                  ? const Center(child: Text('暂无相关讨论'))
                  : TabBarView(
                      children: [
                        for (final tab in tabs)
                          _ActivityTab(api: widget.api, tab: tab),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}

class _EventSponsor extends StatefulWidget {
  const _EventSponsor({required this.api, required this.user});
  final CoolapkApi api;
  final Map<String, dynamic> user;
  @override
  State<_EventSponsor> createState() => _EventSponsorState();
}

class _EventSponsorState extends State<_EventSponsor> {
  late bool _following = _field(widget.user, 'isFollow') == '1';
  bool _busy = false;
  Future<void> _follow() async {
    if (_busy) return;
    if (!widget.api.hasAccount) {
      AppToast.show(context, widget.api.loginRequiredMessage);
      return;
    }
    setState(() => _busy = true);
    try {
      final uid = _field(widget.user, 'uid');
      if (widget.api.isAnonymous) await widget.api.getUserSpace(uid);
      await widget.api.followUser(uid, following: _following);
      if (mounted) setState(() => _following = !_following);
    } catch (error) {
      if (mounted) AppToast.show(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      InkWell(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                UserSpacePage(api: widget.api, uid: _field(widget.user, 'uid')),
          ),
        ),
        child: AppAvatar(
          api: widget.api,
          url: _field(widget.user, 'userAvatar'),
          size: 40,
          name: _field(widget.user, 'username'),
          verified: _field(widget.user, 'verify_status') == '1',
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          _field(widget.user, 'username'),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      OutlinedButton(
        onPressed: _busy ? null : _follow,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF009688),
          side: const BorderSide(color: Color(0xFF009688)),
          minimumSize: const Size(56, 28),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          _following ? '已关注' : '关注',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}
