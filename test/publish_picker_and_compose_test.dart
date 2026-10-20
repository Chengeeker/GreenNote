import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/utils/haptic_feedback_util.dart';
import 'package:greennote/features/shell/main_pages.dart';

class _FakePublishApi implements CoolapkApi {
  String? createdMessage;
  String? createdPic;
  String? createdType;
  String? createdTag;
  String? createdLocation;
  String? createdProductId;
  String? createdVoteId;
  String? createdExtraTitle;

  @override
  String get loginRequiredMessage => '请先使用酷安账号登录';

  @override
  bool get isAnonymous => false;

  @override
  bool get hasCookie => true;

  @override
  String get currentUid => '1001';

  @override
  Future<String> uploadFeedImage(Uint8List bytes) async {
    return 'https://image.coolapk.com/feed/mock_picked_image.png';
  }

  @override
  Future<void> createFeed(
    String message, {
    String? pic,
    String type = 'feed',
    String? extraTitle,
    String? tag,
    String? location,
    String? productId,
    String? voteId,
  }) async {
    createdMessage = message;
    createdPic = pic;
    createdType = type;
    createdExtraTitle = extraTitle;
    createdTag = tag;
    createdLocation = location;
    createdProductId = productId;
    createdVoteId = voteId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('CoolapkPublishPickerSheet renders 8 official items with NEW badges and cancel button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePublishApi();
    String? selectedType;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => CoolapkPublishPickerSheet(
                    api: api,
                    onSelectType: (type) => selectedType = type,
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap to open sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify all 8 items exist
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('图文'), findsOneWidget);
    expect(find.text('点评广场'), findsOneWidget);
    expect(find.text('二手'), findsOneWidget);
    expect(find.text('酷图'), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);
    expect(find.text('天梯榜'), findsOneWidget);
    expect(find.text('投票'), findsOneWidget);

    // Verify NEW badges (点评广场, 清单, 天梯榜)
    expect(find.text('NEW'), findsNWidgets(3));

    // Verify 取消 button
    expect(find.text('取消'), findsOneWidget);

    // Tap 动态 selects 'feed'
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    expect(selectedType, 'feed');
  });

