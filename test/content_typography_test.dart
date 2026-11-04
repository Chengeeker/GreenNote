import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/feed/article_body.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'post body and bold titles share a size across all card layouts dark=$dark',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final theme = dark ? AppTheme.darkTheme() : AppTheme.lightTheme();
        expect(theme.textTheme.bodyMedium!.fontSize, AppTheme.contentFontSize);
        expect(theme.textTheme.bodyLarge!.fontSize, AppTheme.contentFontSize);
        for (final mode in [
          'normal',
          'price',
          'official',
          'headline',
          'article',
          'detail',
        ]) {
          final feed = CoolapkFeed.fromJson({
            'id': '12345',
            'uid': '20',
            'username': '作者',
            'title': '样例标题',
            'message': '相同字号的测试正文',
            if (mode == 'article') 'feedType': 'feedArticle',
            if (mode == 'price') ...{
              'tsubid': 6,
              'tsubdata': {'final_price': 3850},
            },
          });
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: FeedCard(
                      key: ValueKey(mode),
                      api: MockChannelApi(),
                      feed: feed,
                      officialLayout: mode == 'official',
                      isHeadline: mode == 'headline',
                      isDetail: mode == 'detail',
                    ),
                  ),
                ),
              ),
            ),
          );
          final body = find.byWidgetPredicate(
            (widget) => widget is CoolapkRichText && widget.text == '相同字号的测试正文',
          );
          expect(
            tester.widget<CoolapkRichText>(body).style!.fontSize,
            AppTheme.contentFontSize,
            reason: mode,
          );
          final title = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data ?? widget.textSpan?.toPlainText()) == '样例标题',
          );
          final titleStyle = tester.widget<Text>(title).style!;
          expect(titleStyle.fontSize, AppTheme.contentFontSize, reason: mode);
          expect(titleStyle.fontWeight, FontWeight.bold, reason: mode);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ArticleBody(
                api: MockChannelApi(),
                feed: CoolapkFeed.fromJson({'id': '12345'}),
                parts: const [
                  (type: 'text', text: '文章段落', url: '', caption: ''),
                ],
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<CoolapkRichText>(find.byType(CoolapkRichText))
              .style!
              .fontSize,
          AppTheme.contentFontSize,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
