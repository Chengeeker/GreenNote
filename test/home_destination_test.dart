import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/product_selector.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/feed_vote.dart';
import 'package:greennote/features/shared/home_destination_page.dart';
import 'package:greennote/features/shared/product_selector_page.dart';

const _selectorHtml = '''
<div class="filter-item" data="default">综合</div>
<div class="filter-item" data="hot_num">热度</div>
<div class="filter-item" data="owner_star_average_score">评分</div>
<div class="filter-item" data="follow_num">关注数</div>
<div class="modal-item" data="v4_score_item_1_o_avg_score">续航</div>
<div class="filter-section" data-group="brand_id"><div class="filter-section-title">品牌<button class="expand-button">展开</button></div>
<div class="filter-modal-item" data="1005">苹果</div></div>
<div class="phone-item" data-product-id="100"><div class="phone-name">机型甲</div><div class="phone-image"><img src=""></div><div class="phone-price">¥ 5699</div><div class="phone-specs">芯片 A | 9000mAh</div><div class="phone-specs-tags"><div class="tag-item">评分9.5</div><div class="tag-item">屏幕9.5</div></div></div>
<div class="phone-item" data-product-id="101"><div class="phone-name">机型乙</div><div class="phone-price">¥4499</div><div class="phone-specs">芯片 B</div><div class="phone-specs-tags"></div></div>
''';

ProductSelectorSource selectorSource(List<RequestOptions> requests) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(
          Response(
            requestOptions: request,
            statusCode: 200,
            data: request.method == 'GET'
                ? _selectorHtml
                : jsonEncode({'status': 200, 'data': _selectorHtml}),
          ),
        );
      },
    ),
  );
  return ProductSelectorSource(client: dio);
}

class HomeApi implements CoolapkApi {
  HomeApi({this.hasCookie = true});
  @override
  final bool hasCookie;
  @override
  bool get hasAccount => hasCookie;
  @override
  bool get isAnonymous => false;
  @override
  String get currentUid => '99';
  @override
  String get currentUserAvatar => '';
  @override
  String get loginRequiredMessage => '请先登录';
  @override
  Map<String, String> imageHeadersFor() => {};
  final requests = <String>[];
  final votes = <List<String>>[];
  int follows = 0;
  @override
  Future<void> followUser(String uid, {required bool following}) async {
    follows++;
  }

