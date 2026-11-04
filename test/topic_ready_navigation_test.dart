import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/services/cache_service.dart';
import 'package:greennote/core/widgets/review_refresh_header.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/activity_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_navigation_test.dart' show ActivityApi;
import 'home_destination_test.dart' as fixture;

class _ReadyApi extends ActivityApi {
  final detail = Completer<Map<String, dynamic>>();
  final firstPage = Completer<ApiPage>();
  final pageQueries = <Map<String, dynamic>>[];
  final topicFollows = <bool>[];
  ApiPage? refreshedPage;
  @override
  Future<void> followTopic(String tag, {required bool following}) async {
    topicFollows.add(following);
  }

  String session = 'ready-session';
  @override
  String get notificationSessionKey => session;
  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) {
    queriedTags.add(tag);
    return detail.future;
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) {
    if (path == '/v6/topic/tagFeedList' && query['tag'] == 'ready') {
      pageQueries.add(Map.of(query));
      if (query['page'] == 1) {
        return refreshedPage == null
            ? firstPage.future
            : Future.value(refreshedPage);
      }
      return Future.value(
        const ApiPage(
          items: [],
          page: 2,
          hasMore: false,
          firstItem: '',
          lastItem: '',
        ),
      );
    }
    return super.getList(path, query: query);
  }
}

Map<String, dynamic> get _detail => {
  'data': {
    'title': '准备话题',
    'selectedTab': 'discussion',
    'userAction': {'follow': 0},
    'tabList': [
      {'title': '有奖活动', 'page_name': 'activity', 'url': 'V8_PRIZE'},
      {
        'title': '讨论',
        'page_name': 'discussion',
        'url': '/v6/topic/tagFeedList?tag=ready',
      },
    ],
  },
};

const _firstPage = ApiPage(
  items: [
    {'id': '601', 'title': '首屏内容', 'entityType': 'text'},
    {
      'entityTemplate': 'sortSelectCard',
      'entities': [
        {'title': '默认', 'url': '/v6/topic/tagFeedList?tag=ready'},
        {
          'title': '最新',
          'url': '/v6/topic/tagFeedList?tag=ready&sortField=dateline_desc',
        },
      ],
    },
  ],
  page: 1,
  hasMore: false,
  firstItem: '601',
  lastItem: '601',
);

