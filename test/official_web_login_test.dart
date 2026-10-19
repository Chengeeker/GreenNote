import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Tests implement the platform interface already installed by webview_flutter.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/account/official_login_page.dart';

class _Api extends Fake implements CoolapkApi {
  final saved = <String>[];
  bool reject = false;
  @override
  Future<void> validateAndSaveCookie(String cookie) async {
    if (reject) throw const CoolapkApiException('需要验证码');
    saved.add(cookie);
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late NavigationRequestCallback navigate;
  late PageEventCallback finished;
  late ProgressCallback progress;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    progress = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  late _Delegate delegate;
  bool clearedDocument = false;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _Delegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    delegate.progress(100);
  }

  @override
  Future<void> reload() async {
    delegate.progress(100);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    final decision = await delegate.navigate(
      const NavigationRequest(url: 'about:blank', isMainFrame: true),
    );
    if (decision != NavigationDecision.navigate) {
      throw StateError('Cleanup document blocked');
    }
    clearedDocument = true;
  }
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('官方登录网页');
}

class _Platform extends WebViewPlatform {
  late _Controller controller;
  int created = 0;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    created++;
    return controller = _Controller(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late _Api api;
  late List<String> calls;
  late List<bool> clearedDocuments;
  late String cookie;
  Completer<void>? initializing;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
    api = _Api();
    calls = [];
    clearedDocuments = [];
    cookie = '';
    initializing = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.green.note/login_cookies'),
          (call) async {
            calls.add(call.method);
            if (call.method == 'read') return cookie;
            if (calls.length == 1 && initializing != null) {
              await initializing!.future;
            }
            if (calls.length > 1 && platform.created > 0) {
              clearedDocuments.add(platform.controller.clearedDocument);
            }
            return null;
          },
        );
  });

  Future<void> open(WidgetTester tester, {bool wait = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => OfficialWebLoginPage(api: api),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    if (!wait) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    await tester.pumpAndSettle();
    expect(calls, ['clear']);
    expect(find.text('官方登录网页'), findsOneWidget);
  }

  testWidgets('only HTTPS official top-level pages can navigate', (
    tester,
  ) async {
    await open(tester);
    final delegate = platform.controller.delegate;
    expect(
      await delegate.navigate(
        const NavigationRequest(
          url: 'https://account.coolapk.com/auth/login',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.navigate,
    );
    for (final url in [
      'https://account.coolapk.com.evil.org/',
      'http://www.coolapk.com/',
      'https://example.org/',
      'https://user@www.coolapk.com/',
    ]) {
      expect(
        await delegate.navigate(NavigationRequest(url: url, isMainFrame: true)),
        NavigationDecision.prevent,
      );
    }
    expect(
      await delegate.navigate(
        const NavigationRequest(
          url: 'https://cstaticdun.126.net/',
          isMainFrame: false,
        ),
      ),
      NavigationDecision.navigate,
    );
    await tester.pump();
    expect(api.saved, isEmpty);
  });

  testWidgets(
    'missing credentials never save, explicit retry validates then clears cookies',
    (tester) async {
      await open(tester);
      platform.controller.delegate.finished('https://www.coolapk.com/');
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      cookie = 'uid=123; token=new-token; SESSID=session';
      api.reject = true;
      await tester.tap(find.text('已完成网页登录，校验并保存'));
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      expect(find.textContaining('账号校验未通过'), findsOneWidget);
      api.reject = false;
      await tester.tap(find.text('已完成网页登录，校验并保存'));
      await tester.pumpAndSettle();
      expect(api.saved, [cookie]);
      expect(calls.last, 'clear');
      expect(find.text('已完成网页登录，校验并保存'), findsNothing);
    },
  );

  testWidgets(
    'back cancels without changing account and clears browser session',
    (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      expect(calls, ['clear', 'clear']);
      expect(clearedDocuments, [true]);
      expect(find.textContaining('清理失败'), findsNothing);
      expect(find.text('官方登录网页'), findsNothing);
    },
  );

  testWidgets(
    'cancelling initialization cannot reopen the browser or save an account',
    (tester) async {
      initializing = Completer<void>();
      await open(tester, wait: false);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      initializing!.complete();
      await tester.pumpAndSettle();
      expect(platform.created, 0);
      expect(api.saved, isEmpty);
      expect(calls, ['clear', 'clear']);
      expect(find.text('酷安官方网页登录'), findsNothing);
    },
  );

  testWidgets(
    'untrusted and non-landing pages cannot trigger credential reads',
    (tester) async {
      await open(tester);
      cookie = 'uid=123; token=new-token';
      platform.controller.delegate.finished('https://example.org/');
      platform.controller.delegate.finished('https://www.coolapk.com/feed/123');
      await tester.pumpAndSettle();
      expect(calls, ['clear']);
      expect(api.saved, isEmpty);
      platform.controller.delegate.finished('https://www.coolapk.com/');
      await tester.pumpAndSettle();
      expect(api.saved, [cookie]);
      expect(calls, ['clear', 'read', 'clear']);
    },
  );
}
