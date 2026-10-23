import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class _MockProductCoolapkApi extends Fake implements CoolapkApi {
  @override
  bool get isAnonymous => false;
  @override
  bool get hasAccount => true;

  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> requestedQueries = [];

  Map<String, dynamic>? mockProductDetail;
  Map<String, dynamic> mockProductConfig = const {};
  final List<String> requestedConfigIds = [];

  @override
  bool get hasCookie => false;

  @override
  String get currentUserAvatar => '';

  @override
  Future<Map<String, dynamic>> getProductDetail(String productId) async {
    requestedPaths.add('/v6/product/detail');
    requestedQueries.add({'id': productId});
    return mockProductDetail ??
        {
          'title': '小米 14',
          'logo': 'http://image.coolapk.com/xiaomi14.png',
          'score': '9.1',
          'hot_num_txt': '120.5万',
          'feed_num_txt': '5.2万',
          'follow_num_txt': '8.6万',
          'comment_num_txt': '1.2万机主点评 8000详细点评',
          'release_time_txt': '2023-10-26',
          'chip': '骁龙 8 Gen 3',
          'screen_size': '6.36 英寸',
          'screen_type': '直屏',
          'battery': '4610mAh',
          'charging': '90W 有线 + 50W 无线',
          'is_follow': 0,
        };
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    if (path == '/v6/product/config') {
      requestedConfigIds.add('${query['id'] ?? ''}');
      return mockProductConfig;
    }
    throw UnimplementedError('Unexpected request: $path');
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requestedPaths.add(path);
    requestedQueries.add(Map<String, dynamic>.from(query));

    if (path == '/v6/page/dataList') {
      final type = query['type']?.toString();
      if (type == 'feed') {
        return const ApiPage(
          items: [
            {
              'id': 10001,
              'entityType': 'feed',
              'message': '手感无敌，续航依旧给力！',
              'username': '极客小明',
              'userAvatar': 'http://image.coolapk.com/avatar1.png',
              'dateline': 1729000000,
              'likenum': 256,
              'replynum': 48,
            },
          ],
          page: 1,
          hasMore: false,
          firstItem: '10001',
          lastItem: '10001',
        );
      }
    }

    return const ApiPage(
      items: [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  Future<void> followProduct(
    String productId, {
    required bool following,
    Map<String, dynamic>? product,
  }) async {
    requestedPaths.add('/v6/product/follow');
  }
}

void main() {
  for (final route in [
    '/topic/tagList?keywords=鸿蒙6&filterId=1&ratingUI=1',
    '#/topic/tagList?keywords=鸿蒙6&filterId=1&ratingUI=1',
    '/page?url=%2Ftopic%2FtagList%3Fkeywords%3D%E9%B8%BF%E8%92%996&filterId=1&ratingUI=1',
  ]) {
    testWidgets('system subtab retains filtered page route: $route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _MockProductCoolapkApi()
        ..mockProductDetail = {
          'title': '华为 Mate',
          'tabList': [
            {'title': '讨论', 'url': '/product/feedList?id=500&type=feed'},
            {'title': '鸿蒙', 'url': route},
          ],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: ProductPage(api: api, id: '500', title: '华为 Mate'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(Tab, '鸿蒙'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      final page = tester
          .widgetList<ApiListPage>(find.byType(ApiListPage))
          .firstWhere((page) => page.title == '鸿蒙');
      expect(page.path, '/v6/page/dataList');
      final url = page.query['url'] as String;
      final target = Uri.parse(url.substring(1));
      expect(target.path, '/topic/tagList');
      expect(target.queryParameters, {
        'keywords': '鸿蒙6',
        'filterId': '1',
        'ratingUI': '1',
      });
    });
  }
  group('ProductPage Tests', () {
    testWidgets(
      'renders ProductPage with default tabs and opens 讨论 tab by default',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = _MockProductCoolapkApi();

        await tester.pumpWidget(
          MaterialApp(
            home: ProductPage(api: mockApi, id: '14339', title: '小米 14'),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        // Header title and specs
        expect(find.text('小米 14'), findsWidgets);
        expect(find.text('9.1'), findsOneWidget);
        expect(find.text('酷安评分'), findsOneWidget);
        expect(find.text('骁龙 8 Gen 3'), findsOneWidget);
        expect(find.text('6.36 英寸'), findsOneWidget);

        // Verify default tabs exist: 参数, 讨论, 点评, 图文, 问答, 视频, 二手
        expect(find.text('参数'), findsOneWidget);
        expect(find.text('讨论'), findsOneWidget);
        expect(find.text('点评'), findsOneWidget);
        expect(find.text('图文'), findsOneWidget);
        expect(find.text('问答'), findsOneWidget);
        expect(find.text('视频'), findsOneWidget);
        expect(find.text('二手'), findsOneWidget);

        // Verify discussion sub-filters exist
        expect(find.text('全部讨论'), findsOneWidget);
        expect(find.text('默认'), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);
        expect(find.text('热度'), findsOneWidget);

        // Verify feed items are displayed (not empty)
        expect(find.textContaining('手感无敌'), findsOneWidget);

        // Verify API query was directed to /v6/page/dataList with url=/page?url=/product/feedList and type=feed
        final dataListRequests = mockApi.requestedQueries
            .where((q) => q['url'] == '/page?url=/product/feedList')
            .toList();
        expect(dataListRequests.isNotEmpty, isTrue);
        final feedRequest = dataListRequests.firstWhere(
          (q) => q['type'] == 'feed',
        );
        expect(feedRequest['id'], '14339');
        expect(feedRequest['listType'], 'lastupdate_desc');
      },
    );

    testWidgets(
      'dynamic tabs update when tabList from server includes subTabFeed',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = _MockProductCoolapkApi();
        mockApi.mockProductDetail = {
          'title': 'vivo X200 Pro',
          'logo': 'http://image.coolapk.com/vivox200.png',
          'score': '9.3',
          'tabList': [
            {
              'title': '参数',
              'url': '/page?url=/product/feedList?id=34676&type=main',
              'is_open': 1,
            },
            {
              'title': '讨论',
              'url': '/page?url=/product/feedList?id=34676&type=feed',
              'is_open': 1,
            },
            {
              'title': '点评',
              'url': '/page?url=/product/feedList?id=34676&type=rating',
              'is_open': 1,
            },
            {
              'title': '样张',
              'url': '/page?url=/product/feedList?id=34676&type=subTabFeed&subId=4',
              'is_open': 1,
            },
            {
              'title': '续航',
              'url': '/page?url=/product/feedList?id=34676&type=subTabFeed&subId=1',
              'is_open': 1,
            },
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            home: ProductPage(
              api: mockApi,
              id: '34676',
              title: 'vivo X200 Pro',
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(find.widgetWithText(Tab, '样张'), findsOneWidget);
        expect(find.widgetWithText(Tab, '续航'), findsOneWidget);
      },
    );

    testWidgets(
      'missing model chip and screen size are loaded from its real config',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = _MockProductCoolapkApi()
          ..mockProductDetail = {
            'title': 'vivo X300 Pro',
            'configRows': [
              {'id': 'config-x300-pro'},
            ],
          }
          ..mockProductConfig = {
            'data': {
              'config_data': {
                '处理器': {'CPU型号': '天玑 9400+'},
                '屏幕与显示': {'屏幕尺寸': '6.78英寸'},
              },
            },
          };

        await tester.pumpWidget(
          MaterialApp(
            home: ProductPage(
              api: mockApi,
              id: '35000',
              title: 'vivo X300 Pro',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.pump();

        expect(mockApi.requestedConfigIds, ['config-x300-pro']);
        expect(find.text('天玑 9400+'), findsOneWidget);
        expect(find.text('6.78英寸'), findsOneWidget);
        expect(find.text('天玑 9500'), findsNothing);
        expect(find.text('6.78 英寸'), findsNothing);
      },
    );

    testWidgets('official spec tags stay complete and in server order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const tags = [
        '2024-10 上市',
        '骁龙 8 至尊版',
        '6.36英寸',
        'LTPO OLED',
        '120Hz',
        '2670×1200',
        '5400mAh',
        '90W有线充电',
        '50W无线充电',
        'IP68',
        '徕卡影像',
        '超声波指纹',
      ];
      final api = _MockProductCoolapkApi()
        ..mockProductDetail = {
          'title': '测试机型',
          'product_specs': tags,
          'chip': '不应覆盖官方标签',
          'configRows': [
            {'id': 'unused-config'},
          ],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: ProductPage(api: api, id: '35002', title: '测试机型'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('product-spec-tags')),
      );
      final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, tags.length * 2 - 1);
      final context = tester.element(
        find.byKey(const ValueKey('product-spec-tags')),
      );
      for (var i = 0; i < tags.length; i++) {
        final tag = delegate.builder(context, i * 2)! as Container;
        expect((tag.child! as Text).data, tags[i]);
      }
      expect(api.requestedConfigIds, isEmpty);
      expect(find.text('不应覆盖官方标签'), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('product-spec-tags')),
        const Offset(-2200, 0),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('超声波指纹'), findsOneWidget);
    });

    testWidgets('missing model specs never display shared fabricated values', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockProductCoolapkApi()
        ..mockProductDetail = {'title': '未知机型'};

      await tester.pumpWidget(
        MaterialApp(
          home: ProductPage(api: mockApi, id: '35001', title: '未知机型'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('天玑 9500'), findsNothing);
      expect(find.text('6.78 英寸'), findsNothing);
      expect(find.text('2025-10-13 上市'), findsNothing);
      expect(find.text('直屏'), findsNothing);
      expect(mockApi.requestedConfigIds, isEmpty);
    });

    testWidgets('tapping sort chips updates listType filter', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = _MockProductCoolapkApi();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductPage(api: mockApi, id: '14339', title: '小米 14'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Tap '最新'
      await tester.tap(find.text('最新'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final latestQueries = mockApi.requestedQueries
          .where((q) => q['listType'] == 'dateline_desc')
          .toList();
      expect(latestQueries.isNotEmpty, isTrue);

      // Tap '热度'
      await tester.tap(find.text('热度'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final hotQueries = mockApi.requestedQueries
          .where((q) => q['listType'] == 'hot_desc')
          .toList();
      expect(hotQueries.isNotEmpty, isTrue);
    });
  });
}
