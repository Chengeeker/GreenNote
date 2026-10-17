import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/utils/spring_page_route.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';
import 'package:greennote/features/shared/app_market_page.dart';
import 'package:greennote/features/shared/app_management_page.dart';
import 'package:greennote/features/shared/app_detail_page.dart';

const app = <String, dynamic>{
  'entityType': 'apk',
  'id': '123',
  'title': '测试应用',
  'apkname': 'com.example.app',
  'apkversioncode': '10',
  'downCount': '431万',
  'commentnum': 899,
};

class MarketApi implements CoolapkApi {
  final requests = <(String, Map<String, dynamic>)>[];
  bool fail = false;
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    requests.add((path, query));
    return {
      'data': {'description': '真实应用集简介'},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requests.add((path, query));
    if (fail) throw const CoolapkApiException('商城请求失败');
    final rows = switch (query['url']) {
      'V10_MARKET_HOME' => <Map<String, dynamic>>[
        {
          'entityTemplate': 'linkCard',
          'entities': [
            {'title': '应用分类', 'url': '/apk/categoryList?apkType=1'},
            {'title': '游戏分类', 'url': '/apk/categoryList?apkType=2'},
            {'title': '今日更新', 'url': '/apk/updateList'},
            {'title': '好软推荐', 'url': '/apk/recommendList'},
          ],
        },
        {
          'entityTemplate': 'apkImageCard',
          'entities': [
            {...app, 'subTitle': '联动活动'},
          ],
        },
        {
          'entityTemplate': 'apkListCard',
          'title': '酷友刚刚关注',
          'entities': [app],
        },
        {'entityTemplate': 'configCard', 'title': '内部配置'},
      ],
      'V10_MARKET_RANK' => <Map<String, dynamic>>[
        {
          'entityTemplate': 'selectorLinkCard',
          'entities': [
            {'title': '全站榜', 'url': '#/apk/realRankList?apkType=0'},
            {'title': '应用榜', 'url': '#/apk/realRankList?apkType=1'},
          ],
        },
      ],
      _ => <Map<String, dynamic>>[app],
    };
    return ApiPage(
      items: rows,
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ),
);

class ScreenshotApi extends MarketApi {
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async => {
    'data': {
      ...app,
      'screenList': ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    },
  };
}

void main() {
  testWidgets(
    'app screenshots use the gallery route without Material page transition',
    (tester) async {
      await tester.pumpWidget(
        host(AppDetailPage(api: ScreenshotApi(), id: 'com.example.app')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final thumbnail = find.byType(ImageGalleryHeroThumbnail).at(1);
      await tester.ensureVisible(thumbnail);
      await tester.pump(const Duration(milliseconds: 300));
      final scope = tester.widget<ImageGalleryHeroThumbnail>(thumbnail).scope;
      await tester.tap(thumbnail);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final gallery = find.byType(ImageGalleryPage);
      final route = ModalRoute.of(tester.element(gallery));
      expect(route, isA<PhysicsSpringGalleryRoute<void>>());
      expect(route, isNot(isA<MaterialPageRoute<void>>()));
      expect(route!.transitionDuration, const Duration(milliseconds: 220));
      expect(tester.widget<ImageGalleryPage>(gallery).initialIndex, 1);
      expect(tester.widget<ImageGalleryPage>(gallery).heroScope, same(scope));
      await tester.pump(const Duration(milliseconds: 250));
      Navigator.of(tester.element(gallery)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ImageGalleryPage), findsNothing);
      expect(find.byType(AppDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('market routes retain native query and never substitute feed rank', () {
    expect(marketRequest('/apk/updateList').path, '/v6/apk/updateList');
    final category = marketRequest('/apk/categoryList?apkType=2');
    expect(category.path, '/v6/apk/categoryList');
    expect(category.query['apkType'], '2');
    final recommendation = marketRequest('/apk/recommendList');
    expect(recommendation.path, '/v6/apk/recommendList');
    expect(recommendation.query['apkType'], '1');
    expect(recommendation.query['title'], '好软推荐');
    final customRecommendation = marketRequest(
      '/apk/recommendList?apkType=2&title=自定义推荐',
    );
    expect(customRecommendation.query['apkType'], '2');
    expect(customRecommendation.query['title'], '自定义推荐');
    final rank = marketRequest('#/apk/realRankList?apkType=1');
    expect(rank.path, '/v6/page/dataList');
    expect(rank.query['url'], '#/apk/realRankList?apkType=1');
    expect(
      marketRequest('/page?url=V10_MARKET_HOME').query['url'],
      'V10_MARKET_HOME',
    );
    expect(
      marketExtra({
        'extraData': jsonEncode({'cover': 'x'}),
      })['cover'],
      'x',
    );
    expect(marketExtra({'extraData': '{broken'}), isEmpty);
  });

  testWidgets('store starts at official selection and visits tabs on demand', (
    tester,
  ) async {
    final api = MarketApi();
    await tester.pumpWidget(host(AppMarketPage(api: api)));
    await tester.pumpAndSettle();
    expect(api.requests.map((r) => r.$2['url']), ['V10_MARKET_HOME']);
    for (final title in [
      '精选',
      '应用',
      '游戏',
      '应用集',
      '排行',
      '应用分类',
      '游戏分类',
      '今日更新',
      '好软推荐',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('内部配置'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('酷友刚刚关注'), findsOneWidget);
    expect(find.text('431万下载  899评论'), findsWidgets);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(api.requests.any((r) => r.$2['url'] == 'V8_MARKET_APP'), isTrue);
    final count = api.requests
        .where((r) => r.$2['url'] == 'V10_MARKET_HOME')
        .length;
    await tester.tap(find.text('精选'));
    await tester.pumpAndSettle();
    expect(
      api.requests.where((r) => r.$2['url'] == 'V10_MARKET_HOME').length,
      count,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('store toolbar opens app management', (tester) async {
    const channel = MethodChannel('com.green.note/app_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => <Object?>[]);
    try {
      await tester.pumpWidget(host(AppMarketPage(api: MarketApi())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('应用管理'));
      await tester.pumpAndSettle();
      expect(find.byType(AppManagementPage), findsOneWidget);
      expect(find.text('应用管理'), findsOneWidget);
      expect(find.text('显示系统预装应用'), findsOneWidget);
      expect(find.text('检查应用更新'), findsNothing);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
    'update shortcut opens list instead of treating endpoint as package',
    (tester) async {
      final api = MarketApi();
      await tester.pumpWidget(host(AppMarketPage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日更新'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDetailPage), findsNothing);
      expect(api.requests.last.$1, '/v6/apk/updateList');
    },
  );

  testWidgets(
    'good software shortcut loads recommendation with official query',
    (tester) async {
      final api = MarketApi();
      await tester.pumpWidget(host(AppMarketPage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('好软推荐'));
      await tester.pumpAndSettle();
      expect(api.requests.last.$1, '/v6/apk/recommendList');
      expect(api.requests.last.$2['apkType'], '1');
      expect(api.requests.last.$2['title'], '好软推荐');
      expect(find.byType(AppDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rank selector stays in store and sends exact server route', (
    tester,
  ) async {
    final api = MarketApi();
    await tester.pumpWidget(host(AppMarketPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用榜'));
    await tester.pumpAndSettle();
    expect(api.requests.last.$1, '/v6/page/dataList');
    expect(api.requests.last.$2['url'], '#/apk/realRankList?apkType=1');
    expect(find.text('全站榜'), findsOneWidget);
    expect(find.text('应用榜'), findsOneWidget);
  });

  testWidgets('failure remains visible and retry reloads store', (
    tester,
  ) async {
    final api = MarketApi()..fail = true;
    await tester.pumpWidget(host(AppMarketPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('商城请求失败'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('应用分类'), findsOneWidget);
  });

  testWidgets('album opens detail and paginated apk list', (tester) async {
    final api = MarketApi();
    await tester.pumpWidget(
      host(
        Scaffold(
          body: MarketCard(
            api: api,
            data: {
              'entityType': 'album',
              'id': '42',
              'url': '/album/42',
              'title': '应用集甲',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用集甲'));
    await tester.pumpAndSettle();
    expect(api.requests.map((r) => r.$1), [
      '/v6/album/detail',
      '/v6/album/apkList',
    ]);
    expect(api.requests.last.$2['id'], '42');
    expect(find.text('真实应用集简介'), findsOneWidget);
    expect(find.text('测试应用'), findsOneWidget);
  });

  testWidgets(
    'video uses metadata duration and banner ignores configuration children',
    (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: MarketCard(
              api: MarketApi(),
              data: {
                'entityTemplate': 'apkImageCard',
                'entities': [
                  {
                    ...app,
                    'videoParams': jsonEncode({
                      'duration': 61230,
                      'requestParams': '{}',
                    }),
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('00:01:01'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: MarketCard(
              api: MarketApi(),
              data: {
                'entityTemplate': 'imageScaleCard',
                'extraDataArr': {'dimensionRatio': '984:450'},
                'entities': [
                  {'title': '内部配置不可渲染'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内部配置不可渲染'), findsNothing);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        984 / 450,
      );
    },
  );

  testWidgets('360dp and large text do not overflow cards or shortcuts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(AppMarketPage(api: MarketApi()), textScale: 1.6),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: MarketCard(
            api: MarketApi(),
            data: {
              'entityTemplate': 'apkScrollCard',
              'entities': [app, app],
            },
          ),
        ),
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
