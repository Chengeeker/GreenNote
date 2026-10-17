import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/app_management_page.dart';

const _appChannel = MethodChannel('com.green.note/app_manager');

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'getInstalledApps':
              return [
                _app(
                  packageName: 'com.green.note',
                  label: 'GreenNote',
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
        .setMockMethodCallHandler(_appChannel, null);
  });

  testWidgets('本机应用页默认隐藏系统应用并可显示预装应用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: const AppManagementPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('应用(1)'), findsOneWidget);
    expect(find.text('GreenNote'), findsOneWidget);
    expect(find.text('系统设置'), findsNothing);
    expect(find.text('1.2.2  31.63M'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('应用(2)'), findsOneWidget);
    expect(find.text('系统设置'), findsOneWidget);
  });

  testWidgets('本机应用行可启动应用，列表支持切换分页', (tester) async {
    await tester.pumpWidget(MaterialApp(home: const AppManagementPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(calls.any((call) => call.method == 'launchApp'), isTrue);

    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text('暂未接入更新检查'), findsOneWidget);
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
