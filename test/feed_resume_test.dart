import 'dart:async';
import 'dart:convert';

import 'package:easy_refresh/easy_refresh.dart';

import 'package:greennote/core/services/cache_service.dart';
import 'package:greennote/features/shared/notification_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

class _ResumeApi extends MockChannelApi {
  int reads = 0;
  bool fail = true;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    throw const CoolapkApiException('当前访问需要验证码');
  }

  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    reads++;
    if (fail) throw const CoolapkApiException('当前访问需要验证码');
    return const FeedPage(
      items: [],
      cards: [
        {
          'entityType': 'card',
          'entityTemplate': 'messageCard',
          'title': '频道头部',
        },
      ],
      firstItem: '',
      lastItem: '',
      hasMore: false,
    );
  }
}

class _CacheApi extends MockChannelApi {
  _CacheApi(String uid) : super(currentUid: uid);
  int reads = 0;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {
    'headline': '/page?url=CACHED_HEADLINE',
  };
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    reads++;
    return FeedPage(
      items: [
        CoolapkFeed.fromJson({
          'id': '800',
          'username': '缓存作者',
          'message': '手动刷新后的内容',
        }),
      ],
      cards: [],
      firstItem: '800',
      lastItem: '800',
      hasMore: false,
    );
  }
}

class _PendingApi extends MockChannelApi {
  _PendingApi() : super(currentUid: 'pending-account');
  final pending = Completer<FeedPage>();
  int reads = 0;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    reads++;
    if (reads == 1) return pending.future;
    return FeedPage(
      items: [
        CoolapkFeed.fromJson({
          'id': '400',
          'username': '恢复作者',
          'message': '自动恢复加载成功',
        }),
      ],
      cards: [],
      firstItem: '400',
      lastItem: '400',
      hasMore: false,
    );
  }
}

class _FollowingApi extends MockChannelApi {
  _FollowingApi() : super(currentUid: 'following-account');
  final timeline = Completer<FeedPage>();
  bool recentRequested = false;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) {
    if (route.contains('FOLLOW')) {
      if (Uri.parse(route).queryParameters['type'] == 'circle') {
        recentRequested = true;
        return Future.value(
          const FeedPage(
            items: [],
            cards: [
              {
                'entityTemplate': 'iconMiniScrollCard',
                'title': '最近更新',
                'entities': [
                  {
                    'entityType': 'user',
                    'uid': '21',
                    'username': '优先出现的酷友',
                    'userAvatar': '',
                  },
                ],
              },
            ],
            firstItem: '',
            lastItem: '',
            hasMore: false,
          ),
        );
      }
      return timeline.future;
    }
    return super.getHomeChannelPage(
      route,
      page,
      firstItem: firstItem,
      lastItem: lastItem,
    );
  }
}

