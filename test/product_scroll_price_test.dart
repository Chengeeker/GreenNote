import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/product_price.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class ProductLayoutApi extends Fake implements CoolapkApi {
  @override
  bool get hasAccount => true;

  final queries = <Map<String, dynamic>>[];
  int configRequests = 0;
  int followRequests = 0;
  bool initiallyFollowing = false;
  bool failFollow = false;

  @override
  bool get hasCookie => false;
  @override
  bool get isAnonymous => false;
  @override
  String get currentUid => '';
  @override
  String get currentUserAvatar => '';

  @override
  Future<Map<String, dynamic>> getProductDetail(String id) async => {
    'title': 'REDMI K100 Pro Max',
    'star_average_score': '8.9',
    'userAction': {'follow': initiallyFollowing ? '1' : '0'},
    'subtab_statistics_item6':
        '{"final_price":2199,"update_time":"2026-08-29 16:20"}',
    'configRows': [
      {'id': 9030, 'title': '12GB+256GB'},
      {'id': 9033, 'title': '16GB+512GB'},
    ],
    'tabList': [
      {
        'title': '参数',
        'url': '/page?url=%2Fproduct%2FfeedList%3Ftype%3Dmain%26id%3D5636',
      },
      {
        'title': '讨论',
        'url': '/page?url=%2Fproduct%2FfeedList%3Ftype%3Dfeed%26id%3D5636',
      },
      {
        'title': '到手价',
        'url': '/page?url=%2Fproduct%2FfeedList%3Ftype%3DsubTabFeed%26withSortCard%3D1%26id%3D5636%26subId%3D6',
      },
    ],
  };

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    queries.add(Map.of(query));
    return ApiPage(
      items: [
        {
          'id': '74390506',
          'entityType': 'feed',
          'username': '燕麦纯牛奶',
          'message': '4000内拿下已经很满足了',
          'tsubid': 6,
          'tsubdata': '{"final_price":3980,"config_name":"16GB+512GB","config_id":9033}',
        },
        {
          'id': '74366281',
          'entityType': 'feed',
          'username': '晨风花草春',
          'message': '最低配3199算便宜吗',
          'tsubid': '6',
          'tsubdata': {
            'final_price': 3199,
            'config_name': '12GB+256GB',
            'config_id': 9030,
          },
        },
      ],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    expect(path, '/v6/product/config');
    configRequests++;
    return {
      'data': {
        'id': query['id'],
        'config_data': {
          '性能': {
            'SoC型号': '真实配置处理器',
            'RAM容量': query['id'] == '9030' ? '12' : '16',
          },
          '屏幕': {for (var i = 0; i < 35; i++) '参数$i': '实测字段$i'},
        },
      },
    };
  }

  @override
  Future<void> followProduct(
    String id, {
    required bool following,
    Map<String, dynamic>? product,
  }) async {
    followRequests++;
    if (failFollow) throw const CoolapkApiException('测试关注失败');
  }
}

