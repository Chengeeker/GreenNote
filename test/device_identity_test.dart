import 'package:greennote/features/account/official_login_page.dart';
import 'package:greennote/core/network/coolapk_login.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Exercise failures through the interface already installed by shared_preferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/official_device_identity.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/features/settings/app_settings_page.dart';
import 'package:greennote/features/settings/device_identity_page.dart';
import 'package:greennote/features/settings/device_identity_guide_page.dart';

const _id = 'synthetic-shuzlm_123456789';
const _profile = {
  'manufacturer': 'Example',
  'brand': 'example',
  'model': 'Test Phone',
  'display': 'Build.123',
};
const _copy =
    '设备ID: unused-device\r\nShuzlmID: $_id\r\nAndroidID: unused-android\r\nUUID: unused-uuid';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(super.values) : super.withData();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
  @override
  Future<bool> remove(String key) async => false;
}

class _Api extends Fake implements CoolapkApi {
  bool official = false;
  bool fail = false;
  int imports = 0;
  String? submitted;
  @override
  bool get hasOfficialDeviceIdentity => official;
  @override
  Future<void> importOfficialDeviceIdentity(String text) async {
    imports++;
    if (fail) throw StateError('Synthetic save failure');
    submitted = text;
    official = true;
  }

  @override
  Future<void> restoreOriginalDeviceIdentity() async {
    official = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var profileCalls = 0;
  var clipboardCalls = 0;
  var secureWrites = 0;
  var openOfficialCalls = 0;
  setUp(() {
    profileCalls = 0;
    clipboardCalls = 0;
    secureWrites = 0;
    openOfficialCalls = 0;
    SharedPreferences.setMockInitialValues({
      'guest_device_code': 'original-device-code',
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return 'existing-test-cookie';
        secureWrites++;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.green.note/ui'),
      (call) async {
        if (call.method == 'getDeviceProfile') {
          profileCalls++;
          return _profile;
        }
        if (call.method == 'openOfficialIdSettings') {
          openOfficialCalls++;
          throw PlatformException(code: 'official_not_installed');
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardCalls++;
        return {'text': _copy};
      }
      return null;
    });
  });

  test(
    'parser extracts only the unique ShuzlmID from full official copies',
    () {
      expect(OfficialDeviceIdentity.parse(_copy), _id);
      expect(OfficialDeviceIdentity.parse('\uFEFF  shuzlmid： $_id\n'), _id);
      for (final text in [
        'OAID: $_id',
        'AndroidID: $_id\nUUID: $_id',
        '$_copy\nShuzlmID: $_id',
        'ShuzlmID:\nAndroidID: $_id',
        'ShuzlmID: null',
        'ShuzlmID: undefined',
        'ShuzlmID: too-short;',
        'ShuzlmID: injected;header',
        'ShuzlmID: abcdefgh\u0000',
        'x' * 32769,
      ]) {
        expect(() => OfficialDeviceIdentity.parse(text), throwsFormatException);
      }
    },
  );

  test('encoding preserves all remaining fields and matches reversed unpadded base64', () {
    final fields = [
      _id,
      ' original-mac',
      ' old-field',
      ' ',
      ' OEM',
      ' brand',
      ' model',
      ' build',
      ' null',
    ];
    final previous = base64Encode(utf8.encode(fields.join(';')))
        .split('')
        .reversed
        .join()
        .replaceAll('=', '');
    final next = OfficialDeviceIdentity.encode(
      'replacement-id_123',
      previous: previous,
    );
    expect(OfficialDeviceIdentity.fields(next), [
      'replacement-id_123',
      ...fields.skip(1),
    ]);
    expect(next, isNot(contains('=')));
    expect(OfficialDeviceIdentity.fields('malformed'), isNull);
    expect(
      () => OfficialDeviceIdentity.encode(
        _id,
        previous: 'uuid',
        profile: {..._profile, 'brand': 'bad;field'},
      ),
      throwsFormatException,
    );
  });

  test('import applies to headers and signatures, survives restart, restores exact original and keeps accounts', () async {
    final api = await CoolapkApi.create();
    addTearDown(api.close);
    final scope = api.notificationSessionKey;
    final oldHeader = api.imageHeadersFor();
    final prefs = await SharedPreferences.getInstance();
    await api.localAccount.profile('Local user', '');
    await api.localAccount.setActive(true);
    api.guestSessionCookie = 'SESSID=old-guest';
    await api.importOfficialDeviceIdentity(_copy);
    expect(api.hasOfficialDeviceIdentity, isTrue);
    expect(api.isAnonymous, isTrue);
    expect(api.localAccount.name, 'Local user');
    expect(api.guestSessionCookie, isNull);
    final headers = api.imageHeadersFor();
    final code = headers['X-App-Device']!;
    expect(OfficialDeviceIdentity.fields(code), [
      _id,
      ' ',
      ' ',
      ' ',
      ' Example',
      ' example',
      ' Test Phone',
      ' Build.123',
      ' null',
    ]);
    expect(headers['X-App-Token'], isNot(oldHeader['X-App-Token']));
    expect(prefs.getString('guest_device_code'), 'original-device-code');
    expect(prefs.getString(OfficialDeviceIdentity.storageKey), code);
    expect(code, isNot(contains('unused-android')));
    expect(profileCalls, 1);
    await api.importOfficialDeviceIdentity('ShuzlmID: replacement-id_123');
    expect(profileCalls, 1);
    final recreated = await CoolapkApi.create();
    addTearDown(recreated.close);
    expect(recreated.hasOfficialDeviceIdentity, isTrue);
    expect(
      recreated.imageHeadersFor()['X-App-Device'],
      api.imageHeadersFor()['X-App-Device'],
    );
    await api.restoreOriginalDeviceIdentity();
    expect(api.hasOfficialDeviceIdentity, isFalse);
    expect(api.imageHeadersFor()['X-App-Device'], 'original-device-code');
    expect(api.isAnonymous, isTrue);
    await api.localAccount.setActive(false, enableCookie: true);
    expect(api.notificationSessionKey, scope);
    expect(secureWrites, 0);
    expect(clipboardCalls, 0);
  });

  test('invalid import and damaged stored data preserve the original device and login', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      OfficialDeviceIdentity.storageKey,
      'broken-persisted-code',
    );
    final api = await CoolapkApi.create();
    addTearDown(api.close);
    expect(api.hasOfficialDeviceIdentity, isFalse);
    final original = api.imageHeadersFor()['X-App-Device'];
    await expectLater(
      api.importOfficialDeviceIdentity('AndroidID: unrelated'),
      throwsFormatException,
    );
    expect(api.imageHeadersFor()['X-App-Device'], original);
    expect(api.hasCookie, isTrue);
    expect(profileCalls, 0);
    expect(secureWrites, 0);
  });

