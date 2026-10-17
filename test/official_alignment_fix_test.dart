import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/activity_pages.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'use_liquid_glass': false});
  });

  test(
    'Emoji mapping resolves standard, numeric and currency codes properly',
    () {
      expect(getCoolapkEmotionCode('滑稽'), 'c-huaji');
      expect(getCoolapkEmotionCode('手动滑稽'), 'c-huaji');
      expect(getCoolapkEmotionCode('[doge]'), 'c-doge');
      expect(getCoolapkEmotionCode('1元'), 'c-1yuan');
      expect(getCoolapkEmotionCode('10元'), 'c-10yuan');
      expect(getCoolapkEmotionCode('1毛'), 'c-1mao');
      expect(getCoolapkEmotionCode('1分'), 'c-1fen');
      expect(getCoolapkEmotionCode('1'), 'c-1');
      expect(getCoolapkEmotionCode('40'), 'c-40');
      expect(getCoolapkEmotionCode('c-1'), 'c-1');
      expect(getCoolapkEmotionUrl('滑稽'), contains('c-huaji.png'));
    },
  );

  testWidgets(
    'CoolapkRichText renders emotion inline widgets and unicode fallbacks',
    (tester) async {
      final api = MockChannelApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolapkRichText(
              api: api,
              text: '测试文本 [滑稽] 酷安 [doge] 太阳 [太阳]',
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify text contains non-markup parts
      expect(find.textContaining('测试文本'), findsOneWidget);
      // Emotion tags are parsed into widgets or spans, not raw bracket text
      expect(find.text('[滑稽]'), findsNothing);
      expect(find.text('[doge]'), findsNothing);
    },
  );

  testWidgets(
    'ApiListPage renders CollectionTile with official 84x64 card dimensions',
    (tester) async {
      final api = MockChannelApi();
      final collectionItem = {
        'id': '12345',
        'entityType': 'collection',
        'title': '测试收藏夹',
        'is_open': '1',
        'follow_num': '10',
        'content_num': '25',
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: ApiEntityCard(api: api, entity: collectionItem),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('测试收藏夹'), findsOneWidget);
      expect(find.text('公开  10人关注  25个内容'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);

      // Verify folder container dimensions
      final containerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.constraints != null) {
          return widget.constraints!.maxWidth == 84 &&
              widget.constraints!.maxHeight == 64;
        }
        return false;
      });
      expect(containerFinder, findsOneWidget);
    },
  );

  testWidgets('ActivityTopicView uses circular FAB with border highlight', (
    tester,
  ) async {
    final api = MockChannelApi();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: ActivityTopicView(
            api: api,
            tag: '测试活动',
            detail: const {'title': '测试活动'},
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify FAB presence and circular shape
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(fabFinder);
    expect(fab.shape, isA<CircleBorder>());
    expect((fab.shape as CircleBorder).side.width, 1.5);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
