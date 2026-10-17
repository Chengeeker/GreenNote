import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';

class _MockFeedApi extends Fake implements CoolapkApi {
  final List<String> callLogs = [];
  bool favoritedState = false;

  @override
  bool get isAnonymous => false;

  @override
  bool get hasAccount => true;

  @override
  bool get hasCookie => true;

  @override
  String get currentUserAvatar => 'http://example.com/avatar.png';

  @override
  String get currentUid => '1001';

  @override
  Future<void> favoriteFeed(
    String id, {
    required bool favorited,
    CoolapkFeed? feed,
  }) async {
    callLogs.add('favoriteFeed:$id:$favorited');
    favoritedState = !favorited;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FeedCard top-right downward arrow opens 1:1 official more actions modal',
      (tester) async {
    final api = _MockFeedApi();
    final feed = CoolapkFeed(
      id: '998877',
      uid: '12345',
      username: '上来看看贴',
      avatar: 'http://example.com/avatar.png',
      message: '测试动态内容',
      date: '10分钟前',
      likeCount: '10',
      replyCount: '5',
      pictures: const [],
      raw: {
        'id': '998877',
        'uid': '12345',
        'username': '上来看看贴',
        'message': '测试动态内容',
        'device_title': '华为Mate 90 Pro Max',
        'user_level': '6',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FeedCard(
                api: api,
                feed: feed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Author and device should be visible
    expect(find.text('上来看看贴'), findsOneWidget);
    expect(find.text('华为Mate 90 Pro Max'), findsAtLeastNWidgets(1));

    // 2. The author link row should NOT contain keyboard_arrow_down_rounded
    // (It was previously next to the username)
    final authorLinkFinder = find.byKey(const ValueKey('feed-author-link'));
    expect(authorLinkFinder, findsOneWidget);
    expect(
      find.descendant(
        of: authorLinkFinder,
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      ),
      findsNothing,
    );

    // 3. The card header trailing should contain the more actions button
    final moreBtnFinder = find.byKey(const ValueKey('feed-more-actions-btn'));
    expect(moreBtnFinder, findsOneWidget);

    // 4. Tap more button to open the bottom sheet modal
    await tester.tap(moreBtnFinder);
    await tester.pumpAndSettle();

    // 5. Verify the 3 rows and cancel button from media_1792223976690_1c10b668.jpg
    // Row 1: 收藏, 屏蔽, 举报
    expect(find.byKey(const ValueKey('action-favorite')), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-block')), findsOneWidget);
    expect(find.text('屏蔽'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-report')), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);

    // Row 2: 推荐上头条
    expect(find.byKey(const ValueKey('action-recommend-headline')), findsOneWidget);
    expect(find.text('推荐上头条'), findsOneWidget);

    // Row 3: 动态, 私信, 生成分享图, 看看号, 微信, 朋友圈, QQ, 复制链接, 更多
    expect(find.byKey(const ValueKey('action-share-feed')), findsOneWidget);
    expect(find.text('动态'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-message')), findsOneWidget);
    expect(find.text('私信'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-poster')), findsOneWidget);
    expect(find.text('生成分享图'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-kankan')), findsOneWidget);
    expect(find.text('看看号'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-wechat')), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);

    // Scroll horizontally to reveal the rest
    await tester.drag(
      find.byKey(const ValueKey('action-share-kankan')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('action-share-moments')), findsOneWidget);
    expect(find.text('朋友圈'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-qq')), findsOneWidget);
    expect(find.text('QQ'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-copy-link')), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
    expect(find.byKey(const ValueKey('action-share-more')), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);

    // Bottom cancel button
    final cancelBtn = find.byKey(const ValueKey('action-sheet-cancel'));
    expect(cancelBtn, findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 6. Tap cancel to dismiss
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();

    // Sheet dismissed
    expect(find.byKey(const ValueKey('action-sheet-cancel')), findsNothing);

    // 7. Open sheet again and tap 收藏 to verify toggle
    await tester.tap(moreBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('action-favorite')));
    await tester.pumpAndSettle();

    expect(api.callLogs, contains('favoriteFeed:998877:false'));

    // Drain toast timer
    await tester.pump(const Duration(seconds: 3));
  });
}