  test('failed persistence cannot change live headers or replace the saved identity', () async {
    final api = await CoolapkApi.create();
    addTearDown(api.close);
    final original = api.imageHeadersFor()['X-App-Device'];
    final platform = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _FailingStore({
      'flutter.guest_device_code': 'original-device-code',
    });
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
    await expectLater(
      api.importOfficialDeviceIdentity(_copy),
      throwsStateError,
    );
    expect(api.imageHeadersFor()['X-App-Device'], original);
    expect(api.hasOfficialDeviceIdentity, isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(OfficialDeviceIdentity.storageKey), isNull);
    expect(secureWrites, 0);
  });

  test('WebDAV backup excludes imported identifiers and raw official copied fields', () async {
    final api = await CoolapkApi.create();
    addTearDown(api.close);
    await api.importOfficialDeviceIdentity(_copy);
    final settings = AppSettingsNotifier();
    addTearDown(settings.dispose);
    final backup = await settings.exportBackup(
      webDavUrl: 'https://example.org',
      webDavUsername: 'test',
      webDavDirectory: 'GreenNote',
    );
    final json = jsonEncode(backup);
    expect(json, isNot(contains(_id)));
    expect(json, isNot(contains(OfficialDeviceIdentity.storageKey)));
    expect(json, isNot(contains(api.imageHeadersFor()['X-App-Device']!)));
    expect(json, isNot(contains('unused-android')));
  });

