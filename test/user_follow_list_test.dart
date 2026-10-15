import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shell/main_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            if (call.method == 'read') return null;
            return null;
          },
        );
  });

  test('follow list parser flattens user cards and keeps each UID once', () {
    final users = CoolapkApi.parseUserFollowList({
      'data': [
        {
          'entityType': 'card',
          'uid': 'card-id',
          'title': '关注列表',
          'entities': [
            {'entityType': 'user', 'id': '101', 'username': '甲'},
            {'entityType': 'contacts', 'uid': 202, 'userName': '乙'},
            {'uid': '101', 'username': '重复项'},
            {
              'user_info': {'uid': '303', 'username': '丙'},
            },
          ],
        },
        {
          'uid': 'target-account',
          'username': '主页本人',
          'entities': [
            {'entityType': 'user', 'id': '404', 'username': '丁'},
          ],
        },
      ],
    });

    expect(users.map((user) => user['uid']), ['101', '202', '303', '404']);
    expect(users.every((user) => user['entityType'] == 'user'), isTrue);
  });

  test('relationship rows use followed UID and profile instead of owner', () {
    final users = CoolapkApi.parseUserFollowList({
      'data': [
        {
          'uid': 10002,
          'username': '主页本人',
          'fuid': 12202,
          'fusername': '关注对象',
          'entityType': 'userFollow',
          'fUserInfo': {
            'uid': 12202,
            'username': '关注对象资料',
            'userAvatar': 'https://example.com/avatar.png',
          },
        },
        {
          'uid': 10002,
          'fuid': 12345,
          'fusername': '无嵌套资料',
          'fUserAvatar': 'https://example.com/fallback.png',
        },
      ],
    });
    expect(users.map((user) => user['uid']), ['12202', '12345']);
    expect(users.first['username'], '关注对象资料');
    expect(users.last['userAvatar'], 'https://example.com/fallback.png');
    expect(users.map((user) => user['id']), ['12202', '12345']);
  });

  testWidgets(
    'anonymous account keeps shortcuts and official cards without duplicate follows',
    (tester) async {
      final api = (await tester.runAsync(CoolapkApi.create))!;
      await tester.runAsync(() async {
        await api.localAccount.setActive(true);
        await api.localAccount.toggle('follows', '101', {
          'uid': '101',
          'username': '关注用户',
          'userAvatar': '',
        });
        await api.localAccount.toggle('favorites', '201', {
          'id': '201',
          'message': '收藏动态',
        });
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountPage(api: api)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('动态'), findsOneWidget);
      expect(find.text('关注'), findsOneWidget);
      expect(find.text('粉丝'), findsOneWidget);
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('我的关注'), findsNothing);
      expect(find.text('本地收藏'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('我的收藏单'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('我的收藏单'), findsOneWidget);
    },
  );
}
