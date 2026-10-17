import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/product_comparison_page.dart';

class _MockComparisonApi extends Fake implements CoolapkApi {
  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> requestedQueries = [];

  Map<String, dynamic>? mockProductDetail;
  Map<String, dynamic>? mockConfigResponse;

  @override
  bool get isAnonymous => false;

  @override
  bool get hasAccount => true;

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
          'id': productId,
          'title': '测试手机 $productId',
          'logo': 'http://image.coolapk.com/phone.png',
          'price': '3999',
          'chip': '骁龙 8 至尊版',
          'battery': '6000mAh',
          'configRows': [
            {'id': '101', 'title': '12GB + 256GB', 'price': '3999'},
            {'id': '102', 'title': '16GB + 512GB', 'price': '4499'},
          ],
        };
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    requestedPaths.add(path);
    requestedQueries.add(Map<String, dynamic>.from(query));

    if (path == '/v6/product/config') {
      final configId = query['id']?.toString() ?? '101';
      return mockConfigResponse ??
          {
            'data': {
              'id': configId,
              'price': configId == '102' ? '4499' : '3999',
              'config_data': {
                '性能': {
                  '芯片': '骁龙 8 至尊版',
                  'RAM & ROM': configId == '102'
                      ? '16GB + 512GB\nLPDDR5X + UFS4.0'
                      : '12GB + 256GB\nLPDDR5X + UFS4.0',
                },
                '屏幕': {
                  '屏幕': '6.78英寸\n120Hz 1.5K OLED',
                },
              },
            },
          };
    }
    return {};
  }
}