  testWidgets(
    'explicit paste hides raw data and save/restore preserve the UI flow on narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _Api();
      await tester.pumpWidget(MaterialApp(home: DeviceIdentityPage(api: api)));
      await tester.pumpAndSettle();
      expect(clipboardCalls, 0);
      await tester.scrollUntilVisible(
        find.text('粘贴并识别'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('粘贴并识别'));
      await tester.pumpAndSettle();
      expect(clipboardCalls, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.textContaining(_id), findsNothing);
      await tester.scrollUntilVisible(
        find.text('保存并应用'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      api.fail = true;
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(api.official, isFalse);
      expect(find.textContaining('保存失败'), findsOneWidget);
      api.fail = false;
      await tester.scrollUntilVisible(
        find.text('保存并应用'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存并应用'));
      await tester.pumpAndSettle();
      expect(api.submitted, 'ShuzlmID: $_id');
      await tester.scrollUntilVisible(
        find.text('恢复原设备码'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复原设备码'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.official, isTrue);
      await tester.tap(find.text('恢复原设备码'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(api.official, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'official app launch failure has a clear message and invalid text never saves',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(MaterialApp(home: DeviceIdentityPage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开酷安 OAID 界面'));
      await tester.pumpAndSettle();
      expect(openOfficialCalls, 1);
      expect(find.textContaining('请先安装官方酷安'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'OAID: wrong-field');
      await tester.ensureVisible(find.text('识别输入内容'));
      await tester.tap(find.text('识别输入内容'));
      await tester.pumpAndSettle();
      expect(api.imports, 0);
      expect(clipboardCalls, 0);
      expect(find.textContaining('未找到唯一'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'offline guide opens locally, supports large text and preserves import draft ($brightness)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = _Api();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: DeviceIdentityPage(api: api),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(TextField),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(find.byType(TextField), '未识别的导入草稿');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('查看操作教程'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看操作教程'));
        await tester.pumpAndSettle();
        expect(find.byType(DeviceIdentityGuidePage), findsOneWidget);
        for (final heading in [
          '1. 准备官方酷安',
          '2. 在同一页面复制 5 次',
          '3. 确认包含 ShuzlmID',
          '4. 返回 GreenNote 识别并保存',
          '常见问题',
          '标识与隐私',
        ]) {
          expect(find.text(heading), findsOneWidget);
        }
        expect(find.text('操作说明已保存在应用内，可离线阅读。'), findsOneWidget);
        expect(clipboardCalls, 0);
        expect(openOfficialCalls, 0);
        expect(api.imports, 0);
        await tester.ensureVisible(find.text('返回导入页'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('返回导入页'));
        await tester.pumpAndSettle();
        expect(find.byType(DeviceIdentityGuidePage), findsNothing);
        await tester.scrollUntilVisible(
          find.byType(TextField),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '未识别的导入草稿',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'device identity is below account login without requiring a login',
    (tester) async {
      final api = (await tester.runAsync(CoolapkApi.create))!;
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AppSettingsPage(
            api: api,
            onOpenCookieManager: () async {},
            onAccountChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('导入官方设备标识'), findsNothing);
      expect(find.text('多匿名账户管理'), findsNothing);
      expect(find.text('酷安个人资料'), findsNothing);
      expect(find.textContaining('当前登录方式：'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialLoginPage(api: api, login: _PreparedLogin()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('导入官方设备标识'));
      await tester.tap(find.text('导入官方设备标识'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceIdentityPage), findsOneWidget);
      expect(clipboardCalls, 0);
    },
  );
}

class _PreparedLogin extends CoolapkLogin {
  @override
  Future<void> prepare() async {}
}
