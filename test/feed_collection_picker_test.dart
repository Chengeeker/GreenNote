import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_collection_picker.dart';

class _Api extends Fake implements CoolapkApi {
  bool anonymous = false, failRead = false, failWrite = false;
  String session = 'account-a';
  final writes = <({List<String> selected, List<String> cancelled})>[];
  Completer<void>? pendingWrite;
  List<FeedCollection> items = [
    FeedCollection.fromJson({
      'id': '1',
      'title': '系统收藏',
      'isDefault': 1,
      'isBeCollected': 1,
    }),
    FeedCollection.fromJson({'id': '2', 'title': '数码资料'}),
  ];
  @override
  bool get hasCookie => !anonymous;
  @override
  bool get isAnonymous => anonymous;
  @override
  String get notificationSessionKey => session;
  @override
  Future<List<FeedCollection>> getFeedCollections(
    String id, {
    required String scope,
  }) async {
    if (failRead) throw const CoolapkApiException('读取失败');
    return items;
  }

  @override
  Future<void> updateFeedCollections(
    String id, {
    required List<String> selected,
    required List<String> cancelled,
    required String scope,
    CoolapkFeed? feed,
  }) async {
    if (scope != session) throw const CoolapkApiException('账号已变更');
    writes.add((selected: selected, cancelled: cancelled));
    if (failWrite) throw const CoolapkApiException('保存失败');
    await pendingWrite?.future;
  }
}

void main() {
  final feed = CoolapkFeed.fromJson({'id': '42', 'entityType': 'feed'});
  Future<void> open(WidgetTester tester, _Api api, {bool dark = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedCollectionPicker(context, api, feed),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'picker preserves memberships and saves explicit changes dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = _Api();
        await open(tester, api, dark: dark);
        final checkboxes = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(checkboxes.map((item) => item.value), [true, false]);
        await tester.tap(find.text('数码资料'));
        expect(api.writes, isEmpty);
        await tester.tap(find.text('系统收藏'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(api.writes.single.selected, ['2']);
        expect(api.writes.single.cancelled, ['1']);
        expect(find.text('选择收藏夹'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('read errors retry and failed saves preserve the draft', (
    tester,
  ) async {
    final api = _Api()..failRead = true;
    await open(tester, api);
    expect(find.textContaining('读取失败'), findsOneWidget);
    api.failRead = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数码资料'));
    api.failWrite = true;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((item) => item.value!),
      isTrue,
    );
    api.failWrite = false;
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(api.writes.last.selected, ['1', '2']);
    expect(api.writes.last.cancelled, isEmpty);
    expect(find.text('选择收藏夹'), findsNothing);
  });

  testWidgets('switching accounts blocks writes; cancel never saves', (
    tester,
  ) async {
    final api = _Api();
    await open(tester, api);
    api.session = 'account-b';
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.textContaining('账号已变更'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('选择收藏夹'), findsNothing);
  });

  testWidgets('a pending write blocks repeat taps and back navigation', (
    tester,
  ) async {
    final api = _Api()..pendingWrite = Completer<void>();
    await open(tester, api);
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('选择收藏夹'), findsOneWidget);
    expect(api.writes, hasLength(1));
    api.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('选择收藏夹'), findsNothing);
  });

  testWidgets('empty collections and anonymous accounts never write', (
    tester,
  ) async {
    final api = _Api()..items = [];
    await open(tester, api);
    expect(find.textContaining('暂无可用收藏夹'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    api.anonymous = true;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('选择收藏夹'), findsNothing);
    expect(api.writes, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
}
