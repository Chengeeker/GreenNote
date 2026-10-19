import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/notification_entry.dart';
import 'package:greennote/features/shared/official_notification_center_page.dart';

class _Api implements CoolapkApi {
  bool official = true, sameSession = true, read = false;
  int failId = 0;
  bool repeat = false;
  final calls = <({String path, String method, Map<String, dynamic> query})>[];
  final rows = <Map<String, dynamic>>[
    {
      'id': '1',
      'entityType': 'notification',
      'note': '你举报的回复已被处理，感谢你的举报。',
      'dateline': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 72000,
    },
    {
      'id': '2',
      'entityType': 'notification',
      'fromusername': '莎尘暴2000',
      'fromuid': '20',
      'note': '评论了你的动态：<a href="/feed/333?rid=222">买一个标准版🐶</a>',
      'dateline': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400,
      'feedInfo': {'message': '这台手机的产品力已经到了一定水平'},
    },
    {
      'id': '3',
      'entityType': 'notification',
      'fromusername': '可以吗可以',
      'fromuid': '21',
      'note': '回复了你的评论：<a href="/feed/333?rid=223">其他板块没有官网直降 1000</a>',
      'replyRow': {'message': '我指的是优惠力度的差异，默认起…'},
      'feedInfo': {'message': '这台手机的产品力已经到了一定水平'},
      'dateline': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400,
    },
  ];
  @override
  bool get hasCookie => official;
  @override
  bool get isAnonymous => !official;
  @override
  String get notificationSessionKey => 'session-a';
  @override
  Future<bool> notificationSessionMatches(String key) async =>
      official && sameSession && key == notificationSessionKey;
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    calls.add((path: path, method: 'GET', query: query));
    final page = (query['page'] as int?) ?? 1;
    return ApiPage(
      items: repeat || page == 1 ? List.of(rows) : [],
      page: page,
      hasMore: repeat,
      firstItem: '1',
      lastItem: '3',
    );
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    calls.add((path: path, method: method, query: query));
    if (path.endsWith('clearCount')) read = true;
    if (path.endsWith('/delete')) {
      if (query['id'] == '$failId') throw StateError('模拟删除失败');
      rows.removeWhere((row) => row['id'] == query['id']);
    }
    return {
      'data': read ? {} : {'feedlike': 3, 'contacts_follow': 2, 'message': 1},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    for (final entry in {
      'PreviewCJK': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons': 'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });

  test('notification HTML separates author and action while retaining content links', () {
    final parts = notificationTextParts({
      'fromusername': '酷友',
      'fromuid': '20',
      'note': '<a href="/u/20">酷友</a> 评论了你的动态：<a href="/feed/333?rid=222">你好 &amp; 再见</a>',
    }, '/v6/notification/list');
    expect(parts.sender, '酷友');
    expect(parts.action, '评论了你的动态');
    expect(parts.content, contains('你好 &amp; 再见'));
    expect(parts.content, isNot(contains('/feed/333?rid=222')));
    expect(parts.content, isNot(contains('/u/20')));
    expect(parts.system, false);
    expect(notificationTextParts({'note': '系统处理结果'}, '').system, true);
  });

  test(
    'clear snapshots real IDs and stops on repeated pages or changed account',
    () async {
      final api = _Api();
      expect(await clearInboxNotifications(api, 'session-a'), 3);
      expect(
        api.calls
            .where((call) => call.path.endsWith('/delete'))
            .map((call) => call.query['id']),
        ['1', '2', '3'],
      );
      expect(
        api.calls
            .where((call) => call.path.endsWith('/delete'))
            .every((call) => call.method == 'POST'),
        true,
      );
      final repeated = _Api()..repeat = true;
      await expectLater(
        clearInboxNotifications(repeated, 'session-a'),
        throwsStateError,
      );
      expect(repeated.rows.length, 3);
      expect(
        repeated.calls.any((call) => call.path.endsWith('/delete')),
        false,
      );
      final switched = _Api()..sameSession = false;
      await expectLater(
        clearInboxNotifications(switched, 'session-a'),
        throwsStateError,
      );
      expect(switched.calls, isEmpty);
      final failing = _Api()..failId = 2;
      await expectLater(
        clearInboxNotifications(failing, 'session-a'),
        throwsStateError,
      );
      expect(failing.rows.map((row) => row['id']), ['2', '3']);
    },
  );

  for (final dark in [true, false]) {
    testWidgets(
      'official center layout, categories and confirmed writes ${dark ? 'dark' : 'light large text'}',
      (tester) async {
        final api = _Api();
        tester.view.physicalSize = Size(dark ? 420 : 360, 940);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'PreviewCJK',
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(dark ? 1 : 1.5)),
                  child: child!,
                ),
                initialRoute: '/inbox',
                routes: {
                  '/': (_) => const Scaffold(),
                  '/inbox': (_) => OfficialNotificationCenterPage(
                    api: api,
                    messagesBuilder: (_) => const Text('私信列表'),
                  ),
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('通知中心'), findsOneWidget);
        for (final label in ['点赞', '关注', '私信']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('系统消息', findRichText: true), findsOneWidget);
        expect(
          find.textContaining('莎尘暴2000', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (dark) {
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('tmp/official-notification-preview-dark.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text('关注'));
        await tester.pumpAndSettle();
        expect(
          api.calls.any((call) => call.path.endsWith('contactsFollowList')),
          true,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('设为全部已读'));
        await tester.pumpAndSettle();
        final read = api.calls.firstWhere(
          (call) => call.path.endsWith('clearCount'),
        );
        expect(read.method, 'POST');
        expect(read.query, {'type': 'all'});
        await tester.pump(const Duration(seconds: 4));
        await tester.tap(find.byTooltip('清除通知'));
        await tester.pumpAndSettle();
        expect(api.calls.any((call) => call.path.endsWith('/delete')), false);
        await tester.tap(find.text('确认'));
        await tester.pumpAndSettle();
        expect(api.rows, isEmpty);
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
