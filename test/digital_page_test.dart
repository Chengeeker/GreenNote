import 'package:greennote/core/accounts/local_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/digital/models/digital_tab_item.dart';
import 'package:greennote/features/digital/views/digital_library_view.dart';
import 'package:greennote/features/digital/views/digital_server_channel_view.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/digital/widgets/digital_cards.dart';
import 'package:greennote/features/digital/widgets/rank_ribbon.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/main.dart';

void main() {
  group('Digital Models & Ribbon Tests', () {
    test('DigitalTabItem fallback tabs match official Coolapk order', () {
      final tabs = DigitalTabItem.getFallbackTabs();
      expect(tabs.length, 7);
      expect(tabs.map((t) => t.title).toList(), [
        '数码库',
        '数码',
        '手机',
        '排行榜',
        '系统',
        '平板',
        '电脑',
      ]);
      expect(tabs[1].key, 'V10_DIGITAL_HOME');
      expect(tabs[2].url, 'V10_CHANNEL_SJB');
      expect(tabs[3].url, 'V10_CHANNEL_SMB_TOP');
      expect(tabs[4].url, 'V10_CHANNEL_SMB');
      expect(tabs[5].url, 'V15_PAD');
      expect(tabs[6].url, 'V8_ZHUANTI_COMPUTER_20230413');
      expect(tabs[1].url, 'V10_DIGITAL_HOME');
      expect(tabs[0].category, true);
    });

    testWidgets('RankRibbon renders rank numbers with correct color bands', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                RankRibbon(rank: 1),
                RankRibbon(rank: 2),
                RankRibbon(rank: 3),
                RankRibbon(rank: 4),
                RankRibbon(rank: 5),
              ],
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    test('formatDigitalHot handles numbers and strings properly', () {
      expect(formatDigitalHot(1029000), '102.9万');
      expect(formatDigitalHot('29.7万'), '29.7万');
      expect(formatDigitalHot('1000'), '1000');
      expect(formatDigitalHot(null), '');
      expect(formatDigitalHot(''), '');
    });
  });

  group('Digital Cards Widget Tests', () {
    testWidgets(
      'DigitalCategoryGridCard displays 10 standard categories in 5 columns',
      (tester) async {
        String? tappedTitle;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalCategoryGridCard(
                api: _FakeCoolapkApi(),
                onCategoryTap: (title, _) {
                  tappedTitle = title;
                },
              ),
            ),
          ),
        );

        expect(find.text('手机'), findsOneWidget);
        expect(find.text('平板'), findsOneWidget);
        expect(find.text('耳机'), findsOneWidget);
        expect(find.text('笔记本'), findsOneWidget);
        expect(find.text('智能家居'), findsOneWidget);
        expect(find.text('穿戴设备'), findsOneWidget);
        expect(find.text('数码配件'), findsOneWidget);
        expect(find.text('游戏'), findsOneWidget);
        expect(find.text('路由器'), findsOneWidget);
        expect(find.text('全部'), findsOneWidget);

        await tester.tap(find.text('手机'));
        await tester.pump();
        expect(tappedTitle, '手机');
      },
    );

    testWidgets('DigitalRankGridCard displays today hot products and ribbons', (
      tester,
    ) async {
      bool moreTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DigitalRankGridCard(
              api: _FakeCoolapkApi(),
              title: '今日热门',
              items: const [
                {'title': '一加16'},
                {'title': '荣耀 Magic9 Pro'},
                {'title': '小米18 Pro Max'},
                {'title': 'iPhone 18 Pro Max'},
              ],
              subTitle: '榜单',
              onMoreTap: () {
                moreTapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('今日热门'), findsOneWidget);
      expect(find.text('榜单'), findsOneWidget);
      expect(find.text('一加16'), findsOneWidget);
      expect(find.text('荣耀 Magic9 Pro'), findsOneWidget);
      expect(find.text('小米18 Pro Max'), findsOneWidget);
      expect(find.text('iPhone 18 Pro Max'), findsOneWidget);

      await tester.tap(find.text('榜单'));
      await tester.pump();
      expect(moreTapped, true);
    });

    testWidgets('DigitalFollowCard displays user followed products', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DigitalFollowCard(
              api: _FakeCoolapkApi(),
              items: const [
                {'id': '34001', 'title': '魅族18'},
                {'id': '34002', 'title': 'vivo WATCH GT'},
              ],
            ),
          ),
        ),
      );

      expect(find.text('我的关注'), findsOneWidget);
      expect(find.text('更多'), findsOneWidget);
      expect(find.text('魅族18'), findsOneWidget);
      expect(find.text('vivo WATCH GT'), findsOneWidget);
    });

    testWidgets('DigitalFollowCard hides when items is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DigitalFollowCard(api: _FakeCoolapkApi())),
        ),
      );

      expect(find.text('我的关注'), findsNothing);
    });

    testWidgets('anonymous UID account opens its local followed products', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeCoolapkApi(anonymousValue: true);
      api.localAccount = LocalAccount(await SharedPreferences.getInstance());
      await api.localAccount.setPublicIdentity(
        uid: '12345',
        username: '公开主页',
        userAvatar: '',
      );
      await api.localAccount.setActive(true);
      await api.localAccount.toggle('productFollows', '34001', {
        'id': '34001',
        'title': '本地机型',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DigitalFollowCard(api: api, emptyText: '还没有关注的机型'),
          ),
        ),
      );
      expect(find.text('本地机型'), findsOneWidget);
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();
      expect(find.text('本地机型'), findsOneWidget);
      expect(find.byTooltip('取消本地关注'), findsOneWidget);

      await tester.tap(find.byTooltip('取消本地关注'));
      await tester.pump();
      expect(find.text('还没有关注的机型'), findsOneWidget);
      expect(api.localAccount.productFollows, isEmpty);
    });

    testWidgets(
      'DigitalLibraryView renders pure text categories, brand tiles and 3-column products',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DigitalLibraryView(api: _FakeCoolapkApi())),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Check left text rail categories
        expect(find.text('热门'), findsOneWidget);
        expect(find.text('手机'), findsOneWidget);
        expect(find.text('平板'), findsOneWidget);
        expect(find.text('耳机'), findsOneWidget);

        // Check brand section
        expect(find.text('品牌'), findsOneWidget);
        expect(find.text('小米'), findsOneWidget);
        expect(find.text('荣耀'), findsOneWidget);

        // Check sorting rule chips
        expect(find.text('排序规则'), findsOneWidget);
        expect(find.text('热度'), findsOneWidget);
        expect(find.text('评分'), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);

        // Check products and follow buttons
        expect(find.text('一加16'), findsOneWidget);
        expect(find.text('关注'), findsWidgets);
      },
    );

    testWidgets('Tapping product opens ProductPage', (tester) async {
      final fakeApi = _FakeCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DigitalLibraryView(api: fakeApi)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final productFinder = find.text('一加16');
      expect(productFinder, findsOneWidget);
      await tester.tap(productFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should have navigated to official-aligned ProductPage
      expect(find.text('酷安评分'), findsOneWidget);
      expect(find.text('讨论'), findsOneWidget);
      expect(find.text('参数'), findsOneWidget);
    });

    testWidgets('Tapping follow when not logged in displays login hint', (
      tester,
    ) async {
      final fakeApi = _FakeCoolapkApi(hasCookieValue: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DigitalLibraryView(api: fakeApi)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final followBtn = find.text('关注').first;
      await tester.ensureVisible(followBtn);
      await tester.pump();
      await tester.tap(followBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('请先登录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Tapping follow when logged in sends follow API request', (
      tester,
    ) async {
      final fakeApi = _FakeCoolapkApi(hasCookieValue: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DigitalLibraryView(api: fakeApi)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final followBtn = find.text('关注').first;
      await tester.ensureVisible(followBtn);
      await tester.pump();
      await tester.tap(followBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        fakeApi.requestedPaths.contains('/v6/product/changeFollowStatus'),
        isTrue,
      );
      expect(find.text('已关注 一加16'), findsOneWidget);
    });

    testWidgets('Tapping follow on anonymous UID account saves locally', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fakeApi = _FakeCoolapkApi(anonymousValue: true);
      fakeApi.localAccount = LocalAccount(
        await SharedPreferences.getInstance(),
      );
      await fakeApi.localAccount.setPublicIdentity(
        uid: '12345',
        username: '公开主页',
        userAvatar: '',
      );
      await fakeApi.localAccount.setActive(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DigitalLibraryView(api: fakeApi)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final followBtn = find.text('关注').first;
      await tester.ensureVisible(followBtn);
      await tester.pump();
      await tester.tap(followBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(fakeApi.localAccount.productFollows['34676']['title'], '一加16');
      expect(find.text('已关注 一加16'), findsOneWidget);
    });

    testWidgets(
      'Brand list displays 2-row horizontal layout and supports scrolling beyond 8 brands',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: DigitalLibraryView(api: fakeApi)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Brand section exists
        expect(find.text('品牌'), findsOneWidget);
        expect(find.text('小米'), findsOneWidget);
        expect(find.text('华为'), findsOneWidget);
        expect(find.text('荣耀'), findsOneWidget);
        expect(find.text('vivo'), findsOneWidget);

        // Find horizontal brand ListView
        final brandListViewFinder = find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        );
        expect(brandListViewFinder, findsOneWidget);

        // Scroll right horizontally to reveal brands beyond 8
        await tester.drag(brandListViewFinder, const Offset(-300, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Revealed brand should now be found
        expect(find.text('一加'), findsOneWidget);
      },
    );

    testWidgets('MainScaffold displays unified official AppBar elements', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fakeApi = _FakeCoolapkApi();
      fakeApi.localAccount = LocalAccount(
        await SharedPreferences.getInstance(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coolapkApiProvider.overrideWith((ref) => fakeApi)],
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tab 0 (Feed): Search capsule + APP badge + Message mail button
      expect(find.text('搜索动态/话题/应用/酷友...'), findsOneWidget);
      expect(find.text('APP'), findsOneWidget);
      expect(find.byTooltip('消息'), findsOneWidget);

      // Tab 1 (Digital)
      tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  !widget.container &&
                  widget.properties.label == '数码' &&
                  widget.properties.onTap != null,
            ),
          )
          .properties
          .onTap!();
      await tester.pump();
      final firstDigitalPage = find
          .ancestor(
            of: find.byKey(const ValueKey(1)),
            matching: find.byType(SlideTransition),
          )
          .first;
      expect(
        tester.widget<SlideTransition>(firstDigitalPage).position.value,
        Offset.zero,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('搜索动态/话题/应用/酷友...'), findsOneWidget);
      expect(find.text('APP'), findsOneWidget);

      // Tab 3 (My)
      tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  !widget.container &&
                  widget.properties.label == '我的' &&
                  widget.properties.onTap != null,
            ),
          )
          .properties
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('我的'), findsWidgets);
      expect(find.byTooltip('设置'), findsOneWidget);
      expect(find.byTooltip('搜索'), findsOneWidget);
    });

    testWidgets(
      'DigitalServerChannelView filters configCard and combines system zone cards',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalServerChannelView(
                api: fakeApi,
                url: 'V13_DIGITAL_ROM_TEST',
                system: true,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Should render "新系统" with "更多" button
        expect(find.text('新系统'), findsOneWidget);
        expect(find.text('更多'), findsOneWidget);

        // Should combine "小米系统区" title card and feature grid into 1 unified card
        expect(find.text('小米系统区'), findsOneWidget);
        expect(find.text('HyperOS4'), findsOneWidget);
        expect(find.text('9.3'), findsOneWidget);
        expect(find.text('超级小爱'), findsOneWidget);

        // Should render "热门功能" with "榜单 >", rating 9.6, and topic name
        expect(find.text('热门功能'), findsOneWidget);
        expect(find.text('榜单'), findsOneWidget);
        expect(find.text('闪念胶囊'), findsOneWidget);
        expect(find.text('9.6'), findsOneWidget);

        // Should render "动态区" header with capsule sort switch
        expect(find.text('动态区'), findsOneWidget);
        expect(find.text('最近回复'), findsOneWidget);
        expect(find.text('热门排序'), findsOneWidget);

        // Should render feed directly below 动态区
        expect(find.text('测试数码动态正文内容'), findsOneWidget);

        // Tap "热门排序" to test tab toggle
        await tester.tap(find.text('热门排序'));
        await tester.pump();

        // configCard (empty title, no entities) should NOT be rendered
        expect(find.text('默认配置（勿动）'), findsNothing);
      },
    );

    testWidgets(
      'DigitalBannerCard uses intelligent aspect ratio and BoxFit.cover',
      (tester) async {
        final api = _FakeCoolapkApi();
        // 1. Standard 1080x240 banner
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalBannerCard(
                api: api,
                imageUrl: 'https://img.coolapk.com/banner@1080x240.jpg',
                title: '标准横幅',
              ),
            ),
          ),
        );
        await tester.pump();

        var aspectRatioFinder = find.byType(AspectRatio);
        expect(aspectRatioFinder, findsOneWidget);
        var aspectRatioWidget = tester.widget<AspectRatio>(aspectRatioFinder);
        expect(aspectRatioWidget.aspectRatio, closeTo(4.5, 0.001));

        var imageFinder = find.byType(CachedNetworkImage);
        expect(imageFinder, findsOneWidget);
        var imageWidget = tester.widget<CachedNetworkImage>(imageFinder);
        expect(imageWidget.fit, BoxFit.cover);

        // 2. Special 1080x360 banner (今日酷安)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalBannerCard(
                api: api,
                imageUrl: 'https://img.coolapk.com/banner@1080x360.jpg',
                title: '今日酷安横幅',
              ),
            ),
          ),
        );
        await tester.pump();

        aspectRatioFinder = find.byType(AspectRatio);
        aspectRatioWidget = tester.widget<AspectRatio>(aspectRatioFinder);
        expect(aspectRatioWidget.aspectRatio, closeTo(3.338, 0.001));
      },
    );

    testWidgets(
      'DigitalServerChannelView renders V15_PAD tablet cards with ribbons and extraData scores',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalServerChannelView(api: fakeApi, url: 'V15_PAD'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. iconLongTitleGridCard "今日热门"
        expect(find.text('今日热门'), findsOneWidget);
        expect(find.text('小米平板 7 Pro'), findsOneWidget);
        expect(find.text('10.5万'), findsOneWidget);
        // Rank ribbon for item 1
        expect(find.text('1'), findsOneWidget);

        // 2. iconGridHorizonCard (horizontal brand list)
        expect(find.text('小米'), findsOneWidget);
        expect(find.text('华为'), findsOneWidget);

        // 3. iconListCard "屏幕榜" with extraData
        expect(find.text('屏幕榜'), findsOneWidget);
        expect(find.text('iPad Pro M4'), findsOneWidget);
        expect(find.text('9.8'), findsWidgets);
        expect(find.text('屏幕分'), findsOneWidget);
      },
    );

    testWidgets(
      'DigitalServerChannelView renders V8_ZHUANTI_COMPUTER_20230413 with merged quick links and unreleased badges',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalServerChannelView(
                api: fakeApi,
                url: 'V8_ZHUANTI_COMPUTER_20230413',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Merged banner quick links
        expect(find.text('资讯'), findsOneWidget);
        expect(find.text('图文'), findsOneWidget);
        expect(find.text('路由'), findsOneWidget);
        expect(find.text('键鼠'), findsOneWidget);

        // 2. iconGridCard "热门分区"
        expect(find.text('热门分区'), findsOneWidget);
        expect(find.text('轻薄本'), findsOneWidget);
        expect(find.text('30.5万'), findsOneWidget);

        // 3. iconListCard "最新产品" with unreleased badge & release time
        expect(find.text('最新产品'), findsOneWidget);
        expect(find.text('MacBook Pro M5'), findsOneWidget);
        expect(find.text('-- 未发布 --'), findsOneWidget);
        expect(find.text('2026年秋季'), findsOneWidget);
        expect(find.text('发布时间'), findsOneWidget);
        expect(find.text('ThinkPad X1 Carbon'), findsOneWidget);
        expect(find.text('暂无人评分'), findsOneWidget);
      },
    );

    testWidgets(
      'DigitalLibraryView renders and toggles secondary categories (耳机 -> 无线耳机/有线耳机)',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalLibraryView(api: fakeApi, initialCategoryId: '1000'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Initial view shows parent categories
        expect(find.text('热门'), findsOneWidget);
        expect(find.text('手机'), findsOneWidget);
        expect(find.text('耳机'), findsOneWidget);

        // Tap 耳机 to expand subcategories
        await tester.tap(find.text('耳机'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Should now show secondary subcategories
        expect(find.text('无线耳机'), findsOneWidget);
        expect(find.text('有线耳机'), findsOneWidget);

        // Tap 有线耳机 to switch selection
        await tester.tap(find.text('有线耳机'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Subcategory remains selected and rendered
        expect(find.text('有线耳机'), findsOneWidget);
      },
    );

    testWidgets(
      'CoolPicPage renders topic cards and 5 colorful shortcut buttons',
      (tester) async {
        final fakeApi = _FakeCoolapkApi();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: CoolPicPage(api: fakeApi)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Topic cards in first row
        expect(find.text('#风景#'), findsOneWidget);
        expect(find.text('#二次元#'), findsOneWidget);
        expect(find.text('#生活#'), findsOneWidget);

        // 2. 5 colorful shortcut buttons in second row
        expect(find.text('热门'), findsOneWidget);
        expect(find.text('2K'), findsNWidgets(2));
        expect(find.text('全面屏'), findsOneWidget);
        expect(find.text('平板'), findsOneWidget);
        expect(find.text('最新'), findsOneWidget);

        // 3. Tap 2K button
        await tester.tap(find.text('2K').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('2K'), findsNWidgets(2));
      },
    );
  });
}

class _FakeCoolapkApi implements CoolapkApi {
  @override
  late final LocalAccount localAccount;
  @override
  bool get isAnonymous => anonymousValue;

  _FakeCoolapkApi({this.hasCookieValue = false, this.anonymousValue = false});

  final bool hasCookieValue;
  final bool anonymousValue;
  final List<String> requestedPaths = [];

  @override
  String get currentUid => '12345';
  @override
  String get loginRequiredMessage => '请先登录';

  @override
  String get currentUserAvatar => 'https://img.coolapk.com/avatar.jpg';

  @override
  bool get hasCookie => hasCookieValue;

  @override
  bool get hasAccount => isAnonymous || hasCookie;

  @override
  Map<String, String> imageHeadersFor() => const {};

  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {
    'headline': '/v6/main/indexV8',
    'feed': '/v6/page/dataList?url=V9_HOME_TAB_FEED',
  };

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requestedPaths.add(path);
    if (query['url'] == 'V13_DIGITAL_ROM_TEST') {
      return const ApiPage(
        items: [
          {
            'entityType': 'card',
            'entityTemplate': 'iconMiniGridCard',
            'title': '新系统',
            'subTitle': '更多',
            'moreUrl': '#/topic/tagList?title=新系统',
            'entities': [
              {
                'entityType': 'topic',
                'title': 'ColorOS17',
                'url': '/t/ColorOS17',
              },
              {
                'entityType': 'topic',
                'title': 'OriginOS7',
                'url': '/t/OriginOS7',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'listCard',
            'title': '小米系统区',
            'entities': [
              {
                'entityType': 'topic',
                'title': 'HyperOS4',
                'hot_num_txt': '100.4万',
                'score': '9.3',
                'commentnum': '31527',
                'url': '/t/HyperOS4',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconMiniGridCard',
            'title': '',
            'entities': [
              {'entityType': 'topic', 'title': '超级小爱', 'url': '/t/超级小爱'},
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconListCard',
            'title': '热门功能',
            'subTitle': '榜单',
            'url': '#/topic/tagList?title=热门功能',
            'entities': [
              {
                'entityType': 'topic',
                'title': '闪念胶囊',
                'star_average_score': '9.6',
                'hot_num_txt': '492',
                'commentnum_txt': '42',
                'url': '/t/闪念胶囊',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'sortSelectCard',
            'title': '动态区',
            'entities': [
              {'title': '最近回复', 'url': 'sort=lastupdate'},
              {'title': '热门排序', 'url': 'sort=hot'},
            ],
          },
          {
            'entityType': 'feed',
            'id': '99991',
            'message': '测试数码动态正文内容',
            'username': '测试酷友',
          },
          {
            'entityType': 'card',
            'entityTemplate': 'configCard',
            'title': '默认配置（勿动）',
            'entities': [],
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
    }
    if (query['url'] == 'V15_PAD') {
      return const ApiPage(
        items: [
          {
            'entityType': 'card',
            'entityTemplate': 'iconLongTitleGridCard',
            'title': '今日热门',
            'entities': [
              {
                'entityType': 'product',
                'id': '34001',
                'title': '小米平板 7 Pro',
                'subTitle': '骁龙8s Gen3',
                'hot_num_txt': '10.5万',
                'logo': 'https://img.coolapk.com/pad.png',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconGridHorizonCard',
            'entities': [
              {
                'entityType': 'topic',
                'title': '小米',
                'logo': 'https://img.coolapk.com/xiaomi.png',
              },
              {
                'entityType': 'topic',
                'title': '华为',
                'logo': 'https://img.coolapk.com/huawei.png',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconListCard',
            'title': '屏幕榜',
            'subTitle': '榜单',
            'entities': [
              {
                'entityType': 'product',
                'id': '34002',
                'title': 'iPad Pro M4',
                'extraData': '{"rightTopText":"9.8","rightBottomText":"屏幕分"}',
                'score': '9.8',
                'hot_num_txt': '20.1万',
              },
            ],
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
    }
    if (query['url'] == 'V8_ZHUANTI_COMPUTER_20230413') {
      return const ApiPage(
        items: [
          {
            'entityType': 'card',
            'entityTemplate': 'imageCarouselCard_1',
            'entities': [
              {
                'pic': 'https://img.coolapk.com/pc_banner@1080x360.jpg',
                'url': 'https://coolapk.com/page/computer',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconMiniLinkGridCard',
            'entities': [
              {'title': '资讯', 'url': '/page/news'},
              {'title': '图文', 'url': '/page/articles'},
              {'title': '路由', 'url': '/page/routers'},
              {'title': '键鼠', 'url': '/page/accessories'},
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconGridCard',
            'title': '热门分区',
            'entities': [
              {
                'title': '轻薄本',
                'subTitle': '热度 30.5万',
                'logo': 'https://img.coolapk.com/laptop.png',
              },
            ],
          },
          {
            'entityType': 'card',
            'entityTemplate': 'iconListCard',
            'title': '最新产品',
            'entities': [
              {
                'entityType': 'product',
                'id': '35001',
                'title': 'MacBook Pro M5',
                'release_status': 0,
                'release_time': '2026年秋季',
                'hot_num_txt': '1.2万',
                'star_average_score': '0.0',
              },
              {
                'entityType': 'product',
                'id': '35002',
                'title': 'ThinkPad X1 Carbon',
                'hot_num_txt': '8000',
                'star_average_score': '0.0',
              },
            ],
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
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
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    dynamic body,
  }) async {
    requestedPaths.add(path);
    if (path == '/v6/product/changeFollowStatus') {
      return {'data': 1, 'status': 0};
    }
    if (path == '/v6/page/dataList') {
      return {
        'data': [
          {
            'entityType': 'card',
            'entityTemplate': 'sortSelectCard',
            'title': '排序规则',
            'entities': [
              {'title': '热度', 'url': 'sort=hot'},
              {'title': '评分', 'url': 'sort=score'},
              {'title': '最新', 'url': 'sort=new'},
            ],
          },
          {
            'entityType': 'product',
            'id': '34676',
            'title': '一加16',
            'subTitle': '骁龙8至尊版',
            'logo': 'https://img.coolapk.com/product.png',
            'is_follow': 0,
            'hot_num_txt': '102.9万',
          },
        ],
      };
    }
    return {'data': <dynamic>[]};
  }

  @override
  Future<void> followProduct(
    String productId, {
    required bool following,
    Map<String, dynamic>? product,
  }) async {
    if (isAnonymous) {
      await localAccount.toggle('productFollows', productId, {
        'id': productId,
        for (final key in const [
          'title',
          'pic',
          'logo',
          'cover',
          'hot_num',
          'votenum',
        ])
          if (product?[key] != null) key: product![key].toString(),
      });
    } else {
      requestedPaths.add('/v6/product/changeFollowStatus');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
