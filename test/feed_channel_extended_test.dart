import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/feed/feed_pages.dart';

class MockChannelApi implements CoolapkApi {
  @override
  bool get isAnonymous => false;

  MockChannelApi({this.hasCookie = true, this.currentUid = '10086'});

  @override
  final bool hasCookie;

  @override
  final String currentUid;
  @override
  String get notificationSessionKey => 'session-$currentUid';
  String? openedUserSpaceUid;

  @override
  String get currentUserAvatar => 'https://avatar.coolapk.com/user.jpg';

  @override
  Map<String, String> imageHeadersFor() => {};

  @override
  Future<Map<String, dynamic>> getFeedDetail(String feedId) async => {
    'data': {
      'id': feedId,
      'message': '这是详情正文',
      'replynum': 5,
      'likenum': 12,
      'favnum': 3,
      'forwardnum': 1,
    },
  };

  @override
  Future<ApiPage> getReplyPage(
    String feedId,
    int page, {
    String listType = 'lastupdate_desc',
    String? firstItem,
    String? lastItem,
    String feedType = 'feed',
    bool fromFeedAuthor = false,
  }) async => ApiPage(
    items: [
      {
        'id': '9001',
        'uid': 'author_1',
        'username': '楼主用户',
        'message': '这是第一条楼层评论',
        'dateline': '1700000000',
        'likenum': '8',
        'replynum': '2',
        'replyRows': [
          {
            'id': '9002',
            'uid': 'sub_author',
            'username': '楼中楼用户',
            'ruid': 'reply_target',
            'rusername': '被回复用户',
            'message': '这是楼中楼回复',
          },
        ],
      },
    ],
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );

