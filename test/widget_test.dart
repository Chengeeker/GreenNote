import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/design_system/components/review_navigation_bar.dart';
import 'package:greennote/core/design_system/components/review_card.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/nine_grid_view.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/settings/personalization_page.dart';
import 'package:greennote/core/design_system/components/review_choice_tile.dart';
import 'package:greennote/main.dart' show MainScaffold;

class FakeApi implements CoolapkApi {
  @override
  bool get isAnonymous => false;

  final paths = <String>[];
  final queries = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> productSearchResults = const [];
  @override
  String get currentUid => '1';
  @override
  String get currentUserAvatar => '';
  @override
  bool get hasCookie => false;
  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async => {
    'data': {
      'username': '示例酷友',
      'feedNum': 123,
      'followNum': 24,
      'fansNum': 56,
    },
  };
  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async => {
    'data': <String, dynamic>{},
  };
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    paths.add(path);
    queries.add(Map<String, dynamic>.from(query));
    return ApiPage(
      items: path == '/v6/search' ? productSearchResults : const [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  Future<Map<String, dynamic>> getProductDetail(String productId) async => {
    'id': productId,
    'title': '已解析机型',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'startup waits on a clean background without a title or spinner',
    (tester) async {
      final apiCompleter = Completer<CoolapkApi>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coolapkApiProvider.overrideWith((ref) => apiCompleter.future),
          ],
          child: const MaterialApp(home: MainScaffold()),
        ),
      );

      expect(find.text('GreenNote'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('feed parsing retains all server pictures', () {
    final urls = List.generate(
      12,
      (index) => 'https://image.coolapk.com/$index.jpg',
    );
    expect(CoolapkFeed.fromJson({'id': '1', 'picArr': urls}).pictures, urls);
  });
  testWidgets(
    'Review grid keeps nine previews and opens all original pictures',
    (tester) async {
      final pics = List.generate(
        12,
        (index) => GalleryImage('https://image.coolapk.com/$index.jpg'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NineGridView(api: FakeApi(), pics: pics, statusId: 'grid'),
            ),
          ),
        ),
      );
      expect(find.text('+3'), findsOneWidget);
      final grid = tester.widget<GridView>(find.byType(GridView));
      final layout =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(layout.crossAxisCount, 3);
      expect(layout.crossAxisSpacing, 7);
      expect(find.byType(ImageGalleryHeroThumbnail), findsNWidgets(9));
      await tester.tap(find.byType(ImageGalleryHeroThumbnail).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<ImageGalleryPage>(find.byType(ImageGalleryPage))
            .pics
            .length,
        12,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('green baseline and original dark surfaces are retained', () {
    const state = AppSettingsState();
    expect(state.themeSeedArgb, 0xFF2E7D32);
    expect(state.useDynamicColor, false);
    expect(state.useFloatingNavBar, true);
    expect(state.useLiquidGlassNavBar, true);
    final dark = AppTheme.darkTheme(colorIndex: 3);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF111215));
    expect(dark.cardTheme.color, const Color(0xFF1B1C20));
    expect(
      AppTheme.darkTheme(
        colorIndex: 3,
        isPureBlack: true,
      ).scaffoldBackgroundColor,
      Colors.black,
    );
  });
  test(
    'liquid glass defaults on while a saved selection is retained',
    () async {
      final firstInstall = AppSettingsNotifier();
      await firstInstall.setFloatingNavBar(true);
      expect(firstInstall.state.useFloatingNavBar, true);
      expect(firstInstall.state.useLiquidGlassNavBar, true);
      await firstInstall.setLiquidGlassNavBar(false);
      firstInstall.dispose();

      final existingInstall = AppSettingsNotifier();
      await existingInstall.setFloatingNavBar(true);
      expect(existingInstall.state.useLiquidGlassNavBar, false);
      existingInstall.dispose();
    },
  );
  test(
    'WebDAV folder defaults to GreenNote and keeps a saved custom path',
    () async {
      final settings = AppSettingsNotifier();
      expect(
        (await settings.loadWebDavConfig())['directory'],
        defaultWebDavDirectory,
      );

      await settings.saveWebDavConfig(
        url: 'https://example.com/dav',
        username: 'user',
        directory: 'My Archive',
      );
      expect((await settings.loadWebDavConfig())['directory'], 'My Archive');
      settings.dispose();
    },
  );
  test(
    'backup includes UI preferences and remains compatible with v1',
    () async {
      final controller = AppSettingsNotifier();
      await controller.setPureBlackDark(true);
      await controller.setFloatingNavBar(false);
      await controller.setLiquidGlassNavBar(true);
      await controller.setUseCustomFontWeight(true);
      await controller.setCustomFontWeightDelta(100);
      final backup = await controller.exportBackup(
        webDavUrl: '',
        webDavUsername: '',
        webDavDirectory: 'Greennote',
      );
      final prefs = backup['preferences'] as Map<String, dynamic>;
      expect(prefs['pureBlackDark'], true);
      expect(prefs['floatingNavBar'], false);
      expect(prefs['liquidGlassNavBar'], true);
      expect(prefs['customFontWeightDelta'], 100);
      for (final key in [
        'pureBlackDark',
        'floatingNavBar',
        'liquidGlassNavBar',
        'useCustomFontWeight',
        'customFontWeightDelta',
      ]) {
        prefs.remove(key);
      }
      await controller.restoreBackup(backup);
      expect(controller.state.useFloatingNavBar, true);
      expect(controller.state.useLiquidGlassNavBar, true);
      expect(controller.state.isPureBlackDark, false);
      backup['preferences'] = <String, dynamic>{
        ...prefs,
        'floatingNavBar': null,
      };
      await expectLater(
        controller.restoreBackup(backup),
        throwsFormatException,
      );
      expect(controller.state.useFloatingNavBar, true);
      backup['preferences'] = <String, dynamic>{
        ...prefs,
        'liquidGlassNavBar': 'true',
      };
      await expectLater(
        controller.restoreBackup(backup),
        throwsFormatException,
      );
      controller.dispose();
    },
  );
  testWidgets(
    'five destinations keep publish as an action and support standard bar',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'greennote.liquid_glass_nav': false,
      });
      var selected = -1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ReviewNavigationBar(
                selectedIndex: 0,
                onSelected: (value) => selected = value,
                hasBottomInset: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['首页', '数码', '发布', '发现', '我的']) {
        expect(find.text(title), findsOneWidget);
      }
      await tester.tap(find.text('发布'));
      expect(selected, 2);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReviewNavigationBar)),
      );
      await container
          .read(appSettingsProvider.notifier)
          .setFloatingNavBar(false);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        5,
      );
      final settings = container.read(appSettingsProvider.notifier);
      await settings.setFloatingNavBar(true);
      await settings.setLiquidGlassNavBar(true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('liquid-glass-publish-action')),
        findsOneWidget,
      );
      expect(find.text('发布'), findsNothing);
      selected = -1;
      await tester.tap(find.text('发现'));
      expect(selected, 3);
      selected = -1;
      await tester.tap(
        find.byKey(const ValueKey('liquid-glass-publish-action')),
      );
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('standard feed card keeps its geometry and typography', (
    tester,
  ) async {
    const feed = CoolapkFeed(
      id: '1',
      username: '示例酷友',
      avatar: '',
      message: '相同正文用于布局检查',
      date: '1小时前',
      likeCount: '8',
      replyCount: '3',
      pictures: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(colorIndex: 3),
        home: Scaffold(
          body: FeedCard(api: FakeApi(), feed: feed),
        ),
      ),
    );
    final card = tester.widget<ReviewCard>(find.byType(ReviewCard));
    expect(card.margin, const EdgeInsets.symmetric(horizontal: 8, vertical: 4));
    expect(card.elevation, 1);
    expect(
      (card.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(20),
    );
    final body = tester.widget<Text>(find.text(feed.message));
    expect(body.style!.fontSize, 16);
    expect(body.style!.height, 1.3);
    expect(tester.takeException(), isNull);
  });
  testWidgets('feed device link opens the resolved product discussion', (
    tester,
  ) async {
    final api = FakeApi()
      ..productSearchResults = const [
        {'id': '14339', 'title': '小米 14'},
      ];
    const feed = CoolapkFeed(
      id: 'device-link-test',
      username: '示例酷友',
      avatar: '',
      message: '机型点击测试',
      date: '刚刚',
      likeCount: '0',
      replyCount: '0',
      pictures: [],
      uid: 'user-1',
      raw: {'device_title': '小米 14'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(api: api, feed: feed),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('feed-device-link')));
    await tester.pumpAndSettle();

    expect(api.queries.first, {
      'type': 'product',
      'searchValue': '小米 14',
      'page': 1,
    });
    expect(find.byType(ProductPage), findsOneWidget);
    expect(find.text('讨论'), findsOneWidget);
    final discussionRequestIndex = api.paths.indexOf('/v6/page/dataList');
    expect(discussionRequestIndex, greaterThanOrEqualTo(0));
    expect(
      api.queries[discussionRequestIndex],
      containsPair('url', '/page?url=/product/feedList'),
    );
    expect(api.queries[discussionRequestIndex], containsPair('id', '14339'));
    expect(api.queries[discussionRequestIndex], containsPair('type', 'feed'));

    Navigator.of(tester.element(find.byType(ProductPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feed-author-link')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<UserSpacePage>(find.byType(UserSpacePage)).uid,
      'user-1',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'profile has one tab strip and horizontal swipes follow the selected tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(colorIndex: 3),
          home: UserSpacePage(api: api, uid: '2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.isScrollable, true);
      expect(tabs.tabAlignment, TabAlignment.start);
      await tester.drag(find.byType(TabBarView), const Offset(-340, 0));
      await tester.pumpAndSettle();
      final controller = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );
      expect(controller.index, 2);
      expect(api.paths, contains('/v6/user/replyList'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'personalization uses original choice rows and handles large fonts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme(colorIndex: 3),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const PersonalizationPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewChoiceTile<ThemeMode>), findsNWidgets(3));
      expect(find.text('纯黑深色模式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('liquid glass setting follows the floating bar setting', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: const PersonalizationPage())),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('使用液态玻璃效果'), findsOneWidget);

    final settings = ProviderScope.containerOf(
      tester.element(find.byType(PersonalizationPage)),
    ).read(appSettingsProvider.notifier);
    await settings.setFloatingNavBar(false);
    await tester.pumpAndSettle();
    expect(find.text('使用液态玻璃效果'), findsNothing);

    await settings.setFloatingNavBar(true);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('使用液态玻璃效果'), findsOneWidget);
  });
}
