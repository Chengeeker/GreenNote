import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/nine_grid_view.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';
import 'package:greennote/features/shared/discovery_channel_page.dart';

Map<String, dynamic> module(
  String template,
  String title,
  List<Map<String, dynamic>> items,
) => {
  'entityType': 'card',
  'entityTemplate': template,
  'entityId': template,
  'title': title,
  'entities': items,
};
Map<String, dynamic> post(String id) => {
  'id': id,
  'entityType': 'feed',
  'entityTemplate': 'feed',
  'message': '动态$id',
  'uid': '7',
  'username': '作者',
  'replynum': 69,
  'goods': {'price': '29.90'},
  'ershou_info': {'product_price': 999, 'store_type_txt': '闲鱼'},
};

class DiscoveryApi implements CoolapkApi {
  final calls = <(String, Map<String, dynamic>)>[];
  final pages = <String, List<Map<String, dynamic>>>{};
  String? failed;
  int writes = 0;
  @override
  bool get hasCookie => false;
  @override
  bool get isAnonymous => true;
  @override
  String get currentUid => '';
  @override
  String get loginRequiredMessage => '当前为匿名登录，无法使用此功能';
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    writes++;
    return {};
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    calls.add((path, {...query}));
    final route = '${query['url'] ?? path}';
    if (route == failed) throw const CoolapkApiException('模拟失败');
    return ApiPage(
      items: pages[route] ?? [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PagingDiscoveryApi extends DiscoveryApi {
  late Future<ApiPage> Function(String, Map<String, dynamic>) answer;
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) {
    calls.add((path, {...query}));
    return answer(path, query);
  }
}

ApiPage response(
  List<Map<String, dynamic>> rows, {
  bool more = false,
  String first = '',
  String last = '',
}) => ApiPage(
  items: rows,
  page: 1,
  hasMore: more,
  firstItem: first,
  lastItem: last,
);

const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
final _launchedUrls = <String>[];

Future<void> mount(
  WidgetTester tester,
  DiscoveryApi api,
  String title, {
  String route = '/page?url=root',
  double scale = 1,
  double height = 800,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
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
            body: DiscoveryChannelPage(api: api, title: title, route: route),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'cool pictures use three image columns and open the original post gallery',
    (tester) async {
      final api = DiscoveryApi()
        ..pages['root'] = [
          for (var i = 0; i < 6; i++)
            {
              ...post('$i'),
              'picArr': [
                {
                  'url': 'https://example.com/picture-$i.jpg',
                  'width': 300,
                  'height': 450 + i * 30,
                },
                {
                  'url': 'https://example.com/second-$i.jpg',
                  'width': 300,
                  'height': 600,
                },
              ],
            },
        ];
      await mount(tester, api, '酷图', settle: false);
      expect(find.byType(FeedCard), findsNothing);
      final tiles = find.byType(DiscoveryPictureTile);
      expect(tiles.evaluate().length, 12);
      final positions = <Offset>[];
      for (final item in [('0', 0), ('0', 1), ('1', 0)]) {
        final tile = find.byWidgetPredicate(
          (w) =>
              w is DiscoveryPictureTile &&
              w.row['id'] == item.$1 &&
              w.imageIndex == item.$2,
        );
        positions.add(tester.getTopLeft(tile));
        final size = tester.getSize(tile);
        expect(size.width, lessThan(tester.view.physicalSize.width / 2));
      }
      expect(positions.map((p) => p.dx).toSet(), hasLength(3));
      expect(positions.map((p) => p.dy).toSet(), hasLength(1));
      final firstImage = find.byWidgetPredicate(
        (w) =>
            w is DiscoveryPictureTile &&
            w.row['id'] == '0' &&
            w.imageIndex == 0,
      );
      final secondImage = find.byWidgetPredicate(
        (w) =>
            w is DiscoveryPictureTile &&
            w.row['id'] == '0' &&
            w.imageIndex == 1,
      );
      expect(
        tester.getSize(secondImage).height,
        greaterThan(tester.getSize(firstImage).height),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DiscoveryPictureTile &&
              w.row['id'] == '0' &&
              w.imageIndex == 1,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final gallery = tester.widget<ImageGalleryPage>(
        find.byType(ImageGalleryPage),
      );
      expect(gallery.feed?.id, '0');
      expect(gallery.feed?.uid, '7');
      expect(gallery.pics, hasLength(2));
      expect(gallery.initialIndex, 1);
      expect(gallery.pics.first.url, 'https://example.com/picture-0.jpg');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _launchedUrls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, (call) async {
          if (call.method == 'launch') {
            _launchedUrls.add(
              (call.arguments as Map<Object?, Object?>)['url']! as String,
            );
          }
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcherChannel, null),
  );
  testWidgets('secondhand notice hides HTML and keeps its agreement link', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        {
          'entityType': 'card',
          'entityTemplate': 'messageCard',
          'description': '交易须知，查看<a href="https://m.coolapk.com/mp/user/ershouAgreement">【安全条款】</a>。',
        },
      ];
    await mount(tester, api, '二手');
    expect(find.text('【安全条款】'), findsOneWidget);
    expect(find.textContaining('<a href'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pagination preserves cursors and removes duplicate feeds', (
    tester,
  ) async {
    final api = PagingDiscoveryApi()
      ..answer = (path, query) async {
        if (query['page'] == 1) {
          return response(
            List.generate(8, (i) => post('${i + 1}')),
            more: true,
            first: 'first',
            last: 'last',
          );
        }
        return response([post('8'), post('9')]);
      };
    await mount(tester, api, '宠物');
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(2));
    expect(api.calls.last.$2, containsPair('page', 2));
    expect(api.calls.last.$2, containsPair('firstItem', 'first'));
    expect(api.calls.last.$2, containsPair('lastItem', 'last'));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final ids = tester
        .widgetList<FeedCard>(find.byType(FeedCard))
        .map((card) => card.feed.id)
        .toList();
    expect(ids.where((id) => id == '8'), hasLength(1));
    expect(ids.where((id) => id == '9'), hasLength(1));
    expect(api.calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('stale sort response cannot replace a newer selection', (
    tester,
  ) async {
    final pending = Completer<ApiPage>();
    final api = PagingDiscoveryApi()
      ..answer = (path, query) async {
        if (query['url'] == '#/hot') return pending.future;
        if (query['url'] == '#/recent') return response([post('3')]);
        return response([
          module('sortSelectCard', '动态区', [
            {'title': '最近回复', 'url': '#/recent'},
            {'title': '热门排序', 'url': '#/hot'},
          ]),
          post('1'),
        ]);
      };
    await mount(tester, api, '宠物');
    await tester.tap(find.text('热门排序'));
    await tester.pump();
    await tester.tap(find.text('最近回复'));
    await tester.pumpAndSettle();
    pending.complete(response([post('2')]));
    await tester.pumpAndSettle();
    expect(tester.widget<FeedCard>(find.byType(FeedCard)).feed.id, '3');
    expect(tester.takeException(), isNull);
  });
  testWidgets('horizontal categories do not invoke vertical refresh', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        module(
          'imageSquareScrollCard',
          '',
          List.generate(7, (i) => {'title': '分类$i', 'url': '/t/category$i'}),
        ),
        for (var i = 0; i < 15; i++)
          {
            ...post('$i'),
            'picArr': [
              {'url': 'https://example.com/picture-$i.jpg'},
            ],
          },
      ];
    await mount(tester, api, '酷图', settle: false);
    final before = api.calls.length;
    await tester.drag(find.text('分类2'), const Offset(190, 12));
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.calls, hasLength(before));
    expect(tester.takeException(), isNull);
  });
  test(
    'discovery routes preserve nested flex URL and clear unresolved guest UID',
    () {
      expect(discoveryPageRequest('/page?url=V15_CHONGWU').query, {
        'url': 'V15_CHONGWU',
      });
      expect(
        discoveryPageRequest('/user/dyhSubscribe').path,
        '/v6/user/dyhSubscribe',
      );
      expect(
        discoveryPageRequest(r'/goods/goodsFeedList?uid=${uid}&type=store')
            .query,
        {'url': '/goods/goodsFeedList?uid=&type=store'},
      );
    },
  );
  testWidgets(
    'pet sort retains headers when API only returns feeds and on error',
    (tester) async {
      final api = DiscoveryApi()
        ..pages['root'] = [
          module('iconMiniGridCard', '讨论区', [
            {'title': '乌龟', 'url': '/t/乌龟'},
          ]),
          module('sortSelectCard', '动态区', [
            {'title': '最近回复', 'url': '#/recent'},
            {'title': '热门排序', 'url': '#/hot'},
          ]),
          post('1'),
        ];
      api.pages['#/hot'] = [post('2')];
      await mount(tester, api, '宠物');
      await tester.tap(find.text('热门排序'));
      await tester.pumpAndSettle();
      expect(find.text('讨论区'), findsOneWidget);
      expect(find.text('最近回复'), findsOneWidget);
      expect(find.byType(FeedCard), findsOneWidget);
      expect(tester.widget<FeedCard>(find.byType(FeedCard)).feed.id, '2');
      api.failed = '#/recent';
      await tester.tap(find.text('最近回复'));
      await tester.pumpAndSettle();
      expect(find.text('讨论区'), findsOneWidget);
      expect(tester.widget<FeedCard>(find.byType(FeedCard)).feed.id, '2');
      expect(find.textContaining('模拟失败'), findsOneWidget);
      api.failed = null;
      api.pages['#/recent'] = [post('3')];
      await tester.tap(find.textContaining('加载失败，点击重试'));
      await tester.pumpAndSettle();
      expect(api.calls.last.$2['page'], 1);
      expect(api.calls.last.$2['url'], '#/recent');
      expect(tester.widget<FeedCard>(find.byType(FeedCard)).feed.id, '3');
      expect(tester.takeException(), isNull);
    },
  );
  for (final title in ['二手', '商家']) {
    testWidgets('$title loads config headers then real flex waterfall', (
      tester,
    ) async {
      final api = DiscoveryApi()
        ..pages['root'] = [
          module('iconLinkGridCard', '', [
            {'title': '分类', 'url': '/page?url=categories'},
          ]),
          {
            ...module('configCard', '后台配置', []),
            'extraData': '{"flexList":"1","url":"#/flow"}',
          },
        ];
      api.pages['#/flow'] = [post('1'), post('2'), post('3')];
      await mount(tester, api, title, scale: 1.6);
      expect(api.calls.map((e) => e.$2['url']), ['root', '#/flow']);
      expect(find.byType(SliverCrossAxisGroup), findsOneWidget);
      expect(find.byType(DiscoveryWaterfallCard), findsNWidgets(3));
      expect(find.text('后台配置'), findsNothing);
      expect(find.text(title == '二手' ? '¥999' : '¥29.90'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('cool pictures use server categories and inline shortcut feed', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        module('imageSquareScrollCard', '', [
          {'title': '#风景#', 'url': '/t/风景'},
        ]),
        module('iconLinkGridCard', '', [
          {'title': '热门', 'url': '#/pictureHot'},
          {'title': '2K', 'url': '#/picture2k'},
        ]),
        {
          ...post('1'),
          'picArr': [
            {'url': 'https://example.com/picture-1.jpg'},
          ],
        },
      ];
    api.pages['#/picture2k'] = [
      {
        ...post('2'),
        'picArr': [
          {'url': 'https://example.com/picture-2.jpg'},
        ],
      },
    ];
    await mount(tester, api, '酷图', settle: false);
    await tester.tap(find.text('2K'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('#风景#'), findsOneWidget);
    expect(api.calls.last.$2['url'], '#/picture2k');
    expect(
      tester
          .widget<DiscoveryPictureTile>(find.byType(DiscoveryPictureTile))
          .row['id'],
      '2',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('cool products use official modules and real destinations', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        {
          ...module('imageCarouselCard_1', '', [
            {
              'entityType': 'image_1',
              'title': 'jd',
              'url': 'https://u.jd.com/qO7urjj',
              'pic': 'https://image.coolapk.com/banner@1920x640.jpg',
            },
          ]),
          'entityId': 'banner',
        },
        {
          ...module('iconButtonGridCard', '', [
            {
              'entityType': 'iconButton',
              'url': 'https://u.jd.com/promo',
              'pic': 'https://image.coolapk.com/jd@386x157.jpg',
            },
            {
              'entityType': 'iconButton',
              'url': 'https://s.click.taobao.com/promo',
              'pic': 'https://image.coolapk.com/tmall@386x157.jpg',
            },
          ]),
          'entityId': '33005',
        },
        {
          ...module('iconButtonGridCard', '', [
            {
              'entityType': 'iconButton',
              'url':
                  'https://www.coolapk.com/link?url=https%3A%2F%2Fshop.example',
              'pic': 'https://image.coolapk.com/meituan@500x225.jpg',
            },
            {
              'entityType': 'iconButton',
              'url': '/clickUrl/csjNewInterAction?posId=103',
              'pic': 'https://image.coolapk.com/douyin@343x154.jpg',
            },
          ]),
          'entityId': '34938',
        },
        module('iconLinkGridCard', '', [
          {
            'title': '酷安授权店',
            'url':
                'https://www.coolapk.com/link?url=https%3A%2F%2Fshop.example',
            'pic': '',
          },
          {
            'title': '9.9包邮',
            'url': '#/goods/materialGoodsList?eliteId=4',
            'pic': '',
          },
          {
            'title': '外卖补贴',
            'url': 'https://coupons.example/takeout',
            'pic': '',
          },
          {'title': '专属礼金', 'url': 'https://coupons.example/gift', 'pic': ''},
          {
            'title': '隐藏优惠券',
            'url': 'https://coupons.example/search',
            'pic': '',
          },
        ]),
        {
          ...module(
            'iconLargeScrollCard',
            '大家都在买',
            List.generate(
              3,
              (i) => {
                'entityType': 'pear_goods',
                'goods_title': '商品$i',
                'goods_pic': 'https://image.coolapk.com/item$i@300x300.jpg',
                'goods_promo_title': '券后26.29元',
                'goods_buy_text': '领50元券',
                'goods_url': 'https://item.example/product?sku=$i',
                'goods_buy_url': 'https://coupon.example/buy?sku=$i',
              },
            ),
          ),
          'url': '#/goods/jingfenGoodsList?eliteId=41&title=大家都在买',
        },
        {
          'entityType': 'pear_goods',
          'title': '更多商品',
          'goods_title': '更多商品',
          'goods_pic': 'https://image.coolapk.com/list@300x300.jpg',
          'goods_promo_title': '券后10.99元',
          'goods_buy_text': '前往购买',
          'goods_url': 'https://item.example/product?sku=list',
          'goods_buy_url': 'https://item.example/buy?sku=list',
        },
      ];

    await mount(tester, api, '酷品', height: 1800, settle: false);
    final banner = find.byKey(const ValueKey('cool-products-banner'));
    expect(banner, findsOneWidget);
    expect(tester.getSize(banner).height, closeTo(344 / 3, 1));
    final promo = find.byKey(const ValueKey('cool-products-promo-33005-0'));
    expect(
      tester.getSize(promo).width / tester.getSize(promo).height,
      closeTo(386 / 157, 0.05),
    );
    expect(find.text('酷安内容'), findsNothing);
    expect(find.text('大家都在买'), findsOneWidget);
    expect(find.text('商品0'), findsOneWidget);
    expect(find.text('券后26.29元'), findsWidgets);
    expect(find.text('更多商品'), findsOneWidget);
    final labels = [
      '酷安授权店',
      '9.9包邮',
      '外卖补贴',
      '专属礼金',
      '隐藏优惠券',
    ].map(find.text).toList();
    expect(labels.every((finder) => finder.evaluate().length == 1), isTrue);
    expect(
      labels.map((finder) => tester.getTopLeft(finder).dy).toSet(),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('大家都在买'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      api.calls.last.$2['url'],
      '#/goods/jingfenGoodsList?eliteId=41&title=大家都在买',
    );
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('9.9包邮'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls.last.$2['url'], '#/goods/materialGoodsList?eliteId=4');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(banner);
    await tester.pump();
    expect(_launchedUrls.last, 'https://u.jd.com/qO7urjj');
    await tester.tap(find.byKey(const ValueKey('cool-products-promo-34938-1')));
    await tester.pump();
    expect(
      _launchedUrls.last,
      'https://api.coolapk.com/clickUrl/csjNewInterAction?posId=103',
    );
    await tester.tap(find.byKey(const ValueKey('cool-products-item-0')));
    await tester.pump();
    expect(_launchedUrls.last, 'https://item.example/product?sku=0');
    await tester.tap(find.text('领50元券').first);
    await tester.pump();
    expect(_launchedUrls.last, 'https://coupon.example/buy?sku=0');
    await tester.tap(find.text('更多商品'));
    await tester.pump();
    expect(_launchedUrls.last, 'https://item.example/product?sku=list');
    await tester.tap(find.text('前往购买'));
    await tester.pump();
    expect(_launchedUrls.last, 'https://item.example/buy?sku=list');
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
  });
  testWidgets('sports equipment keeps four columns and real product names', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        module(
          'iconLongTitleGridCard',
          '运动装备',
          List.generate(
            8,
            (i) => {
              'title': '装备$i',
              'url': '/product/${i + 1}',
              'entityType': 'product',
            },
          ),
        ),
      ];
    await mount(tester, api, '运动', scale: 1.6);
    expect(find.text('装备7'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('装备0')).dy,
      tester.getTopLeft(find.text('装备3')).dy,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('anonymous subscription button never sends cloud write', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        module('unLoginCard', '', []),
        module('iconLongTitleGridCard', '站内订阅', [
          {'id': 1, 'title': '看看号甲', 'entityType': 'dyh', 'follownum': 8034},
        ]),
      ];
    await mount(tester, api, '看看号');
    await tester.tap(find.text('订阅'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('我订阅的看看号'), findsOneWidget);
    expect(find.text('8034人订阅'), findsOneWidget);
    expect(api.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('goods ranking reads nested real item prices and totals', (
    tester,
  ) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        {
          ...post('1'),
          'entityTemplate': 'goodsRankingCard',
          'title': '推荐鼠标',
          'goodsListInfo': {'item_num': 45, 'vote_num': 1269},
          'goodsListItem': List.generate(
            3,
            (i) => {
              'product_goods_title': '鼠标$i',
              'price': '149.00',
              'url': '/goods/$i',
            },
          ),
        },
      ];
    await mount(tester, api, '好物榜');
    expect(find.text('¥149.00'), findsNWidgets(3));
    expect(find.text('45个好物 · 1269人投票'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dyh article uses real source relation header', (tester) async {
    final api = DiscoveryApi()
      ..pages['root'] = [
        {
          ...post('1'),
          'entityTemplate': 'articleItem',
          'relationRows': [
            {'title': '值得细品的观点', 'url': '/dyh/1', 'logo': ''},
          ],
        },
      ];
    await mount(tester, api, '看看号');
    expect(find.byType(DiscoveryArticleHeader), findsOneWidget);
    expect(find.text('来自 作者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'joined five pictures keep original order and Hero scope in 2+3 rows',
    (tester) async {
      final api = DiscoveryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: NineGridView(
                api: api,
                statusId: 'five',
                joinedImages: true,
                pics: List.generate(
                  5,
                  (i) => GalleryImage('https://image.coolapk.com/$i.jpg'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final tiles = tester
          .widgetList<ImageGalleryHeroThumbnail>(
            find.byType(ImageGalleryHeroThumbnail),
          )
          .toList();
      expect(tiles.map((tile) => tile.index), [0, 1, 2, 3, 4]);
      expect(tiles.map((tile) => tile.scope).toSet(), hasLength(1));
      final finder = find.byType(ImageGalleryHeroThumbnail);
      expect(
        tester.getTopLeft(finder.at(0)).dy,
        tester.getTopLeft(finder.at(1)).dy,
      );
      expect(
        tester.getTopLeft(finder.at(2)).dy,
        tester.getTopLeft(finder.at(4)).dy,
      );
      expect(
        tester.getSize(finder.at(0)).width,
        greaterThan(tester.getSize(finder.at(2)).width),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
