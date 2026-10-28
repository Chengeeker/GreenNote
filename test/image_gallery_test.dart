// ignore_for_file: unnecessary_underscores, unnecessary_const
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:greennote/core/utils/spring_page_route.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/coolapk_image.dart';
import 'package:greennote/core/utils/haptic_feedback_util.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';
import 'package:greennote/features/feed/nine_grid_view.dart';
import 'package:greennote/features/shared/api_list_page.dart'
    show UserSpacePage;

class GalleryApi implements CoolapkApi {
  @override
  bool get isAnonymous => false;

  const GalleryApi();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const galleryTestPic = GalleryImage('https://example.com/gallery-test.jpg');

const portraitGalleryTestPic = GalleryImage(
  'https://example.com/portrait-gallery-test.jpg',
  width: 9,
  height: 16,
);

class RecordingNavigatorObserver extends NavigatorObserver {
  String? poppedRouteName;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRouteName = route.settings.name;
    super.didPop(route, previousRoute);
  }
}

class InterruptibleGalleryRoute extends PhysicsSpringGalleryRoute<void> {
  InterruptibleGalleryRoute({required super.child});

  void beginReturn() => controller!.reverse();
  void cancelReturn() => controller!.forward();
}

class GalleryFeedApi extends GalleryApi {
  final actions = <String>[];
  Map<String, dynamic> detail = {};
  Future<Map<String, dynamic>>? pendingDetail;
  bool rejectNextLike = false;
  String session = 'gallery-account';
  @override
  String get notificationSessionKey => session;
  @override
  Future<Map<String, dynamic>> getFeedDetail(String id) =>
      pendingDetail ?? Future.value(detail);
  @override
  String get currentUid => '99';
  @override
  bool get hasCookie => true;
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async =>
      throw const CoolapkApiException('离线测试');
  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async => {};
  @override
  Future<void> followUser(String uid, {required bool following}) async =>
      actions.add('follow:$uid:$following');
  @override
  Future<void> likeFeed(String id, {required bool liked}) async {
    actions.add('like:$id:$liked');
    if (rejectNextLike) {
      rejectNextLike = false;
      throw const CoolapkApiException('不要重复点赞');
    }
  }

  @override
  Future<void> favoriteFeed(
    String id, {
    required bool favorited,
    CoolapkFeed? feed,
  }) async => actions.add('favorite:$id:$favorited');
}

class _DoubleTapState extends Fake implements ExtendedImageGestureState {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_DoubleTapState';
  double scale = 1;
  @override
  Offset get pointerDownPosition => const Offset(100, 100);
  @override
  GestureDetails get gestureDetails => GestureDetails(totalScale: scale);
  @override
  void handleDoubleTap({double? scale, Offset? doubleTapPosition}) {
    this.scale = scale ?? this.scale;
  }
}

