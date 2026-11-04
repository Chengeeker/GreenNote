import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/app_detail_page.dart';
import 'package:greennote/features/shared/app_management_page.dart';

const _appChannel = MethodChannel('com.green.note/app_manager');
const _downloadsChannel = MethodChannel('com.green.note/downloads');

Map<String, dynamic> _app({
  required String packageName,
  required String label,
  required bool isSystem,
  required int updatedAt,
}) => {
  'packageName': packageName,
  'label': label,
  'version': '1.2.2',
  'sizeBytes': 33166479,
  'updatedAt': updatedAt,
  'isSystem': isSystem,
  'canLaunch': true,
  'icon': Uint8List(0),
};

class _ArticleApi implements CoolapkApi {
  @override
  bool get hasCookie => false;
  @override
  bool get isAnonymous => true;
  @override
  String get currentUid => '';
  @override
  String get loginRequiredMessage => '请先登录';
  @override
  Map<String, String> imageHeadersFor() => const {};
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async => const {};
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async => ApiPage(
    items: const [
      {
        'id': 'article-1',
        'entityType': 'feedArticle',
        'entityTemplate': 'feedArticle',
        'uid': '7',
        'username': '测试作者',
        'title': 'Hinge 办公套件',
        'message': '正文应该完整显示，不再被截成普通动态的短摘要。',
        'picArr': [
          'https://example.com/article-1.jpg',
          'https://example.com/article-2.jpg',
        ],
      },
    ],
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AppDetailApi extends _ArticleApi {
  final requests = <(String, Map<String, dynamic>)>[];
  bool fail = false;

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    requests.add((path, query));
    if (fail) throw const CoolapkApiException('商店中未找到此应用');
    return {
      'data': {'id': '123', 'title': '微信', 'apkname': 'com.tencent.mm'},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async => ApiPage(
    items: const [],
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_downloadsChannel, (_) async => <dynamic>[]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'getInstalledApps':
              return [
                _app(
                  packageName: 'com.tencent.mm',
                  label: '微信',
                  isSystem: false,
                  updatedAt: 20,
                ),
                _app(
                  packageName: 'android.settings',
                  label: '系统设置',
                  isSystem: true,
                  updatedAt: 10,
                ),
              ];
            case 'launchApp':
            case 'showAppInfo':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_downloadsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appChannel, null);
  });

  testWidgets('resume checks changes without clearing the installed list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AppManagementPage(api: _ArticleApi())),
    );
    await tester.pumpAndSettle();
    expect(find.text('微信'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('微信'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      calls.where((call) => call.method == 'getInstalledApps'),
      hasLength(1),
    );
    expect(calls.last.method, 'getInstalledAppsIfChanged');
    await tester.pumpAndSettle();
  });

  testWidgets('本机应用页默认隐藏系统应用并可显示预装应用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppManagementPage(api: _ArticleApi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用(1)'), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);
    expect(find.text('系统设置'), findsNothing);
    expect(find.text('1.2.2  31.63M'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('应用(2)'), findsOneWidget);
    expect(find.text('系统设置'), findsOneWidget);
  });

  testWidgets('应用管理四个标签在窄屏和大字下等宽且居中', (tester) async {
    for (final size in [const Size(320, 800), const Size(420, 900)]) {
      for (final scale in [1.0, 1.6]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: AppManagementPage(api: _ArticleApi()),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = find.byType(Tab);
        expect(tabs, findsNWidgets(4));
        final centers = [
          for (var i = 0; i < 4; i++) tester.getCenter(tabs.at(i)).dx,
        ];
        for (var i = 0; i < 4; i++) {
          expect(centers[i], closeTo(size.width * (i + 0.5) / 4, 0.1));
        }
        await tester.tap(find.text('安装包'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('本机应用行可启动应用，列表支持切换分页', (tester) async {
    final api = _AppDetailApi();
    await tester.pumpWidget(MaterialApp(home: AppManagementPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'launchApp');
    expect(calls.last.arguments, {'packageName': 'com.tencent.mm'});
    expect(find.byType(AppDetailPage), findsNothing);
    expect(api.requests, isEmpty);

    await tester.tap(find.byTooltip('应用选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用详情'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'showAppInfo');
    expect(calls.last.arguments, {'packageName': 'com.tencent.mm'});
    expect(find.byType(AppDetailPage), findsNothing);
    expect(api.requests, isEmpty);

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsOneWidget);
  });

  for (final target in ['名称', '图标', '行空白']) {
    testWidgets('点击本机应用$target按包名进入应用内商店详情，返回保留列表', (tester) async {
      final api = _AppDetailApi();
      await tester.pumpWidget(MaterialApp(home: AppManagementPage(api: api)));
      await tester.pumpAndSettle();

      switch (target) {
        case '图标':
          await tester.tap(find.byIcon(Icons.android_rounded));
        case '行空白':
          final row = find
              .ancestor(of: find.text('微信'), matching: find.byType(InkWell))
              .first;
          await tester.tapAt(tester.getTopLeft(row) + const Offset(3, 3));
        default:
          await tester.tap(find.text('微信'));
      }
      await tester.pumpAndSettle();

      final detail = tester.widget<AppDetailPage>(find.byType(AppDetailPage));
      expect(detail.api, same(api));
      expect(detail.id, 'com.tencent.mm');
      expect(api.requests, hasLength(1));
      expect(api.requests.single.$1, '/v6/apk/detail');
      expect(api.requests.single.$2, {'id': 'com.tencent.mm'});
      expect(calls.map((call) => call.method), ['getInstalledApps']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('微信'), findsOneWidget);
      expect(find.text('应用(1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('商店查不到应用时保留详情错误和重试入口', (tester) async {
    final api = _AppDetailApi()..fail = true;
    await tester.pumpWidget(MaterialApp(home: AppManagementPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('微信'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDetailPage), findsOneWidget);
    expect(find.textContaining('商店中未找到此应用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.requests.length, 2);
    expect(calls.map((call) => call.method), ['getInstalledApps']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的图文列表使用官方图文卡片排版（标题、题图、正文摘要）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ApiListPage(
          api: _ArticleApi(),
          title: '我的图文',
          path: '/v6/user/htmlFeedList',
          query: const {'uid': '7'},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final card = tester.widget<FeedCard>(find.byType(FeedCard));
    expect(card.articleLayout, isTrue);
    expect(find.text('Hinge 办公套件'), findsOneWidget);
    final body = find.text('正文应该完整显示，不再被截成普通动态的短摘要。');
    expect(body, findsOneWidget);
    final coverFinder = find.byWidgetPredicate(
      (w) => w is AspectRatio && (w.aspectRatio - 2.0).abs() < 0.05,
    );
    expect(coverFinder, findsOneWidget);
    expect(
      tester.getTopLeft(body).dy,
      greaterThan(tester.getTopLeft(coverFinder).dy),
    );
  });
}
