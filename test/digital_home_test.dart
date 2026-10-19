import 'dart:convert';
import 'dart:io';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/digital/views/digital_home_view.dart';
import 'package:greennote/features/digital/widgets/digital_cards.dart';
import 'package:greennote/features/digital/widgets/digital_home_cards.dart';
import 'package:greennote/features/digital/widgets/rank_ribbon.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/feed/feed_pages.dart';

List<Map<String, dynamic>> fixture() => (jsonDecode(
  File('test/fixtures/digital_home.json').readAsStringSync(),
) as List).cast<Map<String, dynamic>>();

class HomeApi extends Fake implements CoolapkApi {
  @override
  String get notificationSessionKey => 'synthetic-home-session';
  HomeApi({this.loggedIn = false});
  bool loggedIn;
  bool anonymous = false;
  LocalAccount? local;
  bool fail = false;
  bool failFollow = false;
  final calls = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> cards = fixture();
  List<Map<String, dynamic>> next = [];
  bool hasMore = false;
  final likes = <String>[];
  @override
  Future<void> likeFeed(String id, {required bool liked}) async {
    likes.add(id);
  }

  List<Map<String, dynamic>> followed = [
    {'entityType': 'product', 'id': 'actual-follow', 'title': '真实关注设备'},
  ];
  @override
  bool get hasCookie => loggedIn;
  @override
  bool get hasAccount => loggedIn || anonymous;
  @override
  bool get isAnonymous => anonymous;
  @override
  LocalAccount get localAccount => local!;
  @override
  String get currentUid => loggedIn ? '123' : '';
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    calls.add({'path': path, ...query});
    if (fail) throw StateError('网络错误');
    final follow = query['url'] == '#/product/followProductList';
    if (follow && failFollow) throw StateError('关注读取失败');
    final page = query['page'] as int? ?? 1;
    return ApiPage(
      items: follow
          ? followed
          : query['url'] == 'V10_DIGITAL_HOME'
          ? (page == 1 ? cards : next)
          : [],
      page: page,
      hasMore: hasMore && page == 1,
      firstItem: 'first',
      lastItem: 'last-$page',
    );
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> query = const {},
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async => {'data': <String, dynamic>{}};
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> showHome(
  WidgetTester tester,
  HomeApi api, {
  double height = 720,
  double scale = 1,
  ValueChanged<String>? onCategory,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(360, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(360, height),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: DigitalHomeView(
              api: api,
              onSelectLibraryCategory: onCategory,
            ),
          ),
        ),
      ),
    ),
  );
  await frames(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'live-shaped modules retain official order and independent grids',
    (tester) async {
      final api = HomeApi();
      await showHome(tester, api, height: 6000);
      final titles = [
        '我的关注',
        '今日热门',
        '热门系统',
        '上市新品',
        '发布日历',
        '性能榜',
        '热门平板',
        '最近流行',
        '高分功能',
        '爆料站',
        '酷友点评',
      ];
      double last = -1;
      for (final title in titles) {
        expect(find.text(title), findsOneWidget);
        final y = tester.getTopLeft(find.text(title)).dy;
        expect(y, greaterThan(last), reason: title);
        last = y;
      }
      expect(find.byType(DigitalCategoryGridCard), findsOneWidget);
      expect(find.byType(DigitalHomeCarousel), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(DigitalCategoryGridCard)).dy,
        greaterThan(tester.getTopLeft(find.text('我的关注')).dy),
      );
      final grids = tester
          .widgetList<DigitalRankGridCard>(find.byType(DigitalRankGridCard))
          .toList();
      expect(grids.map((g) => g.title), [
        '今日热门',
        '热门系统',
        '性能榜',
        '热门平板',
        '高分功能',
      ]);
      expect(grids.map((g) => g.items.length), [8, 8, 8, 8, 4]);
      expect(grids.map((g) => g.showRanking), [
        true,
        false,
        true,
        false,
        false,
      ]);
      expect(find.byType(RankRibbon), findsNWidgets(16));
      expect(find.text('10.15'), findsNWidgets(2));
      expect(find.text('2026'), findsNWidgets(8));
      expect(find.text('第一行正文摘要'), findsNWidgets(3));
      expect(find.text('正常使用一天'), findsNWidgets(3));
      expect(api.calls.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'following uses real page route only when signed in; server card avoids another request',
    (tester) async {
      final api = HomeApi(loggedIn: true);
      await showHome(tester, api);
      expect(find.text('真实关注设备'), findsOneWidget);
      expect(api.calls[1]['url'], '#/product/followProductList');
      await tester.tap(
        find.descendant(
          of: find.byType(DigitalFollowCard),
          matching: find.text('更多'),
        ),
      );
      await frames(tester);
      final page = tester.widget<ApiListPage>(find.byType(ApiListPage));
      expect(page.query['url'], '#/product/followProductList');
      await tester.pumpWidget(const SizedBox());
      api.calls.clear();
      api.cards.insert(0, {
        'entityTemplate': 'followCard',
        'title': '我的关注',
        'entities': api.followed,
      });
      await showHome(tester, api);
      expect(api.calls.length, 1);
      expect(find.text('真实关注设备'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'anonymous UID account shows local followed models on digital home',
    (tester) async {
      final api = HomeApi()..anonymous = true;
      api.local = LocalAccount(await SharedPreferences.getInstance());
      await api.local!.setPublicIdentity(
        uid: '12345',
        username: '公开主页',
        userAvatar: '',
      );
      await api.local!.setActive(true);
      await api.local!.toggle('productFollows', '34001', {
        'id': '34001',
        'title': '本地首页机型',
      });

      await showHome(tester, api);

      expect(find.text('本地首页机型'), findsOneWidget);
      expect(api.calls.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'carousel swipes, auto advances, opens selected banner and boundary does not refresh',
    (tester) async {
      final api = HomeApi();
      api.cards = [
        {
          'entityType': 'card',
          'entityTemplate': 'imageCarouselCard_1',
          'entityId': 'carousel',
          'entities': [
            for (var i = 0; i < 3; i++)
              {
                'title': 'banner$i',
                'url': '#/page?url=BANNER_$i',
                'pic': 'https://example.com/$i.jpg',
              },
          ],
        },
      ];
      await showHome(tester, api);
      final pager = find.byType(PageView);
      PageController controller() => tester.widget<PageView>(pager).controller!;
      await tester.drag(pager, const Offset(180, 30));
      await frames(tester);
      expect(controller().page, closeTo(0, .01));
      expect(api.calls.length, 1);
      await tester.drag(pager, const Offset(-280, 0));
      await frames(tester);
      expect(controller().page, closeTo(1, .01));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 800));
      expect(controller().page, closeTo(2, .01));
      await tester.drag(pager, const Offset(-180, 30));
      await frames(tester);
      expect(controller().page, closeTo(2, .01));
      expect(api.calls.length, 1);
      await tester.tap(pager);
      await frames(tester);
      expect(
        tester.widget<ApiListPage>(find.byType(ApiListPage)).query['url'],
        '#/page?url=BANNER_2',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('vertical pull still refreshes after horizontal protection', (
    tester,
  ) async {
    final api = HomeApi()..cards = [];
    await showHome(tester, api);
    await tester.drag(find.text('我的关注'), const Offset(0, 140));
    await frames(tester);
    expect(api.calls.length, 2);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
  testWidgets('category and module more use the correct destinations', (
    tester,
  ) async {
    String? selected;
    final api = HomeApi();
    await showHome(tester, api, onCategory: (value) => selected = value);
    await tester.tap(find.text('手机'));
    await frames(tester);
    expect(selected, '1000');
    final grid = find.byType(DigitalRankGridCard).first;
    await tester.tap(find.descendant(of: grid, matching: find.text('榜单')));
    await frames(tester);
    expect(
      tester.widget<ApiListPage>(find.byType(ApiListPage)).query['url'],
      api.cards[2]['url'],
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('system grid opens topic rather than product', (tester) async {
    final api = HomeApi();
    api.cards = [api.cards[3]];
    await showHome(tester, api);
    final topic = (api.cards.single['entities'] as List).first as Map;
    await tester.tap(find.text(topic['title']));
    await frames(tester);
    expect(find.byType(TopicPage), findsOneWidget);
    expect(find.byType(ProductPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'refresh errors preserve cards; pagination passes cursors and removes duplicates',
    (tester) async {
      final api = HomeApi();
      api.hasMore = true;
      api.next = [
        api.cards[2],
        {
          'entityType': 'card',
          'entityTemplate': 'iconGridCard',
          'entityId': 'next',
          'title': '下一页模块',
          'entities': [
            {'title': '下一页项目'},
          ],
        },
      ];
      await showHome(tester, api);
      final refresh = tester.widget<EasyRefresh>(find.byType(EasyRefresh));
      api.fail = true;
      expect(await refresh.onRefresh!(), IndicatorResult.fail);
      await frames(tester);
      expect(find.text('今日热门'), findsOneWidget);
      api.fail = false;
      expect(await refresh.onLoad!(), IndicatorResult.noMore);
      await frames(tester);
      expect(api.calls.last['page'], 2);
      expect(api.calls.last['firstItem'], 'first');
      expect(api.calls.last['lastItem'], 'last-1');
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await frames(tester);
      // Count models in the list without making eagerly built widgets a requirement.
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
        14,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'initial error retries and failed following does not hide the homepage',
    (tester) async {
      final api = HomeApi(loggedIn: true)..fail = true;
      await showHome(tester, api);
      expect(find.text('重试'), findsOneWidget);
      api.fail = false;
      api.failFollow = true;
      await tester.tap(find.text('重试'));
      await frames(tester);
      expect(find.text('关注加载失败，点击重试'), findsOneWidget);
      expect(find.text('今日热门'), findsOneWidget);
      api.failFollow = false;
      await tester.tap(find.text('关注加载失败，点击重试'));
      await frames(tester);
      expect(find.text('真实关注设备'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('360dp large type grids, timelines, reviews have no overflow', (
    tester,
  ) async {
    await showHome(tester, HomeApi(), height: 8500, scale: 1.6);
    expect(find.text('酷友点评'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('home review keeps shared author, like and comment actions', (
    tester,
  ) async {
    final api = HomeApi();
    api.cards = [api.cards[11]];
    await showHome(tester, api, height: 3000);
    final review = find.byType(FeedCard).first;
    final raw = (api.cards.single['entities'] as List).first as Map;
    await tester.tap(
      find.descendant(
        of: review,
        matching: find.byIcon(Icons.thumb_up_outlined),
      ),
    );
    await frames(tester);
    expect(api.likes, [raw['id'].toString()]);
    await tester.tap(
      find.descendant(
        of: review,
        matching: find.byKey(const ValueKey('feed-author-link')),
      ),
    );
    await frames(tester);
    expect(find.byType(UserSpacePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await showHome(tester, api, height: 3000);
    await tester.tap(
      find.descendant(
        of: find.byType(FeedCard).first,
        matching: find.byIcon(Icons.chat_bubble_outline_rounded),
      ),
    );
    await frames(tester);
    expect(find.byType(FeedDetailPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'news titles and legacy review metadata tolerate missing structured fields',
    () {
      expect(
        digitalNewsTitle({
          'message_title': '',
          'message': '<b>真实摘要</b>\n下一行',
          'title': '作者的动态',
        }),
        '真实摘要',
      );
      expect(
        digitalHomeExtra({'extraData': '{"withRanking":"1"}'})['withRanking'],
        '1',
      );
      expect(digitalHomeExtra({'extraData': 'invalid'}), isEmpty);
    },
  );
  testWidgets(
    'legacy and malformed rating JSON fall back without fake scores',
    (tester) async {
      final api = HomeApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DigitalHomeRatingBody(
              api: api,
              item: {
                'v4_rating_message': 'broken',
                'comment_good': '真实优点',
                'rating_score': 'NaN',
              },
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('优点'), findsOneWidget);
      expect(find.text('真实优点'), findsOneWidget);
      expect(find.text('评分'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