  @override
  Future<Map<String, dynamic>> submitVote(
    String id,
    List<String> optionIds, {
    bool anonymous = false,
  }) async {
    votes.add(optionIds);
    return {
      'data': {'total_vote_num': 133},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final route = '${query['url'] ?? path}';
    requests.add(route);
    final names = switch (route) {
      'V8_ZHUANTI_20180327' => ['图文', '热门', '教程', '全部'],
      'V8_JINRI_NEWS' => ['全部', '手机', '汽车', 'PC', '配件', 'IoT', '游戏'],
      'V11_ACTIVITIES' => ['众测', '线下', '线上'],
      'V8_RECOMMEND_USER' => ['优质酷友', '推荐关注', '最受欢迎', '今日活跃'],
      'V9_LISHITOUTIAO_NEW' => ['头条榜', '全部头条', '最新动态'],
      'V11_ZHUANTI_EDITORIALDEPARTMENT_20211117' => ['评测与图赏', '邀请函与礼盒'],
      _ => <String>[],
    };
    return ApiPage(
      firstItem: '',
      lastItem: '',
      items: names.isEmpty
          ? [
              {
                'entityType': 'card',
                'entityTemplate': 'configCard',
                'title': '内部配置',
              },
              if (route.contains('V8_RECOMMEND_USER'))
                {
                  'entityType': 'user',
                  'uid': '1',
                  'username': '酷友甲',
                  'follow': 103,
                  'fans': 61067,
                }
              else if (route.contains('V11_ACTIVITIES'))
                {
                  'entityType': 'card',
                  'entityTemplate': 'imageTextGridCard',
                  'entities': [
                    {
                      'entityType': 'imageText',
                      'title': '真实众测',
                      'url': '/event/1086',
                    },
                  ],
                }
              else
                {
                  'entityType': 'feed',
                  'id': '1',
                  'uid': '1',
                  'username': '作者',
                  'message': '内容',
                  'title': '标题',
                  'picArr': [],
                },
            ]
          : [
              if (route == 'V8_JINRI_NEWS')
                {
                  'entityType': 'card',
                  'entityTemplate': 'messageCard',
                  'description': '这里是每日资讯投递平台',
                },
              {
                'entityType': 'card',
                'entityTemplate': 'iconTabLinkGridCard',
                'entities': [
                  for (final name in names)
                    {'title': name, 'url': '#/feed/$route?tab=$name'},
                ],
              },
              {
                'entityType': 'card',
                'entityTemplate': 'configCard',
                'title': '内部配置',
              },
            ],
      page: 1,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(Widget home, {double scale = 1}) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  ),
);

void main() {
  test(
    'server cards with empty titles and URLs retain distinct identities',
    () {
      const first = {
        'entityType': 'card',
        'entityTemplate': 'imageTextGridCard',
        'entityId': 1,
        'title': '',
        'url': '',
      };
      const second = {
        'entityType': 'card',
        'entityTemplate': 'imageTextGridCard',
        'entityId': 2,
        'title': '',
        'url': '',
      };
      expect(coolapkEntityKey(first), isNot(coolapkEntityKey(second)));
      expect(
        coolapkEntityKey({
          ...first,
          'entityId': null,
          'entities': [
            {'url': '/event/1'},
          ],
        }),
        isNot(
          coolapkEntityKey({
            ...first,
            'entityId': null,
            'entities': [
              {'url': '/event/2'},
            ],
          }),
        ),
      );
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('selector parses only actual DOM values and serializes public search filters', () async {
    final data = ProductSelectorData.parse(_selectorHtml);
    expect(data.items.first['title'], '机型甲');
    expect(data.items.first['price'], '¥5699');
    expect(data.filters.single['title'], '品牌');
    expect(data.subScores.keys, ['v4_score_item_1_o_avg_score']);
    final calls = <RequestOptions>[];
    final source = selectorSource(calls);
    await source.load(1);
    await source.load(
      2,
      keyword: '苹果',
      sort: 'hot_num',
      filters: {
        'brand_id': ['1005'],
      },
    );
    expect(calls.last.method, 'POST');
    expect(calls.last.queryParameters, {
      'page': 2,
      'keyWord': '苹果',
      'sortValue': 'hot_num',
    });
    expect(calls.last.data, {'selectedFilters[brand_id][0]': '1005'});
    expect(calls.last.headers.containsKey('Cookie'), isFalse);
    source.dispose();
  });
  for (final entry in homeDestinationEntries.entries) {
    testWidgets('${entry.key} opens official title and server tabs', (
      tester,
    ) async {
      final api = HomeApi();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openHeadlineTarget(context, api, {
                  'title': entry.key,
                  'url': entry.value.$3,
                }),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeDestinationPage), findsOneWidget);
      expect(find.text(entry.value.$2).first, findsOneWidget);
      expect(find.text('内部配置'), findsNothing);
      if (entry.value.$1 != HomeDestination.polls) {
        final bar = tester.widget<TabBar>(find.byType(TabBar));
        expect(bar.tabs.length, greaterThan(1));
        final tab = bar.tabs[1] as Tab;
        await tester.tap(
          find.descendant(
            of: find.byType(TabBar),
            matching: find.text(tab.text!),
          ),
        );
        await tester.pumpAndSettle();
        expect(api.requests.last, contains('tab=${tab.text}'));
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'legacy headline placeholder is handled before generic rank routing',
    (tester) async {
      final api = HomeApi();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openHeadlineTarget(context, api, {
                  'title': '头条榜',
                  'url': '/page?url=V9_HEADLINE_RANK',
                }),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(api.requests.first, 'V9_LISHITOUTIAO_NEW');
      expect(find.text('更多精彩'), findsOneWidget);
    },
  );
  testWidgets('user ranking rows preserve stats and follow action', (
    tester,
  ) async {
    final api = HomeApi();
    await tester.pumpWidget(
      app(
        HomeDestinationPage(
          api: api,
          destination: HomeDestination.users,
          title: '推荐关注',
          route: '/page?url=V8_RECOMMEND_USER',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('103关注  61067粉丝'), findsOneWidget);
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(api.follows, 1);
    expect(find.text('已关注'), findsOneWidget);
  });
  testWidgets('activity cards retain wide poster ratio and readable caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: HomeChannelCard(
            api: HomeApi(),
            destination: HomeDestination.activities,
            entity: const {
              'entityType': 'card',
              'entityTemplate': 'imageTextGridCard',
              'entities': [
                {'title': '真实众测', 'url': '/event/1'},
              ],
            },
          ),
        ),
      ),
    );
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      closeTo(2.22, 0.01),
    );
    expect(find.text('真实众测'), findsOneWidget);
  });
  testWidgets(
    'selector search and compare remain functional at narrow large-text size',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <RequestOptions>[];
      await tester.pumpWidget(
        app(
          ProductSelectorPage(api: HomeApi(), source: selectorSource(calls)),
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('机型甲'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '苹果');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls.last.queryParameters['keyWord'], '苹果');
      await tester.tap(find.text('＋对比').first);
      await tester.pump();
      await tester.tap(find.text('＋对比').first);
      await tester.pump();
      expect(find.text('PK 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'single-choice VS submits real option id and updates returned count',
    (tester) async {
      final api = HomeApi();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: FeedVote(
              api: api,
              feedId: '7',
              vote: const {
                'type': 0,
                'end_time': 9999999999,
                'max_select_num': 1,
                'total_vote_num': 132,
                'total_comment_num': 3,
                'options': [
                  {'id': 10, 'title': '左手'},
                  {'id': 20, 'title': '右手'},
                ],
              },
            ),
          ),
        ),
      );
      expect(find.text('VS'), findsOneWidget);
      await tester.tap(find.text('左手'));
      await tester.pumpAndSettle();
      expect(api.votes, [
        ['10'],
      ]);
      expect(find.text('133人投票 · 3个观点 · 已投票'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('anonymous poll taps never submit a cloud vote', (tester) async {
    final api = HomeApi(hasCookie: false);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: FeedVote(
            api: api,
            feedId: '7',
            vote: const {
              'type': 0,
              'end_time': 9999999999,
              'options': [
                {'id': 10, 'title': '左手'},
                {'id': 20, 'title': '右手'},
              ],
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('左手'));
    await tester.pumpAndSettle();
    expect(api.votes, isEmpty);
    expect(find.text('请先登录'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
