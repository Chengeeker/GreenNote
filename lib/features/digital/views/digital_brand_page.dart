import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_frosted_app_bar.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/review_refresh_header.dart';
import 'digital_server_channel_view.dart';

class DigitalBrandPage extends StatefulWidget {
  const DigitalBrandPage({
    required this.api,
    required this.title,
    required this.url,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String url;

  @override
  State<DigitalBrandPage> createState() => _DigitalBrandPageState();
}

class _DigitalBrandPageState extends State<DigitalBrandPage> {
  List<Map<String, dynamic>> _tabs = const [];
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.api.getList(
        '/v6/page/dataList',
        query: {'url': widget.url, 'page': 1},
      );
      Map<String, dynamic>? tabCard;
      for (final item in page.items) {
        if ((item['entityTemplate'] ?? '').toString().toLowerCase() ==
            'icontablinkgridcard') {
          tabCard = item;
          break;
        }
      }

      final rawTabs = tabCard?['entities'];
      final tabs = rawTabs is List
          ? rawTabs
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .where((tab) => (tab['url'] ?? '').toString().isNotEmpty)
                .toList(growable: false)
          : <Map<String, dynamic>>[];
      var configuredIndex = 0;
      final rawExtra = tabCard?['extraData'] ?? tabCard?['extra_data'];
      if (rawExtra is Map) {
        configuredIndex =
            int.tryParse(
              (rawExtra['selectedTab'] ?? tabCard?['selectedTab'] ?? '')
                  .toString(),
            ) ??
            0;
      } else if (rawExtra is String) {
        try {
          final extra = jsonDecode(rawExtra);
          if (extra is Map) {
            configuredIndex =
                int.tryParse(
                  (extra['selectedTab'] ?? tabCard?['selectedTab'] ?? '')
                      .toString(),
                ) ??
                0;
          }
        } on FormatException {
          // Use the first server tab when optional tab metadata is malformed.
        }
      } else {
        configuredIndex =
            int.tryParse((tabCard?['selectedTab'] ?? '').toString()) ?? 0;
      }

      final markedIndex = tabs.indexWhere((tab) {
        final selected =
            tab['selected'] ?? tab['isSelected'] ?? tab['is_selected'];
        return selected == true || selected == 1 || selected == '1';
      });
      final selectedIndex = markedIndex >= 0
          ? markedIndex
          : configuredIndex >= 0 && configuredIndex < tabs.length
          ? configuredIndex
          : 0;
      if (!mounted) return;
      setState(() {
        _tabs = tabs;
        _selectedIndex = selectedIndex;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Widget _series(String url) => DigitalServerChannelView(
    key: ValueKey(url),
    api: widget.api,
    url: url,
    bottomPadding: 24,
    groupProductRows: true,
    initialSortTitle: '最新',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: Text(widget.title)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：$_error'),
                TextButton(onPressed: _loadTabs, child: const Text('重新加载')),
              ],
            ),
          )
        : _tabs.isEmpty
        ? _series(widget.url)
        : DefaultTabController(
            length: _tabs.length,
            initialIndex: _selectedIndex,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  labelColor: const Color(0xFF00B074),
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 16),
                  indicatorColor: const Color(0xFF00B074),
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  onTap: (_) => HapticFeedbackUtil.selection(),
                  tabs: [
                    for (final tab in _tabs)
                      Tab(text: (tab['title'] ?? '').toString()),
                  ],
                ),
                Expanded(
                  child: filterHorizontalScrollNotifications(
                    TabBarView(
                      physics: const ClampingScrollPhysics(),
                      children: [
                        for (final tab in _tabs) _series(tab['url'].toString()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}
