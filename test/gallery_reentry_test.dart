import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/network/coolapk_image.dart';
import 'package:greennote/core/utils/spring_page_route.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_gallery_test.dart' show GalleryApi, galleryTestPic;

void main() {
  testWidgets('pending image tap cannot dismiss a newer route', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('原文章')),
      ),
    );
    nav.currentState!.push(
      PhysicsSpringGalleryRoute<void>(
        child: const ImageGalleryPage(
          api: GalleryApi(),
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'pending-tap',
          useLiquidGlass: false,
        ),
      ),
    );
    await _pumpFrames(tester);
    await tester.tapAt(const Offset(20, 220));
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('新页面')),
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('新页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'closing a nested gallery restores the previous native callback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      for (var i = 0; i < 2; i++) {
        nav.currentState!.push(
          PhysicsSpringGalleryRoute<void>(
            child: ImageGalleryPage(
              api: const GalleryApi(),
              pics: const [galleryTestPic],
              initialIndex: 0,
              statusId: 'nested-$i',
              useLiquidGlass: false,
            ),
          ),
        );
        await _pumpFrames(tester);
      }
      nav.currentState!.pop();
      await _pumpFrames(tester);
      const url = 'https://image.coolapk.com/restored-native-callback.jpg';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'com.green.note/media',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('hdrImageDecoded', {'url': url, 'hasGainMap': true}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(HdrImageDetector.isKnownHdr(url), isTrue);
      expect(find.byType(ImageGalleryPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'old gallery disposal must not clear the reopened native callback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('原文章')),
        ),
      );
      void open() => nav.currentState!.push(
        PhysicsSpringGalleryRoute<void>(
          child: const ImageGalleryPage(
            api: GalleryApi(),
            pics: [galleryTestPic],
            initialIndex: 0,
            statusId: 'overlap',
            useLiquidGlass: false,
          ),
        ),
      );
      open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      const url = 'https://image.coolapk.com/reopened-native-callback.jpg';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'com.green.note/media',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('hdrImageDecoded', {'url': url, 'hasGainMap': true}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(HdrImageDetector.isKnownHdr(url), isTrue);
      expect(find.byType(ImageGalleryPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final material in [false, true]) {
    testWidgets('repeated gallery close keeps the source route ($material)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Center(
              child: FilledButton(
                child: const Text('原文章图片'),
                onPressed: () {
                  const gallery = ImageGalleryPage(
                    api: GalleryApi(),
                    pics: [galleryTestPic],
                    initialIndex: 0,
                    statusId: 'rapid-reentry',
                    useLiquidGlass: false,
                  );
                  nav.currentState!.push(
                    material
                        ? MaterialPageRoute<void>(builder: (_) => gallery)
                        : PhysicsSpringGalleryRoute<void>(child: gallery),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final sourcePoint = tester.getCenter(find.text('原文章图片'));
      for (var cycle = 0; cycle < 12; cycle++) {
        await tester.tapAt(sourcePoint);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(ImageGalleryPage), findsOneWidget);
        final back = tester.getCenter(find.byTooltip('返回'));
        // Input can be delivered twice before the next rendered frame.
        await tester.tapAt(back);
        await tester.tapAt(back);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(nav.currentState!.canPop(), isFalse);
        expect(find.text('原文章图片'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(ImageGalleryPage), findsNothing);
      expect(nav.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Network image placeholders can animate indefinitely in widget tests.
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