  testWidgets('ComposeFeedPage 1:1 official layout renders all elements, switches cover mode, inserts tags, and submits feed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePublishApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ComposeFeedPage(api: api),
      ),
    );
    await tester.pump();

    // Verify Top Bar: Close icon, 大封面 and 九宫格 segmented switcher, 发布 button
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    expect(find.text('大封面'), findsOneWidget);
    expect(find.text('九宫格'), findsOneWidget);
    expect(find.text('发布'), findsOneWidget);

    // Verify 发布到 row
    expect(find.text('发布到'), findsOneWidget);
    expect(find.text('选择合适的板块会有更多的赞'), findsOneWidget);

    // Verify Media Upload Area text hints
    expect(find.text('长按图片可拖动排序'), findsOneWidget);
    expect(find.text('发无关图、色情图将会被禁言'), findsOneWidget);

    // Verify Text placeholder
    expect(find.text('分享你此刻的想法…'), findsOneWidget);

    // Verify 谁可以看 row
    expect(find.text('谁可以看'), findsOneWidget);
    expect(find.text('公开'), findsOneWidget);

    // Verify Recommended topic chips
    expect(find.text('# 数码日常'), findsOneWidget);
    expect(find.text('# 123云盘'), findsOneWidget);
    expect(find.text('# VibeCoding'), findsOneWidget);

    // Verify Bottom Dock toolbar 6 buttons
    expect(find.byIcon(Icons.sentiment_satisfied_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.alternate_email_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);

    // Tap # 数码日常 chip inserts tag into input
    await tester.tap(find.text('# 数码日常'));
    await tester.pump();
    expect(find.textContaining('#数码日常#'), findsOneWidget);

    // Toggle 九宫格
    await tester.tap(find.text('九宫格').first);
    await tester.pump();

    // Enter message text
    await tester.enterText(find.byType(TextField).first, '#数码日常# 今天天气真不错，分享一张生活照片');
    await tester.pump();

    // Tap 发布 button
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Verify API called with proper parameters
    expect(api.createdMessage, contains('今天天气真不错'));
    expect(api.createdType, 'feed');
    expect(api.createdTag, '数码日常');
  });

  testWidgets('ComposeFeedPage emoji keyboard and symbol insertion works properly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePublishApi();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ComposeFeedPage(api: api),
      ),
    );
    await tester.pump();

    // Tap emoji button to toggle emoji keyboard
    await tester.tap(find.byIcon(Icons.sentiment_satisfied_alt_outlined));
    await tester.pump();

    // Verify Coolapk emojis like [滑稽] and [doge] are displayed
    expect(find.text('[滑稽]'), findsOneWidget);
    expect(find.text('[doge]'), findsOneWidget);

    // Tap [滑稽] inserts into message field
    await tester.tap(find.text('[滑稽]'));
    await tester.pump();
    expect(find.textContaining('[滑稽]'), findsNWidgets(2));

    // Tap # symbol button
    await tester.tap(find.byIcon(Icons.tag_rounded));
    await tester.pump();
    expect(find.textContaining('##'), findsOneWidget);
  });

  testWidgets('ComposeFeedPage album photo selection picks image, previews thumbnail, and uploads on publish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockPngBytes = File('assets/greennote_icon.png').readAsBytesSync();
    const channel = MethodChannel('com.green.note/avatar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'pickImage') {
              return mockPngBytes;
            }
            return null;
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final api = _FakePublishApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ComposeFeedPage(api: api),
      ),
    );
    await tester.pump();

    // Tap + to pick image from album
    await tester.tap(find.byKey(const ValueKey('compose-media-add-box')));
    await tester.pumpAndSettle();

    // Verify thumbnail image is rendered (Image)
    expect(find.byType(Image), findsOneWidget);

    // Enter message
    await tester.enterText(find.byType(TextField).first, '配图动态测试');
    await tester.pump();

    // Tap 发布 button
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    // Verify API called with uploaded image url
    expect(api.createdMessage, '配图动态测试');
    expect(api.createdPic, 'https://image.coolapk.com/feed/mock_picked_image.png');
  });

  testWidgets('CoolapkPublishPickerSheet triggers haptic feedback on items and cancel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();

    final api = _FakePublishApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: CoolapkPublishPickerSheet(api: api, onSelectType: (_) {}),
        ),
      ),
    );
    await tester.pump();

    // Tap 动态 item
    await tester.tap(find.text('动态'));
    await tester.pump();

    expect(hapticCalls.any((c) => c.arguments == 'HapticFeedbackType.lightImpact'), isTrue);
  });

  testWidgets('CoolapkPublishPickerSheet cancel triggers haptic feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();

    final api = _FakePublishApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: CoolapkPublishPickerSheet(api: api),
        ),
      ),
    );
    await tester.pump();

    // Tap 取消 button
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(hapticCalls.any((c) => c.arguments == 'HapticFeedbackType.lightImpact'), isTrue);
  });

  testWidgets('ComposeFeedPage triggers haptic feedback on cover mode toggle and submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();

    final api = _FakePublishApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ComposeFeedPage(api: api),
      ),
    );
    await tester.pump();

    // Toggle 九宫格
    await tester.tap(find.text('九宫格'));
    await tester.pump();
    expect(hapticCalls.any((c) => c.arguments == 'HapticFeedbackType.selectionClick'), isTrue);

    // Enter text and submit
    hapticCalls.clear();
    HapticFeedbackUtil.resetForTesting();
    await tester.enterText(find.byType(TextField).first, '动态测试');
    await tester.pump();
    await tester.tap(find.text('发布'));
    await tester.pump();

    expect(hapticCalls.any((c) => c.arguments == 'HapticFeedbackType.lightImpact'), isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('ComposeFeedPage close button with empty draft pops directly without double haptics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hapticCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    HapticFeedbackUtil.isEnabled = true;
    HapticFeedbackUtil.resetForTesting();

    final api = _FakePublishApi();
    bool popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ComposeFeedPage(api: api)),
                );
                popped = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Open ComposeFeedPage
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposeFeedPage), findsOneWidget);

    hapticCalls.clear();
    HapticFeedbackUtil.resetForTesting();

    // Tap Close IconButton
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.byType(ComposeFeedPage), findsNothing);
    // Haptic should only trigger at most once (from splash) and not twice
    expect(hapticCalls.length, lessThanOrEqualTo(1));
  });

  testWidgets('ComposeFeedPage close button with draft asks confirmation and discards cleanly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakePublishApi();
    bool popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ComposeFeedPage(api: api)),
                );
                popped = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Open ComposeFeedPage
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Enter draft text
    await tester.enterText(find.byType(TextField).first, '草稿内容');
    await tester.pump();

    // Tap Close IconButton
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Expect dialog
    expect(find.text('确定放弃编辑吗？'), findsOneWidget);
    expect(popped, isFalse);

    // Tap 继续编辑
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('确定放弃编辑吗？'), findsNothing);
    expect(find.byType(ComposeFeedPage), findsOneWidget);
    expect(popped, isFalse);

    // Tap Close again and choose 放弃
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('确定放弃编辑吗？'), findsOneWidget);

    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.byType(ComposeFeedPage), findsNothing);
  });
}
