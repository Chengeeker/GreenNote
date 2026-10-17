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
