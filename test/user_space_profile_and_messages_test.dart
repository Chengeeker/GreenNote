import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/following_page.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shell/main_pages.dart';

class _FakeProfileApi implements CoolapkApi {
  _FakeProfileApi({
    this.currentUidValue = '1001',
    this.loginTimeValue,
  });

  final String currentUidValue;
  final int? loginTimeValue;
  final List<String> requestedPaths = [];

  @override
  String get currentUid => currentUidValue;

  @override
  String get currentUserNickname => '极客酷友';

  @override
  String get currentUserAvatar => 'https://image.coolapk.com/avatar/test.png';

  @override
  @override
  bool get hasCookie => true;

  @override
  bool get isAnonymous => false;

  @override
  String get notificationSessionKey => 'session-key-test';

  @override
  ValueNotifier<int> get accountProfileRevision => ValueNotifier<int>(0);

  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};


  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    requestedPaths.add('/v6/user/profile:$uid');
    return {
      'data': {
        'uid': uid,
        'username': '极客酷友',
        'userAvatar': 'https://image.coolapk.com/avatar/test.png',
        'avatarFrame': 'https://image.coolapk.com/frame/test.png',
        'level': 5,
        'bio': '喜欢数码与编程的酷友',
        'gender': 1,
        'birth_year': 2002,
        'province': '广东',
        'city': '佛山',
        'astro': '天秤座',
        'logintime': loginTimeValue ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60),
        'be_like_num': 2996,
        'follow_num': 33,
        'fans_num': 249,
        'feed_num': 331,
        'buy_num': 27,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async {
    requestedPaths.add('/v6/user/space:$uid');
    return {
      'data': {
        'uid': uid,
        'username': '极客酷友',
        'userAvatar': 'https://image.coolapk.com/avatar/test.png',
        'avatarFrame': 'https://image.coolapk.com/frame/test.png',
        'level': 5,
        'bio': '喜欢数码与编程的酷友',
        'gender': 1,
        'birth_year': 2002,
        'province': '广东',
        'city': '佛山',
        'astro': '天秤座',
        'logintime': loginTimeValue ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60),
        'be_like_num': 2996,
        'follow_num': 33,
        'fans_num': 249,
        'feed_num': 331,
        'buy_num': 27,
      },
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requestedPaths.add(path);
    if (path.contains('/v6/message/list')) {
      return const ApiPage(
        items: [
          {
            'ukey': 'session-1',
            'uid': '2001',
            'username': '酷友小明',
            'userAvatar': 'https://image.coolapk.com/avatar/2001.png',
            'lastMessage': '你好，请问这个还在吗？',
            'dateline': 1729400000,
          },
          {
            'ukey': 'session-2',
            'uid': '2002',
            'username': '酷友小华',
            'userAvatar': 'https://image.coolapk.com/avatar/2002.png',
            'lastMessage': '收到，多谢解答！',
            'dateline': 1729390000,
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: 'session-1',
        lastItem: 'session-2',
      );
    }
    return const ApiPage(
      items: [
        {
          'id': 'feed-1',
          'message': '测试动态正文',
          'username': '极客酷友',
          'dateline': 1729400000,
        },
      ],
      page: 1,
      hasMore: false,
      firstItem: 'feed-1',
      lastItem: 'feed-1',
    );
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body = const {},
  }) async {
    requestedPaths.add('$method:$path');
    return {'data': {}};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('UserSpacePage displays 1:1 official layout for self profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi(currentUidValue: '1001');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: UserSpacePage(api: api, uid: '1001'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Avatar with avatarFrame exists
    expect(find.byType(AppAvatar), findsWidgets);
    final avatarWidget = tester.widget<AppAvatar>(find.byType(AppAvatar).first);
    expect(avatarWidget.size, 76);
    expect(avatarWidget.avatarFrame, contains('frame/test.png'));

    // Verify Username and Level Badge
    expect(find.text('极客酷友'), findsWidgets);
    expect(find.text('Lv.5'), findsOneWidget);

    // Verify Bio and Tag Icon
    expect(find.text('喜欢数码与编程的酷友'), findsOneWidget);
    expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);

    // Verify Inline Stats
    expect(find.text('2996'), findsOneWidget);
    expect(find.text('获赞'), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
    expect(find.text('关注'), findsWidgets);
    expect(find.text('249'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);

    // Verify Chips (Gender + Era, Region, Astro, Active status)
    expect(find.text('♂ 00后'), findsOneWidget);
    expect(find.text('广东 佛山'), findsOneWidget);
    expect(find.text('天秤座'), findsOneWidget);
    expect(find.textContaining('活跃'), findsOneWidget);

    // Verify Equipment Card for Self
    expect(find.text('我的装备'), findsOneWidget);
    expect(find.text('27个装备'), findsOneWidget);

    // Verify Action button for Self is 编辑资料 + grid icon
    expect(find.text('编辑资料'), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);

    // Verify TabBar includes 点评 right after 回复
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('点评'), findsOneWidget);

    // Verify 全部动态 (331) sub-header is present on the feed list
    expect(find.text('全部动态 (331)'), findsOneWidget);
  });

  testWidgets('UserSpacePage displays 1:1 official layout for other user profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi(currentUidValue: '9999');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: UserSpacePage(api: api, uid: '1001'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Equipment Card for Other User is TA的装备
    expect(find.text('TA的装备'), findsOneWidget);
    expect(find.text('27个装备'), findsOneWidget);

    // Verify Action buttons for Other User: 关注 + 私信 + more icon
    expect(find.text('关注'), findsWidgets);
    expect(find.text('私信'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    // Tap 私信 navigates to MessageChatPage
    await tester.tap(find.text('私信'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MessageChatPage), findsOneWidget);
  });

  testWidgets('Notification center top right buttons align and private messages layout matches official', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MessageCenterPage(api: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Done All and Clear Notifications buttons
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    // Verify alignment: vertical centers should be equal
    final doneAllCenter = tester.getCenter(find.byIcon(Icons.done_all_rounded));
    final deleteSweepCenter = tester.getCenter(
      find.byIcon(Icons.delete_outline_rounded),
    );
    expect(doneAllCenter.dy, equals(deleteSweepCenter.dy));
  });


  testWidgets('UserSpacePage correctly formats relative active time without leaking raw timestamps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 25 minutes ago
    final logintime25m = nowSec - 25 * 60;

    final api = _FakeProfileApi(
      currentUidValue: '1001',
      loginTimeValue: logintime25m,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: UserSpacePage(api: api, uid: '1001'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('25分钟前活跃'), findsOneWidget);
    expect(find.textContaining('1729'), findsNothing);
  });

  testWidgets('FollowingChannelHeader renders compact official layout and supports selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi();
    String selectedFilter = 'circle';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: FollowingChannelHeader(
            api: api,
            cards: const [],
            feeds: const [],
            selected: selectedFilter,
            onSelect: (val) => selectedFilter = val,
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify 好友关注 is selected by default
    expect(find.text('好友关注'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);

    // Verify compact avatar size for "最近更新"
    final circleAvatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(circleAvatar.radius, 19);

    // Tap 全部 switches selection
    await tester.tap(find.text('全部'));
    await tester.pump();
    expect(selectedFilter, '');
  });

  testWidgets('FeedCard renders compact 36dp avatar and official proportions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi();
    const testFeed = CoolapkFeed(
      id: '9901',
      username: '极客酷友',
      avatar: 'https://image.coolapk.com/avatar/test.png',
      message: '测试紧凑卡片动态内容',
      date: '2小时前',
      likeCount: '10',
      replyCount: '5',
      pictures: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: FeedCard(
            api: api,
            feed: testFeed,
            isHeadline: true,
          ),
        ),
      ),
    );
    await tester.pump();

    // Author avatar in FeedCard is 36dp
    final avatars = tester.widgetList<AppAvatar>(find.byType(AppAvatar)).toList();
    expect(avatars.any((a) => a.size == 36), isTrue);

    // Message text is rendered
    expect(find.text('测试紧凑卡片动态内容'), findsOneWidget);
  });
  testWidgets('Home channel TabBar has no underline indicator, uses primary theme color, and height is 38', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PreferredSizeWidget? currentTabBar;
    final api = _FakeProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              appBar: currentTabBar != null
                  ? AppBar(bottom: currentTabBar)
                  : null,
              body: FeedHomePage(
                api: api,
                onTopBarChanged: (bar) {
                  currentTabBar = bar;
                  setState(() {});
                },
                onLoginRequested: () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(currentTabBar, isNotNull);
    expect(currentTabBar!.preferredSize.height, 38.0);

    // Verify TabBar indicator is transparent decoration
    final tabBarFinder = find.byType(TabBar);
    expect(tabBarFinder, findsWidgets);
    final tabBar = tester.widget<TabBar>(tabBarFinder.first);
    expect(tabBar.indicator, isA<BoxDecoration>());
    final box = tabBar.indicator as BoxDecoration;
    expect(box.color, Colors.transparent);
    expect(tabBar.labelColor, AppTheme.lightTheme().colorScheme.primary);
  });

  testWidgets('Private messages page has only single delete action and supports multi-select single/all deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MessageCenterPage(api: api),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Open private messages page by tapping 私信 tile
    await tester.tap(find.text('私信'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify AppBar title is 私信
    expect(find.text('私信'), findsWidgets);

    // Verify top right action has ONLY ONE delete button (no more_vert icon in AppBar)
    expect(find.byTooltip('管理私信'), findsOneWidget);
    expect(find.byTooltip('清空会话'), findsNothing);

    // Tap 管理私信 to enter multi-select selection mode
    await tester.tap(find.byTooltip('管理私信'));
    await tester.pump();

    // Verify selection mode UI: 取消 on leading, 全选 on action, bottom bar has 删除
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('选择会话'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // Tap first conversation row: turns to 1 selected
    await tester.tap(find.text('酷友小明'));
    await tester.pump();
    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(find.text('删除 (1)'), findsOneWidget);

    // Tap 全选: both selected
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);
    expect(find.text('删除 (2)'), findsOneWidget);

    // Tap 取消: exits selection mode
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('取消'), findsNothing);
    expect(find.text('全选'), findsNothing);
    expect(find.byTooltip('管理私信'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
