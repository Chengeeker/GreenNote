import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Exercise the installed WebView platform without contacting the verification SDK.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:greennote/core/network/coolapk_captcha.dart';
import 'package:greennote/features/shared/captcha_page.dart';

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late NavigationRequestCallback navigate;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  late JavaScriptChannelParams channel;
  late _Delegate delegate;
  String html = '';
  String? base;
  bool fail = false;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _Delegate;
  }

  @override
  Future<void> loadHtmlString(String value, {String? baseUrl}) async {
    if (fail) throw StateError('synthetic WebView failure');
    html = value;
    base = baseUrl;
  }
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('验证组件');
}

class _Platform extends WebViewPlatform {
  late _Controller controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _Widget(params);
}

void main() {
  late _Platform platform;
  String? result;
  int completions = 0;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
    result = null;
    completions = 0;
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const CoolapkCaptchaPage(
                      challenge: CoolapkCaptchaChallenge(
                        '5fc4c10eccd64d178982bc560da43a91',
                        '',
                      ),
                    ),
                  ),
                );
                completions++;
              },
              child: const Text('验证榜单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('验证榜单'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'verification returns only a valid SDK result once and blocks top-level navigation',
    (tester) async {
      await open(tester);
      expect(
        platform.controller.html,
        contains('https://cstaticdun.126.net/load.min.js'),
      );
      expect(platform.controller.html, isNot(contains('SESSID')));
      expect(platform.controller.base, 'https://captcha.greennote.invalid/');
      expect(
        await platform.controller.delegate.navigate(
          const NavigationRequest(
            url: 'https://example.com/',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      expect(
        await platform.controller.delegate.navigate(
          const NavigationRequest(
            url: 'https://c.dun.163.com/frame',
            isMainFrame: false,
          ),
        ),
        NavigationDecision.navigate,
      );
      platform.controller.channel.onMessageReceived(
        const JavaScriptMessage(message: 'bad\nproof'),
      );
      await tester.pump();
      expect(find.text('人机验证'), findsOneWidget);
      platform.controller.channel.onMessageReceived(
        const JavaScriptMessage(message: 'synthetic-validate'),
      );
      platform.controller.channel.onMessageReceived(
        const JavaScriptMessage(message: 'duplicate'),
      );
      await tester.pumpAndSettle();
      expect(result, 'synthetic-validate');
      expect(completions, 1);
      platform.controller.channel.onMessageReceived(
        const JavaScriptMessage(message: 'late'),
      );
      await tester.pump();
      expect(completions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back cancels verification without producing a proof', (
    tester,
  ) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(completions, 1);
    expect(find.text('验证榜单'), findsOneWidget);
  });

  testWidgets('a failed reload can be retried within the verification page', (
    tester,
  ) async {
    await open(tester);
    platform.controller.fail = true;
    await tester.tap(find.byTooltip('重新加载验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证页面加载失败，请重试'), findsOneWidget);
    platform.controller.fail = false;
    await tester.tap(find.byTooltip('重新加载验证'));
    await tester.pumpAndSettle();
    expect(find.text('验证组件'), findsOneWidget);
    expect(result, isNull);
  });
}
