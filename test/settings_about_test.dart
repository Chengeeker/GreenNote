import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/design_system/components/review_preference_tile.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/features/settings/app_settings_page.dart';

class _Api implements CoolapkApi {
  @override
  bool get hasCookie => false;
  @override
  bool get hasAccount => false;
  @override
  bool get isAnonymous => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester, {
  bool dark = false,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: AppSettingsPage(
        api: _Api(),
        onOpenCookieManager: () async {},
        onAccountChanged: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const uiChannel = MethodChannel('com.green.note/ui');
  const linkChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final calls = <MethodCall>[];
  var versionFails = false;
  var linkSucceeds = true;
  setUp(() {
    calls.clear();
    versionFails = false;
    linkSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiChannel, (call) async {
          calls.add(call);
          if (versionFails) throw PlatformException(code: 'unavailable');
          return '1.9.25';
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(linkChannel, (call) async {
          calls.add(call);
          return linkSucceeds;
        });
  });
  tearDown(() {
    for (final channel in [uiChannel, linkChannel]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      'settings keep one compact status and open app about dark=$dark',
      (tester) async {
        await _mount(tester, dark: dark);
        expect(calls, isEmpty);
        final loginTile = tester.widget<ReviewPreferenceTile>(
          find.widgetWithText(ReviewPreferenceTile, '登录方式与账号管理'),
        );
        expect(loginTile.subtitle, '当前登录方式：游客（未登录）');
        final title = tester.widget<Text>(find.text('登录方式与账号管理'));
        final status = tester.widget<Text>(find.text(loginTile.subtitle!));
        expect(title.style!.fontSize, 15);
        expect(status.style!.fontSize, 12.5);
        for (final tile in tester.widgetList<ReviewPreferenceTile>(
          find.byType(ReviewPreferenceTile),
        )) {
          if (tile.title != loginTile.title) expect(tile.subtitle, isNull);
        }
        final about = find.text('关于 GreenNote');
        await tester.scrollUntilVisible(about, 250);
        await tester.ensureVisible(about);
        await tester.pumpAndSettle();
        expect(find.text('首页滑动诊断'), findsNothing);
        await tester.tap(about);
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call.method == 'getAppVersion'),
          hasLength(1),
        );
        expect(find.text('GreenNote'), findsOneWidget);
        expect(find.text('v1.9.25'), findsOneWidget);
        expect(find.text('github.com/Chengeeker/GreenNote'), findsOneWidget);
        expect(find.textContaining('复用自'), findsNothing);
        expect(find.byType(Divider), findsNothing);
        await tester.tap(find.text('GitHub 开源地址'));
        await tester.pumpAndSettle();
        final launch = calls.singleWhere((call) => call.method == 'launch');
        expect(
          launch.arguments['url'],
          'https://github.com/Chengeeker/GreenNote',
        );
        await tester.tap(find.text('我知道了'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'about stays usable on a short screen when metadata or link fails',
    (tester) async {
      versionFails = true;
      linkSucceeds = false;
      await _mount(tester, height: 560);
      final about = find.text('关于 GreenNote');
      await tester.scrollUntilVisible(about, 250);
      await tester.ensureVisible(about);
      await tester.pumpAndSettle();
      await tester.tap(about);
      await tester.pumpAndSettle();
      expect(find.text('版本未知'), findsOneWidget);
      final repo = find.text('GitHub 开源地址');
      await tester.ensureVisible(repo);
      await tester.tap(repo);
      await tester.pumpAndSettle();
      expect(find.text('无法打开仓库地址'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
