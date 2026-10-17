import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/features/digital/views/digital_brand_page.dart';

class _BrandApi extends Fake implements CoolapkApi {
  final urls = <String>[];
  bool failSort = false;
  bool includeSortControls = false;

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final url = query['url'].toString();
    urls.add(url);
    if (failSort && url.endsWith('/score')) throw StateError('sort failed');
    final series = url.split('/').first;
    return ApiPage(
      items: url == 'brand'
          ? [
              {
                'entityType': 'card',
                'entityTemplate': 'iconTabLinkGridCard',
                'entities': [
                  {'title': '全部', 'url': 'all'},
                  {'title': 'MIX系列', 'url': 'mix'},
                  {'title': 'Civi系列', 'url': 'civi'},
                ],
              },
            ]
          : [
              // Sort endpoints can return products only, without page controls.
              if (!url.contains('/') || includeSortControls)
                {
                  'entityType': 'card',
                  'entityTemplate': 'sortSelectCard',
                  'title': '排序规则',
                  'entities': [
                    {'title': '热度', 'url': '$series/hot'},
                    {'title': '评分', 'url': '$series/score'},
                    {'title': '最新', 'url': '$series/new'},
                  ],
                },
              {
                'entityType': 'product',
                'id': series,
                'title': 'product-$url',
                'logo': 'https://example.com/unreleased.jpg',
                'release_status': 0,
              },
            ],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }
}

void main() {
  Future<void> pumpFrames(WidgetTester tester) async {
    // Network-image placeholders animate independently of the API fixture.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> open(WidgetTester tester, _BrandApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DigitalBrandPage(api: api, title: '品牌', url: 'brand'),
      ),
    );
    await pumpFrames(tester);
  }

  testWidgets(
    'brand series swipe and taps select lazy pages with newest sorting',
    (tester) async {
      final api = _BrandApi();
      await open(tester, api);
      expect(find.text('product-all/new'), findsOneWidget);
      final newest = tester.widget<Text>(find.text('最新'));
      expect(newest.style!.fontWeight, FontWeight.bold);
      final selectedPill = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('最新'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (selectedPill.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      expect(api.urls, isNot(contains('civi')));
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(
              of: find.byType(CachedNetworkImage),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.circular(8));

      await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
      await pumpFrames(tester);
      expect(find.text('product-mix/new'), findsOneWidget);
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        1,
      );
      await tester.tap(find.text('Civi系列'));
      await pumpFrames(tester);
      expect(find.text('product-civi/new'), findsOneWidget);
      await tester.tap(find.text('全部'));
      await pumpFrames(tester);
      expect(find.text('product-all/new'), findsOneWidget);
      expect(api.urls.where((url) => url == 'all/new'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first-series outward swipe never refreshes, vertical pull still refreshes sorted URL',
    (tester) async {
      final api = _BrandApi();
      await open(tester, api);
      expect(
        tester.widget<EasyRefresh>(find.byType(EasyRefresh)).triggerAxis,
        Axis.vertical,
      );
      final count = api.urls.length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TabBarView)),
      );
      await gesture.moveBy(const Offset(350, 30));
      await tester.pump();
      expect(find.text('下拉刷新').hitTestable(), findsNothing);
      await gesture.up();
      await pumpFrames(tester);
      expect(api.urls.length, count);
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        0,
      );

      await tester.tap(find.text('评分'));
      await pumpFrames(tester);
      expect(find.text('product-all/score'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('评分')).style!.fontWeight,
        FontWeight.bold,
      );
      final beforeRefresh = api.urls.length;
      await tester.drag(find.byType(ListView).last, const Offset(0, 300));
      await pumpFrames(tester);
      expect(api.urls.length, greaterThan(beforeRefresh));
      expect(api.urls.last, 'all/score');
      expect(find.text('product-all/score'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed sort keeps previous data and selection', (tester) async {
    final api = _BrandApi();
    await open(tester, api);
    api.failSort = true;
    await tester.tap(find.text('评分'));
    await pumpFrames(tester);
    expect(find.text('product-all/new'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('最新')).style!.fontWeight,
      FontWeight.bold,
    );
    expect(find.textContaining('sort failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sort controls survive product-only responses and do not duplicate',
    (tester) async {
      final api = _BrandApi();
      await open(tester, api);
      for (final sort in [('热度', 'hot'), ('评分', 'score'), ('最新', 'new')]) {
        await tester.tap(find.text(sort.$1));
        await pumpFrames(tester);
        expect(api.urls.last, 'all/${sort.$2}');
        expect(find.text('product-all/${sort.$2}'), findsOneWidget);
        expect(find.text('排序规则'), findsOneWidget);
        for (final title in ['热度', '评分', '最新']) {
          expect(find.text(title), findsOneWidget);
        }
        expect(
          tester.widget<Text>(find.text(sort.$1)).style!.fontWeight,
          FontWeight.bold,
        );
      }
      await tester.widget<EasyRefresh>(find.byType(EasyRefresh)).onRefresh!();
      await pumpFrames(tester);
      expect(find.text('排序规则'), findsOneWidget);
      api.includeSortControls = true;
      await tester.widget<EasyRefresh>(find.byType(EasyRefresh)).onRefresh!();
      await pumpFrames(tester);
      expect(find.text('排序规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