void main() {
  group('ComparisonProduct Unit Tests', () {
    test('fromDetail parses basic information and config rows', () {
      final detail = {
        'id': '12345',
        'title': '一加 13',
        'logo': 'http://image.coolapk.com/oneplus13.png',
        'price': '4499',
        'chip': '骁龙8至尊版',
        'battery': '6000mAh',
        'charging': '100W 有线快充',
        'configRows': [
          {'id': '1', 'title': '12GB + 256GB', 'price': '4499'},
          {'id': '2', 'title': '16GB + 512GB', 'price': '4899'},
        ],
      };

      final product = ComparisonProduct.fromDetail(id: '12345', detail: detail);

      expect(product.id, '12345');
      expect(product.title, '一加 13');
      expect(product.logo, 'http://image.coolapk.com/oneplus13.png');
      expect(product.price, '4499');
      expect(product.selectedConfigId, '1');
      expect(product.selectedConfigName, '12GB + 256GB');
      expect(product.configRows.length, 2);

      // Verify specs populated
      expect(product.getSpec('性能', '芯片'), '骁龙8至尊版');
      expect(product.getSpec('续航', '电池'), '6000mAh');
      expect(product.getSpec('续航', '充电'), '100W 有线快充');
      expect(product.getSpec('性能', '不存在的配置'), '-');
    });

    test('loadConfigData loads specs from API', () async {
      final api = _MockComparisonApi();
      final product = ComparisonProduct.fromDetail(
        id: '12345',
        detail: {
          'id': '12345',
          'title': '小米 15 Pro',
          'configRows': [
            {'id': '101', 'title': '12GB + 256GB', 'price': '3999'},
            {'id': '102', 'title': '16GB + 512GB', 'price': '4499'},
          ],
        },
      );

      await product.loadConfigData(api, '102');

      expect(product.selectedConfigId, '102');
      expect(product.selectedConfigName, '16GB + 512GB');
      expect(product.price, '4499');
      expect(
        product.getSpec('性能', 'RAM & ROM'),
        '16GB + 512GB\nLPDDR5X + UFS4.0',
      );
      expect(api.requestedPaths, contains('/v6/product/config'));
    });
  });

  group('JD Buy URL Generation Tests', () {
    test('Constructs correct JD deep link and web search link', () {
      const searchTitle = 'OPPO Find X8';
      final jdParams = jsonEncode({
        'category': 'jump',
        'des': 'search',
        'keyWord': searchTitle,
      });

      final jdAppUri = Uri.parse(
        'openapp.jdmobile://virtual?params=${Uri.encodeComponent(jdParams)}',
      );
      final jdWebUri = Uri.parse(
        'https://so.m.jd.com/ware/search.action?keyword=${Uri.encodeComponent(searchTitle)}',
      );

      expect(jdAppUri.scheme, 'openapp.jdmobile');
      expect(jdAppUri.queryParameters['params'], jdParams);

      expect(jdWebUri.scheme, 'https');
      expect(jdWebUri.host, 'so.m.jd.com');
      expect(jdWebUri.queryParameters['keyword'], searchTitle);
    });
  });

  group('ProductComparisonPage Widget Tests', () {
    testWidgets('Renders comparison page and handles switch and removal', (
      tester,
    ) async {
      final api = _MockComparisonApi();

      final p1 = ComparisonProduct(
        id: '1001',
        title: 'iQOO 13',
        logo: '',
        price: '3999',
        selectedConfigName: '12GB + 256GB',
        configRows: [
          {'id': '1', 'title': '12GB + 256GB', 'price': '3999'},
          {'id': '2', 'title': '16GB + 512GB', 'price': '4499'},
        ],
        specs: {
          '性能': {'芯片': '骁龙 8 至尊版', 'RAM & ROM': '12GB + 256GB'},
          '续航': {'电池': '6150mAh', '充电': '120W'},
        },
      );

      final p2 = ComparisonProduct(
        id: '1002',
        title: '一加 13',
        logo: '',
        price: '4499',
        selectedConfigName: '12GB + 256GB',
        configRows: [
          {'id': '3', 'title': '12GB + 256GB', 'price': '4499'},
        ],
        specs: {
          '性能': {'芯片': '骁龙 8 至尊版', 'RAM & ROM': '12GB + 256GB'},
          '续航': {'电池': '6000mAh', '充电': '100W'},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductComparisonPage(
            api: api,
            initialProducts: [p1, p2],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Page Title
      expect(find.text('配置对比'), findsOneWidget);
      expect(find.text('隐藏相同配置'), findsOneWidget);
      expect(find.text('2款配置对比'), findsOneWidget);

      // Verify Products Header
      expect(find.text('iQOO 13'), findsOneWidget);
      expect(find.text('一加 13'), findsOneWidget);
      expect(find.text('¥3999'), findsOneWidget);
      expect(find.text('¥4499'), findsOneWidget);
      expect(find.text('添加对比'), findsOneWidget);

      // Verify specs table: chip is same for both
      expect(find.text('芯片'), findsOneWidget);

      // Toggle '隐藏相同配置'
      final switchFinder = find.byType(CupertinoSwitch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Since both phones have '芯片' == '骁龙 8 至尊版', '芯片' row should be hidden!
      expect(find.text('芯片'), findsNothing);

      // But '电池' differs (6150mAh vs 6000mAh), so '电池' must still be visible!
      expect(find.text('电池'), findsOneWidget);

      // Test remove one product
      final cardCloseIcons = find.byIcon(Icons.close);
      expect(cardCloseIcons, findsNWidgets(2)); // 2 on cards
      await tester.tap(cardCloseIcons.first);
      await tester.pumpAndSettle();

      // Now only 1 product remains
      expect(find.text('1款配置对比'), findsOneWidget);
      expect(find.text('iQOO 13'), findsNothing);
      expect(find.text('一加 13'), findsOneWidget);

      // Verify the last product can also be removed (allowing 0 products per official behavior)
      final remainingClose = find.byIcon(Icons.close);
      expect(remainingClose, findsNWidgets(1)); // 1 on remaining card
      await tester.tap(remainingClose.first);
      await tester.pumpAndSettle();

      // All products removed - shows empty comparison state
      expect(find.text('暂无对比机型'), findsOneWidget);
      expect(find.text('一加 13'), findsNothing);
      expect(find.text('点击上方“添加对比”选择机型'), findsOneWidget);
    });
  });
}
