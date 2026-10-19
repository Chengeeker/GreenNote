import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/utils/coolapk_url_handler.dart';
import 'package:greennote/core/utils/haptic_feedback_util.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/features/feed/article_body.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

const cover = 'https://image.coolapk.com/cover.jpg';
const image1 = 'https://image.coolapk.com/one.jpg';
const image2 = 'https://image.coolapk.com/two.jpg';
final models = [
  {'type': 'text', 'message': '第一段'},
  {'type': 'image', 'url': image1, 'description': '图一说明'},
  {'type': 'text', 'message': '图片之间的第二段'},
  {'type': 'image', 'url': image2},
  {'type': 'text', 'message': '第三段'},
  {'type': 'image', 'url': image1},
  {'type': 'shareUrl', 'title': '参考链接', 'url': 'https://example.com/read'},
];
Map<String, dynamic> article() => {
  'id': '12345',
  'entityType': 'feed',
  'feedType': 'feedArticle',
  'uid': '20',
  'username': '作者',
  'message_title': '图文标题',
  'message': '旧的扁平正文',
  'message_cover': cover,
  'picArr': [image1, image2],
  'message_raw_output': jsonEncode(models),
};

class _Api extends MockChannelApi {
  @override
  Future<Map<String, dynamic>> getFeedDetail(String id) async => article();
}

void main() {
  final feedback = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    feedback.clear();
    HapticFeedbackUtil.resetForTesting();
    HapticFeedbackUtil.isEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') feedback.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    HapticFeedbackUtil.resetForTesting();
  });

  test('structured article preserves author order, captions, duplicate images and link blocks', () {
    for (final raw in [models, jsonEncode(models)]) {
      final parts = parseArticleParts({'message_raw_output': raw});
      expect(parts.map((p) => p.type), [
        'text',
        'image',
        'text',
        'image',
        'text',
        'image',
        'link',
      ]);
      expect(parts.where((p) => p.type == 'image').map((p) => p.url), [
        image1,
        image2,
        image1,
      ]);
      expect(parts[1].caption, '图一说明');
      expect(parts[2].text, '图片之间的第二段');
    }
  });
  test('HTML img stays between paragraphs and emoji stays inline', () {
    final parts = parseArticleParts({
      'message_raw_output': '{broken',
      'message':
          '<p>前文<img src="emoji.png" alt="[滑稽]"></p><figure><img data-original="$image1" src="thumb.jpg"></figure><p><a href="/t/话题">后文</a></p>',
    });
    expect(parts.map((p) => p.type), ['text', 'image', 'text']);
    expect(parts.first.text, contains('[滑稽]'));
    expect(parts[1].url, image1);
    expect(parts.last.text, contains('href='));
  });
  test('unsafe image/link schemes do not become media and plain posts retain fallback', () {
    expect(parseArticleParts({'message': '普通动态'}), isEmpty);
    final parts = parseArticleParts({
      'message_raw_output': [
        {'type': 'image', 'url': 'javascript:bad'},
        {'type': 'shareUrl', 'url': 'file:///private'},
        {'type': 'text', 'message': '<script>bad()</script>正文'},
      ],
    });
    expect(parts.single.type, 'text');
    expect(parts.single.text, '正文');
  });
  test(
    'feed link IDs come from exact official routes and query parameters',
    () {
      for (final url in [
        '/feed/12345',
        'feed/12345',
        '#/feed/12345',
        '/feed/detail?id=12345',
        'coolmarket://feed/detail?id=12345',
        'https://www.coolapk.com/feed/12345',
      ]) {
        expect(feedIdFromCoolapkUrl(url), '12345', reason: url);
      }
      for (final url in [
        'https://evil.example/feed/12345',
        '/feed/reply/12345',
        '/feed/detail?id=',
        '/feed/0',
        '/feed/reply/12345?id=999',
        'javascript:/feed/12345',
      ]) {
        expect(feedIdFromCoolapkUrl(url), isEmpty, reason: url);
      }
    },
  );

  Future<void> mount(WidgetTester tester, {required bool detail}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FeedCard(
                api: _Api(),
                feed: CoolapkFeed.fromJson(article()),
                isDetail: detail,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'detail interleaves images once and body gallery follows authored sequence',
    (tester) async {
      await mount(tester, detail: true);
      expect(find.byType(ArticleBody), findsOneWidget);
      expect(find.text('旧的扁平正文', findRichText: true), findsNothing);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((w) => w.url),
        [cover, image1, image2, image1],
      );
      final body = find.byType(ArticleBody);
      final blocks = tester
          .widget<Column>(
            find.descendant(of: body, matching: find.byType(Column)).first,
          )
          .children;
      expect(blocks.map((w) => w.key), [
        for (var i = 0; i < 7; i++) ValueKey('article-part-$i'),
      ]);
      await tester.tap(find.bySemanticsLabel('查看图文正文图片').at(1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final gallery = tester.widget<ImageGalleryPage>(
        find.byType(ImageGalleryPage),
      );
      expect(gallery.initialIndex, 1);
      expect(gallery.pics.map((p) => p.url), [image1, image2, image1]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'article without a separate cover does not lift the first body image to the top',
    (tester) async {
      final data = article()
        ..remove('message_cover')
        ..remove('feedType')
        ..['pic'] = image1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: FeedCard(
                  api: _Api(),
                  feed: CoolapkFeed.fromJson(data),
                  isDetail: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('查看图文题图'), findsNothing);
      expect(
        tester
            .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .map((w) => w.url),
        [image1, image2, image1],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cover only opens gallery in detail with one haptic', (
    tester,
  ) async {
    await mount(tester, detail: true);
    expect(find.bySemanticsLabel('查看图文题图'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('查看图文题图'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ImageGalleryPage), findsOneWidget);
    expect(feedback, hasLength(1));
    expect(feedback.single.arguments, 'HapticFeedbackType.lightImpact');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('list cover opens the article instead of a gallery', (
    tester,
  ) async {
    await mount(tester, detail: false);
    expect(find.bySemanticsLabel('查看图文题图'), findsNothing);
    await tester.tap(find.byType(CachedNetworkImage).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FeedDetailPage), findsOneWidget);
    expect(find.byType(ImageGalleryPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
