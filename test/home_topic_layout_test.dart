import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

const _names = [
  '薅羊毛小分队',
  'iOS27',
  '今日热点',
  '酷安夜话',
  '鸿蒙7',
  'ColorOS17',
  'HyperOS4',
  '数码日常',
  'OriginOS7',
  '临时root免解BL锁',
  '随身wifi',
  'Magisk模块',
];

class _TopicApi extends MockChannelApi {
  final requests = <Map<String, dynamic>>[];
  bool fail = false;
  bool more = false;
  bool includePlaceholders = false;
  Completer<ApiPage>? pending;
  String? openedTag;
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async =>
      const FeedPage(items: [], firstItem: '', lastItem: '', hasMore: false);
  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async {
    openedTag = tag;
    return {
      'data': {'tag': tag, 'title': tag},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    requests.add({'path': path, ...query});
    if (query['url'] == 'V11_VERTICAL_TOPIC') {
      return const ApiPage(
        items: [
          {
            'entityType': 'card',
            'entities': [
              {'title': '推荐', 'url': '#/topic/recommendTagList'},
              {'title': '热门', 'url': '#/topic/hotTagList'},
              {'title': '我的关注', 'url': '#/topic/userFollowTagList'},
              {
                'title': '系统',
                'url': '/page?url=%23%2Ftopic%2FtagList%3Fkeywords%3D%E7%B3%BB%E7%BB%9F',
              },
            ],
          },
        ],
        page: 1,
        firstItem: '',
        lastItem: '',
        hasMore: false,
      );
    }
    if (pending != null && query['url'] == '#/topic/recommendTagList') {
      return pending!.future;
    }
    if (fail) throw const CoolapkApiException('网络失败');
    final page = query['page'] as int? ?? 1;
    return ApiPage(
      items: [
        if (includePlaceholders) ...[
          {'entityType': 'page', 'id': 'container', 'entities': []},
          {'entityType': 'topic', 'id': 'blank', 'title': ' \n ', 'name': null},
          {'entityType': 'topic', 'id': 'new', 'title': '刚创建的话题'},
          {'entityType': 'tag', 'id': 'tag-only', 'tag': '仅标签话题', 'hot_num': 0},
        ],
        ...List.generate(
          more ? 30 : _names.length,
          (index) => {
            'entityType': 'topic',
            'id': '${page * 100 + index}',
            'title': page == 1 && index < _names.length
                ? _names[index]
                : '话题$page-$index',
            'url': '/t/${Uri.encodeComponent('实际标签$page-$index')}',
            'logo': index < 3
                ? 'https://image.coolapk.com/topic-$index.png'
                : '',
            'hot_num': index == 0 ? 5242000 : null,
            'hot_num_txt': index == 0
                ? ''
                : index == 1
                ? '220.1万'
                : '0',
            'description': '不应该出现在紧凑网格中的长说明',
          },
        ),
      ],
      page: page,
      firstItem: 'first',
      lastItem: 'last-$page',
      hasMore: more && page == 1,
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _TopicApi api, {
  double width = 360,
  double scale = 1,
  Brightness brightness = Brightness.dark,
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
  if (const bool.fromEnvironment('GENERATE_TOPIC_PREVIEW')) {
    await tester.runAsync(() async {
      await (FontLoader('TopicPreviewSans')..addFont(
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
      textTheme: theme.textTheme.apply(fontFamily: 'TopicPreviewSans'),
    );
  }
  final topBar = ValueNotifier<PreferredSizeWidget?>(null);
  final home = FeedHomePage(
    api: api,
    onLoginRequested: () async {},
    onTopBarChanged: (value) => topBar.value = value,
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: ValueListenableBuilder<PreferredSizeWidget?>(
          valueListenable: topBar,
          builder: (_, bar, _) => Scaffold(
            appBar: AppBar(bottom: bar),
            body: home,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.ensureVisible(find.text('话题').first);
  await _pumpFrames(tester);
  await tester.tap(find.text('话题').first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('blank API entries do not occupy topic grid cells', (
    tester,
  ) async {
    final api = _TopicApi()..includePlaceholders = true;
    await _mount(tester, api);
    // Valid new topics without an icon or heat must remain visible.
    expect(find.text('刚创建的话题'), findsOneWidget);
    expect(find.text('仅标签话题'), findsOneWidget);
    expect(find.text('暂无热度'), findsOneWidget);
    final newTopic = tester.getTopLeft(find.text('刚创建的话题'));
    final tagTopic = tester.getTopLeft(find.text('仅标签话题'));
    final firstNamed = tester.getTopLeft(find.text(_names.first));
    expect(newTopic.dy, tagTopic.dy);
    expect(tagTopic.dy, firstNamed.dy);
    expect(newTopic.dx, lessThan(tagTopic.dx));
    expect(tagTopic.dx, lessThan(firstNamed.dx));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'home topics use three compact columns with actual heat and lazy rows',
    (tester) async {
      final api = _TopicApi()..more = true;
      final boundary = GlobalKey();
      await _mount(tester, api, boundary: boundary);
      expect(api.requests[1]['url'], '#/topic/hotTagList');
      final first = tester.getTopLeft(find.text(_names[0]));
      final second = tester.getTopLeft(find.text(_names[1]));
      final third = tester.getTopLeft(find.text(_names[2]));
      expect(first.dy, second.dy);
      expect(second.dy, third.dy);
      expect(first.dx, lessThan(second.dx));
      expect(second.dx, lessThan(third.dx));
      expect(
        tester.getTopLeft(find.text(_names[3])).dy,
        greaterThan(first.dy + 100),
      );
      expect(find.text('524.2万'), findsOneWidget);
      expect(find.text('220.1万'), findsOneWidget);
      expect(find.textContaining('不应该出现'), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(tester.widget<Text>(find.text(_names[0])).style!.fontSize, 14);
      expect(find.text('话题1-29'), findsNothing); // Not all rows are mounted.
      final grid = tester.widget<ApiListPage>(find.byType(ApiListPage).first);
      expect(grid.gridColumns, 3);
      final icons = tester.widgetList<CachedNetworkImage>(
        find.descendant(
          of: find.byType(ApiListPage).first,
          matching: find.byType(CachedNetworkImage),
        ),
      );
      expect(icons.length, 3);
      expect(
        icons.every((image) => image.width == 56 && image.height == 56),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('GENERATE_TOPIC_PREVIEW')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3.5);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('tmp/verification/1.9.31/home-topics.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text(_names[0]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.openedTag, '实际标签1-0');
      expect(find.byType(TopicPage), findsOneWidget);
    },
  );

  testWidgets(
    'category routing keeps keywords and ignores late prior category',
    (tester) async {
      final api = _TopicApi();
      await _mount(tester, api);
      api.pending = Completer<ApiPage>();
      await tester.tap(find.text('推荐').first);
      await tester.pump();
      await tester.tap(find.text('系统').first);
      await _pumpFrames(tester);
      expect(api.requests.last['path'], '/v6/page/dataList');
      expect(api.requests.last['url'], '#/topic/tagList?keywords=系统');
      api.pending!.complete(
        const ApiPage(
          items: [
            {'entityType': 'topic', 'title': '迟到旧分类'},
          ],
          page: 1,
          firstItem: '',
          lastItem: '',
          hasMore: false,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('迟到旧分类'), findsNothing);
      expect(find.text(_names[0]), findsOneWidget);
    },
  );

  testWidgets('grid refresh, pagination cursors and retry remain usable', (
    tester,
  ) async {
    final api = _TopicApi()..fail = true;
    await _mount(tester, api);
    expect(find.text('重试'), findsOneWidget);
    api
      ..fail = false
      ..more = true;
    await tester.tap(find.text('重试'));
    await _pumpFrames(tester);
    final list = find
        .descendant(
          of: find.byType(ApiListPage).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(list, const Offset(0, -1400));
    await _pumpFrames(tester);
    expect(
      api.requests.where((r) => r['page'] == 2).single['lastItem'],
      'last-1',
    );
    final refresh = tester.widget<EasyRefresh>(
      find
          .descendant(
            of: find.byType(ApiListPage).first,
            matching: find.byType(EasyRefresh),
          )
          .first,
    );
    final beforeRefresh = api.requests.length;
    await refresh.onRefresh!();
    await _pumpFrames(tester);
    expect(api.requests[beforeRefresh]['page'], 1);
    expect(api.requests[beforeRefresh].containsKey('lastItem'), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('narrow topic grid supports large text in $brightness', (
      tester,
    ) async {
      await _mount(
        tester,
        _TopicApi(),
        width: 320,
        scale: 1.6,
        brightness: brightness,
      );
      expect(find.text(_names[0]), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(CachedNetworkImage), findsNWidgets(3));
    });
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Network image placeholders can animate indefinitely in widget tests.
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