Future<void> _mount(
  WidgetTester tester,
  _ReadyApi api, {
  ValueNotifier<bool>? enabled,
  bool carousel = false,
  bool singleItem = false,
  bool fullHome = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget source() => carousel
      ? EasyRefresh(
          triggerAxis: Axis.vertical,
          onRefresh: () async {},
          child: filterHorizontalScrollNotifications(
            ListView(
              children: [
                HomeChannelCardsHeader(
                  api: api,
                  channelId: 'headline',
                  activeCategoryIndex: 0,
                  onSelectCategory: (_, _) {},
                  cards: [
                    {
                      'entityTemplate': 'imageCarouselCard_1',
                      'entities': [
                        {
                          'title': '准备话题',
                          'url': '/t/ready',
                          'pic': 'https://image.coolapk.com/banner.jpg',
                        },
                        if (!singleItem)
                          {
                            'title': '另一个话题',
                            'url': '/t/next',
                            'pic': 'https://image.coolapk.com/next.jpg',
                          },
                      ],
                    },
                  ],
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        )
      : Builder(
          builder: (context) => FilledButton(
            onPressed: () => openHeadlineTarget(context, api, {
              'title': '准备话题',
              'url': '/t/ready',
            }),
            child: const Text('打开话题'),
          ),
        );
  await tester.pumpWidget(
    fixture.app(
      Scaffold(
        body: fullHome
            ? DefaultTabController(
                length: 2,
                child: TabBarView(children: [source(), const Text('其他频道')]),
              )
            : enabled == null
            ? source()
            : ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (_, value, _) =>
                    TickerMode(enabled: value, child: source()),
              ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _carousel => find
    .descendant(
      of: find.byType(HomeChannelCardsHeader),
      matching: find.byType(PageView),
    )
    .first;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'source remains visible until metadata and selected first page are ready',
    (tester) async {
      final api = _ReadyApi();
      await _mount(tester, api);
      await tester.tap(find.text('打开话题'));
      await tester.tap(find.text('打开话题'));
      await tester.pump();
      expect(api.queriedTags, ['ready']);
      expect(find.byType(TopicPage), findsNothing);
      api.detail.complete(_detail);
      await tester.pump();
      expect(api.pageQueries, hasLength(1));
      expect(find.byType(TopicPage), findsNothing);
      api.firstPage.complete(_firstPage);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ActivityTopicView), findsOneWidget);
      expect(find.text('有奖活动'), findsOneWidget);
      expect(find.text('全部讨论'), findsOneWidget);
      expect(find.text('首屏内容'), findsOneWidget);
      expect(find.text('最新发布'), findsNothing);
      expect(api.pageQueries, hasLength(1));
      expect(api.queriedTags, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('默认'));
      await tester.pumpAndSettle();
      expect(api.pageQueries, hasLength(3));
    },
  );

  testWidgets(
    'carousel still rotates and swipes while the requested topic is preparing',
    (tester) async {
      final api = _ReadyApi();
      await _mount(tester, api, carousel: true, fullHome: true);
      expect(api.queriedTags, ['ready']);
      final pager = _carousel;
      final controller = tester.widget<PageView>(pager).controller!;
      final original = controller.page!;
      await tester.tap(
        find.descendant(of: pager, matching: find.byType(InkWell)).first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TopicPage), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator &&
              widget.semanticsLabel == '正在打开话题',
        ),
        findsNothing,
      );
      final progress = find.byWidgetPredicate(
        (widget) =>
            widget is LinearProgressIndicator &&
            widget.semanticsLabel == '正在打开话题',
      );
      expect(progress, findsOneWidget);
      expect(tester.getTopLeft(progress).dy, lessThan(20));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.page!, greaterThan(original));
      final automatic = controller.page!;
      await tester.drag(pager, const Offset(-300, 0));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.page!, greaterThan(automatic));
      expect(api.queriedTags, ['ready']);
      api.detail.complete(_detail);
      await tester.pump();
      api.firstPage.complete(_firstPage);
      await tester.pumpAndSettle();
      expect(find.byType(ActivityTopicView), findsOneWidget);
      expect(find.text('首屏内容'), findsOneWidget);
      expect(progress, findsNothing);
    },
  );

  testWidgets(
    'background ready data opens without a progress flash or repeat requests',
    (tester) async {
      final api = _ReadyApi();
      await _mount(tester, api, carousel: true);
      api.detail.complete(_detail);
      await tester.pump();
      api.firstPage.complete(_firstPage);
      await tester.pump();
      await tester.pump();
      final pager = _carousel;
      await tester.tap(
        find.descendant(of: pager, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActivityTopicView), findsOneWidget);
      expect(find.text('首屏内容'), findsOneWidget);
      expect(api.queriedTags, ['ready']);
      expect(api.pageQueries, hasLength(1));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is LinearProgressIndicator &&
              widget.semanticsLabel == '正在打开话题',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('switching account discards a background prepared topic', (
    tester,
  ) async {
    final api = _ReadyApi();
    await _mount(tester, api, carousel: true);
    api.session = 'another-session';
    final pager = _carousel;
    await tester.tap(
      find.descendant(of: pager, matching: find.byType(InkWell)).first,
    );
    expect(api.queriedTags, ['ready', 'ready']);
    api.detail.complete(_detail);
    await tester.pump();
    api.firstPage.complete(_firstPage);
    await tester.pumpAndSettle();
    expect(find.byType(ActivityTopicView), findsOneWidget);
    expect(api.pageQueries, hasLength(1));
  });
  testWidgets(
    'repeat visits and remounts retain the same session first screen',
    (tester) async {
      final api = _ReadyApi();
      api.detail.complete(_detail);
      api.firstPage.complete(_firstPage);
      await _mount(tester, api, carousel: true, singleItem: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      for (var visit = 0; visit < 3; visit++) {
        await tester.tap(
          find.descendant(of: _carousel, matching: find.byType(InkWell)).first,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.text('首屏内容'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (visit == 0) {
          await tester.tap(find.text('关注'));
          await tester.pump();
          expect(api.topicFollows, [false]);
          expect(find.text('已关注'), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
        } else {
          expect(find.text('已关注'), findsOneWidget);
        }
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await tester.pump(const Duration(minutes: 2));
        if (visit == 1) {
          await tester.pumpWidget(const SizedBox());
          await _mount(tester, api, carousel: true, singleItem: true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
        }
      }
      expect(api.queriedTags, ['ready']);
      expect(api.pageQueries, hasLength(1));
      CacheService.revision.value++;
      await tester.tap(
        find.descendant(of: _carousel, matching: find.byType(InkWell)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(api.queriedTags, ['ready', 'ready']);
      expect(api.pageQueries, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('manual refresh updates the retained default first page', (
    tester,
  ) async {
    final api = _ReadyApi();
    api.detail.complete(_detail);
    api.firstPage.complete(_firstPage);
    await _mount(tester, api, carousel: true, singleItem: true);
    await tester.tap(
      find.descendant(of: _carousel, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    api.refreshedPage = const ApiPage(
      items: [
        {'id': '602', 'title': '刷新后的首屏', 'entityType': 'text'},
      ],
      page: 1,
      hasMore: false,
      firstItem: '602',
      lastItem: '602',
    );
    final refresh = find
        .descendant(
          of: find.byType(ActivityTopicView),
          matching: find.byType(EasyRefresh),
        )
        .first;
    await tester.widget<EasyRefresh>(refresh).onRefresh!();
    await tester.pumpAndSettle();
    expect(find.text('刷新后的首屏'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(
      find.descendant(of: _carousel, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('刷新后的首屏'), findsOneWidget);
    expect(find.text('首屏内容'), findsNothing);
    expect(api.queriedTags, ['ready']);
    expect(api.pageQueries, hasLength(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'a one-item server carousel stays single without invented slides',
    (tester) async {
      final api = _ReadyApi();
      await _mount(
        tester,
        api,
        carousel: true,
        singleItem: true,
        fullHome: true,
      );
      final view = tester.widget<PageView>(_carousel);
      final controller = view.controller!;
      expect(
        (view.childrenDelegate as SliverChildBuilderDelegate).childCount,
        1,
      );
      await tester.pump(const Duration(seconds: 11));
      expect(controller.page, 0);
      await tester.drag(_carousel, const Offset(-300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.page, 0);
      expect(find.text('其他频道'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final cancel in [
    'route',
    'session',
    'tab',
    'cache',
    'late_session',
    'late_cache',
  ]) {
    testWidgets('pending topic does not open after $cancel changes', (
      tester,
    ) async {
      final api = _ReadyApi();
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      await _mount(tester, api, enabled: enabled);
      await tester.tap(find.text('打开话题'));
      if (cancel.startsWith('late_')) {
        api.detail.complete(_detail);
        await tester.pump();
        if (cancel == 'late_cache') {
          CacheService.revision.value++;
        } else {
          api.session = 'another-account';
        }
        api.firstPage.complete(_firstPage);
      } else if (cancel == 'session') {
        api.session = 'another-account';
      } else if (cancel == 'cache') {
        CacheService.revision.value++;
      } else if (cancel == 'tab') {
        enabled.value = false;
        await tester.pump();
      } else {
        Navigator.of(tester.element(find.text('打开话题'))).push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
        );
        await tester.pumpAndSettle();
      }
      if (!cancel.startsWith('late_')) api.detail.complete(_detail);
      await tester.pumpAndSettle();
      expect(find.byType(TopicPage), findsNothing);
      expect(api.pageQueries, hasLength(cancel.startsWith('late_') ? 1 : 0));
    });
  }

  testWidgets('failure stays on source and a later tap retries', (
    tester,
  ) async {
    final api = _ReadyApi();
    await _mount(tester, api);
    await tester.tap(find.text('打开话题'));
    api.detail.completeError(const CoolapkApiException('网络不可用'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicPage), findsNothing);
    expect(find.text('打开话题'), findsOneWidget);
    expect(find.textContaining('打开话题失败'), findsOneWidget);
    await tester.tap(find.text('打开话题'));
    await tester.pumpAndSettle();
    expect(api.queriedTags, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('seeded list continues with its real page and cursors', (
    tester,
  ) async {
    final api = _ReadyApi();
    await tester.pumpWidget(
      fixture.app(
        ApiListPage(
          api: api,
          title: '预载列表',
          path: '/v6/topic/tagFeedList',
          query: const {'tag': 'ready'},
          initialPage: ApiPage(
            items: List.generate(
              20,
              (index) => {'id': '$index', 'title': '条目$index'},
            ),
            page: 1,
            hasMore: true,
            firstItem: '0',
            lastItem: '19',
          ),
          itemBuilder: (_, item) =>
              SizedBox(height: 100, child: Text('${item['title']}')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.pageQueries, isEmpty);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(api.pageQueries, hasLength(1));
    expect(api.pageQueries.single, containsPair('page', 2));
    expect(api.pageQueries.single, containsPair('firstItem', '0'));
    expect(api.pageQueries.single, containsPair('lastItem', '19'));
    expect(tester.takeException(), isNull);
  });
}
