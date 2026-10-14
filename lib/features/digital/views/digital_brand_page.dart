import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_frosted_app_bar.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/utils/haptic_feedback_util.dart';
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
  String _contentUrl = '';
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
        _contentUrl = tabs.isEmpty
            ? widget.url
            : (tabs[selectedIndex]['url'] ?? widget.url).toString();
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

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    HapticFeedbackUtil.selection();
    setState(() {
      _selectedIndex = index;
      _contentUrl = (_tabs[index]['url'] ?? '').toString();
    });
  }

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
        : Column(
            children: [
              if (_tabs.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _tabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 24),
                    itemBuilder: (context, index) {
                      final selected = index == _selectedIndex;
                      return InkWell(
                        onTap: () => _selectTab(index),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                (_tabs[index]['title'] ?? '').toString(),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: selected
                                      ? const Color(0xFF00B074)
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Container(
                              height: 3,
                              width: 24,
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF00B074)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              Expanded(
                child: DigitalServerChannelView(
                  key: ValueKey(_contentUrl),
                  api: widget.api,
                  url: _contentUrl,
                  bottomPadding: 24,
                  groupProductRows: true,
                ),
              ),
            ],
          ),
  );
}
