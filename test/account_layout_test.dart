import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/app_management_page.dart';
import 'package:greennote/features/shell/main_pages.dart';

class AccountLayoutApi implements CoolapkApi {
  AccountLayoutApi(this.localAccount);
  @override
  final LocalAccount localAccount;
  final reads = <String>[];
  int loginChecks = 0;
  int spaceRequests = 0;
  Map<String, dynamic>? spaceData;
  @override
  bool get isAnonymous => localAccount.active;
  @override
  bool get hasCookie => !isAnonymous;
  @override
  String get currentUid => isAnonymous ? '' : '123';
  @override
  String get currentUserAvatar => '';
  @override
  String get loginRequiredMessage => '请先登录';
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<Map<String, dynamic>> checkLogin() async {
    loginChecks++;
    return {
      'data': {'uid': '123'},
    };
  }

  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async {
    spaceRequests++;
    return {
      'data':
          spaceData ??
          {
            'userInfo': {
              'username': '布局预览用户',
              'level': '3',
              'experience': '100',
              'next_level_experience': '1000',
              'feed_num': '12',
              'followNum': '3',
              'fansNum': '4',
            },
            'feed_num': '',
          },
    };
  }

  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async => {
    'data': {
      'user_info': {'feed_num': ''},
    },
  };
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    reads.add(path);
    final List<Map<String, dynamic>> items;
    if (path.contains('myFollowTopicList')) {
      items = List.generate(
        4,
        (i) => {
          'id': '${100 + i}',
          'entityType': 'topic',
          'title': '话题${i + 1}',
          'feedNumTxt': '12',
        },
      );
    } else if (path.contains('recentHistoryList')) {
      items = List.generate(
        4,
        (i) => {
          'id': '${200 + i}',
          'entityType': 'product',
          'title': '产品${i + 1}',
          'typeName': '数码',
        },
      );
    } else if (path.contains('hitHistoryList')) {
      items = List.generate(
        5,
        (i) => {
          'id': '${500 + i}',
          'entityType': 'history',
          'url': '/u/${701 + i}',
          'title': '访问用户${i + 1}',
          'typeName': '用户',
          'subTitle': '最近浏览的内容',
          'dateline': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 300}',
        },
      );
    } else if (path.contains('/collection/')) {
      items = List.generate(
        3,
        (i) => {
          'id': '${300 + i}',
          'entityType': 'collection',
          'title': '收藏单${i + 1}',
          'follownum': '1',
          'feednum': '8',
        },
      );
    } else {
      items = [];
    }
    return ApiPage(
      items: items,
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  Future<ApiPage> getUserPage(
    String route,
    String uid,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    reads.add(route);
    return const ApiPage(
      items: [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AccountLayoutApi> mountAccount(
  WidgetTester tester, {
  bool anonymous = false,
  double textScale = 1,
  Map<String, dynamic>? spaceData,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final account = (await tester.runAsync(() async {
    final account = LocalAccount(await SharedPreferences.getInstance());
    if (anonymous) {
      await account.setActive(true);
      await account.setPublicIdentity(
        uid: '456',
        username: '公开用户',
        userAvatar: '',
      );
    }
    return account;
  }))!;
  final api = AccountLayoutApi(account)..spaceData = spaceData;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: AccountPage(api: api)),
      ),
    ),
  );
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  return api;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('应用管理入口打开本机应用列表而不要求开发者主页', (tester) async {
    const channel = MethodChannel('com.green.note/app_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getInstalledApps') return const [];
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await mountAccount(tester, anonymous: true);
    await tester.tap(find.text('应用管理'));
    await tester.pumpAndSettle();

    expect(find.byType(AppManagementPage), findsOneWidget);
    expect(find.text('开发者应用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final count in [330, 0]) {
    testWidgets('bound UID reads public feed field including $count', (
      tester,
    ) async {
      await mountAccount(
        tester,
        anonymous: true,
        spaceData: {
          'username': '公开用户',
          'feed': count,
          'follow': 33,
          'fans': 249,
        },
      );
      expect(find.text('$count'), findsOneWidget);
      expect(find.text('33'), findsOneWidget);
      expect(find.text('249'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pulling down on account page refreshes cloud profile and cards',
    (tester) async {
      final api = await mountAccount(tester);
      final initialReads = api.reads.length;
      final initialLoginChecks = api.loginChecks;
      final initialSpaceRequests = api.spaceRequests;

      await tester.drag(
        find.byKey(const ValueKey('account-refreshable-list')),
        const Offset(0, 420),
      );
      await tester.pumpAndSettle();

      expect(api.loginChecks, initialLoginChecks + 1);
      expect(api.spaceRequests, greaterThan(initialSpaceRequests));
      expect(api.reads.length, greaterThan(initialReads));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account cards match the reference grouping and four-column previews',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountAccount(tester);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('酷回收订单'), findsOneWidget);
      expect(find.text('卡片管理'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('话题1')).dy,
        tester.getTopLeft(find.text('话题4')).dy,
      );
      for (final title in ['我关注的话题', '我的常去', '浏览历史', '我的收藏单', '我的问答']) {
        await tester.scrollUntilVisible(
          find.text(title),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        final material = tester.widget<Material>(
          find
              .ancestor(of: find.text(title), matching: find.byType(Material))
              .first,
        );
        expect(material.color, const Color(0xFF1E1E1E));
        expect(material.borderRadius, BorderRadius.circular(14));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'bound anonymous identity only reads public collections and questions',
    (tester) async {
      final api = await mountAccount(tester, anonymous: true);
      expect(find.byIcon(Icons.person_search_outlined), findsNothing);
      expect(
        api.reads,
        containsAll(['/v6/collection/list', '/v6/user/questionAndAnswerList']),
      );
      expect(api.reads, isNot(contains('/v6/topic/myFollowTopicList')));
      expect(api.reads, isNot(contains('/v6/member/recentHistoryList')));
      expect(api.reads, isNot(contains('/v6/user/hitHistoryList')));
      expect(api.reads, isNot(contains('/v6/collection/myCollectionList')));
      expect(find.text('12'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('我的收藏单'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('我的收藏单'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history opens its target user rather than the history record ID',
    (tester) async {
      await mountAccount(tester);
      await tester.scrollUntilVisible(
        find.text('访问用户1'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('访问用户1'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<UserSpacePage>(find.byType(UserSpacePage)).uid,
        '701',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large text keeps cards readable and card visibility saves locally',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountAccount(tester, textScale: 1.6);
      await tester.scrollUntilVisible(
        find.text('卡片管理'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('卡片管理'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, '浏览历史');
      await tester.tap(toggle);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      final saved = await tester.runAsync(
        () async => (await SharedPreferences.getInstance()).getStringList(
          'greennote.account.hiddenCards',
        ),
      );
      expect(saved, contains('浏览历史'));
      expect(tester.takeException(), isNull);
    },
  );
}
