import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/main.dart';

const emptyPage = FeedPage(
  items: [],
  firstItem: '',
  lastItem: '',
  hasMore: false,
);

class TimelineApi implements CoolapkApi {
  TimelineApi(this.localAccount);
  @override
  final LocalAccount localAccount;
  @override
  final ValueNotifier<int> accountProfileRevision = ValueNotifier<int>(0);
  @override
  bool get isAnonymous => true;
  @override
  bool get hasCookie => false;
  @override
  String get currentUserAvatar => '';
  @override
  Map<String, String> imageHeadersFor() => {};
  int followReads = 0;
  int feedReads = 0;
  Completer<FeedPage>? pending;
  @override
  Future<ApiPage> getUserPage(
    String route,
    String uid,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    followReads++;
    return ApiPage(
      items: [
        {'uid': '${uid}1'},
      ],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  Future<FeedPage> getUserFeedPage(
    String uid,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    feedReads++;
    if (pending != null) return pending!.future;
    return FeedPage(
      items: [
        CoolapkFeed.fromJson({
          'id': uid,
          'uid': uid,
          'username': '作者',
          'message': '保留的动态',
          'dateline': 100,
        }),
      ],
      firstItem: uid,
      lastItem: uid,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadHomeTabRoutes) {
      return Future.value(<String, String>{});
    }
    if (invocation.memberName == #getHomeChannelPage) {
      return Future.value(emptyPage);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets(
    'bound avatar updates and refresh reuses follow IDs without clearing feeds',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = (await tester.runAsync(
        () async =>
            TimelineApi(LocalAccount(await SharedPreferences.getInstance())),
      ))!;
      await tester.runAsync(() async {
        await api.localAccount.setActive(true);
        await api.localAccount.setPublicIdentity(
          uid: '123',
          username: '远端头像',
          userAvatar: 'https://example.com/remote.png',
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coolapkApiProvider.overrideWith((ref) async => api)],
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widgetList<AppAvatar>(find.byType(AppAvatar))
            .any((a) => a.url == 'https://example.com/remote.png'),
        isTrue,
      );
      await tester.tap(find.text('关注').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.followReads, 1);
      expect(find.text('保留的动态'), findsOneWidget);
      final timeline = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_LocalFollowTimeline',
      );
      final refresh = tester.widget<EasyRefresh>(
        find.descendant(of: timeline, matching: find.byType(EasyRefresh)),
      );
      api.pending = Completer<FeedPage>();
      final refreshing = refresh.onRefresh!();
      await tester.pump();
      expect(api.followReads, 1);
      expect(api.feedReads, 2);
      expect(find.text('保留的动态'), findsOneWidget);
      api.pending!.complete(emptyPage);
      await refreshing;
      api.pending = null;
      await tester.pump();
      await tester.runAsync(
        () => api.localAccount.setPublicIdentity(
          uid: '456',
          username: '新头像',
          userAvatar: 'https://example.com/new.png',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.followReads, 2);
      expect(
        tester
            .widgetList<AppAvatar>(find.byType(AppAvatar))
            .any((a) => a.url == 'https://example.com/new.png'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
