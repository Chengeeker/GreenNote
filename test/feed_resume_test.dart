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

void main() {
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