Future<void> openProduct(
  WidgetTester tester,
  ProductLayoutApi api, {
  Size size = const Size(420, 933),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      theme: ThemeData.dark(useMaterial3: true),
      home: ProductPage(api: api, id: '5636'),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> settleProduct(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  test('price payloads accept JSON/maps and reject missing, malformed and nonfinite prices', () {
    expect(ProductPrice.tryParse('{"final_price":2199}')?.formatted, '2199');
    expect(
      ProductPrice.tryParse({'final_price': '2199.50'})?.formatted,
      '2199.5',
    );
    for (final value in [
      null,
      '',
      'oops',
      '[]',
      {},
      {'final_price': 0},
      {'final_price': -1},
      {'final_price': 'NaN'},
      {'final_price': 'Infinity'},
    ]) {
      expect(ProductPrice.tryParse(value), isNull);
    }
  });

  testWidgets(
    'outer header collapse exposes model, rating and working follow action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final api = ProductLayoutApi();
      await openProduct(tester, api);
      expect(
        find.byKey(const ValueKey('product-compact-header')),
        findsNothing,
      );
      final nested = tester.state<NestedScrollViewState>(
        find.byKey(const ValueKey('product-nested-scroll')),
      );
      nested.outerController.jumpTo(
        nested.outerController.position.maxScrollExtent,
      );
      await settleProduct(tester);
      expect(
        find.byKey(const ValueKey('product-compact-header')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('机型评分 8.9 分')), findsOneWidget);
      semantics.dispose();
      await tester.tap(find.byKey(const ValueKey('product-compact-follow')));
      await tester.pump();
      expect(api.followRequests, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('product-compact-follow')),
          matching: find.text('已关注'),
        ),
        findsOneWidget,
      );
      nested.outerController.jumpTo(0);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('product-compact-header')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact follow reads server state and restores it on failure', (
    tester,
  ) async {
    final api = ProductLayoutApi()
      ..initiallyFollowing = true
      ..failFollow = true;
    await openProduct(tester, api);
    final nested = tester.state<NestedScrollViewState>(
      find.byKey(const ValueKey('product-nested-scroll')),
    );
    nested.outerController.jumpTo(
      nested.outerController.position.maxScrollExtent,
    );
    await settleProduct(tester);
    final button = find.byKey(const ValueKey('product-compact-follow'));
    expect(
      find.descendant(of: button, matching: find.text('已关注')),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    expect(api.followRequests, 1);
    expect(
      find.descendant(of: button, matching: find.text('已关注')),
      findsOneWidget,
    );
    expect(find.textContaining('测试关注失败'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'price tab shows server minimum, timestamp, per-post price and live sort requests',
    (tester) async {
      final api = ProductLayoutApi();
      await openProduct(tester, api);
      await tester.tap(find.widgetWithText(Tab, '到手价'));
      await settleProduct(tester);
      final nested = tester.state<NestedScrollViewState>(
        find.byKey(const ValueKey('product-nested-scroll')),
      );
      nested.outerController.jumpTo(
        nested.outerController.position.maxScrollExtent,
      );
      await settleProduct(tester);
      expect(
        find.byKey(const ValueKey('product-price-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('当前最低价'), findsOneWidget);
      expect(find.text('发布时间：2026-08-29 16:20'), findsOneWidget);
      expect(find.text('¥3980'), findsWidgets);
      expect(find.text('¥3199'), findsWidgets);
      expect(find.text('16GB+512GB'), findsWidgets);
      expect(
        find.byKey(const ValueKey('feed-product-price')),
        findsNWidgets(2),
      );
      final tabsBottom = tester.getBottomLeft(find.byType(TabBar)).dy;
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('product-price-summary')))
            .dy,
        greaterThanOrEqualTo(tabsBottom),
      );
      await tester.tap(find.text('热度').hitTestable());
      await settleProduct(tester);
      expect(api.queries.last['subId'], '6');
      expect(api.queries.last['listType'], 'rank_score');
      await tester.tap(find.text('最新').hitTestable());
      await settleProduct(tester);
      expect(api.queries.last['listType'], 'dateline_desc');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parameter scroll uses real config once and retains it across tab switches',
    (tester) async {
      final api = ProductLayoutApi();
      await openProduct(tester, api);
      await tester.tap(find.widgetWithText(Tab, '参数'));
      await settleProduct(tester);
      final nested = tester.state<NestedScrollViewState>(
        find.byKey(const ValueKey('product-nested-scroll')),
      );
      nested.outerController.jumpTo(
        nested.outerController.position.maxScrollExtent,
      );
      await settleProduct(tester);
      expect(find.text('真实配置处理器'), findsOneWidget);
      final count = api.configRequests;
      await tester.fling(find.text('真实配置处理器'), const Offset(0, -600), 1800);
      await settleProduct(tester);
      expect(api.configRequests, count);
      await tester.tap(find.widgetWithText(Tab, '讨论'));
      await settleProduct(tester);
      await tester.tap(find.widgetWithText(Tab, '参数'));
      await settleProduct(tester);
      expect(api.configRequests, count);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact product and price cards fit a small screen with large text',
    (tester) async {
      await openProduct(
        tester,
        ProductLayoutApi(),
        size: const Size(360, 800),
        textScale: 1.6,
      );
      final nested = tester.state<NestedScrollViewState>(
        find.byKey(const ValueKey('product-nested-scroll')),
      );
      nested.outerController.jumpTo(
        nested.outerController.position.maxScrollExtent,
      );
      await settleProduct(tester);
      await tester.tap(find.widgetWithText(Tab, '到手价'));
      await settleProduct(tester);
      expect(
        find.byKey(const ValueKey('product-compact-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('product-price-summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
