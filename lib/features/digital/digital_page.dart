import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../shared/api_list_page.dart';
import 'models/digital_tab_item.dart';
import 'views/digital_home_view.dart';
import 'views/digital_device_overview.dart';
import 'views/digital_library_view.dart';
import 'views/digital_ranking_view.dart';
import 'views/digital_server_channel_view.dart';

class DigitalPage extends StatefulWidget {
  const DigitalPage({required this.api, this.onTopBarChanged, super.key});

  final CoolapkApi api;
  final ValueChanged<PreferredSizeWidget?>? onTopBarChanged;

  @override
  State<DigitalPage> createState() => _DigitalPageState();
}

class _DigitalPageState extends State<DigitalPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<DigitalTabItem> _tabs = DigitalTabItem.getFallbackTabs();
  String _libraryCategoryId = '1000';
  int _librarySelectionRevision = 0;

  @override
  void initState() {
    super.initState();
    // 默认激活索引 1 对应的 "数码" (V10_DIGITAL_HOME)
    const initialIndex = 1;
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: initialIndex,
      vsync: this,
    );
    _tabController.addListener(_onTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTopBarChanged?.call(_buildTabBar());
    });
  }

  void _onTabChange() {
    if (_tabController.indexIsChanging) {
      HapticFeedbackUtil.selection();
    }
  }

  PreferredSizeWidget _buildTabBar() => PreferredSize(
    preferredSize: const Size.fromHeight(kTextTabBarHeight),
    child: Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          labelColor: colorScheme.primary,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.normal,
          ),
          tabs: [for (final tab in _tabs) Tab(text: tab.title)],
        );
      },
    ),
  );

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: _tabController,
      children: [
        // 0: 数码库
        DigitalLibraryView(
          api: widget.api,
          initialCategoryId: _libraryCategoryId,
          selectionRevision: _librarySelectionRevision,
        ),

        // 1: 数码 (V10_DIGITAL_HOME)
        DigitalHomeView(
          api: widget.api,
          onSelectLibraryCategory: (categoryId) {
            setState(() {
              _libraryCategoryId = categoryId;
              _librarySelectionRevision++;
            });
            _tabController.animateTo(0);
          },
          onSelectTab: (index) {
            if (index >= 0 && index < _tabs.length) {
              HapticFeedbackUtil.selection();
              _tabController.animateTo(index);
            }
          },
        ),

        // 2: 手机
        Column(
          children: [
            DigitalDeviceOverview(
              api: widget.api,
              onOpenPhones: () => _tabController.animateTo(0),
              onOpenSystems: () => _tabController.animateTo(4),
            ),
            Expanded(
              child: ApiListPage(
                api: widget.api,
                title: '手机',
                path: '/v6/page/dataList',
                query: const {'url': 'V10_CHANNEL_SJB'},
                showAppBar: false,
              ),
            ),
          ],
        ),

        // 3: 排行榜
        DigitalRankingView(api: widget.api),

        // 4: 系统
        DigitalServerChannelView(
          api: widget.api,
          url: 'V13_DIGITAL_ROM',
          system: true,
        ),

        // 5: 平板频道；6: 电脑频道。
        DigitalServerChannelView(
          key: const ValueKey('digital-tablets'),
          api: widget.api,
          url: 'V15_PAD',
        ),
        DigitalServerChannelView(
          key: const ValueKey('digital-computers'),
          api: widget.api,
          url: 'V8_ZHUANTI_COMPUTER_20230413',
        ),
      ],
    );
  }
}
