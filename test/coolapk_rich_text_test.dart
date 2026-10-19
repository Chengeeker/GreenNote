import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/coolapk_rich_text.dart';

class _MockCoolapkApi extends Fake implements CoolapkApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'visible truncation preserves the complete topic target and hides HTML',
    (tester) async {
      const topic = '懂车帝测试尊界V800刹车踏板断裂';
      final raw =
          '前文<a class="feed-link-tag" href="/t/${Uri.encodeComponent(topic)}?type=0">#$topic#</a>后文';
      expect(CoolapkRichText.visibleText(raw), '前文#$topic#后文');
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolapkRichText(
              api: _MockCoolapkApi(),
              text: raw,
              maxCharacters: 8,
              onTapTag: (tag) => opened = tag,
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      expect(rich.text.toPlainText(), '前文#懂车帝测试');
      final link =
          (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
              .children!
              .whereType<TextSpan>()
              .firstWhere((span) => span.recognizer != null);
      (link.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, topic);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolapkRichText(
              api: _MockCoolapkApi(),
              text: '😀<a href="/feed/1">后文</a>',
              maxCharacters: 1,
            ),
          ),
        ),
      );
      expect(
        tester.widget<RichText>(find.byType(RichText)).text.toPlainText(),
        '',
      );
    },
  );

  group('sanitizeCoolapkMessage Tests', () {
    test('sanitizes malicious tags while preserving <a> and formatting', () {
      const raw =
          '<p>Hello world<br><a class="feed-link-url" href="https://m.coolapk.com/feed/123">查看链接</a><script>alert(1)</script></p>';
      final sanitized = sanitizeCoolapkMessage(raw);

      expect(sanitized, contains('Hello world'));
      expect(
        sanitized,
        contains(
          '<a class="feed-link-url" href="https://m.coolapk.com/feed/123">查看链接</a>',
        ),
      );
      expect(sanitized, isNot(contains('<script>')));
      expect(sanitized, isNot(contains('alert(1)')));
    });

    test('replaces coolapk emoji images with textual fallback', () {
      const raw =
          '<img alt="[偷笑]" src="https://static.coolapk.com/emotion/1.png" />';
      final sanitized = sanitizeCoolapkMessage(raw);
      expect(sanitized, '[偷笑]');
    });
  });

  group('CoolapkRichText HTML Link & Entity Rendering Tests', () {
    testWidgets(
      'renders HTML <a> tag as clickable link text and decodes entities',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        const sample =
            '请点击：<a class="feed-link-url" href="https://coolapk.com/feed/99999">查看链接</a> &amp; 关注 #测试话题# @酷安小编';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoolapkRichText(api: mockApi, text: sample),
            ),
          ),
        );

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsOneWidget);

        final richText = tester.widget<RichText>(richTextFinder);
        final plainText = richText.text.toPlainText();

        // Ensure raw HTML tags are NOT shown
        expect(plainText, isNot(contains('<a')));
        expect(plainText, isNot(contains('</a>')));
        expect(plainText, isNot(contains('class="feed-link-url"')));

        // Ensure displayText "查看链接" is shown
        expect(plainText, contains('查看链接'));
        // Ensure HTML entity &amp; is decoded to &
        expect(plainText, contains('&'));
        expect(plainText, isNot(contains('&amp;')));
        // Ensure topic and mention are present
        expect(plainText, contains('#测试话题#'));
        expect(plainText, contains('@酷安小编'));
      },
    );

    testWidgets(
      'renders relative HTML <a> href without displaying raw markup',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        const sample = '<a href="/feed/12345">查看动态</a>';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoolapkRichText(api: mockApi, text: sample),
            ),
          ),
        );

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsOneWidget);

        final richText = tester.widget<RichText>(richTextFinder);
        final plainText = richText.text.toPlainText();

        expect(plainText, '查看动态');
      },
    );

    testWidgets(
      'tags and mentions do not have underline, and trailing Chinese text is separated',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        const sample =
            '<a href="/t/ProjectTreble">#ProjectTreble#</a> 并且 <a href="/u/12345">@oosexgang团队透露</a> 了信息，另外纯文本 @酷安小编 也一样，请点 <a href="https://coolapk.com">查看链接</a>';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoolapkRichText(api: mockApi, text: sample),
            ),
          ),
        );

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsOneWidget);

        final richText = tester.widget<RichText>(richTextFinder);
        final textSpan = richText.text as TextSpan;
        final spans = <TextSpan>[];
        textSpan.visitChildren((span) {
          if (span is TextSpan && span.text != null && span.text!.isNotEmpty) {
            spans.add(span);
          }
          return true;
        });

        // 1. Tag #ProjectTreble# has NO underline
        final tagSpan = spans.firstWhere((s) => s.text == '#ProjectTreble#');
        expect(tagSpan.style?.decoration, isNot(TextDecoration.underline));
        expect(tagSpan.style?.fontWeight, FontWeight.w600);

        // 2. HTML Mention @oosexgang has NO underline, and 团队透露 is separated
        final mentionSpan = spans.firstWhere((s) => s.text == '@oosexgang');
        expect(mentionSpan.style?.decoration, isNot(TextDecoration.underline));
        expect(mentionSpan.style?.fontWeight, FontWeight.w600);

        final trailingSpan = spans.firstWhere((s) => s.text == '团队透露');
        expect(trailingSpan.style?.fontWeight, isNot(FontWeight.w600));

        // 3. Plain text mention @酷安小编 has NO underline
        final plainMentionSpan = spans.firstWhere((s) => s.text == '@酷安小编');
        expect(
          plainMentionSpan.style?.decoration,
          isNot(TextDecoration.underline),
        );
        expect(plainMentionSpan.style?.fontWeight, FontWeight.w600);

        // 4. URL "查看链接" has underline and matching decorationColor
        final urlSpan = spans.firstWhere((s) => s.text == '查看链接');
        expect(urlSpan.style?.decoration, TextDecoration.underline);
        expect(urlSpan.style?.decorationColor, equals(urlSpan.style?.color));
      },
    );

    testWidgets('email addresses are not parsed as mentions', (tester) async {
      final mockApi = _MockCoolapkApi();
      const sample = '联系我们：support@coolapk.com 谢谢';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolapkRichText(api: mockApi, text: sample),
          ),
        ),
      );

      final richTextFinder = find.byType(RichText);
      expect(richTextFinder, findsOneWidget);

      final richText = tester.widget<RichText>(richTextFinder);
      final plainText = richText.text.toPlainText();
      expect(plainText, '联系我们：support@coolapk.com 谢谢');

      final textSpan = richText.text as TextSpan;
      final spans = textSpan.children!;
      // Should not contain a mention token for @coolapk
      expect(spans.any((s) => s is TextSpan && s.text == '@coolapk'), isFalse);
    });

    testWidgets(
      'handles non-percent-encoded Chinese URI without throwing exception or gray screen',
      (tester) async {
        final mockApi = _MockCoolapkApi();
        const sample =
            '感谢大佬<a class="feed-link-uname" href="/u/暗影双生">@暗影双生</a> 的贡献！以及链接 <a href="/t/小米14">#小米14#</a>';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoolapkRichText(api: mockApi, text: sample),
            ),
          ),
        );

        final richTextFinder = find.byType(RichText);
        expect(richTextFinder, findsOneWidget);

        final richText = tester.widget<RichText>(richTextFinder);
        final plainText = richText.text.toPlainText();
        expect(plainText, contains('@暗影双生'));
        expect(plainText, contains('#小米14#'));
      },
    );
  });
}
