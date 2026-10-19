import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/services/reply_notification_service.dart';
import 'package:greennote/core/services/reply_notification_state.dart';
import 'package:greennote/features/settings/notification_center_page.dart';
import 'package:greennote/features/shared/reply_notifications_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements CoolapkApi {
  bool official = true;
  bool matches = true;
  String scope = 'a' * 64;
  int requests = 0;
  Future<dynamic> Function()? response;
  List<Map<String, dynamic>> items = [];

  @override
  bool get hasCookie => official;
  @override
  String get notificationSessionKey => official ? scope : '';
  @override
  Future<bool> notificationSessionMatches(String key) async =>
      matches && key == scope && official;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    expect(path, '/v6/notification/list');
    expect(method, 'GET');
    requests++;
    return response == null ? {'data': items} : await response!();
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async => ApiPage(
    items: items,
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late List<String> delivered;
  Future<String> check({
    bool force = true,
    bool permission = true,
    bool failDelivery = false,
  }) => checkForReplyNotifications(
    api: api,
    force: force,
    canNotify: () async => permission,
    deliver: (scope, items, preview) async {
      expect(preview, isFalse);
      if (failDelivery) throw StateError('delivery failed');
      delivered.addAll(items.map((item) => item.id));
    },
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _Api();
    delivered = [];
    await saveReplyNotificationSettings(
      const ReplyNotificationSettings(enabled: true),
    );
  });

  test('safe defaults, nested parsing, HTML preview and invalid payload', () {
    final defaults = ReplyNotificationSettings.fromJson({
      'intervalMinutes': -1,
    });
    expect(defaults.enabled, isFalse);
    expect(defaults.showPreview, isFalse);
    expect(defaults.intervalMinutes, 1);
    final items = ReplyNotificationItem.parse({
      'data': {
        'list': [
          {
            'id': 1,
            'dateline': 1700000000000,
            'note': '<b>Hello</b> &amp; world',
          },
        ],
      },
    });
    expect(items.single.timestamp, 1700000000);
    expect(items.single.preview, 'Hello & world');
    expect(
      () => ReplyNotificationItem.parse({'data': 'invalid'}),
      throwsFormatException,
    );
    final fallback = ReplyNotificationItem({'id': 0, 'uid': 7, 'note': 'text'});
    expect(fallback.id.length, 64);
    expect(
      fallback.id,
      ReplyNotificationItem({'id': 0, 'uid': 7, 'note': 'text'}).id,
    );
  });

  test(
    'persisted identity guard rejects changed Cookie and local login modes',
    () async {
      var cookie = 'test-cookie-a';
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'read' ? cookie : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final client = await CoolapkApi.create();
      addTearDown(client.close);
      final scope = client.notificationSessionKey;
      expect(scope.length, 64);
      expect(await client.notificationSessionMatches(scope), true);
      cookie = 'test-cookie-b';
      expect(await client.notificationSessionMatches(scope), false);
      cookie = 'test-cookie-a';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('greennote.local.active', true);
      expect(await client.notificationSessionMatches(scope), false);
      await prefs.setBool('greennote.local.active', false);
      await prefs.setBool('greennote.cookie.enabled', false);
      expect(await client.notificationSessionMatches(scope), false);
    },
  );

  testWidgets(
    'reply list renders notification sender and note rather than a feed ID',
    (tester) async {
      api.items = [
        {
          'id': '99',
          'entityType': 'notification',
          'fromusername': '回复人',
          'note': '评论了你的动态：<a href="/feed/333?rid=222">评论内容</a>',
        },
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: ReplyNotificationsPage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('回复人', findRichText: true), findsOneWidget);
      expect(find.textContaining('评论内容', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('baseline, batch dedup, old reflow and bounded history', () {
    var history = const ReplyNotificationHistory();
    final first = history.merge('a', [
      ReplyNotificationItem({'id': 1, 'dateline': 100}),
    ]);
    expect(first.fresh, isEmpty);
    history = first.history;
    final next = history.merge('a', [
      ReplyNotificationItem({'id': 2, 'dateline': 101}),
      ReplyNotificationItem({'id': 2, 'dateline': 101}),
      ReplyNotificationItem({'id': 3, 'dateline': 99}),
    ]);
    expect(next.fresh.map((item) => item.id), ['2']);
    expect(
      next.history.merge('b', [
        ReplyNotificationItem({'id': 4}),
      ]).fresh,
      isEmpty,
    );
    final many = next.history.merge(
      'a',
      List.generate(300, (i) => ReplyNotificationItem({'id': i + 10})),
    );
    expect(many.history.seen.length, 200);
  });

  test('first baseline then new reply only once, status contains no message content', () async {
    api.items = [
      {'id': 1, 'note': 'private text'},
    ];
    await check();
    expect(delivered, isEmpty);
    api.items.insert(0, {'id': 2, 'note': 'secret'});
    await check();
    await check();
    expect(delivered, ['2']);
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getKeys().map((key) => '${prefs.get(key)}').join();
    expect(state, isNot(contains('private text')));
    expect(state, isNot(contains('secret')));
  });

  test(
    'disabled, anonymous or denied permission never queries private endpoint',
    () async {
      api.official = false;
      await check();
      api.official = true;
      await check(permission: false);
      await saveReplyNotificationSettings(const ReplyNotificationSettings());
      await check();
      expect(api.requests, 0);
    },
  );

  test('account change creates a new baseline', () async {
    await check();
    api.scope = 'b' * 64;
    api.items = [
      {'id': 2},
    ];
    await check();
    expect(delivered, isEmpty);
    api.items = [
      {'id': 3},
      {'id': 2},
    ];
    await check();
    expect(delivered, ['3']);
  });

  test('network errors back off without clearing baseline', () async {
    await check();
    api.response = () async => throw StateError('network');
    expect(await check(), contains('检查失败'));
    final count = api.requests;
    expect(await check(force: false), '等待下次检查');
    expect(api.requests, count);
    api.response = null;
    api.items = [
      {'id': 5},
    ];
    await check();
    expect(delivered, ['5']);
  });

  test(
    'failed notification delivery is retried without consuming new reply',
    () async {
      await check();
      api.items = [
        {'id': 6},
      ];
      await check(failDelivery: true);
      await check();
      expect(delivered, ['6']);
    },
  );

  test('logout or disabling during a request drops stale result', () async {
    await check();
    for (final logout in [false, true]) {
      await saveReplyNotificationSettings(
        const ReplyNotificationSettings(enabled: true),
      );
      final response = Completer<dynamic>();
      api.response = () => response.future;
      final running = check();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (logout) {
        api.matches = false;
      } else {
        await saveReplyNotificationSettings(const ReplyNotificationSettings());
      }
      response.complete({
        'data': [
          {'id': 9},
        ],
      });
      expect(await running, contains('变更'));
    }
    expect(delivered, isEmpty);
  });

  testWidgets(
    'notification center denies enable and saves mode on narrow large text screen',
    (tester) async {
      await saveReplyNotificationSettings(const ReplyNotificationSettings());
      tester.view.reset();
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 900),
                textScaler: TextScaler.linear(1.5),
              ),
              child: ReplyNotificationSettingsPage(
                api: api,
                requestPermission: () async => false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('自动检查新回复'));
      await tester.pumpAndSettle();
      expect((await readReplyNotificationSettings()).enabled, isFalse);
      await tester.tap(
        find.byType(DropdownButtonFormField<ReplyBackgroundMode>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('常驻后台检查').last);
      await tester.pumpAndSettle();
      expect(
        (await readReplyNotificationSettings()).mode,
        ReplyBackgroundMode.resident,
      );
      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('greennote.reply_notifications.settings')!,
        )['enabled'],
        false,
      );
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
