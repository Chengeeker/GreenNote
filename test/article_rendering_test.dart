import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class _MockCoolapkApi extends Fake implements CoolapkApi {
  @override
  bool get hasCookie => false;
  @override
  bool get isAnonymous => true;
  @override
  String get currentUid => '';
  @override
  String get currentUserAvatar => '';

  @override
  Future<Map<String, dynamic>> getFeedDetail(String id) async => {
        'id': id,
        'title': 'Hinge-基于局域网的安卓通用办公套件',
        'message':
            '前言 随着现代移动设备性能的飞跃，手机和平板早已不再局限于娱乐和社交工具，越来越多的人开始尝试将其作为主力或辅助办公设备。',
        'message_cover': 'https://image.coolapk.com/cover.jpg',
        'user_level': '7',
        'replynum': '2',
        'likenum': '2',
      };

  @override
  Future<ApiPage> getHotReplyPage(String id, int page) async => const ApiPage(
        items: [],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );

  @override
  Future<ApiPage> getReplyPage(
    String id,
    int page, {
    String listType = 'lastupdate_desc',
    String feedType = 'feed',
    bool fromFeedAuthor = false,
    String? firstItem,
    String? lastItem,
  }) async =>
      const ApiPage(
        items: [],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockApi = _MockCoolapkApi();

  final articleJson = <String, dynamic>{
    'id': '987654',
    'uid': '12345',
    'username': '不可能虫鸣',
    'userAvatar': 'https://image.coolapk.com/avatar.jpg',
    'user_level': '7',
    'entityType': 'article',
    'feedType': 'feedArticle',
    'title': 'Hinge-基于局域网的安卓通用办公套件',
    'message':
        '前言 随着现代移动设备性能的飞跃，手机和平板早已不再局限于娱乐和社交工具，越来越多的人开始尝试将其作为主力或辅助办公设备。然而，移动端系统（如 Android）与桌面端（Windows/Linux/macOS）之间割裂的操作逻辑和文件管理方式，常常让这种尝试止步于“能用但不好用”的尴尬境地。虽然各类同步工具和投屏方案层出不穷，但很多时候我们需要的仅仅是一个简洁、即时且不依赖外网连接的轻量级解决方案。今天我们要探讨的，便是一款专注于局域网环境下的安卓通用办公套件——Hinge。' *
            10,
    'description':
        '随着现代移动设备性能的飞跃，手机和平板早已不再局限于娱乐和社交工具，越来越多的人开始尝试将其作为主力或辅助办公设备。',
    'message_cover': 'https://image.coolapk.com/cover.jpg',
    'dateline': '1725782400',
    'device_title': 'vivo X200 Pro mini',
    'likenum': '2',
    'replynum': '2',
    'targetRow': {
      'title': '玩机技巧',
      'targetType': 'topic',
      'url': '/t/玩机技巧',
    },
  };

  group('Article (图文) Data & Model Tests', () {
    test('CoolapkFeed correctly identifies article and extracts coverUrl', () {
      final feed = CoolapkFeed.fromJson(articleJson);
      expect(feed.isArticle, isTrue);
      expect(feed.coverUrl, 'https://image.coolapk.com/cover.jpg');
      expect(feed.message, contains('前言 随着现代移动设备性能的飞跃'));
    });

    test('CoolapkFeed identifies article by feedType feedArticle', () {
      final feed = CoolapkFeed.fromJson({
        'id': '111',
        'feedType': 'feedArticle',
        'cover': 'https://image.coolapk.com/cover2.jpg',
      });
      expect(feed.isArticle, isTrue);
      expect(feed.coverUrl, 'https://image.coolapk.com/cover2.jpg');
    });
  });

  group('Article (图文) Card 1:1 Official Layout Tests', () {
    testWidgets('FeedCard renders 1:1 official layout for article in lists',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final feed = CoolapkFeed.fromJson(articleJson);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  FeedCard(api: mockApi, feed: feed),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Author row
      expect(find.text('不可能虫鸣'), findsOneWidget);
      expect(find.text('Lv.7'), findsOneWidget);
      expect(find.text('vivo X200 Pro mini'), findsOneWidget);
      final avatarFinder = find.byType(AppAvatar);
      expect(avatarFinder, findsOneWidget);
      final avatarWidget = tester.widget<AppAvatar>(avatarFinder);
      expect(avatarWidget.size, 38);

      // 2. Title
      expect(find.text('Hinge-基于局域网的安卓通用办公套件'), findsOneWidget);

      // 3. Cover Image (题图) - 2:1 AspectRatio before summary
      final aspectRatioFinder = find.byWidgetPredicate(
        (w) => w is AspectRatio && (w.aspectRatio - 2.0).abs() < 0.05,
      );
      expect(aspectRatioFinder, findsWidgets);

      final cachedImageFinder = find.byType(CachedNetworkImage);
      expect(cachedImageFinder, findsWidgets);

      // Verify the cover image is visually situated below the title and above the summary text
      final titleTop =
          tester.getTopLeft(find.text('Hinge-基于局域网的安卓通用办公套件')).dy;
      final coverTop = tester.getTopLeft(aspectRatioFinder.first).dy;
      expect(coverTop, greaterThan(titleTop));

      // 4. Excerpt / Summary - clamped to max 3 lines with ellipsis
      final richTextFinder = find.byType(CoolapkRichText);
      expect(richTextFinder, findsOneWidget);
      final richTextWidget = tester.widget<CoolapkRichText>(richTextFinder);
      expect(richTextWidget.maxLines, 3);
      expect(richTextWidget.overflow, TextOverflow.ellipsis);
      expect(
        richTextWidget.text,
        '随着现代移动设备性能的飞跃，手机和平板早已不再局限于娱乐和社交工具，越来越多的人开始尝试将其作为主力或辅助办公设备。',
      );

      final summaryTop = tester.getTopLeft(richTextFinder).dy;
      expect(summaryTop, greaterThan(coverTop));

      // 5. Tags / Topics
      expect(find.text('玩机技巧'), findsOneWidget);

      // 6. Action buttons (赞 2, 评论 2, 分享)
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2)); // like count & reply count
    });

    testWidgets('ApiEntityCard renders article as FeedCard', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ApiEntityCard(
                    api: mockApi,
                    entity: articleJson,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(FeedCard), findsOneWidget);
      expect(find.text('Hinge-基于局域网的安卓通用办公套件'), findsOneWidget);
      expect(find.text('Lv.7'), findsOneWidget);
    });
  });
}
