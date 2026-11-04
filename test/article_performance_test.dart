import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

final longArticle = <String, dynamic>{
  'id': '12345',
  'uid': '20',
  'username': '作者',
  'feedType': 'feedArticle',
  'message_title': '长文章性能回归',
  'message': '正文摘要',
  'message_raw_output': [
    for (var i = 0; i < 120; i++) ...[
      {'type': 'text', 'message': '第$i段：${'已加载的正文内容，滚动时不应重新排版整篇文章。' * 8}'},
      if (i % 3 == 0)
        {'type': 'image', 'url': 'https://example.com/article-$i.jpg'},
    ],
  ],
};

class _Api extends MockChannelApi {
  @override
  Future<void> likeFeed(String id, {required bool liked}) async {}
  @override
  Future<Map<String, dynamic>> getFeedDetail(String id) async => longArticle;
}

void main() {
  for (final glass in [false, true]) {
    testWidgets(
      'long article only mounts nearby blocks and images glass=$glass',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'greennote.liquid_glass_nav': glass,
        });
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: FeedDetailPage(
                api: _Api(),
                feed: CoolapkFeed.fromJson(longArticle),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final blocks = find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'article-part-',
              ),
        );
        debugPrint(
          'Article fixture: ${blocks.evaluate().length} mounted blocks, ${find.byType(CachedNetworkImage).evaluate().length} image widgets',
        );
        expect(blocks.evaluate().length, lessThan(20));
        expect(find.byType(CachedNetworkImage).evaluate().length, lessThan(10));
        expect(find.byKey(const ValueKey('article-part-159')), findsNothing);
        final content = tester.widget<FeedCard>(find.byType(FeedCard));
        await tester.tap(find.byIcon(Icons.thumb_up_outlined).last);
        await tester.pump();
        expect(tester.widget<FeedCard>(find.byType(FeedCard)), same(content));
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -650),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(blocks.evaluate().length, lessThan(20));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('article-part-9')),
          600,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey('article-part-9')),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final gallery = tester.widget<ImageGalleryPage>(
          find.byType(ImageGalleryPage),
        );
        expect(gallery.initialIndex, 2);
        expect(gallery.pics, hasLength(40));
        expect(gallery.pics[2].url, 'https://example.com/article-6.jpg');
        Navigator.of(tester.element(find.byType(ImageGalleryPage))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('article-part-9')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'list excerpt bounds layout without truncating the saved article',
    (tester) async {
      final message = '保留的完整长正文' * 3000;
      final feed = CoolapkFeed.fromJson({...longArticle, 'message': message});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [FeedCard(api: _Api(), feed: feed)],
            ),
          ),
        ),
      );
      final excerpt = tester.widget<CoolapkRichText>(
        find.byType(CoolapkRichText).first,
      );
      expect(excerpt.maxCharacters, 1000);
      expect(feed.message, message);
      final rendered = find.descendant(
        of: find.byType(CoolapkRichText).first,
        matching: find.byType(Text),
      );
      expect(
        tester.widget<Text>(rendered).textSpan!.toPlainText().length,
        1000,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('long article notification still reveals the target reply', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'greennote.liquid_glass_nav': false,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FeedDetailPage(
            api: _Api(),
            feed: CoolapkFeed.fromJson(longArticle),
            initialReplyId: '222',
            initialReply: const {
              'id': '222',
              'feedId': '12345',
              'message': '需要定位的评论',
              'username': '回复作者',
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('需要定位的评论').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
