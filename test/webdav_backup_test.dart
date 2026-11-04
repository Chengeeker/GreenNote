import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/webdav_service.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/features/settings/webdav_backup_page.dart';

import 'feed_channel_extended_test.dart' show MockChannelApi;

const cookie = 'uid=10; token=synthetic-login-token';
const password = 'synthetic-dav-password';

class _Dav extends WebDavService {
  Map<String, dynamic>? uploaded, downloaded;
  @override
  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directory,
    required Map<String, dynamic> data,
  }) async {
    uploaded = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> downloadLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directory,
  }) async => downloaded;
}

class _Api extends MockChannelApi {
  _Api(this._localAccount, this.secrets);
  final LocalAccount _localAccount;
  @override
  LocalAccount get localAccount => _localAccount;
  final Map<String, String> secrets;
  bool reject = false;
  String? validated;
  @override
  Future<void> validateAndSaveCookie(String value) async {
    if (reject) throw const CoolapkApiException('synthetic expired session');
    validated = value;
    secrets['coolapk_cookie'] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> secrets;
  late List<String> reads;
  setUp(() {
    secrets = {'coolapk_cookie': cookie, 'greennote.webdav.password': password};
    reads = [];
    SharedPreferences.setMockInitialValues({
      'greennote.webdav.url': 'https://dav.example.com/',
      'greennote.webdav.username': 'test-user',
      'greennote.webdav.directory': 'GreenNote',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = call.arguments['key'] as String;
            switch (call.method) {
              case 'read':
                reads.add(key);
                return secrets[key];
              case 'write':
                secrets[key] = call.arguments['value'] as String;
                return null;
              case 'delete':
                secrets.remove(key);
                return null;
            }
            throw StateError('Unexpected secure storage operation');
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  Future<Map<String, dynamic>> export(
    AppSettingsNotifier settings, {
    bool full = false,
  }) => settings.exportBackup(
    webDavUrl: 'https://restored.example.com/',
    webDavUsername: 'restored-user',
    webDavDirectory: 'Archive',
    includeCredentials: full,
  );

  test(
    'safe backup excludes secrets without reading them and restores font scale',
    () async {
      final settings = AppSettingsNotifier();
      addTearDown(settings.dispose);
      await settings.setFontScale(1.2);
      final backup = await export(settings);
      expect(backup['version'], 2);
      expect(backup.containsKey('credentials'), isFalse);
      expect(reads, isEmpty);
      expect(jsonEncode(backup), isNot(contains('synthetic')));
      await settings.setFontScale(0.8);
      final restored = await settings.restoreBackup({
        ...backup,
        'credentials': {'cookie': cookie, 'webDavPassword': password},
      });
      expect(settings.state.fontScale, 1.2);
      expect(restored.containsKey('cookie'), isFalse);
      expect(secrets['coolapk_cookie'], cookie);
    },
  );

  test('full backup includes only explicit credential fields and validates before mutation', () async {
    final settings = AppSettingsNotifier();
    addTearDown(settings.dispose);
    final backup = await export(settings, full: true);
    expect(backup['version'], 3);
    expect(backup['credentials'], {
      'cookie': cookie,
      'webDavPassword': password,
    });
    expect(reads, ['coolapk_cookie', 'greennote.webdav.password']);
    final previous = await settings.loadWebDavConfig();
    for (final invalid in [
      null,
      {'cookie': 1, 'webDavPassword': password},
      {'cookie': 'bad\nCookie', 'webDavPassword': password},
      {'cookie': cookie},
    ]) {
      await expectLater(
        settings.restoreBackup({...backup, 'credentials': invalid}),
        throwsFormatException,
      );
      expect(await settings.loadWebDavConfig(), previous);
    }
    final restored = await settings.restoreBackup(backup);
    expect(restored['cookie'], cookie);
    expect(restored['webDavPassword'], password);
  });

  Future<void> mount(WidgetTester tester, _Dav dav, _Api api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webDavServiceProvider.overrideWithValue(dav),
          coolapkApiProvider.overrideWith((ref) async => api),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const WebDavBackupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'backup page defaults to safe and only exports secrets after selecting full',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _Api(
        LocalAccount(await SharedPreferences.getInstance()),
        secrets,
      );
      final dav = _Dav();
      await mount(tester, dav, api);
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isFalse,
      );
      await tapText(tester, '立即备份到云端');
      expect(dav.uploaded!['version'], 2);
      expect(jsonEncode(dav.uploaded), isNot(contains('synthetic')));
      await tapText(tester, '全量备份');
      await tapText(tester, '立即备份到云端');
      expect(dav.uploaded!['credentials'], {
        'cookie': cookie,
        'webDavPassword': password,
      });
      expect(find.textContaining('全量备份已上传'), findsOneWidget);
    },
  );

  for (final reject in [false, true]) {
    testWidgets(
      'full restore applies DAV password and validates login without replacing a rejected session reject=$reject',
      (tester) async {
        final settings = AppSettingsNotifier();
        final backup = await export(settings, full: true);
        settings.dispose();
        secrets['coolapk_cookie'] = 'current-cookie';
        secrets['greennote.webdav.password'] = 'current-password';
        final api = _Api(
          LocalAccount(await SharedPreferences.getInstance()),
          secrets,
        )..reject = reject;
        final dav = _Dav()..downloaded = backup;
        await mount(tester, dav, api);
        await tapText(tester, '从云端恢复备份');
        await tapText(tester, '恢复设置');
        expect(secrets['greennote.webdav.password'], password);
        expect(secrets['coolapk_cookie'], reject ? 'current-cookie' : cookie);
        expect(
          find.textContaining(reject ? '当前登录态未替换' : '酷安登录凭据已验证并恢复'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'safe restore to a different server clears the previous DAV password',
    (tester) async {
      final settings = AppSettingsNotifier();
      final backup = await export(settings);
      settings.dispose();
      final api = _Api(
        LocalAccount(await SharedPreferences.getInstance()),
        secrets,
      );
      await mount(tester, _Dav()..downloaded = backup, api);
      await tapText(tester, '从云端恢复备份');
      await tapText(tester, '恢复设置');
      expect(secrets.containsKey('greennote.webdav.password'), isFalse);
      expect(secrets['coolapk_cookie'], cookie);
      expect(api.validated, isNull);
      expect(find.textContaining('请重新输入 WebDAV 密码'), findsOneWidget);
    },
  );
}
