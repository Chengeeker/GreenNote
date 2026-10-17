import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/network/product_selector.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/review_refresh_header.dart';
import 'api_list_page.dart';
import 'product_comparison_page.dart';

class ProductSelectorPage extends StatefulWidget {
  const ProductSelectorPage({
    required this.api,
    this.source,
    this.onProductSelected,
    super.key,
  });
  final CoolapkApi api;
  final ProductSelectorSource? source;
  final void Function(Map<String, dynamic> item)? onProductSelected;
  @override
  State<ProductSelectorPage> createState() => _ProductSelectorPageState();
}

class _ProductSelectorPageState extends State<ProductSelectorPage> {
  late final _source = widget.source ?? ProductSelectorSource();
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  final _selected = <String, Map<String, dynamic>>{};
  Map<String, List<String>> _filters = {};
  String _sort = 'default';
  String? _error;
  int _page = 0;
  int _generation = 0;
  bool _busy = false;
  bool _more = true;
  bool _pending = false;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrollMore);
    _load(true);
  }

  void _scrollMore() {
    if (_scroll.position.extentAfter < 500) _load(false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _source.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(bool refresh) async {
    if (_busy) {
      if (refresh) {
        _generation++;
        _pending = true;
      }
      return;
    }
    if (!refresh && !_more) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    final next = refresh ? 1 : _page + 1;
    try {
      final data = await _source.load(
        next,
        keyword: _query.text.trim(),
        sort: _sort,
        filters: _filters,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (refresh) _items.clear();
        final known = _items.map((e) => e['id']).toSet();
        _items.addAll(data.items.where((e) => known.add(e['id'])));
        _page = next;
        _more = data.items.isNotEmpty;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_pending) {
          _pending = false;
          unawaited(_load(true));
        }
      }
    }
  }

  void _changeSort(String value) {
    setState(() => _sort = value);
    _load(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : scheme.surface;
    final config = _source.configuration;
    final sorts =
        config?.sorts ??
        const {
          'default': '综合',
          'hot_num': '热度',
          'owner_star_average_score': '评分',
          'follow_num': '关注数',
        };
    return Scaffold(
      backgroundColor: bg,
      appBar: ReviewFrostedAppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        backgroundColor: bg,
        showBottomBorder: false,
        title: Container(
          height: 34,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                padding: EdgeInsets.zero,
              ),
              Expanded(
                child: TextField(
                  controller: _query,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '搜索机型',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(true),
                    );
                  },
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _load(true);
                  },
                ),
              ),
              IconButton(
                tooltip: '搜索',
                onPressed: () => _load(true),
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF009688),
        onPressed: _compare,
        child: Text(
          _selected.isEmpty ? 'PK' : 'PK ${_selected.length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: protectHorizontalDragFromVerticalRefresh(
              ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final entry in sorts.entries)
                    TextButton(
                      onPressed: () => _changeSort(entry.key),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 14,
                          color: _sort == entry.key
                              ? const Color(0xFF009688)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '子项评分排序',
                    onSelected: _changeSort,
                    itemBuilder: (_) => [
                      for (final row
                          in config?.subScores.entries ??
                              const Iterable<MapEntry<String, String>>.empty())
                        PopupMenuItem(value: row.key, child: Text(row.value)),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Text('子项分', style: TextStyle(fontSize: 14)),
                          Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: config == null ? null : () => _showFilters(),
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: const Text('筛选'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: protectHorizontalDragFromVerticalRefresh(
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                itemCount: config == null ? 0 : 5,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  const keys = ['price', 'brand_id', '1012', '1034', '1109'];
                  const labels = ['价格', '品牌', '发布时间', 'SoC型号', '电池容量'];
                  final active = _filters[keys[i]]?.isNotEmpty ?? false;
                  return InkWell(
                    onTap: () => _showFilters(keys[i]),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 14,
                              color: active
                                  ? const Color(0xFF009688)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const Icon(Icons.expand_more, size: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: EasyRefresh(
              header: reviewDefaultRefreshHeader,
              triggerAxis: Axis.vertical,
              onRefresh: () => _load(true),
              child: ListView.separated(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 84),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                itemBuilder: (context, i) {
                  if (i == _items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: _busy
                            ? const CircularProgressIndicator()
                            : _error != null
                            ? TextButton(
                                onPressed: () => _load(_items.isEmpty),
                                child: Text(_error!),
                              )
                            : _items.isEmpty
                            ? const Text('暂无符合筛选条件的机型')
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  return _row(_items[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final chosen = _selected.containsKey(id);
    final pic = '${item['pic']}';
    final tags = (item['tags'] as List).cast<String>();
    return InkWell(
      onTap: () {
        if (widget.onProductSelected != null) {
          widget.onProductSelected!(item);
          Navigator.of(context).pop(item);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                ProductPage(api: widget.api, id: id, title: '${item['title']}'),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: pic.isEmpty
                  ? const SizedBox(
                      width: 56,
                      height: 64,
                      child: Icon(Icons.phone_android_outlined),
                    )
                  : CachedNetworkImage(
                      normalizeCoolapkImageUrl(pic),
                      headers: coolapkImageHeaders(pic, api: widget.api),
                      width: 56,
                      height: 64,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.phone_android_outlined),
                    ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['title']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (tag.contains('新品')
                                        ? Colors.red
                                        : tag.startsWith('评分')
                                        ? Colors.deepPurple
                                        : Colors.blue)
                                    .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: tag.contains('新品')
                                  ? Colors.red
                                  : tag.startsWith('评分')
                                  ? const Color(0xFFAD80EB)
                                  : Colors.blue,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item['specs']}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item['price']}',
                          style: const TextStyle(
                            color: Color(0xFFF44336),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            if (chosen) {
                              _selected.remove(id);
                            } else if (_selected.length < 4) {
                              _selected[id] = item;
                            } else {
                              AppToast.show(context, '最多同时对比四款机型');
                            }
                          }),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: Text(
                            chosen ? '已添加' : '＋对比',
                            style: const TextStyle(fontSize: 11),
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
    );
  }

  Future<void> _showFilters([String? only]) async {
    final groups =
        _source.configuration?.filters
            .where((e) => only == null || e['id'] == only)
            .toList() ??
        [];
    if (groups.isEmpty) return;
    final draft = {
      for (final row in _filters.entries) row.key: row.value.toList(),
    };
    final result = await showModalBottomSheet<Map<String, List<String>>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    only == null ? '筛选机型' : '${groups.first['title']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            '${group['title']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final option in group['options'] as List)
                              FilterChip(
                                label: Text('${option['title']}'),
                                selected:
                                    draft['${group['id']}']?.contains(
                                      '${option['value']}',
                                    ) ??
                                    false,
                                onSelected: (selected) => update(() {
                                  final values = draft.putIfAbsent(
                                    '${group['id']}',
                                    () => [],
                                  );
                                  if (selected) {
                                    values.add('${option['value']}');
                                  } else {
                                    values.remove('${option['value']}');
                                  }
                                  if (values.isEmpty) {
                                    draft.remove('${group['id']}');
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => update(() {
                            if (only == null) {
                              draft.clear();
                            } else {
                              draft.remove(only);
                            }
                          }),
                          child: const Text('重置'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, draft),
                          child: const Text('确定'),
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
    );
    if (result != null && mounted) {
      setState(() => _filters = result);
      _load(true);
    }
  }

  void _compare() {
    if (_selected.isEmpty) {
      AppToast.show(context, '请先添加机型进行对比');
      return;
    }
    if (widget.onProductSelected != null) {
      Navigator.of(context).pop(_selected.values.toList());
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProductComparisonPage(
          api: widget.api,
          initialProducts: [
            for (final item in _selected.values)
              ComparisonProduct.fromDetail(
                id: '${item['id']}',
                detail: item,
              ),
          ],
        ),
      ),
    );
  }
}
