import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/features/feed/feed_pages.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

late SharedPreferences _sharedPreferences;

class CommentTestApi extends MockChannelApi {
  CommentTestApi({
    super.hasCookie = false,
    this.replyListThrowsRestricted = false,
    this.feedDetailThrowsRestricted = false,
    this.hotReplyEmpty = false,
  });

  final bool replyListThrowsRestricted;
  final bool feedDetailThrowsRestricted;
  final bool hotReplyEmpty;
  bool authorRepliesEmpty = false;
  bool lastFromFeedAuthor = false;
  String lastListType = '';
  int hotReplyCallCount = 0;
  int replyListCallCount = 0;
  Completer<ApiPage>? delayReplyPage;

  @override
  LocalAccount get localAccount => LocalAccount(_sharedPreferences);

  @override
  bool get isAnonymous => !hasCookie;

  @override
  Future<Map<String, dynamic>> getFeedDetail(String feedId) async {
    if (feedDetailThrowsRestricted) {
      throw const CoolapkApiException('当前访问需要验证码');
    }
    return {
      'data': {
        'id': feedId,
        'uid': 'feed_author',
        'username': '动态发布者',
        'message': '测试动态正文',
        'replynum': 2,
        'likenum': 5,
      },
    };
  }

  @override
  Future<ApiPage> getHotReplyPage(String feedId, int page) async {
    hotReplyCallCount++;
    if (hotReplyEmpty) {
      return ApiPage(
        items: const [],
        page: page,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
    }
    return ApiPage(
      items: [
        {
          'id': 'hot_reply_$page',
          'uid': 'user_$page',
          'username': '热门评论用户$page',
          'userAvatar': 'https://avatar.coolapk.com/user_$page.jpg',
          'message': '这是热门评论内容$page',
          'likenum': 20,
          'replynum': 1,
          'dateline': 1791577411,
          'entityType': 'feed_reply',
          'replyRows': [
            {
              'id': 'sub_reply_1',
              'uid': 'sub_user_1',
              'username': '楼中楼用户',
              'message': '这是楼中楼回复内容',
              'dateline': 1791577412,
              'entityType': 'feed_reply',
            },
          ],
        },
      ],
      page: page,
      hasMore: page < 2,
      firstItem: 'hot_reply_$page',
      lastItem: 'hot_reply_$page',
    );
  }

  @override
  Future<ApiPage> getReplyPage(
    String feedId,
    int page, {
    String listType = 'lastupdate_desc',
    String? firstItem,
    String? lastItem,
    String feedType = 'feed',
    bool fromFeedAuthor = false,
  }) async {
    replyListCallCount++;
    lastFromFeedAuthor = fromFeedAuthor;
    lastListType = listType;
    if (delayReplyPage != null) {
      final res = await delayReplyPage!.future;
      return res;
    }
    if (replyListThrowsRestricted) {
      throw const CoolapkApiException('当前访问需要验证码');
    }
    if (fromFeedAuthor) {
      if (authorRepliesEmpty) {
        return const ApiPage(
          items: [],
          page: 1,
          hasMore: false,
          firstItem: '',
          lastItem: '',
        );
      }
      return ApiPage(
        items: [
          {
            'id': 'author_reply_$page',
            'uid': 'feed_author',
            'username': '动态发布者',
            'message': '这是楼主本人的回复内容',
            'likenum': 5,
            'replynum': 0,
            'entityType': 'feed_reply',
          },
        ],
        page: page,
        hasMore: false,
        firstItem: 'author_reply_$page',
        lastItem: 'author_reply_$page',
      );
    }
    return ApiPage(
      items: [
        {
          'id': 'all_reply_$page',
          'uid': 'user_all_$page',
          'username': '全部评论用户$page',
          'message': '这是全部评论内容$page',
          'likenum': 3,
          'replynum': 0,
          'entityType': 'feed_reply',
        },
      ],
      page: page,
      hasMore: false,
      firstItem: 'all_reply_$page',
      lastItem: 'all_reply_$page',
    );
  }
}

Widget buildTestApp({required CoolapkApi api, required CoolapkFeed feed}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: FeedDetailPage(api: api, feed: feed),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'use_liquid_glass': false});
    _sharedPreferences = await SharedPreferences.getInstance();
  });

  final testFeed = CoolapkFeed(
    id: '74117689',
    uid: 'feed_author',
    username: '动态发布者',
    avatar: 'https://avatar.coolapk.com/author.jpg',
    message: '测试动态正文',
    date: '10分钟前',
    likeCount: '5',
    replyCount: '2',
    pictures: const [],
    pictureMetadata: const {},
    liked: false,
    favorited: false,
    raw: const {
      'id': '74117689',
      'uid': 'feed_author',
      'username': '动态发布者',
      'message': '测试动态正文',
      'replynum': 2,
      'likenum': 5,
    },
  );

  testWidgets('默认加载并展示热门评论，包含楼中楼子回复', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false);
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 验证调用了 getHotReplyPage
    expect(api.hotReplyCallCount, greaterThanOrEqualTo(1));
    expect(api.replyListCallCount, 0);

    // 验证评论内容展示正常
    expect(find.text('热门评论用户1'), findsOneWidget);
    expect(find.text('这是热门评论内容1'), findsOneWidget);

    // 验证楼中楼子评论展示正常
    expect(find.text('楼中楼用户'), findsOneWidget);
    expect(find.textContaining('这是楼中楼回复内容'), findsOneWidget);

    // 验证没有显示任何验证码弹窗或“验证并加载完整评论”按钮
    expect(find.byKey(const ValueKey('feed-reply-verify')), findsNothing);
    expect(find.text('验证并加载完整评论'), findsNothing);
    expect(find.text('当前访问需要验证码'), findsNothing);
  });

  testWidgets('当切换到其他排序且触发访问受限时，自动无缝降级为热门评论且不展示受限警告', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(
      hasCookie: false,
      replyListThrowsRestricted: true,
    );
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 点击“默认”评论排序
    final defaultChip = find.text('默认');
    expect(defaultChip, findsOneWidget);
    await tester.tap(defaultChip);
    await tester.pumpAndSettle();

    // 尝试调用了 replyList，并自动回退触发了 hotReplyList
    expect(api.replyListCallCount, greaterThanOrEqualTo(1));
    expect(api.hotReplyCallCount, greaterThanOrEqualTo(1));

    // 热门评论展示正常，且绝不弹出“当前排序需要登录或访问受限”告警或验证码
    expect(find.text('热门评论用户1'), findsOneWidget);
    expect(find.text('当前排序需要登录或访问受限，已自动为您展示热门评论'), findsNothing);
    expect(find.text('当前访问需要验证码'), findsNothing);
    expect(find.byKey(const ValueKey('feed-reply-verify')), findsNothing);
  });

  testWidgets('当查看用户个人主页的自发动态（热门评论为空但有普通评论或内嵌评论）时，自动展示真实评论，绝不显示访问受限', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 模拟个人主页发布的动态（包含 1 条内嵌回复与普通回复，但热门回复为空）
    final personalFeed = CoolapkFeed(
      id: '88889999',
      uid: 'my_uid',
      username: '我的账号',
      avatar: 'https://avatar.coolapk.com/me.jpg',
      message: '这是我在个人主页发布的自发动态',
      date: '5分钟前',
      likeCount: '1',
      replyCount: '1',
      pictures: const [],
      raw: const {
        'id': '88889999',
        'uid': 'my_uid',
        'feedType': 'feed',
        'message': '这是我在个人主页发布的自发动态',
        'replynum': 1,
        'replyRows': [
          {
            'id': 'personal_embedded_reply_1',
            'uid': 'friend_uid',
            'username': '主页好友评论者',
            'message': '好友在个人动态下的回复内容',
            'dateline': 1791577430,
            'entityType': 'feed_reply',
          },
        ],
      },
    );

    final apiWithRegular = CommentTestApi(
      hasCookie: false,
      hotReplyEmpty: true,
    );
    await tester.pumpWidget(
      buildTestApp(api: apiWithRegular, feed: personalFeed),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部评论用户1'), findsOneWidget);
    expect(find.text('这是全部评论内容1'), findsOneWidget);
    expect(find.text('当前排序需要登录或访问受限，已自动为您展示热门评论'), findsNothing);
    expect(find.text('当前访问需要验证码'), findsNothing);
  });

  testWidgets('当查看用户个人主页自发动态且网络排序受限时，自动无缝展示内嵌评论，绝不显示访问受限', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final personalFeed = CoolapkFeed(
      id: '88889999',
      uid: 'my_uid',
      username: '我的账号',
      avatar: 'https://avatar.coolapk.com/me.jpg',
      message: '这是我在个人主页发布的自发动态',
      date: '5分钟前',
      likeCount: '1',
      replyCount: '1',
      pictures: const [],
      raw: const {
        'id': '88889999',
        'uid': 'my_uid',
        'feedType': 'feed',
        'message': '这是我在个人主页发布的自发动态',
        'replynum': 1,
        'replyRows': [
          {
            'id': 'personal_embedded_reply_1',
            'uid': 'friend_uid',
            'username': '主页好友评论者',
            'message': '好友在个人动态下的回复内容',
            'dateline': 1791577430,
            'entityType': 'feed_reply',
          },
        ],
      },
    );

    final apiWithEmbeddedOnly = CommentTestApi(
      hasCookie: false,
      hotReplyEmpty: true,
      replyListThrowsRestricted: true,
    );
    await tester.pumpWidget(
      buildTestApp(api: apiWithEmbeddedOnly, feed: personalFeed),
    );
    await tester.pumpAndSettle();

    expect(find.text('主页好友评论者'), findsOneWidget);
    expect(find.text('好友在个人动态下的回复内容'), findsOneWidget);
    expect(find.text('当前排序需要登录或访问受限，已自动为您展示热门评论'), findsNothing);
    expect(find.text('当前访问需要验证码'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('点击楼中楼支持通过 initialItems 顺畅展示已获取的子评论', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false);
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 点击评论的“更多”菜单
    final moreBtn = find.byTooltip('更多');
    expect(moreBtn, findsOneWidget);
    await tester.tap(moreBtn);
    await tester.pumpAndSettle();

    // 点击查看楼中楼回复
    final threadItem = find.text('查看楼中楼回复');
    expect(threadItem, findsOneWidget);
    await tester.tap(threadItem);
    await tester.pumpAndSettle();

    // 楼中楼底部弹窗打开，包含回复计数和根评论
    expect(find.text('回复(1)'), findsOneWidget);
    expect(find.text('查看原动态'), findsOneWidget);
  });

  testWidgets('当动态详情接口返回验证码受限时，静默使用已有动态信息，不显示“当前访问需要验证码”和“重试”', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(
      hasCookie: false,
      feedDetailThrowsRestricted: true,
    );
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 动态正常展示
    expect(find.text('动态发布者'), findsOneWidget);
    expect(find.text('测试动态正文'), findsOneWidget);

    // 热门评论正常展示
    expect(find.text('热门评论用户1'), findsOneWidget);

    // 绝对不展示“当前访问需要验证码”或“重试”
    expect(find.text('当前访问需要验证码'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('点击“楼主”（仅看楼主）按钮，调用 fromFeedAuthor 并仅展示楼主本人的回复', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false);
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 点击“楼主”过滤按钮
    final authorChip = find.text('楼主');
    expect(authorChip, findsWidgets);
    await tester.tap(authorChip.first);
    await tester.pumpAndSettle();

    // 验证调用了 fromFeedAuthor == true
    expect(api.lastFromFeedAuthor, isTrue);
    expect(api.lastListType, 'dateline_desc');

    // 仅展示楼主本人的回复
    expect(find.text('这是楼主本人的回复内容'), findsOneWidget);
    expect(find.text('热门评论用户1'), findsNothing);
  });

  testWidgets('当“楼主”模式下无楼主回复时，展示“该动态下暂无楼主回复”，绝不静默回退至热门评论', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false)
      ..authorRepliesEmpty = true;
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 点击“楼主”过滤按钮
    final authorChip = find.text('楼主');
    expect(authorChip, findsWidgets);
    await tester.tap(authorChip.first);
    await tester.pumpAndSettle();

    // 验证调用了 fromFeedAuthor == true
    expect(api.lastFromFeedAuthor, isTrue);

    // 验证明确展示空状态占位
    expect(find.text('该动态下暂无楼主回复'), findsOneWidget);
    // 绝不静默回退展示热门评论
    expect(find.text('热门评论用户1'), findsNothing);
  });

  testWidgets('切换评论筛选方式时保留现有评论内容，不提前清空销毁列表，防止页面高度坍缩', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false);
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 默认展示热门评论
    expect(find.text('热门评论用户1'), findsOneWidget);

    // 模拟网络请求尚未返回（异步挂起）
    final completer = Completer<ApiPage>();
    api.delayReplyPage = completer;

    // 点击“最新”过滤按钮
    final latestChip = find.text('最新');
    expect(latestChip, findsWidgets);
    await tester.tap(latestChip.first);
    // 只 pump 一帧，此时网络尚未返回
    await tester.pump();

    // 核心断言：在请求返回前，原有的评论绝不被清空销毁，继续留在屏幕上，防止列表坍缩跳回顶部
    expect(find.text('热门评论用户1'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // 此时网络返回新模式数据
    completer.complete(
      const ApiPage(
        items: [
          {
            'id': 'latest_reply_1',
            'uid': 'user_latest',
            'username': '最新评论用户',
            'message': '这是最新发表的评论',
            'likenum': 0,
            'replynum': 0,
            'entityType': 'feed_reply',
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: 'latest_reply_1',
        lastItem: 'latest_reply_1',
      ),
    );
    await tester.pumpAndSettle();

    // 加载完成后原地替换为最新评论
    expect(find.text('最新评论用户'), findsOneWidget);
    expect(find.text('热门评论用户1'), findsNothing);
  });

  testWidgets('多筛选模式具备内存缓存，切换回已加载模式时即时秒切无网络请求', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = CommentTestApi(hasCookie: false);
    await tester.pumpWidget(buildTestApp(api: api, feed: testFeed));
    await tester.pumpAndSettle();

    // 初始热门已加载：hotReplyCallCount 为 1
    expect(find.text('热门评论用户1'), findsOneWidget);
    expect(api.hotReplyCallCount, 1);

    // 切换到“最新”
    await tester.tap(find.text('最新').first);
    await tester.pumpAndSettle();
    expect(find.text('全部评论用户1'), findsOneWidget);
    expect(find.text('热门评论用户1'), findsNothing);
    final replyCallsAfterLatest = api.replyListCallCount;

    // 切换回“热门”：直接从缓存秒切，不产生新的网络请求
    await tester.tap(find.text('热门').first);
    await tester.pump(); // 0ms 瞬间渲染
    expect(find.text('热门评论用户1'), findsOneWidget);
    expect(api.hotReplyCallCount, 1); // 未产生二次请求

    // 再次切换回“最新”：直接从缓存秒切，不产生新的网络请求
    await tester.tap(find.text('最新').first);
    await tester.pump();
    expect(find.text('全部评论用户1'), findsOneWidget);
    expect(api.replyListCallCount, replyCallsAfterLatest); // 未产生二次请求
  });
}
