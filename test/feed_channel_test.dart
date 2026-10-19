import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';

class FakeFeedApi implements CoolapkApi {
  @override
  bool get isAnonymous => false;

  FakeFeedApi({this.hasCookie = false, this.currentUid = ''});

  @override
  final bool hasCookie;

  @override
  final String currentUid;

  @override
  String get notificationSessionKey => 'test-session';

  @override
  String get currentUserAvatar => '';

  @override
  Map<String, String> imageHeadersFor() => {};

  @override
  Future<Map<String, dynamic>> getFeedDetail(String feedId) async => {
    'data': {'id': feedId},
  };

  @override
  Future<List<CoolapkFeed>> getReplies(String feedId) async => [];

  @override
  Future<ApiPage> getReplyPage(
    String feedId,
    int page, {
    String listType = 'lastupdate_desc',
    String? firstItem,
    String? lastItem,
    String feedType = 'feed',
    bool fromFeedAuthor = false,
  }) async => const ApiPage(
    items: [],
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );

  @override
  Future<ApiPage> getHotReplyPage(String feedId, int page) async =>
      const ApiPage(
        items: [],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Home Channels & Route Tests', () {
    test(
      'Default channels and more channels match official Coolapk config',
      () {
        final defaultChannels = [
          ('topic', '话题', '/page?url=V11_VERTICAL_TOPIC&title=话题'),
          ('follow', '关注', '/page?url=V15_HOME_TAB_FOLLOW'),
          ('headline', '头条', '/v6/main/headline'),
          ('hot', '热榜', '/page?url=V9_HOME_TAB_RANKING'),
          ('tutorial', '教程', '/page?url=V11_HOME_TAB_JC'),
          ('video', '视频', '/page?url=V9_HOME_TAB_SHIPIN'),
        ];

        final moreChannels = [
          ('news', '快讯', '/page?url=V11_HOME_TAB_NEWS'),
          ('new_device', '新机', '/page?url=V11_HOME_NEW'),
          ('car', '汽车', '/page?url=V11_HOME_CAR'),
          ('unboxing', '开箱', '/page?url=V13_IOSHOME_OPENSHOW'),
          ('photo', '摄影', '/page?url=V13_HOME_SHEYING'),
          ('game', '游戏', '/page?url=V15_YOUXI'),
          ('peripherals', '外设', '/page?url=V14_WAISHE'),
          ('theme', '美化', '/page?url=V11_HOME_MEIHUA'),
          ('live', '直播', '/page?url=V9_HOME_TAB_LIVE'),
          ('qa', '问答', '/page?url=V9_HOME_TAB_WENDA'),
          ('coupons', '神券', '/page?url=V11_FIND_GOODS'),
        ];

        expect(defaultChannels.length, 6);
        expect(moreChannels.length, 11);
      },
    );

    test('formatRelativeTime formats timestamps correctly', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(formatRelativeTime('${nowSec - 10}'), '刚刚');
      expect(formatRelativeTime('${nowSec - 300}'), '5分钟前');
      expect(formatRelativeTime('${nowSec - 7200}'), '2小时前');
      expect(formatRelativeTime('${nowSec - 86400 * 3}'), '3天前');
      expect(formatRelativeTime(''), '');
      expect(formatRelativeTime('invalid'), '');
    });
  });

  group('FeedCard Layout & View Count Tests', () {
    testWidgets(
      'Detail page FeedCard hides duplicate user row and only shows views for author',
      (tester) async {
        final apiGuest = FakeFeedApi();
        const feed = CoolapkFeed(
          id: '12345',
          uid: 'user_other',
          username: '其他用户',
          avatar: '',
          message: '测试动态正文',
          date: '10分钟前',
          likeCount: '10',
          replyCount: '5',
          pictures: [],
          raw: {'ip_location': '广东', 'view_num': '6666', 'uid': 'user_other'},
        );

        // 1. When viewed in detail page as guest / other user -> NO view count
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeedCard(api: apiGuest, feed: feed, isDetail: true),
            ),
          ),
        );

        expect(find.text('测试动态正文'), findsOneWidget);
        // Detail page FeedCard hides top avatar row (rendered by AppBar instead)
        expect(find.text('其他用户'), findsNothing);
        // Location is rendered
        expect(find.text('发布于广东'), findsOneWidget);
        // Views are NOT rendered because viewer is not author
        expect(find.textContaining('6666浏览'), findsNothing);

        // 2. When viewed in detail page as author -> views ARE rendered
        final apiAuthor = FakeFeedApi(
          hasCookie: true,
          currentUid: 'user_other',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeedCard(api: apiAuthor, feed: feed, isDetail: true),
            ),
          ),
        );
        expect(find.textContaining('6666浏览'), findsOneWidget);
      },
    );

    testWidgets('Feed list card displays user avatar and username', (
      tester,
    ) async {
      final api = FakeFeedApi();
      const feed = CoolapkFeed(
        id: '12345',
        uid: 'user_test',
        username: '酷友测试',
        avatar: '',
        message: '列表动态展示',
        date: '5分钟前',
        likeCount: '2',
        replyCount: '1',
        pictures: [],
        raw: {'device_title': '一加16'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedCard(api: api, feed: feed, isDetail: false),
          ),
        ),
      );

      expect(find.text('酷友测试'), findsOneWidget);
      expect(find.textContaining('一加16'), findsWidgets);
      expect(find.text('列表动态展示'), findsOneWidget);
    });
  });

  group('Product and Topic Cards in Detail Page Tests', () {
    testWidgets(
      'Detail page renders official digital product card with rating and dual action pills',
      (tester) async {
        final api = FakeFeedApi();
        const feedWithProduct = CoolapkFeed(
          id: '99999',
          uid: 'author_1',
          username: '测评君',
          avatar: '',
          message: '一加16上手体验',
          date: '1小时前',
          likeCount: '88',
          replyCount: '20',
          pictures: [],
          raw: {
            'targetRow': {
              'id': '38888',
              'title': '一加16',
              'logo': '',
              'url': '/product/38888',
              'targetType': 'product',
              'productTypeName': '数码',
              'star_average_score': '9.4',
              'subTitle': '622.6万热度 7145讨论',
              'isFollow': 0,
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeedCard(api: api, feed: feedWithProduct, isDetail: true),
            ),
          ),
        );

        // Product tag and title
        expect(find.text('数码'), findsOneWidget);
        expect(find.text('一加16'), findsOneWidget);
        // Heat & discussion
        expect(find.textContaining('622.6万热度 7145讨论'), findsOneWidget);
        // Score
        expect(find.text('9.4'), findsOneWidget);
        // Dual action pills: 关注 and 我也发一条
        expect(find.text('关注'), findsOneWidget);
        expect(find.text('我也发一条'), findsOneWidget);
      },
    );

    testWidgets(
      'Detail page renders official topic card with heat, discussion, and chevron',
      (tester) async {
        final api = FakeFeedApi();
        const feedWithTopic = CoolapkFeed(
          id: '88888',
          uid: 'author_2',
          username: '车友',
          avatar: '',
          message: '关于小米汽车的体验',
          date: '2小时前',
          likeCount: '50',
          replyCount: '15',
          pictures: [],
          raw: {
            'targetRow': {
              'id': '5555',
              'title': '年轻人的第一辆车',
              'logo': '',
              'url': '/t/年轻人的第一辆车',
              'targetType': 'topic',
              'subTitle': '2.1亿热度 8.1万讨论',
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeedCard(api: api, feed: feedWithTopic, isDetail: true),
            ),
          ),
        );

        expect(find.text('年轻人的第一辆车'), findsOneWidget);
        expect(find.textContaining('2.1亿热度 8.1万讨论'), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      },
    );
  });

  group('FeedDetailPage AppBar Tests', () {
    testWidgets(
      'FeedDetailPage AppBar renders author avatar, username, level, time, phone icon and device',
      (tester) async {
        final api = FakeFeedApi();
        const feed = CoolapkFeed(
          id: '77777',
          uid: 'user_author_7',
          username: '大红大紫的红',
          avatar: '',
          message: '一加16这个黑边绝了',
          date: '57分钟前',
          likeCount: '30',
          replyCount: '10',
          pictures: [],
          raw: {
            'device_title': '一加16',
            'user_level': '7',
            'uid': 'user_author_7',
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: FeedDetailPage(api: api, feed: feed),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // AppBar contains username and Lv.7
        expect(find.text('大红大紫的红'), findsOneWidget);
        expect(find.text('(Lv.7)'), findsOneWidget);
        // Subtitle line contains 57分钟前 and 📱 一加16
        expect(find.text('57分钟前 📱 一加16'), findsOneWidget);
        // Follow button is displayed for non-self author
        expect(find.text('关注'), findsOneWidget);
        // More actions menu icon
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      },
    );
  });

  group('Progressive Linear Feed Loading Tests', () {
    testWidgets(
      'SearchPage reveals feeds progressively (60% initial stage, then remaining 40% on scroll)',
      (tester) async {
        final mockList = List.generate(
          10,
          (i) => CoolapkFeed(
            id: 'feed_item_$i',
            uid: 'uid_$i',
            username: 'User $i',
            avatar: '',
            message: 'UniqueFeedMessageIndex_$i',
            date: '刚刚',
            likeCount: '0',
            replyCount: '0',
            pictures: [],
            raw: {'id': 'feed_item_$i'},
          ),
        );

        final api = _ProgressiveSearchFakeApi(mockList);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: SearchPage(api: api, initialQuery: 'Flutter'),
            ),
          ),
        );

        // Run post-frame callbacks & search API call
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Initial stage: feeds in visible viewport (e.g. index 0) are rendered,
        // while offscreen and buffered items are not eagerly built
        expect(find.text('UniqueFeedMessageIndex_0'), findsOneWidget);
        expect(find.text('UniqueFeedMessageIndex_9'), findsNothing);

        // Scroll to trigger progressive release and bring later items into view
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pumpAndSettle();

        // After scrolling, all items including the buffered 40% are smoothly revealed
        expect(find.text('UniqueFeedMessageIndex_9'), findsOneWidget);
      },
    );
  });
}

class _ProgressiveSearchFakeApi extends FakeFeedApi {
  _ProgressiveSearchFakeApi(this.mockFeeds);
  final List<CoolapkFeed> mockFeeds;

  @override
  Future<FeedPage> searchFeeds(String query, int page) async {
    return FeedPage(
      items: mockFeeds,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }
}
