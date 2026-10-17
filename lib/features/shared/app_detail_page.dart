import 'dart:async';
import 'dart:convert';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/spring_page_route.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/review_refresh_header.dart';
import '../feed/feed_pages.dart';
import '../feed/image_gallery_page.dart';

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({
    required this.api,
    required this.id,
    this.initialEntity,
    super.key,
  });

  final CoolapkApi api;
  final String id;
  final Map<String, dynamic>? initialEntity;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  final _scroll = ScrollController();
  final _galleryScope = Object();
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _related = [];
  List<Map<String, dynamic>> _items = [];
  ImageProvider? _iconProvider;
  Future<ColorScheme>? _palette;
  String _paletteUrl = '';
  String _tab = 'discussion';
  String _sort = 'lastupdate_desc';
  String _firstItem = '';
  String _lastItem = '';
  String? _error;
  String? _relatedError;
  String? _itemsError;
  int _page = 0;
  bool _loading = false;
  bool _relatedLoading = false;
  bool _itemsLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _data = widget.initialEntity;
    if (_data != null) _preparePalette(_data!);
    unawaited(_loadWithInitialTab());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _value(Map<String, dynamic>? data, Iterable<String> keys) {
    if (data == null) return '';
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  String get _appId => _packageName;

  String get _packageName =>
      _value(_data, [
        'apkname',
        'packageName',
        'package_name',
        'apk_name',
        'pn',
      ]).isNotEmpty
      ? _value(_data, [
          'apkname',
          'packageName',
          'package_name',
          'apk_name',
          'pn',
        ])
      : widget.id;

  String get _title => _value(_data, ['title', 'shorttitle', 'name']).isNotEmpty
      ? _value(_data, ['title', 'shorttitle', 'name'])
      : widget.id;

  void _preparePalette(Map<String, dynamic> data) {
    final logo = _value(data, ['apkRomIcon', 'logo', 'icon', 'pic']);
    final url = normalizeCoolapkImageUrl(logo);
    if (url.isEmpty || url == _paletteUrl) return;
    _paletteUrl = url;
    final provider = NetworkImage(
      url,
      headers: coolapkImageHeaders(logo, api: widget.api),
    );
    _iconProvider = provider;
    _palette = ColorScheme.fromImageProvider(
      provider: provider,
      brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
  }

  Future<void> _loadWithInitialTab() async {
    await _load();
    if (!mounted) return;
    if (_data != null && _tab != 'details' && _items.isEmpty) {
      await _loadItems(refresh: true);
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/v6/apk/detail',
        query: {'id': _packageName},
      );
      final root = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      final raw = root['data'];
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : raw is List && raw.isNotEmpty && raw.first is Map
          ? Map<String, dynamic>.from(raw.first as Map)
          : root;
      if (data.isEmpty) throw const CoolapkApiException('应用详情数据为空');
      if (!mounted) return;
      _preparePalette(data);
      setState(() => _data = data);
      unawaited(_loadRelated());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _load();
    if (!mounted) return;
    if (_data != null && _tab != 'details') {
      await _loadItems(refresh: true);
    }
  }

  Future<void> _loadRelated() async {
    if (_relatedLoading || _packageName.isEmpty) return;
    setState(() {
      _relatedLoading = true;
      _relatedError = null;
    });
    try {
      final page = await widget.api.getList(
        '/v6/apk/search',
        query: {
          'q': _packageName,
          'apkType': 0,
          'searchType': 'related',
          'page': 1,
        },
      );
      if (mounted) setState(() => _related = page.items.take(8).toList());
    } catch (error) {
      if (mounted) setState(() => _relatedError = error.toString());
    } finally {
      if (mounted) setState(() => _relatedLoading = false);
    }
  }

  Future<void> _loadItems({required bool refresh}) async {
    if (_itemsLoading || _tab == 'details' || (!refresh && !_hasMore)) return;
    final tab = _tab;
    final nextPage = refresh ? 1 : _page + 1;
    setState(() {
      _itemsLoading = true;
      _itemsError = null;
    });
    try {
      final page = await widget.api.getList(
        tab == 'discussion' ? '/v6/page/dataList' : '/v6/apk/commentList',
        query: {
          if (tab == 'discussion') 'url': '#/feed/apkCommentList',
          'id': _appId,
          if (tab == 'discussion') 'sort': _sort else 'listType': _sort,
          'page': nextPage,
          if (tab == 'discussion' && !refresh && _firstItem.isNotEmpty)
            'firstItem': _firstItem,
          if (tab == 'discussion' && !refresh && _lastItem.isNotEmpty)
            'lastItem': _lastItem,
        },
      );
      if (!mounted || tab != _tab) return;
      final nextItems = refresh
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.of(_items);
      final known = nextItems.map(_itemKey).toSet();
      nextItems.addAll(page.items.where((item) => known.add(_itemKey(item))));
      setState(() {
        _items = nextItems;
        _page = nextPage;
        _firstItem = page.firstItem;
        _lastItem = page.lastItem;
        _hasMore = page.hasMore && page.items.isNotEmpty;
      });
    } catch (error) {
      if (mounted && tab == _tab) {
        setState(() => _itemsError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _itemsLoading = false);
        if (_tab != tab && _tab != 'details' && _items.isEmpty) {
          unawaited(_loadItems(refresh: true));
        }
      }
    }
  }

  String _itemKey(Map<String, dynamic> item) {
    final id = _value(item, ['id', 'entityId', 'uid']);
    return id.isNotEmpty ? id : jsonEncode(item);
  }

  void _selectTab(String tab) {
    setState(() {
      _tab = tab;
      _items = [];
      _page = 0;
      _hasMore = true;
    });
    if (tab == 'details') {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    } else {
      unawaited(_loadItems(refresh: true));
    }
  }

  String _plainText(Iterable<String> keys) {
    final raw = _value(_data, keys);
    if (raw.isEmpty) return '';
    final withBreaks = raw.replaceAll(
      RegExp(r'<br\s*/?>|</(p|div|li)>', caseSensitive: false),
      '\n',
    );
    return html.parse(withBreaks).body?.text.trim() ?? raw;
  }

  List<String> _listValue(Iterable<String> keys) {
    Object? value;
    for (final key in keys) {
      final candidate = _data?[key];
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        value = candidate;
        break;
      }
    }
    List<String> convert(Iterable<dynamic> values) => values
        .map(
          (item) => item is Map
              ? _value(Map<String, dynamic>.from(item), [
                  'title',
                  'name',
                  'tag',
                  'url',
                  'pic',
                  'image',
                ])
              : item.toString(),
        )
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (value is List) return convert(value);
    if (value == null) return const [];
    final source = value.toString().trim();
    if (source.startsWith('[')) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is List) return convert(decoded);
      } on FormatException {
        // Keep unstructured service text and split it below.
      }
    }
    return source
        .split(RegExp(r'[,，、;；|\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatUpdateTime() {
    final raw = _value(_data, ['lastupdate', 'lastUpdate', 'update_time']);
    final timestamp = int.tryParse(raw);
    if (timestamp == null || timestamp <= 0) return raw;
    final seconds = timestamp > 100000000000 ? timestamp ~/ 1000 : timestamp;
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(seconds * 1000))
        .inDays;
    if (days <= 0) return '今天';
    if (days < 30) return '$days天前';
    if (days < 365) return '${days ~/ 30}个月前';
    return '${days ~/ 365}年前';
  }

  String _formatDownloadCount(String value) {
    final count = num.tryParse(value.replaceAll(',', ''));
    if (count == null || count < 10000 || RegExp(r'[万亿wW]').hasMatch(value)) {
      return value;
    }
    if (count >= 100000000 || (count / 10000).round() >= 10000) {
      final yi = (count / 100000000).toStringAsFixed(1);
      return '${yi.endsWith('.0') ? yi.substring(0, yi.length - 2) : yi}亿';
    }
    return '${(count / 10000).round()}万';
  }

  List<_AppMetric> _metrics() => [
    _AppMetric(
      '下载',
      _formatDownloadCount(
        _value(_data, ['downnum', 'downCount', 'down_count']),
      ),
    ),
    _AppMetric('热度', _value(_data, ['hot_num', 'hotNum', 'hot'])),
    _AppMetric(
      '评论',
      _value(_data, ['commentnum', 'commentCount', 'comment_count']),
    ),
    _AppMetric('关注', _value(_data, ['follow', 'follownum', 'follow_num'])),
  ].where((metric) => metric.value.isNotEmpty).toList();

  Widget _sectionTitle(String title, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 7),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w700),
    ),
  );

  Widget _buildDetailBody(Color accent, Color onAccent, Color cardColor) {
    final data = _data!;
    final theme = Theme.of(context);
    final version = _value(data, ['apkversionname', 'versionName', 'version']);
    final versionCode = _value(data, ['apkversioncode', 'versionCode']);
    final size = _value(data, ['apksize', 'apkSize', 'size']);
    final update = _formatUpdateTime();
    final summary = _plainText(['subtitle', 'shorttitle', 'brief', 'summary']);
    final changelog = _plainText(['changelog', 'changeLog', 'updateInfo']);
    final description = _plainText(['description', 'intro', 'appDescription']);
    final tags = _listValue(['tags', 'tag', 'category_title', 'category']);
    final screenshots = _listValue([
      'screenList',
      'screenshots',
      'screenArr',
      'screenshot',
      'picArr',
    ]);
    final record = _value(data, [
      'apkRecord',
      'apkrecord',
      'recordNumber',
      'icp',
      'beian',
    ]);
    final metrics = _metrics();

    return Container(
      color: accent,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: onAccent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: _iconProvider == null
                          ? Container(
                              color: cardColor,
                              child: Icon(
                                Icons.apps_rounded,
                                color: onAccent,
                                size: 42,
                              ),
                            )
                          : Image(
                              image: _iconProvider!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: cardColor,
                                child: Icon(
                                  Icons.apps_rounded,
                                  color: onAccent,
                                  size: 42,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: onAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          [
                            if (version.isNotEmpty) version,
                            if (versionCode.isNotEmpty) '版本号 $versionCode',
                            if (size.isNotEmpty) size,
                          ].join('  '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: onAccent.withValues(alpha: 0.78),
                          ),
                        ),
                        if (update.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '更新于 $update',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onAccent.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppDownloadButton(api: widget.api, data: data),
            ),
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      for (var index = 0; index < metrics.length; index++) ...[
                        if (index > 0)
                          Container(
                            width: 1,
                            height: 34,
                            color: onAccent.withValues(alpha: 0.15),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                metrics[index].value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                metrics[index].label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: onAccent.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            _buildRating(data, cardColor, onAccent),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“',
                        style: TextStyle(
                          color: onAccent.withValues(alpha: 0.55),
                          fontSize: 28,
                          height: 0.9,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onAccent.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (screenshots.isNotEmpty)
              _buildScreenshots(screenshots, onAccent, cardColor),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tags[index],
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (changelog.isNotEmpty)
              _AppDetailSection(
                title: '新版特性',
                text: changelog,
                onAccent: onAccent,
              ),
            if (description.isNotEmpty)
              _AppDetailSection(
                title: '应用介绍',
                text: description,
                onAccent: onAccent,
              ),
            if (record.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Text(
                  'APP备案号：$record',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onAccent.withValues(alpha: 0.64),
                  ),
                ),
              ),
            _buildRelated(onAccent, cardColor),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRating(
    Map<String, dynamic> data,
    Color cardColor,
    Color onAccent,
  ) {
    final rawScore = _value(data, ['score', 'rating', 'apkScore']);
    final parsedScore = double.tryParse(rawScore);
    final scoreValue = parsedScore == null
        ? null
        : parsedScore > 5
        ? parsedScore / 2
        : parsedScore;
    final score = scoreValue?.toStringAsFixed(1) ?? rawScore;
    final starCount = scoreValue?.round().clamp(0, 5) ?? 0;
    final count = _value(data, ['votenum', 'voteNum', 'score_count']);
    if (score.isEmpty && count.isEmpty) return const SizedBox.shrink();
    final values = [5, 4, 3, 2, 1]
        .map(
          (star) =>
              int.tryParse(
                _value(data, [
                  'votenum$star',
                  'score$star',
                  'score_$star',
                  'star$star',
                  'star_$star',
                  'rating$star',
                ]),
              ) ??
              0,
        )
        .toList();
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '酷安评分',
              style: theme.textTheme.titleSmall?.copyWith(
                color: onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Column(
                    children: [
                      Text(
                        score.isEmpty ? '—' : score,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 38,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var index = 0; index < 5; index++)
                            Icon(
                              index < starCount
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 18,
                              color: Colors.amber.shade400,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (count.isNotEmpty)
                        Text(
                          '$count人点评',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: onAccent.withValues(alpha: 0.72),
                          ),
                        ),
                    ],
                  ),
                ),
                if (total > 0)
                  Expanded(
                    child: Column(
                      children: [
                        for (var index = 0; index < values.length; index++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                Text(
                                  '${5 - index}星',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: onAccent.withValues(alpha: 0.78),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      minHeight: 9,
                                      value: values[index] / total,
                                      backgroundColor: onAccent.withValues(
                                        alpha: 0.12,
                                      ),
                                      color: Colors.amber.shade400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    '${values[index]}',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: onAccent.withValues(alpha: 0.78),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 0.6,
              color: onAccent.withValues(alpha: 0.12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshots(List<String> urls, Color onAccent, Color cardColor) {
    final pics = urls
        .map((url) => GalleryImage(normalizeCoolapkImageUrl(url)))
        .where((pic) => pic.url.isNotEmpty)
        .toList();
    if (pics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('应用截图', onAccent),
        SizedBox(
          height: 192,
          child: protectHorizontalDragFromVerticalRefresh(
            ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: pics.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final pic = pics[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push<void>(
                    PhysicsSpringGalleryRoute<void>(
                      child: ImageGalleryPage(
                        api: widget.api,
                        pics: pics,
                        initialIndex: index,
                        statusId: _appId,
                        isDetail: true,
                        heroScope: _galleryScope,
                      ),
                    ),
                  ),
                  child: ImageGalleryHeroThumbnail(
                    scope: _galleryScope,
                    index: index,
                    pic: pic,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        pic.previewUrl,
                        headers: coolapkImageHeaders(pic.url, api: widget.api),
                        width: 112,
                        height: 192,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 112,
                          color: cardColor,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRelated(Color onAccent, Color cardColor) {
    if (_related.isEmpty && !_relatedLoading && _relatedError == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '相关应用',
            style: theme.textTheme.titleMedium?.copyWith(
              color: onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_relatedLoading && _related.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_relatedError != null && _related.isEmpty)
            TextButton(
              onPressed: _loadRelated,
              child: Text('加载失败，点击重试：$_relatedError'),
            )
          else
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8),
              childAspectRatio: 0.68,
              children: [
                for (final app in _related)
                  _relatedApp(app, onAccent, cardColor),
              ],
            ),
        ],
      ),
    );
  }

  Widget _relatedApp(
    Map<String, dynamic> app,
    Color onAccent,
    Color cardColor,
  ) {
    final logo = _value(app, ['logo', 'apkRomIcon', 'icon', 'pic']);
    final title = _value(app, ['title', 'appName', 'shorttitle', 'name']);
    final score = _value(app, ['score', 'rating']);
    final id = _value(app, [
      'packageName',
      'package_name',
      'apkname',
      'apk_name',
      'id',
    ]);
    return InkWell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AppDetailPage(api: widget.api, id: id, initialEntity: app),
              ),
            ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: logo.isEmpty
                  ? Container(
                      width: 52,
                      height: 52,
                      color: cardColor,
                      child: Icon(Icons.apps_rounded, color: onAccent),
                    )
                  : CachedNetworkImage(
                      normalizeCoolapkImageUrl(logo),
                      headers: coolapkImageHeaders(logo, api: widget.api),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 52,
                        height: 52,
                        color: cardColor,
                        child: Icon(Icons.apps_rounded, color: onAccent),
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              title.isEmpty ? '应用' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: onAccent),
            ),
            if (score.isNotEmpty)
              Text(
                '$score ★',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.amber.shade300),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme scheme) {
    const tabs = {'details': '详情', 'discussion': '讨论', 'reviews': '点评'};
    return Material(
      color: scheme.surface,
      child: Row(
        children: [
          for (final entry in tabs.entries)
            Expanded(
              child: InkWell(
                onTap: () => _selectTab(entry.key),
                child: SizedBox(
                  height: 48,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: _tab == entry.key
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: _tab == entry.key
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 2,
                        decoration: BoxDecoration(
                          color: _tab == entry.key
                              ? scheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSort(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Row(
      children: [
        Text('排序规则', style: TextStyle(color: scheme.onSurfaceVariant)),
        if (_itemsLoading && _items.isNotEmpty) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        const Spacer(),
        for (final entry in const {
          'lastupdate_desc': '默认',
          'dateline_desc': '最新',
          'popular': '热度',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: _sort == entry.key,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: _itemsLoading
                  ? null
                  : (_) {
                      setState(() => _sort = entry.key);
                      _loadItems(refresh: true);
                    },
            ),
          ),
      ],
    ),
  );

  Widget _buildListItem(Map<String, dynamic> item, Color cardColor) {
    final type = _value(item, ['entityType', 'entity_type']).toLowerCase();
    if (type.contains('feed') || item.containsKey('message')) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          cardTheme: theme.cardTheme.copyWith(color: cardColor),
        ),
        child: FeedCard(
          key: ValueKey(_itemKey(item)),
          api: widget.api,
          feed: CoolapkFeed.fromJson(item),
        ),
      );
    }
    final user = _value(item, ['username', 'userName', 'displayUsername']);
    final avatar = _value(item, ['userAvatar', 'avatar', 'logo']);
    final message = _value(item, [
      'message',
      'content',
      'title',
      'description',
    ]);
    final rating = _value(item, ['score', 'rating', 'rate']);
    if (message.isEmpty && user.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (avatar.isNotEmpty)
                    ClipOval(
                      child: CachedNetworkImage(
                        normalizeCoolapkImageUrl(avatar),
                        headers: coolapkImageHeaders(avatar, api: widget.api),
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(user.isEmpty ? '酷安用户' : user)),
                  if (rating.isNotEmpty)
                    Text(
                      '$rating ★',
                      style: TextStyle(color: Colors.amber.shade700),
                    ),
                ],
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ColorScheme>(
    future: _palette,
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final palette = snapshot.data;
      final accent = palette?.primary ?? theme.colorScheme.primary;
      final onAccent = palette?.onPrimary ?? theme.colorScheme.onPrimary;
      final cardColor = Color.lerp(accent, Colors.black, 0.16)!;
      final discussionBackground = isDark
          ? const Color(0xFF09090B)
          : theme.colorScheme.surface;
      final discussionCardColor = isDark
          ? const Color(0xFF1B1C20)
          : theme.colorScheme.surfaceContainerLow;
      return Scaffold(
        backgroundColor: discussionBackground,
        appBar: AppBar(
          title: Text(_data == null ? '应用详情' : _title),
          backgroundColor: accent,
          foregroundColor: onAccent,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: accent,
          ),
        ),
        body: EasyRefresh(
          header: reviewDefaultRefreshHeader,
          triggerAxis: Axis.vertical,
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal) return true;
              if (notification.depth == 0 &&
                  notification is ScrollUpdateNotification &&
                  notification.metrics.extentAfter < 500 &&
                  _tab != 'details') {
                _loadItems(refresh: false);
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (_data != null)
                  SliverToBoxAdapter(
                    child: _buildDetailBody(accent, onAccent, cardColor),
                  )
                else
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!),
                                TextButton(
                                  onPressed: _loadWithInitialTab,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                    ),
                  ),
                if (_data != null) ...[
                  SliverToBoxAdapter(child: _buildTabBar(theme.colorScheme)),
                  if (_tab != 'details') ...[
                    SliverToBoxAdapter(child: _buildSort(theme.colorScheme)),
                    if (_items.isEmpty && _itemsLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_items.isEmpty && _itemsError != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_itemsError!),
                              TextButton(
                                onPressed: () => _loadItems(refresh: true),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('暂无内容')),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index == _items.length) {
                              if (_itemsLoading) {
                                return const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (_itemsError != null) {
                                return TextButton(
                                  onPressed: () => _loadItems(refresh: false),
                                  child: Text('加载失败，点击重试：$_itemsError'),
                                );
                              }
                              return _hasMore
                                  ? const SizedBox(height: 1)
                                  : const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: Text('已经到底了')),
                                    );
                            }
                            return _buildListItem(
                              _items[index],
                              discussionCardColor,
                            );
                          },
                          childCount:
                              _items.length +
                              ((_itemsLoading ||
                                      _itemsError != null ||
                                      !_hasMore)
                                  ? 1
                                  : 0),
                        ),
                      ),
                  ],
                ],
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 24 + MediaQuery.paddingOf(context).bottom,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AppMetric {
  const _AppMetric(this.label, this.value);
  final String label;
  final String value;
}

class _AppDetailSection extends StatefulWidget {
  const _AppDetailSection({
    required this.title,
    required this.text,
    required this.onAccent,
  });
  final String title;
  final String text;
  final Color onAccent;

  @override
  State<_AppDetailSection> createState() => _AppDetailSectionState();
}

class _AppDetailSectionState extends State<_AppDetailSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: widget.onAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(_expanded ? '收起' : '展开'),
              style: TextButton.styleFrom(
                foregroundColor: widget.onAccent.withValues(alpha: 0.75),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.text,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.55,
            color: widget.onAccent.withValues(alpha: 0.88),
          ),
        ),
      ],
    ),
  );
}

class AppDownloadButton extends StatelessWidget {
  const AppDownloadButton({
    required this.api,
    required this.data,
    this.compact = false,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> data;
  final bool compact;

  String _field(Iterable<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(
      _field([
        'downloadUrl',
        'download_url',
        'apkDownloadUrl',
        'apk_download_url',
        'url',
      ]),
    );
    Future<void> download() async {
      try {
        var resolved = uri;
        if (resolved == null ||
            resolved.scheme != 'https' ||
            resolved.host.isEmpty ||
            resolved.userInfo.isNotEmpty) {
          final packageName = _field([
            'apkname',
            'packageName',
            'package_name',
            'apk_name',
            'pn',
          ]);
          final appId = _field(['id', 'apkId', 'aid']);
          final versionCode = _field(['apkversioncode', 'versionCode', 'vc']);
          if (packageName.isEmpty || appId.isEmpty || versionCode.isEmpty) {
            throw const CoolapkApiException('应用缺少下载所需的版本信息');
          }
          resolved = await api.resolveApkDownloadUrl(
            packageName: packageName,
            appId: appId,
            versionCode: versionCode,
          );
        }
        if (resolved.scheme != 'https' ||
            resolved.host.isEmpty ||
            resolved.userInfo.isNotEmpty) {
          throw const CoolapkApiException('酷安没有返回有效的下载地址');
        }
        if (!await launchUrl(resolved, mode: LaunchMode.externalApplication)) {
          throw const CoolapkApiException('无法打开下载地址');
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }

    if (compact) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF009688),
          foregroundColor: Colors.white,
          minimumSize: const Size(56, 30),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: download,
        child: const Text('下载'),
      );
    }
    return FilledButton.icon(
      onPressed: download,
      icon: const Icon(Icons.download_rounded),
      label: const Text('打开下载地址'),
    );
  }
}