void main() {
  test('gallery route uses the requested open and return durations', () {
    final route = PhysicsSpringGalleryRoute<void>(child: const SizedBox());

    expect(route.transitionDuration, const Duration(milliseconds: 330));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
  });

  test(
    'official userAction flags take priority and legacy flags remain supported',
    () {
      for (final value in [1, '1', true]) {
        final feed = CoolapkFeed.fromJson({
          'isLike': 0,
          'userAction': {'like': value, 'collect': value},
        });
        expect(feed.liked, isTrue);
        expect(feed.favorited, isTrue);
      }
      expect(
        CoolapkFeed.fromJson({
          'isLike': 1,
          'userAction': {'like': 0},
        }).liked,
        isFalse,
      );
      expect(
        CoolapkFeed.fromJson({'is_like': 1, 'is_favorite': true}).liked,
        isTrue,
      );
      expect(
        CoolapkFeed.fromJson({'is_like': 1, 'is_favorite': true}).favorited,
        isTrue,
      );
    },
  );
  Future<void> mountFeedGallery(
    WidgetTester tester,
    GalleryFeedApi api, {
    bool glass = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final feed = CoolapkFeed.fromJson({
      'id': '42',
      'uid': '7',
      'username': '图片作者',
      'message': '#艺术#',
      'likenum': 16,
      'replynum': 23,
      'favnum': 7,
      'forwardnum': 9,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ImageGalleryPage(
            api: api,
            pics: const [galleryTestPic],
            initialIndex: 0,
            statusId: '42',
            feed: feed,
            useLiquidGlass: glass,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'duplicate-like response resyncs to liked and next tap cancels it',
    (tester) async {
      final api = GalleryFeedApi();
      await mountFeedGallery(tester, api);
      api.detail = {
        'userAction': {'like': 1},
        'likenum': 66,
      };
      api.rejectNextLike = true;
      await tester.tap(find.byTooltip('点赞'));
      await tester.pump();
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.text('66'), findsOneWidget);
      await tester.tap(find.byTooltip('点赞'));
      await tester.pump();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(api.actions, ['like:42:false', 'like:42:true']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    },
  );
  testWidgets(
    'server liked state is shown and taps alternate unlike then like',
    (tester) async {
      final api = GalleryFeedApi()
        ..detail = {
          'userAction': {'like': 1},
          'likenum': 66,
        };
      await mountFeedGallery(tester, api);
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.text('66'), findsOneWidget);
      await tester.tap(find.byTooltip('点赞'));
      await tester.pump();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('65'), findsOneWidget);
      await tester.tap(find.byTooltip('点赞'));
      await tester.pump();
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.text('66'), findsOneWidget);
      expect(api.actions, ['like:42:true', 'like:42:false']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('late status read cannot undo a new like or cross accounts', (
    tester,
  ) async {
    for (final accountChange in [false, true]) {
      final pending = Completer<Map<String, dynamic>>();
      final api = GalleryFeedApi()..pendingDetail = pending.future;
      await mountFeedGallery(tester, api);
      if (accountChange) {
        api.session = 'another-account';
      } else {
        await tester.tap(find.byTooltip('点赞'));
        await tester.pump();
      }
      pending.complete({
        'userAction': {'like': accountChange ? 1 : 0},
        'likenum': 99,
      });
      await tester.pump();
      expect(find.text('99'), findsNothing);
      expect(
        find.byIcon(accountChange ? Icons.thumb_up_outlined : Icons.thumb_up),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'gallery uses six independent 48px round glass buttons and a spaced glass follow pill',
    (tester) async {
      await mountFeedGallery(tester, GalleryFeedApi(), glass: true);
      final buttons = tester
          .widgetList<GlassButton>(find.byType(GlassButton))
          .toList();
      expect(buttons, hasLength(7));
      for (final button in buttons.where((b) => b.label != '关注')) {
        expect(button.width, 48);
        expect(button.height, 48);
        expect(button.shape, const LiquidOval());
        expect(button.useOwnLayer, isTrue);
      }
      final follow = find.byWidgetPredicate(
        (w) => w is GlassButton && w.label == '关注',
      );
      final more = find.byWidgetPredicate(
        (w) => w is GlassButton && w.label == '更多',
      );
      expect(
        tester.widget<GlassButton>(follow).shape,
        const LiquidRoundedRectangle(borderRadius: 24),
      );
      expect(
        tester.getTopLeft(more).dx - tester.getTopRight(follow).dx,
        greaterThanOrEqualTo(12),
      );
      expect(tester.widget<AppAvatar>(find.byType(AppAvatar)).size, 48);
      for (final count in ['16', '23', '7', '9']) {
        expect(find.text(count), findsOneWidget);
      }
      expect(find.byType(GlassButtonGroup), findsNothing);
      final topKey = GlassBackdropGroup.keyOf(tester.element(follow));
      expect(topKey, isNotNull);
      expect(GlassBackdropGroup.keyOf(tester.element(more)), same(topKey));
      final footerKeys = ['点赞', '回复', '收藏', '分享'].map((label) {
        final button = find.byWidgetPredicate(
          (w) => w is GlassButton && w.label == label,
        );
        return GlassBackdropGroup.keyOf(tester.element(button));
      }).toList();
      expect(footerKeys.first, isNotNull);
      expect(footerKeys, everyElement(same(footerKeys.first)));
      expect(footerKeys.first, isNot(same(topKey)));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'feed gallery has author, real actions and four image menu entries without a single-image strip',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = GalleryFeedApi();
      final feed = CoolapkFeed.fromJson({
        'id': '42',
        'uid': '7',
        'username': '图片作者',
        'message': '#艺术#',
        'likenum': 16,
        'favnum': 7,
        'picArr': [galleryTestPic.url],
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageGalleryPage(
              api: api,
              pics: const [galleryTestPic],
              initialIndex: 0,
              statusId: '42',
              feed: feed,
              useLiquidGlass: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('图片作者'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gallery-thumbnail-strip')),
        findsNothing,
      );
      await tester.tap(find.text('关注'));
      await tester.pump();
      expect(find.text('已关注'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pump();
      expect(find.text('17'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();
      expect(api.actions, [
        'follow:7:false',
        'like:42:false',
        'favorite:42:false',
      ]);
      await tester.tap(find.byTooltip('更多'));
      await tester.pump(const Duration(milliseconds: 400));
      for (final label in ['分享图片', '保存原图', '保存全部原图', '设为壁纸']) {
        expect(find.text(label), findsOneWidget);
      }
      Navigator.of(tester.element(find.text('分享图片'))).pop();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('图片作者'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<UserSpacePage>(find.byType(UserSpacePage)).uid, '7');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'second page keeps its own preview while original decode is pending',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const pics = [
        GalleryImage('https://example.com/preview-first.jpg'),
        GalleryImage('https://example.com/preview-second.jpg'),
      ];
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() => picture.toImage(40, 80)))!;
      picture.dispose();
      final pending = Completer<ImageInfo>();
      final keys = <Object>[];
      for (var index = 0; index < pics.length; index++) {
        for (final width in <int?>[null, 160]) {
          final provider = ExtendedImage.network(
            pics[index].originalUrl,
            cache: true,
            cacheWidth: width,
            headers: coolapkImageHeaders(pics[index].originalUrl),
          ).image;
          final key = await provider.obtainKey(ImageConfiguration.empty);
          keys.add(key);
          tester.binding.imageCache.putIfAbsent(
            key,
            () => OneFrameImageStreamCompleter(
              index == 1 && width == null
                  ? pending.future
                  : Future.value(ImageInfo(image: pixels.clone())),
            ),
          );
        }
      }
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageGalleryPage(
              api: const GalleryApi(),
              pics: pics,
              initialIndex: 0,
              statusId: 'slow-second',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      final pager = tester.widget<ExtendedImageGesturePageView>(
        find.byType(ExtendedImageGesturePageView),
      );
      pager.controller.jumpToPage(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final preview = find.byKey(const ValueKey('gallery-loading-preview-1'));
      expect(preview, findsOneWidget);
      final previewImage = tester.widget<ExtendedImage>(
        find.descendant(of: preview, matching: find.byType(ExtendedImage)),
      );
      expect((previewImage.image as ExtendedResizeImage).width, 160);
      expect(previewImage.fit, BoxFit.contain);
      expect(
        await previewImage.image.obtainKey(ImageConfiguration.empty),
        keys[3],
      );
      expect(
        tester
            .widget<ExtendedImage>(
              find.byKey(const ValueKey('gallery-image-1')),
            )
            .gaplessPlayback,
        isTrue,
      );
      pending.complete(ImageInfo(image: pixels.clone()));
      await tester.pump();
      await tester.pump();
      expect(preview, findsNothing);
      await tester.pumpWidget(const SizedBox());
      for (final key in keys) {
        tester.binding.imageCache.evict(key);
      }
      pixels.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'double tap zoom emits one medium haptic per action and respects disabled feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      });
      final wasEnabled = HapticFeedbackUtil.isEnabled;
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        HapticFeedbackUtil.isEnabled = wasEnabled;
        HapticFeedbackUtil.resetForTesting();
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: ImageGalleryPage(
            api: GalleryApi(),
            pics: [galleryTestPic],
            initialIndex: 0,
            statusId: 'double-tap-feedback',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final image = tester
          .widgetList<ExtendedImage>(find.byType(ExtendedImage))
          .firstWhere((image) => image.onDoubleTap != null);
      final state = _DoubleTapState();
      for (final target in [2.5, 6.0, 1.0]) {
        HapticFeedbackUtil.isEnabled = true;
        HapticFeedbackUtil.resetForTesting();
        calls.clear();
        image.onDoubleTap!(state);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(state.scale, closeTo(target, .01));
        expect(calls, hasLength(1));
        expect(calls.single.arguments, 'HapticFeedbackType.mediumImpact');
      }
      HapticFeedbackUtil.isEnabled = false;
      HapticFeedbackUtil.resetForTesting();
      calls.clear();
      image.onDoubleTap!(state);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(state.scale, closeTo(2.5, .01));
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final finishDecode in [false, true]) {
    testWidgets('Hero keeps preview until original decodes ($finishDecode)', (
      tester,
    ) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final pixels = (await tester.runAsync(() => picture.toImage(40, 80)))!;
      picture.dispose();
      final original = Completer<ImageInfo>();
      final provider = ExtendedImage.network(
        galleryTestPic.originalUrl,
        cache: true,
        headers: coolapkImageHeaders(galleryTestPic.originalUrl),
      ).image;
      final key = await provider.obtainKey(ImageConfiguration.empty);
      tester.binding.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(original.future),
      );
      final scope = Object();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: Center(
              child: ImageGalleryHeroThumbnail(
                scope: scope,
                index: 0,
                pic: galleryTestPic,
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: RawImage(image: pixels, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
      );
      nav.currentState!.push<void>(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => ImageGalleryPage(
            api: const GalleryApi(),
            pics: const [galleryTestPic],
            initialIndex: 0,
            statusId: 'delayed-original',
            heroScope: scope,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      final preview = find.byKey(const ValueKey('gallery-opening-preview'));
      expect(preview, findsOneWidget);
      expect(tester.widget<RawImage>(preview).image!.isCloneOf(pixels), isTrue);
      expect(
        find.byKey(const ValueKey('gallery-image-flight-plane')),
        findsNothing,
      );
      if (finishDecode) {
        original.complete(ImageInfo(image: pixels.clone()));
        await tester.pump();
        await tester.pump();
        expect(preview, findsNothing);
        expect(find.byType(ExtendedImageGesture), findsOneWidget);
      }
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      tester.binding.imageCache.evict(key);
      pixels.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('gallery pairs its fullscreen image with the source thumbnail', (
    tester,
  ) async {
    final heroScope = Object();
    final heroTag = ImageGalleryHeroTag.forPic(
      scope: heroScope,
      index: 0,
      pic: galleryTestPic,
    );
    final sourceThumbnail = find.byKey(const ValueKey('hero-source-thumbnail'));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                key: const ValueKey('hero-source-thumbnail'),
                onTap: () => Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    opaque: false,
                    barrierColor: Colors.black,
                    transitionDuration: const Duration(milliseconds: 220),
                    pageBuilder: (_, __, ___) => ImageGalleryPage(
                      api: const GalleryApi(),
                      pics: const [galleryTestPic],
                      initialIndex: 0,
                      statusId: 'hero-test',
                      heroScope: heroScope,
                    ),
                  ),
                ),
                child: ImageGalleryHeroThumbnail(
                  scope: heroScope,
                  index: 0,
                  pic: galleryTestPic,
                  child: const SizedBox(
                    width: 80,
                    height: 80,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Finder matchingHero() => find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == heroTag,
    );

    expect(matchingHero(), findsOneWidget);
    await tester.tap(sourceThumbnail);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(matchingHero(), findsWidgets);
    // Gallery networking/gesture widgets may keep frames scheduled, so finish
    // the 220 ms route transition with bounded pumps instead of settling all.
    await tester.pump(const Duration(milliseconds: 250));
    expect(matchingHero(), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery chrome fades after route open and as pop begins', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('host page')),
      ),
    );

    navigatorKey.currentState!.push<void>(
      PhysicsSpringGalleryRoute(
        child: const ImageGalleryPage(
          api: const GalleryApi(),
          pics: [galleryTestPic, galleryTestPic],
          initialIndex: 0,
          statusId: 'thumbnail-transition',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final fade = find.byKey(const ValueKey('gallery-thumbnail-strip-fade'));
    final backButtonFade = find.byKey(
      const ValueKey('gallery-back-button-opacity'),
    );
    final counterFade = find.byKey(const ValueKey('gallery-counter-opacity'));
    final downloadButtonFade = find.byKey(
      const ValueKey('gallery-download-button-opacity'),
    );
    final topControlsGate = find.byKey(
      const ValueKey('gallery-top-controls-pointer-gate'),
    );
    final pageView = find.byType(ExtendedImageGesturePageView);
    expect(pageView, findsOneWidget);
    final pageSize = tester.getSize(pageView);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    expect(tester.widget<Opacity>(backButtonFade).opacity, 0);
    expect(tester.widget<Opacity>(counterFade).opacity, 0);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 0);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isTrue);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('保存高清大图到相册'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 330));
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isFalse);
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.widget<Opacity>(backButtonFade).opacity,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.widget<Opacity>(backButtonFade).opacity, 1);
    expect(tester.widget<Opacity>(counterFade).opacity, 1);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 1);
    expect(tester.getSize(pageView), pageSize);

    navigatorKey.currentState!.pop();
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
    expect(tester.widget<IgnorePointer>(topControlsGate).ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      tester.widget<Opacity>(backButtonFade).opacity,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.widget<Opacity>(backButtonFade).opacity, 0);
    expect(tester.widget<Opacity>(counterFade).opacity, 0);
    expect(tester.widget<Opacity>(downloadButtonFade).opacity, 0);
    expect(tester.getSize(pageView), pageSize);
    expect(tester.getSize(pageView), pageSize);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery removes all glass buttons during the return', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('host')),
        ),
      ),
    );
    final route = InterruptibleGalleryRoute(
      child: ImageGalleryPage(
        api: GalleryFeedApi(),
        pics: const [galleryTestPic],
        initialIndex: 0,
        statusId: '42',
        feed: CoolapkFeed.fromJson({'id': '42', 'uid': '7', 'username': '作者'}),
        useLiquidGlass: true,
      ),
    );
    nav.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pump(const Duration(milliseconds: 140));
    final follow = find.byWidgetPredicate(
      (w) => w is GlassButton && w.label == '关注',
    );
    final like = find.byWidgetPredicate(
      (w) => w is GlassButton && w.label == '点赞',
    );
    expect(tester.widget<GlassButton>(like).quality, GlassQuality.premium);
    expect(tester.widget<GlassButton>(follow).quality, GlassQuality.premium);
    route.beginReturn();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byType(GlassButton), findsNothing);
    expect(
      find.byKey(const ValueKey('gallery-top-controls-pointer-gate')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('gallery-footer-backdrop-group')),
      findsNothing,
    );
    route.cancelReturn();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.widget<GlassButton>(like).quality, GlassQuality.premium);
    expect(tester.widget<GlassButton>(follow).quality, GlassQuality.premium);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(ImageGalleryPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary gallery removes glass controls as return begins', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Scaffold()),
    );
    nav.currentState!.push(
      PhysicsSpringGalleryRoute(
        child: const ImageGalleryPage(
          api: GalleryApi(),
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'ordinary',
          useLiquidGlass: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      tester
          .widgetList<GlassButton>(find.byType(GlassButton))
          .map((b) => b.quality),
      everyElement(GlassQuality.premium),
    );
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byType(GlassButton), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(ImageGalleryPage), findsNothing);
  });

  testWidgets('only the selected gallery image pairs with its source Hero', (
    tester,
  ) async {
    final heroScope = Object();
    const pics = [galleryTestPic, galleryTestPic, galleryTestPic];
    ImageGalleryHeroTag tagFor(int index) => ImageGalleryHeroTag.forPic(
      scope: heroScope,
      index: index,
      pic: galleryTestPic,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                pics.length,
                (index) => ImageGalleryHeroThumbnail(
                  scope: heroScope,
                  index: index,
                  pic: pics[index],
                  child: GestureDetector(
                    key: ValueKey('source-thumbnail-$index'),
                    onTap: () => Navigator.of(context).push<void>(
                      PageRouteBuilder<void>(
                        opaque: false,
                        transitionDuration: const Duration(milliseconds: 220),
                        pageBuilder: (_, __, ___) => ImageGalleryPage(
                          api: const GalleryApi(),
                          pics: pics,
                          initialIndex: index,
                          statusId: 'multi-hero-test',
                          heroScope: heroScope,
                        ),
                      ),
                    ),
                    child: const SizedBox(
                      width: 72,
                      height: 72,
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    int heroCount(int index) => find
        .byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == tagFor(index),
        )
        .evaluate()
        .length;

    await tester.tap(find.byKey(const ValueKey('source-thumbnail-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(heroCount(0), 2, reason: 'the open image pairs with its source');
    expect(heroCount(1), 1, reason: 'the adjacent cached page has no Hero');
    expect(heroCount(2), 1);

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('2 / 3'), findsOneWidget);
    expect(heroCount(0), 1, reason: 'the previous image stays at its source');
    expect(heroCount(1), 2, reason: 'only the selected image pairs');
    expect(heroCount(2), 1);

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('3 / 3'), findsOneWidget);
    expect(heroCount(0), 1);
    expect(heroCount(1), 1, reason: 'the previously visited page is cached');
    expect(heroCount(2), 2, reason: 'return animates only the visible image');
    expect(tester.takeException(), isNull);
  });

  for (final pixels in [const Size(240, 120), const Size(120, 240)]) {
    for (final zoom in [1.0, 1.8]) {
      testWidgets(
        'return endpoints match ExtendedImage crop for $pixels zoom $zoom',
        (tester) async {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          // Patterned pixels expose wrong fit/crop, unlike a solid-colour image.
          for (var x = 0; x < pixels.width; x += 10) {
            for (var y = 0; y < pixels.height; y += 10) {
              canvas.drawRect(
                Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
                Paint()
                  ..color = Color.fromARGB(
                    255,
                    x % 256,
                    y % 256,
                    (x + y) % 256,
                  ),
              );
            }
          }
          final picture = recorder.endRecording();
          final image = (await tester.runAsync(
            () => picture.toImage(pixels.width.toInt(), pixels.height.toInt()),
          ))!;
          picture.dispose();
          final navigatorKey = GlobalKey<NavigatorState>();
          final sourceKey = GlobalKey();
          final galleryKey = GlobalKey();
          final boundaryKey = GlobalKey();
          final galleryBoundaryKey = GlobalKey();
          final tag = ImageGalleryHeroTag.forPic(
            scope: Object(),
            index: 0,
            pic: galleryTestPic,
          );
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: Hero(
                      key: sourceKey,
                      tag: tag,
                      flightShuttleBuilder:
                          imageGalleryHeroFlightShuttleBuilder,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ExtendedRawImage(
                            image: image,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          Future<List<int>> screenshot(GlobalKey key) async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final snapshot = await boundary.toImage(pixelRatio: 1);
            final data = await snapshot.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            snapshot.dispose();
            return data!.buffer.asUint8List().toList();
          }

          final expected = await tester.runAsync(() => screenshot(boundaryKey));
          navigatorKey.currentState!.push<void>(
            PhysicsSpringGalleryRoute(
              child: Scaffold(
                body: Center(
                  child: Hero(
                    key: galleryKey,
                    tag: tag,
                    flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
                    child: RepaintBoundary(
                      key: galleryBoundaryKey,
                      child: SizedBox(
                        width: 300,
                        height: 400,
                        child: ExtendedRawImage(
                          image: image,
                          fit: BoxFit.contain,
                          gestureDetails: GestureDetails(
                            totalScale: zoom,
                            offset: const Offset(-25, -35),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expectedStart = await tester.runAsync(
            () => screenshot(galleryBoundaryKey),
          );
          Widget? pushStartShuttle;
          Widget? pushEndShuttle;
          if (zoom == 1.0) {
            pushStartShuttle = imageGalleryHeroFlightShuttleBuilder(
              sourceKey.currentContext!,
              const AlwaysStoppedAnimation(0),
              HeroFlightDirection.push,
              sourceKey.currentContext!,
              galleryKey.currentContext!,
            );
            pushEndShuttle = imageGalleryHeroFlightShuttleBuilder(
              sourceKey.currentContext!,
              const AlwaysStoppedAnimation(1),
              HeroFlightDirection.push,
              sourceKey.currentContext!,
              galleryKey.currentContext!,
            );
          }
          final startShuttle = imageGalleryHeroFlightShuttleBuilder(
            galleryKey.currentContext!,
            const AlwaysStoppedAnimation(1),
            HeroFlightDirection.pop,
            galleryKey.currentContext!,
            sourceKey.currentContext!,
          );
          // Explicit endpoint painting lets us compare every pixel at handoff;
          // the source and destination are real ExtendedRenderImage objects.
          final shuttle = imageGalleryHeroFlightShuttleBuilder(
            galleryKey.currentContext!,
            const AlwaysStoppedAnimation(0),
            HeroFlightDirection.pop,
            galleryKey.currentContext!,
            sourceKey.currentContext!,
          );
          navigatorKey.currentState!.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.byKey(const ValueKey('gallery-image-flight-plane')),
            findsOneWidget,
          );
          expect(
            tester
                .renderObject(
                  find.byKey(const ValueKey('gallery-image-flight-plane')),
                )
                .parent,
            isA<RenderRepaintBoundary>(),
          );
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(width: 300, height: 400, child: startShuttle),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            await tester.runAsync(() => screenshot(boundaryKey)),
            expectedStart,
            reason: 'first flight pixels must keep current zoom/pan and paint offset',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(width: 100, height: 100, child: shuttle),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            await tester.runAsync(() => screenshot(boundaryKey)),
            expected,
            reason: 'last flight pixels must equal the rounded cover thumbnail',
          );
          if (pushStartShuttle != null && pushEndShuttle != null) {
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: pushStartShuttle,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(
              await tester.runAsync(() => screenshot(boundaryKey)),
              expected,
              reason: 'push starts with the visible thumbnail pixels',
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 300,
                      height: 400,
                      child: pushEndShuttle,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(
              await tester.runAsync(() => screenshot(boundaryKey)),
              expectedStart,
              reason: 'push ends with the fullscreen contain-fit image',
            );
          }
          await tester.pumpWidget(const SizedBox());
          image.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('return without decoded pixels keeps existing gallery fallback', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final tag = ImageGalleryHeroTag.forPic(
      scope: Object(),
      index: 0,
      pic: portraitGalleryTestPic,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Center(
          child: Hero(
            tag: tag,
            flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );
    nav.currentState!.push<void>(
      PhysicsSpringGalleryRoute(
        child: Center(
          child: Hero(
            tag: tag,
            flightShuttleBuilder: imageGalleryHeroFlightShuttleBuilder,
            child: const SizedBox(
              key: ValueKey('fallback-gallery'),
              width: 280,
              height: 420,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('fallback-gallery')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail decoding preserves aspect ratio before cover crop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGalleryPage(
          api: const GalleryApi(),
          pics: [galleryTestPic, galleryTestPic],
          initialIndex: 0,
          statusId: 'crop',
        ),
      ),
    );
    final images = tester.widgetList<ExtendedImage>(
      find.descendant(
        of: find.byKey(const ValueKey('gallery-thumbnail-strip')),
        matching: find.byType(ExtendedImage),
      ),
    );
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.fit, BoxFit.cover);
      final provider = image.image as ExtendedResizeImage;
      expect(provider.width, 160);
      expect(provider.height, isNull);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final direction in [-1.0, 1.0]) {
      testWidgets(
        'fast thumbnail fling keeps main image synchronized without rewind: $platform $direction',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: ImageGalleryPage(
                api: const GalleryApi(),
                pics: List.filled(18, galleryTestPic),
                initialIndex: 8,
                statusId: 'fast',
              ),
            ),
          );
          await tester.pump();
          final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
          final thumbnails = tester.widget<PageView>(
            find.descendant(of: strip, matching: find.byType(PageView)),
          );
          final main = tester.widget<ExtendedImageGesturePageView>(
            find.byType(ExtendedImageGesturePageView),
          );
          expect(thumbnails.pageSnapping, isFalse);
          expect(thumbnails.physics, isA<ClampingScrollPhysics>());
          final seen = <String>{'9 / 18'};
          await tester.fling(strip, Offset(direction * 460, 0), 6500);
          for (var frame = 0; frame < 180; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              main.controller.page,
              closeTo(thumbnails.controller!.page!, 0.04),
              reason: 'main and reel should track each other on frame $frame',
            );
            final counter = tester.widget<Text>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text && widget.data?.endsWith(' / 18') == true,
              ),
            );
            seen.add(counter.data!);
          }
          expect(seen.length, greaterThan(2));
          final finalIndex = thumbnails.controller!.page!.round();
          expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
          expect(
            thumbnails.controller!.position.isScrollingNotifier.value,
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('main image follows thumbnail position throughout a drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGalleryPage(
          api: const GalleryApi(),
          pics: List.filled(18, galleryTestPic),
          initialIndex: 0,
          statusId: 'drag',
        ),
      ),
    );
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final main = tester.widget<ExtendedImageGesturePageView>(
      find.byType(ExtendedImageGesturePageView),
    );
    final gesture = await tester.startGesture(tester.getCenter(strip));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(main.controller.page, closeTo(thumbnails.controller!.page!, 0.02));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump(const Duration(milliseconds: 32));
    expect(main.controller.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(find.text('1 / 18'), findsNothing);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 160));
    final finalIndex = thumbnails.controller!.page!.round();
    expect(main.controller.page, closeTo(finalIndex.toDouble(), 0.02));
    expect(find.text('${finalIndex + 1} / 18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main navigation cancels old thumbnail inertia', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGalleryPage(
          api: const GalleryApi(),
          pics: List.filled(18, galleryTestPic),
          initialIndex: 8,
          statusId: 'interrupt',
        ),
      ),
    );
    await tester.pump();
    final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
    await tester.fling(strip, const Offset(-220, 0), 2200);
    await tester.pump(const Duration(milliseconds: 32));
    final main = find.byType(ExtendedImageGesturePageView);
    await tester.drag(main, const Offset(500, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final thumbnails = tester.widget<PageView>(
      find.descendant(of: strip, matching: find.byType(PageView)),
    );
    final mainController = tester
        .widget<ExtendedImageGesturePageView>(main)
        .controller;
    expect(mainController.page, closeTo(thumbnails.controller!.page!, 0.02));
    expect(tester.takeException(), isNull);
  });

  for (final count in [2, 8, 18]) {
    testWidgets(
      'thumbnail roller synchronizes tap and main swipe for $count photos',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ImageGalleryPage(
              api: const GalleryApi(),
              pics: List.filled(count, galleryTestPic),
              initialIndex: 0,
              statusId: 'roller',
            ),
          ),
        );
        await tester.pump();
        final strip = find.byKey(const ValueKey('gallery-thumbnail-strip'));
        expect(strip, findsOneWidget);
        expect(
          tester.getBottomLeft(strip).dy,
          lessThan(tester.view.physicalSize.height),
        );
        await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-1')));
        await tester.pump();
        expect(find.text('2 / $count'), findsOneWidget);
        final selected = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('gallery-thumbnail-1')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(selected.properties.selected, isTrue);
        final main = find.byType(ExtendedImageGesturePageView);
        await tester.drag(main, const Offset(600, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('1 / $count'), findsOneWidget);
        await tester.drag(strip, const Offset(-180, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('1 / $count'), findsNothing);
        expect(find.byType(ImageGalleryPage), findsOneWidget);
        await tester.tapAt(const Offset(400, 200));
        await tester.pump(const Duration(milliseconds: 350));
        expect(strip, findsNothing);
        await tester.tapAt(const Offset(400, 200));
        await tester.pump(const Duration(milliseconds: 350));
        expect(strip, findsOneWidget);
        expect(find.text('1 / $count'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('center tap toggles image gallery top controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageGalleryPage(
          api: const GalleryApi(),
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-thumbnail-strip')), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('side tap exits image gallery', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('host page')),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'image-gallery-test'),
        builder: (_) => const ImageGalleryPage(
          api: const GalleryApi(),
          pics: [galleryTestPic],
          initialIndex: 0,
          statusId: 'gallery-test',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(observer.poppedRouteName, 'image-gallery-test');
  });

  group('HDR Image & Badge Tests', () {
    test('GalleryImage correctly identifies HDR and priority of badgeText', () {
      HdrImageDetector.reset();

      // Normal
      const normalPic = GalleryImage('https://example.com/test.jpg');
      expect(normalPic.isHdr, isFalse);
      expect(normalPic.isGif, isFalse);
      expect(normalPic.isLong, isFalse);
      expect(normalPic.badgeText, '');

      // Explicit isHdr
      const explicitHdr = GalleryImage(
        'https://example.com/test.jpg',
        isHdr: true,
      );
      expect(explicitHdr.isHdr, isTrue);
      expect(explicitHdr.badgeText, 'HDR');

      // Raw metadata is_hdr = 1
      const rawHdr = GalleryImage(
        'https://example.com/test.jpg',
        raw: {'is_hdr': 1},
      );
      expect(rawHdr.isHdr, isTrue);
      expect(rawHdr.badgeText, 'HDR');

      // URL contains hdr=1
      const urlHdr = GalleryImage('https://example.com/test.jpg?hdr=1');
      expect(urlHdr.isHdr, isTrue);
      expect(urlHdr.badgeText, 'HDR');

      // Detected via HdrImageDetector
      const dynamicHdr = GalleryImage('https://example.com/dynamic_hdr.jpg');
      expect(dynamicHdr.isHdr, isFalse);
      HdrImageDetector.markHdr('https://example.com/dynamic_hdr.jpg');
      expect(dynamicHdr.isHdr, isTrue);
      expect(dynamicHdr.badgeText, 'HDR');

      // Badge priority: GIF > HDR > 长图
      const gifHdr = GalleryImage(
        'https://example.com/anim.gif',
        isHdr: true,
        width: 100,
        height: 300,
      );
      expect(gifHdr.isGif, isTrue);
      expect(gifHdr.isHdr, isTrue);
      expect(gifHdr.isLong, isTrue);
      expect(gifHdr.badgeText, 'GIF');

      const hdrLong = GalleryImage(
        'https://example.com/long.jpg',
        isHdr: true,
        width: 100,
        height: 300,
      );
      expect(hdrLong.badgeText, 'HDR');

      const plainLong = GalleryImage(
        'https://example.com/long.jpg',
        width: 100,
        height: 300,
      );
      expect(plainLong.badgeText, '长图');
    });

    test('HdrImageDetector detects Ultra HDR / GainMap byte signatures', () {
      expect(
        HdrImageDetector.checkBytes([
          ...List.filled(20, 0),
          ...('hdrgm:Version="1.0"'.codeUnits),
        ]),
        isTrue,
      );
      expect(
        HdrImageDetector.checkBytes([
          ...List.filled(30, 0),
          ...('urn:iso:std:iso:ts:21496:1'.codeUnits),
        ]),
        isTrue,
      );
      expect(
        HdrImageDetector.checkBytes([
          ...List.filled(10, 0),
          ...('xmlns:GainMap="http://ns.adobe.com/hdr-gain-map/1.0/"'
              .codeUnits),
        ]),
        isTrue,
      );
      expect(
        HdrImageDetector.checkBytes([
          ...List.filled(10, 0),
          ...('UltraHDR'.codeUnits),
        ]),
        isTrue,
      );
      expect(
        HdrImageDetector.checkBytes([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0,
          16,
          0x4A,
          0x46,
          0x49,
          0x46,
          0,
          1,
          1,
          0,
          0,
          1,
        ]),
        isFalse,
      );
    });

    testWidgets('NineGridView displays HDR badge for HDR image', (
      tester,
    ) async {
      const hdrPic = GalleryImage(
        'https://example.com/test_hdr.jpg',
        isHdr: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NineGridView(
              api: GalleryApi(),
              pics: [hdrPic],
              statusId: 'test_hdr',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('HDR'), findsOneWidget);
      await tester.tap(find.byType(ImageGalleryHeroThumbnail));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<ImageGalleryPage>(find.byType(ImageGalleryPage)).feed,
        isNull,
      );
      expect(find.byTooltip('保存高清大图到相册'), findsOneWidget);
      expect(find.byTooltip('更多'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'ImageGalleryPage requests window HDR mode and displays HDR badge',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views_2,
          (call) async => false,
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform_views_2,
            null,
          );
        });
        final methodCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.green.note/media'),
          (call) async {
            methodCalls.add(call);
            if (call.method == 'isHdrDisplaySupported') return true;
            return null;
          },
        );

        const hdrPic = GalleryImage(
          'https://example.com/view_hdr.jpg',
          isHdr: true,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ImageGalleryPage(
                api: GalleryApi(),
                pics: [hdrPic],
                initialIndex: 0,
                statusId: 'gallery_hdr_test',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'com.green.note/media',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('hdrImageDecoded', {
              'url': 'https://example.com/view_hdr.jpg',
              'hasGainMap': true,
            }),
          ),
          (ByteData? data) {},
        );
        await tester.pump();

        // Verifies window HDR was enabled
        final setHdrCalls = methodCalls
            .where((c) => c.method == 'setWindowHdr')
            .toList();
        expect(setHdrCalls.isNotEmpty, isTrue);
        expect(setHdrCalls.any((c) => c.arguments['enabled'] == true), isTrue);

        // Verifies HDR badge appears in full screen gallery
        expect(find.text('HDR'), findsOneWidget);
      },
    );

    for (final hybridSupported in [false, true]) {
      testWidgets('HDR scroll composition with HCPP=$hybridSupported', (
        tester,
      ) async {
        final platformCalls = <MethodCall>[];
        final windowCalls = <MethodCall>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        const mediaChannel = MethodChannel('com.green.note/media');
        messenger.setMockMethodCallHandler(mediaChannel, (call) async {
          if (call.method == 'setWindowHdr') windowCalls.add(call);
          if (call.method == 'isHdrDisplaySupported') return true;
          return null;
        });
        messenger.setMockMethodCallHandler(
          SystemChannels.platform_views_2,
          (call) async => hybridSupported,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          platformCalls.add(call);
          return null;
        });
        addTearDown(() {
          for (final channel in [
            mediaChannel,
            SystemChannels.platform_views,
            SystemChannels.platform_views_2,
          ]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
        });
        const pic = GalleryImage(
          'https://example.com/scroll_hdr.jpg',
          isHdr: true,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: ImageGalleryPage(
              api: GalleryApi(),
              pics: [pic, GalleryImage('https://example.com/scroll_sdr.jpg')],
              initialIndex: 0,
              statusId: 'hdr-scroll',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await messenger.handlePlatformMessage(
          mediaChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('hdrImageDecoded', {
              'url': 'https://example.com/scroll_hdr.jpg',
              'hasGainMap': true,
            }),
          ),
          (_) {},
        );
        await tester.pump();
        final nativeView = find.byType(PlatformViewLink);
        expect(nativeView, findsOneWidget);
        final nativeElement = tester.element(nativeView);
        final scrollContext = tester.element(
          find.byWidgetPredicate(
            (widget) => widget is ExtendedImageGesturePageView,
          ),
        );
        ScrollStartNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 800,
            pixels: 0,
            viewportDimension: 800,
            axisDirection: AxisDirection.right,
            devicePixelRatio: 1,
          ),
          context: scrollContext,
          dragDetails: DragStartDetails(),
        ).dispatch(scrollContext);
        await tester.pump();
        if (hybridSupported) {
          expect(nativeView, findsOneWidget);
          expect(tester.element(nativeView), same(nativeElement));
          final opacity = tester.widget<Opacity>(
            find.ancestor(of: nativeView, matching: find.byType(Opacity)).first,
          );
          expect(opacity.opacity, 1);
          expect(
            platformCalls.where((call) => call.method == 'dispose'),
            isEmpty,
          );
        } else {
          expect(nativeView, findsNothing);
          expect(
            platformCalls.where((call) => call.method == 'dispose'),
            hasLength(1),
          );
        }
        final windowCallCount = windowCalls.length;
        final pager = tester.widget<ExtendedImageGesturePageView>(
          find.byWidgetPredicate(
            (widget) => widget is ExtendedImageGesturePageView,
          ),
        );
        pager.controller.jumpToPage(1);
        await tester.pump();
        expect(windowCalls.length, windowCallCount);
        expect(windowCalls.last.arguments['enabled'], isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }

    testWidgets(
      'ImageGalleryPage disables swipe down exit and does not use ExtendedImageSlidePage',
      (tester) async {
        final pics = [
          const GalleryImage(
            'https://example.com/test_1.jpg',
            width: 800,
            height: 600,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: ImageGalleryPage(
              api: const GalleryApi(),
              pics: pics,
              initialIndex: 0,
              statusId: 'test-swipe-exit',
            ),
          ),
        );
        await tester.pump();

        // Verify ExtendedImageSlidePage is not in the tree
        expect(find.byType(ExtendedImageSlidePage), findsNothing);

        // Drag down on the image
        await tester.drag(
          find.byKey(const ValueKey('gallery-image-0')),
          const Offset(0, 300),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // Page should still be open (not dismissed)
        expect(find.byType(ImageGalleryPage), findsOneWidget);
      },
    );

    testWidgets(
      'ImageGalleryPage renders a sampling scope and GlassButton controls when useLiquidGlass=true',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: ImageGalleryPage(
              api: GalleryApi(),
              pics: [galleryTestPic],
              initialIndex: 0,
              statusId: 'liquid-glass-explicit',
              useLiquidGlass: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(GlassAdaptiveScope), findsOneWidget);
        expect(find.byType(LiquidGlassScope), findsOneWidget);
        expect(find.byType(GlassBackgroundSource), findsOneWidget);

        final glassButtons = tester
            .widgetList<GlassButton>(find.byType(GlassButton))
            .toList();
        expect(glassButtons.length, 2);

        final backButton = glassButtons.firstWhere((b) => b.label == '返回');
        expect(backButton.width, 48);
        expect(backButton.height, 48);
        expect(backButton.stretch, 0.8);
        expect(backButton.quality, GlassQuality.premium);
        expect(backButton.iconColor, Colors.white);
        expect((backButton.icon as Icon).color, Colors.white);
        expect(backButton.settings!.glassColor, const Color(0x66000000));
        expect(backButton.settings!.thickness, 32);
        expect(backButton.settings!.refractiveIndex, 1.24);

        final saveButton = glassButtons.firstWhere(
          (b) => b.label == '保存高清大图到相册',
        );
        expect(saveButton.width, 48);
        expect(saveButton.height, 48);
        expect(saveButton.stretch, 0.8);
        expect(saveButton.quality, GlassQuality.premium);
        expect(saveButton.iconColor, Colors.white);
        expect((saveButton.icon as Icon).color, Colors.white);
        expect(saveButton.settings!.glassColor, const Color(0x66000000));
        expect(saveButton.settings!.thickness, 32);
        expect(saveButton.settings!.refractiveIndex, 1.24);
      },
    );

    testWidgets(
      'ImageGalleryPage binds to appSettingsProvider.useLiquidGlassNavBar in ProviderScope',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'greennote.liquid_glass_nav': true,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ImageGalleryPage(
                api: GalleryFeedApi(),
                pics: const [galleryTestPic],
                initialIndex: 0,
                statusId: 'scope-liquid-glass',
                feed: CoolapkFeed.fromJson({
                  'id': '42',
                  'uid': '7',
                  'username': '图片作者',
                  'replynum': 23,
                }),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final glassButtons = tester
            .widgetList<GlassButton>(find.byType(GlassButton))
            .toList();
        expect(glassButtons, hasLength(7));
        final backButton = glassButtons.firstWhere((b) => b.label == '返回');
        final followButton = glassButtons.firstWhere((b) => b.label == '关注');
        final moreButton = glassButtons.firstWhere((b) => b.label == '更多');
        expect(backButton.iconColor, Colors.white);
        expect((backButton.icon as Icon).color, Colors.white);
        expect(followButton.iconColor, Colors.white);
        expect((followButton.icon as Text).style?.color, Colors.white);
        expect(moreButton.iconColor, Colors.white);
        expect((moreButton.icon as Icon).color, Colors.white);
        for (final button in glassButtons) {
          expect(button.settings!.glassColor, const Color(0x66000000));
        }

        // Switch setting to false
        await tester.runAsync(() async {
          await container
              .read(appSettingsProvider.notifier)
              .setLiquidGlassNavBar(false);
        });
        await tester.pump();

        expect(find.byType(GlassButton), findsNothing);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text('回复'), findsOneWidget);
        expect(find.text('分享'), findsOneWidget);
        await tester.runAsync(
          () => container
              .read(appSettingsProvider.notifier)
              .setLiquidGlassNavBar(true),
        );
        await tester.pump();
        expect(find.byType(GlassButton), findsNWidgets(7));
        expect(find.text('23'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      },
    );
  });
}
