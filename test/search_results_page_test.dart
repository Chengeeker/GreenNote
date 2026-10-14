import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shell/main_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class _MockCoolapkApi extends Fake implements CoolapkApi {
  final List<Map<String, dynamic>> recordedQueries = [];

  @override
  Future<ApiPage> getList(String path, {Map<String, dynamic>? query}) async {
    if (query != null) {
      recordedQueries.add(Map<String, dynamic>.from(query));
    }
    final type = query?['type']?.toString() ?? '';
    final page = query?['page'] as int? ?? 1;

    if (type == 'all') {
      if (page == 1) {
        // Page 1 returns only the User Card, with hasMore = true
        return ApiPage(
          items: [
            {
              'entityType': 'card',
              'entityTemplate': 'iconMiniScrollCard',
              'title': '用户',
              'entities': [
                {
                  'entityType': 'user',
                  'uid': '1001',
                  'username': 'HDR照片评测',
                  'avatar': 'http://image.coolapk.com/avatar1.jpg',
                },
                {
                  'entityType': 'user',
                  'uid': '1002',
                  'username': 'HDR拍照手机',
                  'avatar': 'http://image.coolapk.com/avatar2.jpg',
                },
              ],
            },
          ],
          page: 1,
          hasMore: true,
          firstItem: 'user_card_1',
          lastItem: 'user_card_1',
        );
      } else {
        // Page 2 returns the actual feed items
        return ApiPage(
          items: [
            {
              'id': '2001',
              'entityType': 'feed',
              'message': '这是一条关于HDR照片的精选动态',
              'username': '极客摄影师',
              'uid': '3001',
              'device_title': '小米14 Ultra',
              'dateline': 1727184000,
              'replynum': 16,
              'likenum': 14,
              'forwardnum': 2,
            },
          ],
          page: 2,
          hasMore: false,
          firstItem: '2001',
          lastItem: '2001',
        );
      }
    }

    if (type == 'feed') {
      return ApiPage(
        items: [
          {
            'id': '3001',
            'entityType': 'feed',
            'message': '动态分栏测试动态',
            'username': '酷安达人',
            'uid': '4001',
            'dateline': 1727185000,
            'replynum': 10,
            'likenum': 20,
            'forwardnum': 1,
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: '3001',
        lastItem: '3001',
      );
    }

    return const ApiPage(
      items: [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SearchResultsPage & Official Alignment Tests', () {
    testWidgets('SearchResultsPage renders official AppBar search capsule, 7 tabs, and auto-preloads Page 2 feeds', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsPage(
            api: mockApi,
            query: 'hdr照片',
            initialType: 'all',
          ),
        ),
      );
      await tester.pump();
      // Pump frame callback for auto-preload of page 2
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify Search TextField has query and search icon
      expect(find.text('hdr照片'), findsWidgets);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);

      // 2. Verify all 7 official tabs exist in exact order
      expect(find.text('综合'), findsWidgets);
      expect(find.text('数码'), findsOneWidget);
      expect(find.text('动态'), findsWidgets);
      expect(find.text('话题'), findsOneWidget);
      expect(find.text('用户'), findsWidgets);
      expect(find.text('二手'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);

      // 3. Verify User Card in '综合' tab has '更多相关用户'
      expect(find.text('更多相关用户'), findsOneWidget);

      // 4. Verify sort capsule in '综合' tab has 5 options
      expect(find.text('实时'), findsOneWidget);
      expect(find.text('热度'), findsOneWidget);
      expect(find.text('评论'), findsOneWidget);
      expect(find.text('精确'), findsOneWidget);

      // 5. Verify Page 2 feed item was AUTOMATICALLY loaded without any scroll event!
      expect(find.text('这是一条关于HDR照片的精选动态'), findsOneWidget);
      expect(find.text('小米14 Ultra'), findsWidgets);
      expect(find.byIcon(Icons.smartphone_rounded), findsWidgets);
      expect(find.byIcon(Icons.thumb_up_outlined), findsWidgets);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsWidgets);
      expect(find.byIcon(Icons.share_outlined), findsWidgets);

      // Verify page 1 and page 2 queries were both sent
      final allQueries = mockApi.recordedQueries.where((q) => q['type'] == 'all').toList();
      expect(allQueries.length, greaterThanOrEqualTo(2));
      expect(allQueries[0]['page'], 1);
      expect(allQueries[1]['page'], 2);
    });

    testWidgets('SearchSortCapsule switches selection on tap', (tester) async {
      String selected = 'default';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SearchSortCapsule(
                currentSort: selected,
                onSortChanged: (s) => setState(() => selected = s),
              ),
            ),
          ),
        ),
      );

      expect(selected, 'default');
      await tester.tap(find.text('热度'));
      await tester.pump();
      expect(selected, 'hot');

      await tester.tap(find.text('实时'));
      await tester.pump();
      expect(selected, 'dateline');
    });

    testWidgets('SearchFeedHeaderBar displays sort capsule and filter dropdown with feedArticle and feed', (tester) async {
      String sort = 'default';
      String filter = 'all';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SearchFeedHeaderBar(
                currentSort: sort,
                onSortChanged: (s) => setState(() => sort = s),
                currentFilter: filter,
                onFilterChanged: (f) => setState(() => filter = f),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SearchSortCapsule), findsOneWidget);
      expect(find.byType(SearchFilterDropdown), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();

      expect(find.text('图文'), findsOneWidget);
      expect(find.text('纯文字'), findsOneWidget);

      await tester.tap(find.text('图文'));
      await tester.pumpAndSettle();
      expect(filter, 'feedArticle');
    });

    testWidgets('Tapping 更多相关用户 animates to 用户 tab', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsPage(
            api: mockApi,
            query: 'hdr照片',
            initialType: 'all',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final moreUsersButton = find.text('更多相关用户');
      expect(moreUsersButton, findsOneWidget);

      await tester.tap(moreUsersButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 1));

      // Tab controller should have switched to tab index 4 ('用户')
      final tabControllerFinder = find.byType(TabBar);
      final TabBar tabBar = tester.widget(tabControllerFinder);
      expect(tabBar.controller?.index, 4);
    });

    testWidgets('Switching sort in 综合 tab sends both sort and sortType parameters', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsPage(
            api: mockApi,
            query: 'hdr照片',
            initialType: 'all',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Tap '热度' in 综合 tab
      await tester.tap(find.text('热度'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final hotQueries = mockApi.recordedQueries.where((q) => q['type'] == 'all' && q['sort'] == 'hot').toList();
      expect(hotQueries, isNotEmpty);
      expect(hotQueries.first['sortType'], 'hot');
    });

    testWidgets('Feed tab sends sort, sortType, and feedType parameters', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsPage(
            api: mockApi,
            query: 'hdr照片',
            initialType: 'feed',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final feedQueries = mockApi.recordedQueries.where((q) => q['type'] == 'feed').toList();
      expect(feedQueries, isNotEmpty);
      expect(feedQueries.first['sort'], 'default');
      expect(feedQueries.first['sortType'], 'default');

      // Tap '实时' in 动态 tab
      await tester.tap(find.text('实时'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final datelineQueries = mockApi.recordedQueries.where((q) => q['type'] == 'feed' && q['sort'] == 'dateline').toList();
      expect(datelineQueries, isNotEmpty);
      expect(datelineQueries.first['sortType'], 'dateline');
    });
  });
}
