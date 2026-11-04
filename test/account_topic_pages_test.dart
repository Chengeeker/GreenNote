import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/features/shared/account_topic_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

List<Map<String, dynamic>> publicTopics() => (jsonDecode(
  File('test/fixtures/account_topics_public_20261104.json').readAsStringSync(),
) as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();

class _TopicsApi extends MockChannelApi {
  final requests = <Map<String, dynamic>>[];
  bool more = false;
  bool fail = false;
  String? openedTag;
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requests.add({'path': path, ...query});
    if (fail) throw const CoolapkApiException('网络失败');
    final page = query['page'] as int? ?? 1;
    final items = path.contains('myFollowTopicList')
        ? more
              ? List.generate(
                  20,
                  (i) => {
                    ...publicTopics().first,
                    'id': '$page-$i',
                    'title': '第$page页话题$i',
                  },
                )
              : publicTopics()
        : path.contains('recentHistoryList')
        ? <Map<String, dynamic>>[
            {
              'entityType': 'product',
              'id': '711',
              'title': 'OPPO Find X9s Pro',
              'logo': '',
              'follownum': 6279,
              'commentnum': 9288,
            },
            publicTopics().last,
            {
              'entityType': 'user',
              'id': '999',
              'uid': '456',
              'title': '我的天啊ys',
              'userAvatar': '',
              'follow': 6,
              'fans': 14392,
              'url': '/u/456',
            },
          ]
        : <Map<String, dynamic>>[];
    return ApiPage(
      items: items,
      page: page,
      firstItem: 'first',
      lastItem: 'last-$page',
      hasMore: more && page == 1,
    );
  }

  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async {
    openedTag = tag;
    return {
      'data': {...publicTopics().last, 'title': tag, 'tag': tag},
    };
  }
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _mountTopics(
  WidgetTester tester,
  _TopicsApi api, {
  bool followedTopics = true,
  Brightness brightness = Brightness.dark,
  double width = 360,
  double scale = 1,
  GlobalKey? boundary,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var theme = brightness == Brightness.dark
      ? AppTheme.darkTheme()
      : AppTheme.lightTheme();
  if (const bool.fromEnvironment('GENERATE_ACCOUNT_LIST_PREVIEW')) {
    await tester.runAsync(() async {
      await (FontLoader('AccountListPreview')..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
              ),
            ),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'AccountListPreview'),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: 'AccountListPreview',
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: boundary, child: child!),
      ),
      home: AccountTopicListPage(api: api, followedTopics: followedTopics),
    ),
  );
  await pumpFrames(tester);
}

void main() {
  test('actual public topic payload supplies discussions instead of heat', () {
    final topics = publicTopics();
    expect(accountTopicCount(topics[0]), '7.2万');
    expect(accountTopicCount(topics[1]), '2.5万');
    expect(accountTopicCount(topics[2]), '890');
    expect(accountTopicCount({'commentnum': 0, 'hot_num': 888}), '0');
    expect(accountTopicCount({'hot_num': 888}), '');
  });

  testWidgets(
    'followed topic list uses real heat, discussion and rating fields',
    (tester) async {
      final api = _TopicsApi();
      final boundary = GlobalKey();
      await _mountTopics(tester, api, boundary: boundary);
      expect(api.requests.first['path'], '/v6/topic/myFollowTopicList');
      expect(find.text('鸿蒙6', findRichText: true), findsOneWidget);
      expect(find.text('12.5万热度 7.2万讨论'), findsOneWidget);
      expect(find.text('9.1'), findsOneWidget);
      expect(find.text('3.7'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(10));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      final images = tester.widgetList<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(
        images.every((image) => image.width == 56 && image.height == 56),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('GENERATE_ACCOUNT_LIST_PREVIEW')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/verification/1.9.33/followed-topics.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('双11开箱', findRichText: true));
      await pumpFrames(tester);
      expect(api.openedTag, '双11开箱');
      expect(find.byType(TopicPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'frequent list shows category chips and correct per-type statistics',
    (tester) async {
      final api = _TopicsApi();
      final boundary = GlobalKey();
      await _mountTopics(
        tester,
        api,
        followedTopics: false,
        boundary: boundary,
      );
      expect(find.text('我的常去'), findsOneWidget);
      expect(find.text('数码'), findsOneWidget);
      expect(find.text('话题'), findsOneWidget);
      expect(find.text('用户'), findsOneWidget);
      expect(find.text('6279关注 9288讨论'), findsOneWidget);
      expect(find.text('565关注 890讨论'), findsOneWidget);
      expect(find.text('6关注 14392粉丝'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.star), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('GENERATE_ACCOUNT_LIST_PREVIEW')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/verification/1.9.33/frequent-visits.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.textContaining('我的天啊ys', findRichText: true));
      await pumpFrames(tester);
      expect(
        tester.widget<UserSpacePage>(find.byType(UserSpacePage)).uid,
        '456',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('list keeps retry, pagination and refresh cursors', (
    tester,
  ) async {
    final api = _TopicsApi()..fail = true;
    await _mountTopics(tester, api);
    expect(find.text('重试'), findsOneWidget);
    api
      ..fail = false
      ..more = true;
    await tester.tap(find.text('重试'));
    await pumpFrames(tester);
    final list = find
        .descendant(
          of: find.byType(ApiListPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(list, const Offset(0, -1700));
    await pumpFrames(tester);
    expect(
      api.requests.where((r) => r['page'] == 2).single['lastItem'],
      'last-1',
    );
    final count = api.requests.length;
    await tester.widget<EasyRefresh>(find.byType(EasyRefresh)).onRefresh!();
    await pumpFrames(tester);
    expect(api.requests[count]['page'], 1);
    expect(api.requests[count].containsKey('lastItem'), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final followed in [true, false]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'list adapts to 320dp with large text: $followed $brightness',
        (tester) async {
          await _mountTopics(
            tester,
            _TopicsApi(),
            followedTopics: followed,
            brightness: brightness,
            width: 320,
            scale: 1.6,
          );
          expect(find.byType(AccountTopicListPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
