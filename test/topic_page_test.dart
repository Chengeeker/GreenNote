import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class _MockCoolapkApi extends Fake implements CoolapkApi {
  Map<String, dynamic>? followDetail;
  bool? previousFollow;
  List<Map<String, dynamic>> mockFeedItemsPage1 = [];
  List<Map<String, dynamic>> mockFeedItemsPage2 = [];

  @override
  Future<void> followTopic(String tag, {required bool following}) async {
    previousFollow = following;
  }

  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async {
    if (followDetail != null) {
      return {
        'data': {'tag': tag, 'title': tag, ...followDetail!},
      };
    }
    if (tag.contains('ColorOS')) {
      return {
        'data': {
          'title': 'ColorOS17',
          'tag': 'ColorOS17',
          'logo': 'http://image.coolapk.com/logo_coloros.png',
          'cover': 'http://image.coolapk.com/cover_coloros.png',
          'follow_num': '48000',
          'feed_num': '34000',
          'hot_num_txt': '226.0万热度',
        },
      };
    }
    if (tag.contains('柔光玻璃')) {
      return {
        'data': {
          'title': 'HyperOS4柔光玻璃',
          'tag': 'HyperOS4柔光玻璃',
          'logo': 'http://image.coolapk.com/logo_glass.png',
          'creator_name': '叫我小张',
          'follow_num': '30',
          'feed_num': '184',
          'hot_num_txt': '8055热度',
          'description': '随光而变的柔光玻璃，随心编排的空间，处处顺手的柔性框架。',
        },
      };
    }
    return {
      'data': {'title': tag, 'tag': tag, 'follow_num': '100', 'feed_num': '50'},
    };
  }

  final List<Map<String, dynamic>> requestedQueries = [];

  @override
  Future<ApiPage> getList(String path, {Map<String, dynamic>? query}) async {
    if (query != null) requestedQueries.add(Map<String, dynamic>.from(query));
    final pageNum = query?['page'] as int? ?? 1;
    if (pageNum == 1 && mockFeedItemsPage1.isNotEmpty) {
      return ApiPage(
        items: mockFeedItemsPage1,
        page: 1,
        hasMore: mockFeedItemsPage2.isNotEmpty,
        firstItem: '1',
        lastItem: '20',
      );
    }
    if (pageNum == 2 && mockFeedItemsPage2.isNotEmpty) {
      return ApiPage(
        items: mockFeedItemsPage2,
        page: 2,
        hasMore: false,
        firstItem: '21',
        lastItem: '40',
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
  group('System & Feature Topic Profile Tests', () {
    test('resolveSystemProfile identifies ColorOS 17 with 8 dimensions and purple atmosphere', () {
      final profile = resolveSystemProfile('ColorOS17', 'ColorOS17');
      expect(profile.isSystem, isTrue);
      expect(profile.hasRating, isTrue);
      expect(profile.score, 9.4);
      expect(profile.dimensions.length, 8);
      expect(profile.dimensions, contains('美观度'));
      expect(profile.dimensions, contains('流畅性'));
      expect(profile.dimensions, contains('更新维护'));
      expect(profile.activityTitle, contains('宝藏功能大赏'));
      expect(profile.brandName, contains('OPPO'));
      expect(profile.primaryBg, const Color(0xFF18102A));
    });

    test('resolveSystemProfile identifies HyperOS4柔光玻璃 as feature with 5-star distribution', () {
      final profile = resolveSystemProfile('HyperOS4柔光玻璃', 'HyperOS4柔光玻璃');
      expect(profile.isSystem, isFalse);
      expect(profile.isFeature, isTrue);
      expect(profile.hasRating, isTrue);
      expect(profile.score, 9.6);
      expect(profile.starCounts.length, 5);
      expect(profile.starCounts[0], 24); // 5-star count
      expect(profile.primaryBg, const Color(0xFF13161C));
    });

    test(
      'resolveSystemProfile identifies OriginOS, HarmonyOS, iOS, One UI, Flyme',
      () {
        final origin = resolveSystemProfile('OriginOS 5', 'OriginOS 5');
        expect(origin.isSystem, isTrue);
        expect(origin.score, 9.5);
        expect(origin.brandName, contains('vivo'));

        final harmony = resolveSystemProfile(
          'HarmonyOS NEXT',
          'HarmonyOS NEXT',
        );
        expect(harmony.isSystem, isTrue);
        expect(harmony.score, 9.5);
        expect(harmony.brandName, contains('华为'));

        final ios = resolveSystemProfile('iOS 18', 'iOS 18');
        expect(ios.isSystem, isTrue);
        expect(ios.score, 9.4);
        expect(ios.brandName, 'Apple');

        final oneui = resolveSystemProfile('One UI 7', 'One UI 7');
        expect(oneui.isSystem, isTrue);
        expect(oneui.score, 9.3);

        final flyme = resolveSystemProfile('Flyme 11', 'Flyme 11');
        expect(flyme.isSystem, isTrue);
        expect(flyme.score, 9.3);
      },
    );

    test('resolveSystemProfile identifies feature topics: 灵动岛, 流体云, 自由小窗', () {
      final island = resolveSystemProfile('灵动岛', '灵动岛');
      expect(island.hasRating, isTrue);
      expect(island.isFeature, isTrue);

      final fluid = resolveSystemProfile('流体云', '流体云');
      expect(fluid.hasRating, isTrue);
      expect(fluid.isFeature, isTrue);

      final window = resolveSystemProfile('自由小窗', '自由小窗');
      expect(window.hasRating, isTrue);
      expect(window.isFeature, isTrue);
    });

    test('resolveSystemProfile returns plain profile for normal topic', () {
      final plain = resolveSystemProfile('日常摄影', '日常摄影');
      expect(plain.isSystem, isFalse);
      expect(plain.isFeature, isFalse);
      expect(plain.hasRating, isFalse);
    });
  });

  for (final value in [1, '1', true, 0]) {
    testWidgets(
      'topic follows server userAction $value rather than stale top-level field',
      (tester) async {
        final api = _MockCoolapkApi()
          ..followDetail = {
            'isFollow': value == 0 ? 1 : 0,
            'userAction': {'follow': value},
          };
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(api: api, tag: '日常摄影'),
          ),
        );
        await tester.pumpAndSettle();
        final followed = value != 0;
        expect(find.text(followed ? '已关注' : '关注'), findsWidgets);
        await tester.tap(find.text(followed ? '已关注' : '关注').first);
        await tester.pumpAndSettle();
        expect(api.previousFollow, followed);
      },
    );
  }
  group('TopicPage Widget Tests', () {
    testWidgets(
      'renders ColorOS17 system topic with 8-dimension rating card and 4 tabs',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: 'ColorOS17',
              initialTitle: 'ColorOS17',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Check title and rating elements
        expect(find.text('ColorOS17'), findsWidgets);
        expect(find.text('酷安评分'), findsOneWidget);
        expect(find.text('9.4'), findsAtLeastNWidgets(1));
        expect(find.text('用户评分'), findsOneWidget);

        // Check 8-dimension items
        expect(find.text('美观度'), findsOneWidget);
        expect(find.text('流畅性'), findsOneWidget);
        expect(find.text('更新维护'), findsOneWidget);

        // Check tabs for OS: 新特性, 讨论, 机型区, 点评
        expect(find.text('新特性'), findsOneWidget);
        expect(find.text('讨论'), findsOneWidget);
        expect(find.text('机型区'), findsOneWidget);
        expect(find.text('点评'), findsOneWidget);

        // Check sub-filter row: 全部讨论 and 默认/最新/热度
        expect(find.text('全部讨论'), findsOneWidget);
        expect(find.text('默认'), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);
        expect(find.text('热度'), findsOneWidget);

        // Check FAB
        expect(find.byType(FloatingActionButton), findsOneWidget);
      },
    );

    testWidgets(
      'renders HyperOS4柔光玻璃 feature topic with 5-star distribution and 2 tabs',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: 'HyperOS4柔光玻璃',
              initialTitle: 'HyperOS4柔光玻璃',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Check title and rating elements
        expect(find.text('HyperOS4柔光玻璃'), findsWidgets);
        expect(find.text('酷安评分'), findsOneWidget);
        expect(find.text('9.6'), findsOneWidget);

        // Check 5-star distribution rows
        expect(find.text('5星'), findsOneWidget);
        expect(find.text('4星'), findsOneWidget);
        expect(find.text('1星'), findsOneWidget);

        // Check tabs for feature: 讨论, 点评
        expect(find.text('讨论'), findsOneWidget);
        expect(find.text('点评'), findsOneWidget);
        expect(find.text('机型区'), findsNothing);

        // Check creator row
        expect(find.textContaining('叫我小张 创建'), findsOneWidget);
      },
    );

    testWidgets(
      'retains initialLogo as topic theme logo without fallback letter and without duplicating as 120px top banner',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: '风景',
              initialTitle: '风景',
              initialCover: 'https://image.coolapk.com/scenery_pic.jpg',
              initialLogo: 'https://image.coolapk.com/scenery_pic.jpg',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('#风景#'), findsAtLeastNWidgets(1));
        expect(find.byType(TopicPage), findsOneWidget);

        // Fallback text "风" should NOT be displayed
        expect(find.text('风'), findsNothing);

        // Top banner should NOT duplicate the logo (no 120-height banner)
        final topBannerFinder = find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 120,
        );
        expect(topBannerFinder, findsNothing);
      },
    );

    testWidgets(
      'switching sort buttons (默认/最新/热度) triggers API requests with lastupdate_desc, dateline_desc, hot',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: 'ColorOS17',
              initialTitle: 'ColorOS17',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Initial default sort is lastupdate_desc
        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'lastupdate_desc',
          ),
          isTrue,
        );

        mockApi.requestedQueries.clear();

        // Tap "最新"
        await tester.tap(find.text('最新'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'dateline_desc',
          ),
          isTrue,
        );

        mockApi.requestedQueries.clear();

        // Tap "热度"
        await tester.tap(find.text('热度'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'hot',
          ),
          isTrue,
        );

        mockApi.requestedQueries.clear();

        // Tap "默认"
        await tester.tap(find.text('默认'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'lastupdate_desc',
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'normal topic page tabs (热门/最新发布/最新回复) map correctly to hot, dateline_desc, lastupdate_desc',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: '普通摄影',
              initialTitle: '普通摄影',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Initial tab is 热门 -> listType 'hot'
        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'hot',
          ),
          isTrue,
        );

        mockApi.requestedQueries.clear();

        // Switch to '最新发布' -> listType 'dateline_desc'
        await tester.tap(find.text('最新发布'));
        await tester.pumpAndSettle();

        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'dateline_desc',
          ),
          isTrue,
        );

        mockApi.requestedQueries.clear();

        // Switch to '最新回复' -> listType 'lastupdate_desc'
        await tester.tap(find.text('最新回复'));
        await tester.pumpAndSettle();

        expect(
          mockApi.requestedQueries.any(
            (q) => q['listType'] == 'lastupdate_desc',
          ),
          isTrue,
        );
      },
    );

    test('getFeedHeatScore calculates engagement and parses various count formats', () {
      final normalFeed = {
        'likenum': 100,
        'replynum': 30,
        'favnum': 10,
        'forwardnum': 5,
        'dateline': 1700000000,
      };
      // 100*2 + 30*3 + 10*2 + 5*3 = 200 + 90 + 20 + 15 = 325
      expect(getFeedHeatScore(normalFeed), 325);

      final wanFeed = {
        'likenum': '1.5万',
        'replynum': '200',
        'favnum': '0',
        'forwardnum': '0',
      };
      // 15000*2 + 200*3 = 30000 + 600 = 30600
      expect(getFeedHeatScore(wanFeed), 30600);

      final pinnedFeed = {
        'is_top': 1,
        'likenum': 0,
        'replynum': 0,
      };
      expect(getFeedHeatScore(pinnedFeed), 1000000000);
    });

    test('compareTopicFeedsByHeat places highest interaction feed first and preserves pinned priority', () {
      final feedLow = {
        'id': 'low',
        'message': 'Low activity post',
        'likenum': 1,
        'replynum': 0,
        'dateline': 1700000100,
      };
      final feedMed = {
        'id': 'med',
        'message': 'Medium activity post',
        'likenum': 50,
        'replynum': 20,
        'dateline': 1700000050,
      };
      final feedHigh = {
        'id': 'high',
        'message': 'High activity viral post',
        'likenum': 800,
        'replynum': 250,
        'dateline': 1700000000,
      };
      final feedPinned = {
        'id': 'pin',
        'message': 'Pinned post',
        'is_top': 1,
        'likenum': 0,
        'replynum': 0,
        'dateline': 1699999999,
      };

      final list = [feedLow, feedPinned, feedHigh, feedMed];
      list.sort(compareTopicFeedsByHeat);

      expect(list.map((e) => e['id']).toList(), ['pin', 'high', 'med', 'low']);
    });

    test('compareTopicFeedsByDate sorts feeds by dateline descending', () {
      final oldFeed = {'id': 'old', 'dateline': 1600000000};
      final newFeed = {'id': 'new', 'dateline': 1700000000};
      final pinnedFeed = {'id': 'pin', 'is_top': 1, 'dateline': 1500000000};

      final list = [oldFeed, newFeed, pinnedFeed];
      list.sort(compareTopicFeedsByDate);

      expect(list.map((e) => e['id']).toList(), ['pin', 'new', 'old']);
    });

    testWidgets(
      'topic page hot sort prefetches and displays high-engagement post at top',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        mockApi.mockFeedItemsPage1 = [
          {
            'id': 'p1_low',
            'entityType': 'feed',
            'feedType': 'feed',
            'message': 'Page1 low post',
            'username': 'UserA',
            'likenum': 2,
            'replynum': 0,
            'dateline': 1700000200,
          },
          {
            'id': 'p1_med',
            'entityType': 'feed',
            'feedType': 'feed',
            'message': 'Page1 med post',
            'username': 'UserB',
            'likenum': 30,
            'replynum': 10,
            'dateline': 1700000100,
          },
        ];
        mockApi.mockFeedItemsPage2 = [
          {
            'id': 'p2_viral',
            'entityType': 'feed',
            'feedType': 'feed',
            'message': 'Page2 viral hot post',
            'username': 'UserC',
            'likenum': 999,
            'replynum': 300,
            'dateline': 1700000050,
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: TopicPage(
              api: mockApi,
              tag: '普通摄影',
              initialTitle: '普通摄影',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // In normal topic, first tab is 热门 with prefetchPages=2 & compareTopicFeedsByHeat
        // Page 1 and Page 2 should both be queried
        expect(mockApi.requestedQueries.any((q) => q['page'] == 1), isTrue);
        expect(mockApi.requestedQueries.any((q) => q['page'] == 2), isTrue);

        // Find rendered messages; viral post from page 2 must be rendered
        expect(find.text('Page2 viral hot post'), findsOneWidget);
        expect(find.text('Page1 med post'), findsOneWidget);
      },
    );
  });
}
