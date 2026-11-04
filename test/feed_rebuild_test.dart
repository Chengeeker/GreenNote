import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

class _Api extends MockChannelApi {
  _Api() : super(currentUid: 'rebuild-test');
  final nextPage = Completer<FeedPage>();
  int pageCalls = 0;
  int refreshes = 0;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<void> likeFeed(String id, {required bool liked}) async {}
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    if (page > 1) {
      pageCalls++;
      return nextPage.future;
    }
    refreshes++;
    return FeedPage(
      items: List.generate(
        20,
        (i) => CoolapkFeed.fromJson({
          'id': '$i',
          'username': '作者$i',
          'message': '刷新$refreshes 动态$i：${'用于验证已浏览卡片不应被无关分页重新构建。' * 8}',
        }),
      ),
      firstItem: '0',
      lastItem: '19',
      hasMore: true,
    );
  }
}

void main() {
  testWidgets('paging preserves warm cards while refresh and theme still update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    late StateSetter updateHost;
    var dark = false;
    var scale = 1.0;
    await tester.pumpWidget(
      ProviderScope(
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: FeedHomePage(api: api, onLoginRequested: () async {}),
                ),
              ),
            );
          },
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final listFinder = find.byWidgetPredicate(
      (w) =>
          w is ListView &&
          w.scrollDirection == Axis.vertical &&
          w.controller != null,
    );
    final controller = tester.widget<ListView>(listFinder.first).controller!;
    final first = find.byKey(const ValueKey('feed-0'), skipOffstage: false);
    final original = tester.widget<FeedCard>(first);
    var rebuilds = 0;
    final previousHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousHook?.call(element, builtOnce);
      if (element.widget is FeedCard &&
          (element.widget as FeedCard).feed.id == '0') {
        rebuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousHook);
    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.pageCalls, 1);
    final startRebuilds = rebuilds;
    api.nextPage.complete(
      FeedPage(
        items: [
          CoolapkFeed.fromJson({'id': '20', 'message': '追加内容'}),
        ],
        firstItem: '20',
        lastItem: '20',
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint(
      'Warm card rebuilds: request=$startRebuilds, result=${rebuilds - startRebuilds}',
    );
    expect(
      rebuilds,
      0,
      reason:
          'Loading state and append must not rebuild unchanged retained cards',
    );
    expect(tester.widget<FeedCard>(first), same(original));

    controller.jumpTo(0);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: first,
        matching: find.byIcon(Icons.thumb_up_outlined),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(of: first, matching: find.byIcon(Icons.thumb_up_rounded)),
      findsOneWidget,
    );

    rebuilds = 0;
    updateHost(() {
      dark = true;
      scale = 1.3;
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(Theme.of(tester.element(first)).brightness, Brightness.dark);
    expect(MediaQuery.textScalerOf(tester.element(first)).scale(10), 13);
    expect(rebuilds, greaterThan(0));

    await tester
        .widget<EasyRefresh>(find.byType(EasyRefresh).first)
        .onRefresh!();
    await tester.pump();
    final refreshed = tester.widget<FeedCard>(first);
    expect(refreshed.feed.message, startsWith('刷新2'));
    expect(refreshed, isNot(same(original)));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
  });
}
