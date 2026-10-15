import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/features/account/local_account_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            if (call.method == 'read') return 'saved-test-cookie';
            return null;
          },
        );
  });

  Future<LocalAccount> account() async =>
      LocalAccount(await SharedPreferences.getInstance());

  test(
    'profile, follow, favorite survive mode switches and recreation',
    () async {
      final local = await account();
      await local.profile('本地酷友', '');
      await local.setActive(true);
      await Future.wait([
        local.toggle('follows', '12', {
          'uid': '12',
          'username': '博主',
          'userAvatar': '',
        }),
        local.toggle('favorites', '34', {
          'id': '34',
          'message': '收藏内容',
          'pic': 'https://example.com/photo.png',
        }),
      ]);
      await local.setActive(false);
      final loaded = await account();
      expect(loaded.name, '本地酷友');
      expect(loaded.active, false);
      expect(loaded.follows.keys, ['12']);
      expect(loaded.favorites['34']['message'], '收藏内容');
      await loaded.toggle('follows', '12', {});
      expect(loaded.follows, isEmpty);
    },
  );

  test(
    'public identity survives backup restore and validates its UID',
    () async {
      final local = await account();
      await local.setPublicIdentity(
        uid: '12345',
        username: '公开主页',
        userAvatar: 'https://example.com/avatar.png',
      );
      final backup = local.export();
      await local.clearPublicIdentity();
      await local.restore(backup);
      expect(local.publicIdentity, {
        'uid': '12345',
        'username': '公开主页',
        'userAvatar': 'https://example.com/avatar.png',
      });
      expect(
        () => LocalAccount.validate({
          ...backup,
          'publicIdentity': {
            'uid': 'not-a-uid',
            'username': '公开主页',
            'userAvatar': '',
          },
        }),
        throwsFormatException,
      );
      expect(
        LocalAccount.validate({...backup}..remove('publicIdentity'))['name'],
        '匿名酷友',
      );
    },
  );

  test('public UID binding keeps local follows isolated and restores them on unbind', () async {
    final local = await account();
    await local.toggle('follows', '12', {
      'uid': '12',
      'username': '本地关注',
      'userAvatar': '',
    });
    await local.setPublicIdentity(
      uid: '12345',
      username: '公开主页',
      userAvatar: '',
    );
    expect(local.publicIdentity?['uid'], '12345');
    expect(local.follows.keys, ['12']);

    await local.clearPublicIdentity();
    expect(local.publicIdentity, isNull);
    expect(local.follows.keys, ['12']);
  });

  test(
    'restore validates before changing data and preserves rollback snapshot',
    () async {
      final local = await account();
      await local.profile('原资料', '');
      final backup = local.export()..['name'] = '另一台设备';
      await local.restoreWithRollback(backup);
      expect(local.name, '另一台设备');
      await local.rollback();
      expect(local.name, '原资料');
      await local.rollback();
      expect(local.name, '另一台设备');
      await local.rollback();
      await expectLater(
        local.restoreWithRollback({...backup, 'avatar': 'invalid'}),
        throwsFormatException,
      );
      expect(local.name, '原资料');
      expect(
        () => LocalAccount.validate({
          ...backup,
          'favorites': {
            '7': {'id': '8'},
          },
        }),
        throwsFormatException,
      );
    },
  );

  test('avatar data travels with the account and oversized decoded dimensions are rejected', () async {
    final local = await account();
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=';
    await local.profile('头像测试', png);
    expect((await account()).avatar, png);
    final oversized = base64Decode(png);
    oversized[16] = 0x7f;
    await expectLater(
      local.profile('超大头像', base64Encode(oversized)),
      throwsFormatException,
    );
    expect(local.avatar, png);
  });

  test(
    'backup strips unknown credentials and preserves pictures on round trip',
    () async {
      final local = await account();
      await local.toggle('favorites', '9', {
        'id': '9',
        'message': '正文',
        'pic': 'https://example.com/a.png,https://example.com/b.png',
        'cookie': 'secret',
        'token': 'secret',
      });
      final encoded = jsonEncode(local.export());
      expect(encoded, isNot(contains('secret')));
      expect(
        CoolapkFeed.fromJson(
          Map<String, dynamic>.from(local.favorites['9'] as Map),
        ).pictures,
        hasLength(2),
      );
    },
  );

  test('v2 settings backup restores local data; v1 leaves it alone; invalid preferences do not alter local data', () async {
    final settings = AppSettingsNotifier();
    addTearDown(settings.dispose);
    final local = await account();
    await local.profile('导出资料', '');
    await local.setPublicIdentity(
      uid: '12345',
      username: '公开主页',
      userAvatar: 'https://example.com/avatar.png',
    );
    final backup = await settings.exportBackup(
      webDavUrl: '',
      webDavUsername: '',
      webDavDirectory: 'Greennote',
    );
    expect(backup['version'], 2);
    await local.profile('当前资料', '');
    final broken = jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;
    (broken['preferences'] as Map)['themeMode'] = 9;
    await expectLater(settings.restoreBackup(broken), throwsFormatException);
    expect((await account()).name, '当前资料');
    await settings.restoreBackup(
      {...backup, 'version': 1}..remove('localAccount'),
    );
    expect((await account()).name, '当前资料');
    await settings.restoreBackup(backup);
    local.reload();
    expect(local.name, '导出资料');
    expect(local.publicIdentity?['uid'], '12345');
    await local.rollback();
    expect(local.name, '当前资料');
    expect(jsonEncode(backup), isNot(contains('saved-test-cookie')));
  });

  test('anonymous API suppresses stored cookie and rejects cloud writes before networking', () async {
    final api = await CoolapkApi.create();
    await api.localAccount.setActive(true);
    expect(api.hasCookie, false);
    expect(api.hasAccount, true);
    expect(api.currentUid, isEmpty);
    expect(api.imageHeadersFor().containsKey('Cookie'), false);
    await api.followUser('12', following: false);
    await api.favoriteFeed(
      '34',
      favorited: false,
      feed: CoolapkFeed.fromJson({'id': '34', 'message': '本地图文'}),
    );
    expect(api.localAccount.follows.containsKey('12'), true);
    expect(api.localAccount.favorites.containsKey('34'), true);
    for (final operation in [
      api.likeFeed('34', liked: false),
      api.reply('34', 'test'),
      api.createFeed('test'),
      api.request('/v6/message/list'),
    ]) {
      await expectLater(operation, throwsA(isA<CoolapkApiException>()));
    }
    await expectLater(
      api.validateAndSaveCookie('bad\nvalue'),
      throwsA(isA<CoolapkApiException>()),
    );
    expect(api.isAnonymous, true);
    await api.localAccount.setActive(false);
    expect(api.hasCookie, false);
    await api.localAccount.setActive(false, enableCookie: true);
    expect(api.hasCookie, true);
  });

  testWidgets('login chooser presents both modes and opens local profile', (
    tester,
  ) async {
    final api = (await tester.runAsync(CoolapkApi.create))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLoginOptions(context, api),
              child: const Text('登录'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(find.text('Cookie 登录'), findsOneWidget);
    await tester.tap(find.text('匿名登录'));
    await tester.pumpAndSettle();
    expect(find.text('匿名账户资料'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('local-profile-public-uid')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('local-profile-name')),
      '测试账户',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('进入匿名账户'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(api.isAnonymous, true);
    expect(api.localAccount.name, '测试账户');
  });
}