  @override
  Future<ApiPage> getHotReplyPage(String feedId, int page) async =>
      getReplyPage(feedId, page);

  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async => {
    'data': {
      'tag': tag,
      'title': tag,
      'logo': 'https://image.coolapk.com/tag_$tag.png',
    },
  };

  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async {
    openedUserSpaceUid = uid;
    return {
      'data': {'uid': uid, 'username': '用户 $uid'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async => {'data': {}};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'official card truncates visible content instead of a long HTML href',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const topic = '懂车帝测试尊界V800刹车踏板断裂';
      final message =
          '<a class="feed-link-tag" href="/t/${Uri.encodeComponent(topic)}?type=0">#$topic#</a> ${List.filled(40, '正文内容用于测试截断。').join()}';
      final feed = CoolapkFeed.fromJson({
        'id': 'html-article',
        'username': 'inlook',
        'message': message,
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: FeedCard(
                  api: MockChannelApi(),
                  feed: feed,
                  officialLayout: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final visible = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join('\n');
      expect(visible, contains('#$topic#'));
      expect(visible, contains('…查看更多'));
      expect(visible, isNot(contains('<a')));
      expect(visible, isNot(contains('href=')));
      expect(visible, isNot(contains('%E6')));
      expect(tester.takeException(), isNull);
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Channel Headers & Feed Card Extended Tests', () {
    testWidgets('FeedCard displays rank badge 01 when rankNumber is 1', (
      tester,
    ) async {
      final api = MockChannelApi();
      const feed = CoolapkFeed(
        id: '101',
        username: '热榜酷友',
        avatar: '',
        message: '今天讨论热烈的话题',
        date: '10分钟前',
        likeCount: '99',
        replyCount: '20',
        pictures: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: FeedCard(api: api, feed: feed, rankNumber: 1),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('01'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    });

    testWidgets(
      'FeedCard displays 16:9 video preview card when media_url is present',
      (tester) async {
        final api = MockChannelApi();
        const feed = CoolapkFeed(
          id: '202',
          username: '视频博主',
          avatar: '',
          message: '这是最新开箱视频',
          date: '1小时前',
          likeCount: '50',
          replyCount: '15',
          pictures: [],
          raw: {
            'media_url': 'https://video-qc.coolapk.com/test.mp4',
            'media_info': {
              'cover': 'https://image.coolapk.com/video_cover.jpg',
              'duration': 80000, // 80s = 01:20
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FeedCard(api: api, feed: feed),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.text('01:20'), findsOneWidget);
      },
    );

    testWidgets('FeedCard displays quick reply bar and opens reply dialog', (
      tester,
    ) async {
      final api = MockChannelApi();
      const feed = CoolapkFeed(
        id: '303',
        username: '常驻酷友',
        avatar: '',
        message: '动态正文内容',
        date: '2小时前',
        likeCount: '10',
        replyCount: '5',
        pictures: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: FeedCard(api: api, feed: feed, isHeadline: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('说点儿什么吧'), findsOneWidget);
    });

    testWidgets(
      'FeedCard does not display quick reply bar on non-headline channel',
      (tester) async {
        final api = MockChannelApi();
        const feed = CoolapkFeed(
          id: '304',
          username: '热榜酷友',
          avatar: '',
          message: '动态正文内容',
          date: '2小时前',
          likeCount: '10',
          replyCount: '5',
          pictures: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: FeedCard(api: api, feed: feed, isHeadline: false),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('说点儿什么吧'), findsNothing);
      },
    );

    testWidgets(
      'Hot channel cards render rank icons, news, capsules, and selector',
      (tester) async {
        final api = MockChannelApi();
        final cards = [
          {
            'entityType': 'iconLinkGridCard',
            'entities': [
              {'title': '周榜', 'url': '/page?url=WEEK_RANK'},
              {'title': '月榜', 'url': '/page?url=MONTH_RANK'},
              {'title': '收藏榜', 'url': '/page?url=FAV_RANK'},
              {'title': '酷安指数', 'url': '/page?url=INDEX_RANK'},
              {'title': '酷图榜', 'url': '/page?url=PIC_RANK'},
            ],
          },
          {
            'entityType': 'iconMiniGridCard',
            'entities': [
              {'title': '要闻一', 'url': '/page?url=NEWS_1'},
              {'title': '要闻二', 'url': '/page?url=NEWS_2'},
            ],
          },
          {
            'entityType': 'capsuleListCard',
            'entities': [
              {'title': '热搜一', 'url': 'searchTab://?key=热搜一'},
              {'title': '热搜二', 'url': 'searchTab://?key=热搜二'},
            ],
          },
          {
            'entityType': 'selectorLinkCard',
            'entities': [
              {'title': '今日热门', 'url': '/page?url=HOT'},
              {'title': '手机', 'url': '/page?url=PHONE'},
            ],
          },
        ];

        var selectedIndex = -1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: HomeChannelCardsHeader(
                  api: api,
                  cards: cards,
                  channelId: 'hot',
                  activeCategoryIndex: 0,
                  onSelectCategory: (item, index) {
                    selectedIndex = index;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('周榜'), findsOneWidget);
        expect(find.text('月榜'), findsOneWidget);
        expect(find.text('要闻一'), findsOneWidget);
        expect(find.text('热搜一'), findsOneWidget);
        expect(find.text('今日热门'), findsOneWidget);
        expect(find.text('手机'), findsOneWidget);

        await tester.tap(find.text('手机'));
        await tester.pump();
        expect(selectedIndex, 1);
      },
    );

    testWidgets('Tutorial channel cards render banner and selector pills', (
      tester,
    ) async {
      final api = MockChannelApi();
      final cards = [
        {
          'entityType': 'image_1',
          'pic': 'https://image.coolapk.com/tutorial_banner.jpg',
          'description': '酷安教程中心，收录各类玩机技巧。欢迎各位投送优质教程。',
        },
        {
          'entityType': 'selectorLinkCard',
          'entities': [
            {'title': '全部', 'url': '/page?url=ALL'},
            {'title': '进阶', 'url': '/page?url=ADVANCED'},
            {'title': '苹果', 'url': '/page?url=APPLE'},
          ],
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeChannelCardsHeader(
                api: api,
                cards: cards,
                channelId: 'tutorial',
                activeCategoryIndex: 0,
                onSelectCategory: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('酷安教程中心'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('进阶'), findsOneWidget);
      expect(find.text('苹果'), findsOneWidget);
    });

    testWidgets('Video channel filter bar renders 3 quick options', (
      tester,
    ) async {
      final api = MockChannelApi();
      final cards = [
        {
          'entityType': 'iconMiniLinkGridCard',
          'entities': [
            {'title': '最新发布', 'url': '/page?url=LATEST'},
            {'title': '热门视频', 'url': '/page?url=HOT'},
            {'title': '发视频', 'url': '#/feed/create'},
          ],
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeChannelCardsHeader(
                api: api,
                cards: cards,
                channelId: 'video',
                activeCategoryIndex: 0,
                onSelectCategory: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('最新发布'), findsOneWidget);
      expect(find.text('热门视频'), findsOneWidget);
      expect(find.text('发视频'), findsOneWidget);
    });

    test('AppSettings fontScale changes and persists correctly', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(appSettingsProvider.notifier);
      expect(container.read(appSettingsProvider).fontScale, 1.0);

      await notifier.setFontScale(1.15);
      expect(container.read(appSettingsProvider).fontScale, 1.15);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('greennote.font_scale'), 1.15);
    });

    testWidgets(
      'Hot news mini grid card renders news items and dynamic badges without placeholder box',
      (tester) async {
        final api = MockChannelApi();
        final cards = [
          {
            'entityType': 'iconMiniGridCard',
            'entities': [
              {'title': '荣耀Magic7配置曝光', 'url': '/page?url=HONOR'},
              {'title': '苹果发布新系统', 'url': '/page?url=APPLE'},
              {'title': '华为鸿蒙NEXT更新', 'url': '/page?url=HUAWEI'},
              {'title': '百瓦快充新技术', 'url': '/page?url=CHARGE'},
            ],
          },
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: HomeChannelCardsHeader(
                  api: api,
                  cards: cards,
                  channelId: 'hot',
                  activeCategoryIndex: 0,
                  onSelectCategory: (_, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('荣耀Magic7配置曝光'), findsOneWidget);
        expect(find.text('苹果发布新系统'), findsOneWidget);
        expect(find.text('华为鸿蒙NEXT更新'), findsOneWidget);
        expect(find.text('百瓦快充新技术'), findsOneWidget);
        expect(find.byType(CachedNetworkImage), findsNWidgets(4));
        expect(find.byIcon(Icons.phone_android_rounded), findsNothing);
        expect(find.byIcon(Icons.apple), findsNothing);
      },
    );

    testWidgets(
      'FeedCard detail mode does not wrap in Card and renders topic capsule buttons',
      (tester) async {
        final api = MockChannelApi();
        const feed = CoolapkFeed(
          id: '501',
          uid: '10086',
          username: '酷友小明',
          avatar: '',
          message: '这是测试话题动态',
          date: '10分钟前',
          likeCount: '10',
          replyCount: '5',
          pictures: [],
          raw: {
            'targetRow': {
              'title': '小米15',
              'url': '/topic/123',
              'pic': '',
              'targetType': 'topic',
              'subTitle': '1234热度 567讨论',
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: FeedCard(api: api, feed: feed, isDetail: true),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Card), findsNothing);
        expect(find.text('话题'), findsOneWidget);
        expect(find.text('小米15'), findsOneWidget);
        expect(find.text('关注'), findsOneWidget);
        expect(find.text('我也发一条'), findsOneWidget);
      },
    );

    testWidgets(
      'FeedDetailPage renders 4 sort mode chips, flat replies, and bottom bar',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'greennote.liquid_glass_nav': false,
        });
        final api = MockChannelApi();
        const feed = CoolapkFeed(
          id: '601',
          uid: 'author_1',
          username: '发帖酷友',
          avatar: '',
          message: '这是帖子正文',
          date: '昨天 12:00',
          likeCount: '10',
          replyCount: '1',
          pictures: [],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme(),
              home: FeedDetailPage(api: api, feed: feed),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('默认'), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);
        expect(find.text('热门'), findsOneWidget);
        expect(find.text('楼主'), findsNWidgets(2));

        expect(find.text('楼主用户'), findsOneWidget);
        expect(find.text('这是第一条楼层评论'), findsOneWidget);
        expect(
          find.textContaining('楼中楼用户', findRichText: true),
          findsOneWidget,
        );

        expect(find.text('写评论'), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
        expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
        expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
        expect(
          find.byKey(const ValueKey('feed-detail-action-glass')),
          findsNothing,
        );
      },
    );

    testWidgets('nested reply users open their matching user spaces', (
      tester,
    ) async {
      final api = MockChannelApi();
      const feed = CoolapkFeed(
        id: '601',
        uid: 'author_1',
        username: '发帖酷友',
        avatar: '',
        message: '这是帖子正文',
        date: '昨天 12:00',
        likeCount: '10',
        replyCount: '1',
        pictures: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: FeedDetailPage(api: api, feed: feed),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('楼中楼用户'));
      await tester.pumpAndSettle();
      expect(api.openedUserSpaceUid, 'sub_author');

      Navigator.of(tester.element(find.byType(UserSpacePage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('被回复用户'));
      await tester.pumpAndSettle();
      expect(api.openedUserSpaceUid, 'reply_target');
    });

    test('Coolapk emotion aliases resolve to their original PNG assets', () {
      expect(getCoolapkEmotionUrl('[傲慢]'), endsWith('/c-aoman.png'));
      expect(getCoolapkEmotionUrl('Doge喝茶'), endsWith('/c-dogehechi.png'));
      expect(getCoolapkEmotionUrl('doge笑哭'), endsWith('/c-dogexiaoku.png'));
    });

    testWidgets(
      'liquid glass reuses exact action capsule layout and material',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.runAsync(() async {
          await container
              .read(appSettingsProvider.notifier)
              .setFloatingNavBar(true);
          await container
              .read(appSettingsProvider.notifier)
              .setLiquidGlassNavBar(true);
        });

        const feed = CoolapkFeed(
          id: '601',
          uid: 'author_1',
          username: '发帖酷友',
          avatar: '',
          message: '这是帖子正文',
          date: '昨天 12:00',
          likeCount: '10',
          replyCount: '1',
          pictures: [],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme(colorIndex: 3),
              home: FeedDetailPage(api: MockChannelApi(), feed: feed),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final glass = find.byKey(const ValueKey('feed-detail-action-glass'));
        expect(glass, findsNWidgets(2));
        final left = tester.getRect(glass.at(0));
        final right = tester.getRect(glass.at(1));
        expect(left.height, 44);
        expect(right.height, 44);
        expect(left.left, 14);
        expect(right.right, 386);
        expect(right.left - left.right, 10);
        expect(left.width / right.width, closeTo(0.75, 0.001));

        for (final capsule in tester.widgetList<AdaptiveGlass>(glass)) {
          expect(capsule.quality, GlassQuality.premium);
          expect(capsule.settings.glassColor, const Color(0x66000000));
          expect(capsule.settings.blur, 1.5);
          expect(capsule.settings.refractiveIndex, 1.16);
        }
        expect(tester.widget<Icon>(find.byIcon(Icons.edit_outlined)).size, 16);
        expect(tester.widget<Text>(find.text('写评论')).style!.fontSize, 13.5);
        final rightActions = find.byKey(
          const ValueKey('feed-detail-actions-capsule'),
        );
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: rightActions,
                  matching: find.byIcon(Icons.thumb_up_outlined),
                ),
              )
              .size,
          24,
        );
        expect(
          tester
              .widgetList<Text>(
                find.descendant(of: rightActions, matching: find.byType(Text)),
              )
              .every((text) => text.style!.fontSize == 9),
          isTrue,
        );
      },
    );
  });
}
