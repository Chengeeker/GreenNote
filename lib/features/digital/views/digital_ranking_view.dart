import 'package:flutter/material.dart';

import '../../../core/network/coolapk_api.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import 'digital_server_channel_view.dart';

class DigitalRankingView extends StatefulWidget {
  const DigitalRankingView({required this.api, super.key});

  final CoolapkApi api;

  @override
  State<DigitalRankingView> createState() => _DigitalRankingViewState();
}

class _DigitalRankingViewState extends State<DigitalRankingView>
    with SingleTickerProviderStateMixin {
  static const _rankingUrl = 'V10_CHANNEL_SMB_TOP';
  late Future<List<Map<String, String>>> _routes;
  TabController? _controller;

  @override
  void initState() {
    super.initState();
    _routes = _loadRoutes();
  }

  Future<List<Map<String, String>>> _loadRoutes() async {
    final result = await widget.api.request(
      '/v6/page/dataList',
      query: const {'url': _rankingUrl, 'page': 1},
    );
    final data = result is Map ? result['data'] : null;
    final routes = <Map<String, String>>[];
    void visit(dynamic value) {
      if (value is List) {
        for (final child in value) {
          visit(child);
        }
      } else if (value is Map) {
        final template =
            (value['entityTemplate'] ?? value['entity_template'] ?? '')
                .toString()
                .toLowerCase();
        final title = (value['title'] ?? value['subTitle'] ?? '').toString();
        if (template.startsWith('sortselectcard') ||
            template.startsWith('selectorlinkcard') ||
            title.contains('排序规则')) {
          final entities = value['entities'];
          if (entities is List) {
            for (final item in entities.whereType<Map>()) {
              final name = (item['title'] ?? item['name'] ?? '').toString();
              final url =
                  (item['url'] ??
                          item['target_url'] ??
                          item['entityUrl'] ??
                          item['page_name'] ??
                          '')
                      .toString();
              if (name.isNotEmpty &&
                  url.isNotEmpty &&
                  !routes.any((route) => route['url'] == url)) {
                routes.add({'title': name, 'url': url});
              }
            }
          }
        }
        for (final key in const [
          'data',
          'entities',
          'rows',
          'list',
          'items',
          'cardRows',
          'card_rows',
          'entityList',
          'entity_list',
        ]) {
          if (value.containsKey(key)) visit(value[key]);
        }
      }
    }

    visit(data ?? result);
    return routes;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, String>>>(
    future: _routes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _error(context, snapshot.error.toString());
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final routes = snapshot.data!;
      if (routes.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('排行榜接口没有返回分类入口'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _routes = _loadRoutes()),
                child: const Text('重新加载'),
              ),
            ],
          ),
        );
      }
      final initialIndex = routes.indexWhere((item) => item['title'] == '手机榜');
      _controller ??= TabController(
        length: routes.length,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
        vsync: this,
      );
      return Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              itemCount: routes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _controller!,
                builder: (context, _) {
                  final selected = _controller!.index == index;
                  final colors = Theme.of(context).colorScheme;
                  return Material(
                    color: selected
                        ? colors.primary
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedbackUtil.selection();
                        _controller!.animateTo(index);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Text(
                            routes[index]['title']!,
                            style: TextStyle(
                              color: selected
                                  ? colors.onPrimary
                                  : colors.onSurface,
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
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: [
                for (final route in routes)
                  DigitalServerChannelView(
                    key: ValueKey(route['url']),
                    api: widget.api,
                    url: route['url']!,
                    groupProductRows: true,
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _error(BuildContext context, String message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(
          onPressed: () => setState(() => _routes = _loadRoutes()),
          child: const Text('重试'),
        ),
      ],
    ),
  );
}