class _TargetApi extends MockChannelApi {
  bool failDetail = false;
  @override
  Future<Map<String, dynamic>> getFeedDetail(String feedId) async {
    if (failDetail) throw const CoolapkApiException('当前访问需要验证码');
    return {
      'data': {
        'id': feedId,
        'uid': '20',
        'username': '原帖作者',
        'message': List.filled(30, '这是一段用于检查定位的原帖正文。').join('\n'),
        'replynum': 2,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getReplyDetail(String id) async => {
    'data': {
      'id': id,
      'uid': '22',
      'username': '目标评论作者',
      'feedId': '333',
      'message': '通知指向的精确评论',
    },
  };
}

class _PagingApi extends MockChannelApi {
  _PagingApi() : super(currentUid: 'paging-test');
  final pages = <int>[];
  final cursors = <String>[];
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    pages.add(page);
    cursors.add(lastItem);
    final count = page == 1
        ? 20
        : page == 2
        ? 4
        : page == 3
        ? 1
        : 0;
    final items = List.generate(
      count,
      (i) => CoolapkFeed.fromJson({
        'id': '${page * 100 + i}',
        'uid': '20',
        'username': '浏览作者',
        'message': '第$page页动态$i：连续浏览正文内容。' * 8,
      }),
    );
    return FeedPage(
      items: items,
      firstItem: items.firstOrNull?.id ?? '',
      lastItem: items.lastOrNull?.id ?? '',
      hasMore: items.isNotEmpty,
    );
  }
}

void main() {
  testWidgets(
    'cached headline survives startup and long background until manual refresh',
    (tester) async {
      final api = _CacheApi('cache-first-account');
      SharedPreferences.setMockInitialValues({
        'cached_home_headline_v1': jsonEncode({
          'scope': api.notificationSessionKey,
          'feeds': [
            {'id': '799', 'username': '缓存作者', 'message': '保留当前浏览内容'},
          ],
          'banners': [],
        }),
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedHomePage(api: api, onLoginRequested: () async {}),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('保留当前浏览内容', findRichText: true), findsOneWidget);
      expect(api.reads, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(api.reads, 0);
      expect(find.text('保留当前浏览内容', findRichText: true), findsOneWidget);
      await tester
          .widget<EasyRefresh>(find.byType(EasyRefresh).first)
          .onRefresh!();
      await tester.pump();
      expect(api.reads, 1);
      expect(find.text('手动刷新后的内容', findRichText: true), findsOneWidget);
    },
  );

  testWidgets('another account headline cache is ignored on startup', (
    tester,
  ) async {
    final api = _CacheApi('cache-isolated-account');
    SharedPreferences.setMockInitialValues({
      'cached_home_headline_v1': jsonEncode({
        'scope': 'session-other-account',
        'feeds': [
          {'id': '799', 'message': '其他账号的内容'},
        ],
      }),
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FeedHomePage(api: api, onLoginRequested: () async {}),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.reads, 1);
    expect(find.text('其他账号的内容', findRichText: true), findsNothing);
    expect(find.text('手动刷新后的内容', findRichText: true), findsOneWidget);
  });
  testWidgets(
    'headline shows full first batch and continues through short pages without refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _PagingApi();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedHomePage(api: api, onLoginRequested: () async {}),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final listFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ListView &&
            widget.scrollDirection == Axis.vertical &&
            widget.controller != null,
      );
      final firstList = tester.widget<ListView>(listFinder.first);
      expect(
        firstList.childrenDelegate.estimatedChildCount,
        22,
      ); // 20 rows, header, footer
      for (var i = 0; i < 12 && !api.pages.contains(4); i++) {
        final list = tester.widget<ListView>(listFinder.first);
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(api.pages, containsAllInOrder([1, 2, 3, 4]));
      expect(api.pages.where((p) => p == 1).length, 1);
      expect(api.cursors[1], '119');
      expect(api.cursors[2], '203');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing post body shows a visible retry before jumping to comments',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _TargetApi()..failDetail = true;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: FeedDetailPage(
              api: api,
              feed: CoolapkFeed.fromJson({'id': '333'}),
              initialReplyId: '222',
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('原帖加载失败'), findsOneWidget);
      expect(find.text('重新加载原帖').hitTestable(), findsOneWidget);
      final scroll = tester
          .widget<ListView>(find.byType(ListView).first)
          .controller!;
      expect(scroll.offset, 0);
      api.failDetail = false;
      await tester.tap(find.text('重新加载原帖'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text('通知指向的精确评论', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      scroll.jumpTo(0);
      await tester.pump();
      expect(
        find.textContaining('这是一段用于检查定位的原帖正文', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('原帖加载失败'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resume during a pending request queues recovery and cache clearing reloads automatically',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _PendingApi();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedHomePage(api: api, onLoginRequested: () async {}),
            ),
          ),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      api.pending.complete(
        const FeedPage(
          items: [],
          cards: [],
          firstItem: '',
          lastItem: '',
          hasMore: false,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.reads, 2);
      expect(find.text('自动恢复加载成功', findRichText: true), findsOneWidget);
      CacheService.revision.value++;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.reads, 3);
      expect(find.text('自动恢复加载成功', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recent followed authors appear before the main followed timeline returns',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _FollowingApi();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedHomePage(api: api, onLoginRequested: () async {}),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      tester
          .widget<TabBarView>(find.byType(TabBarView))
          .controller!
          .animateTo(1);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.recentRequested, true);
      expect(api.timeline.isCompleted, false);
      expect(find.text('优先出现的酷友'), findsOneWidget);
      api.timeline.complete(
        const FeedPage(
          items: [],
          cards: [],
          firstItem: '',
          lastItem: '',
          hasMore: false,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification opens the original post with the exact reply visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _TargetApi();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NotificationEntry(
                api: api,
                path: '/v6/notification/list',
                item: const {
                  'id': '999',
                  'fromuid': '20',
                  'fromusername': '通知作者',
                  'note': '评论了你的动态：<a href="/feed/333?rid=222">精确跳转入口</a>',
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('精确跳转入口', findRichText: true));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final detail = tester.widget<FeedDetailPage>(find.byType(FeedDetailPage));
      expect(detail.feed.id, '333');
      expect(detail.initialReplyId, '222');
      expect(
        find.text('通知指向的精确评论', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('定位到的评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('generic official lists retain verification errors and retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApiListPage(
          api: _ResumeApi(),
          title: '我的收藏单',
          path: '/v6/collection/list',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前访问需要验证码'), findsOneWidget);
    expect(find.text('暂无内容'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty resumed feed shows real errors and a retry even with header cards',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _ResumeApi();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedHomePage(api: api, onLoginRequested: () async {}),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('当前访问需要验证码'), findsOneWidget);
      final before = api.reads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      api.fail = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(api.reads, before + 1);
      expect(find.text('当前访问需要验证码'), findsNothing);
      expect(find.text('酷安暂时没有返回动态'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(api.reads, before + 2);
      expect(tester.takeException(), isNull);
    },
  );
}
