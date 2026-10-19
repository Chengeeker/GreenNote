import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/coolapk_login.dart';
import 'package:greennote/features/account/official_login_page.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(
  Object value, {
  List<String> cookies = const [],
  int status = 200,
  String? location,
}) => ResponseBody.fromString(
  value is String ? value : jsonEncode(value),
  status,
  headers: {
    'set-cookie': cookies,
    if (location != null) 'location': [location],
  },
);

CoolapkLogin _login(_Adapter adapter) =>
    CoolapkLogin(dio: Dio()..httpClientAdapter = adapter);

ResponseBody _prepare(RequestOptions options) =>
    options.path.contains('type=mobile')
    ? _body('', cookies: ['SESSID=session; Path=/; Secure; HttpOnly'])
    : _body('<html><body data-request-hash="request-hash"></body></html>');

class _Api extends Fake implements CoolapkApi {
  String? saved;
  Object? failure;
  Completer<void>? validation;
  @override
  Future<void> validateAndSaveCookie(String cookie) async {
    if (validation != null) await validation!.future;
    if (failure != null) throw failure!;
    saved = cookie;
  }
}

class _Login extends CoolapkLogin {
  CoolapkLoginException? failure;
  Completer<String>? pending;
  int calls = 0;
  @override
  Future<void> prepare() async {}
  @override
  Future<String> login(String account, String password, String captcha) async {
    calls++;
    if (failure != null) throw failure!;
    return pending == null ? 'uid=123; token=new-token' : pending!.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('account cookies reject incomplete, guest, expired and injected credentials', () {
    expect(
      CoolapkLogin.hasAccountCookie('uid=123; token=x=y; username=test'),
      isTrue,
    );
    for (final cookie in [
      'uid=0; token=x',
      'uid=10000; token=x',
      'uid=abc; token=x',
      'uid=123',
      'uid=123; token=deleted',
      'uid=123; token=expired',
      'uid=123; token=x\nHeader: value',
    ]) {
      expect(CoolapkLogin.hasAccountCookie(cookie), isFalse, reason: cookie);
    }
  });

  test(
    'login keeps SESSID, submits hash and password once and collects cookies',
    () async {
      final adapter = _Adapter((options) {
        if (options.method == 'GET') return _prepare(options);
        expect(options.headers['Cookie'], contains('SESSID=session'));
        expect(options.headers['X-Requested-With'], 'XMLHttpRequest');
        expect(options.data, containsPair('requestHash', 'request-hash'));
        expect(options.data, containsPair('password', 'test-password'));
        expect(options.followRedirects, isFalse);
        return _body(
          {'status': 1},
          cookies: [
            'uid=123; Domain=.coolapk.com; Path=/',
            'username=test; Path=/',
            'token=new-token; Path=/',
            'evil=ignored; Domain=example.org',
          ],
        );
      });
      final login = _login(adapter);
      addTearDown(login.close);
      await login.prepare();
      final cookie = await login.login('account', 'test-password', '');
      expect(cookie, contains('token=new-token'));
      expect(cookie, isNot(contains('test-password')));
      expect(cookie, isNot(contains('evil=')));
      expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );

  test(
    'GET redirects cannot send the account session outside the official origin',
    () async {
      final adapter = _Adapter(
        (_) => _body(
          '',
          cookies: ['SESSID=private'],
          status: 302,
          location: 'https://example.org/steal',
        ),
      );
      final login = _login(adapter);
      addTearDown(login.close);
      await expectLater(login.prepare(), throwsA(isA<CoolapkLoginException>()));
      expect(adapter.requests, hasLength(1));
    },
  );

  test('a redirect never replays a password POST', () async {
    final adapter = _Adapter(
      (options) => options.method == 'GET'
          ? _prepare(options)
          : _body('', status: 307, location: '/auth/loginByCoolApk'),
    );
    final login = _login(adapter);
    addTearDown(login.close);
    await login.prepare();
    await expectLater(
      login.login('account', 'test-password', ''),
      throwsA(
        isA<CoolapkLoginException>().having(
          (e) => e.webRequired,
          'requires web',
          isTrue,
        ),
      ),
    );
    expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test(
    'image challenges, human verification and incomplete success stay distinct',
    () async {
      var response = _body({'status': -1, 'message': '图形验证码错误'});
      final adapter = _Adapter(
        (options) => options.method == 'GET' ? _prepare(options) : response,
      );
      final login = _login(adapter);
      addTearDown(login.close);
      await login.prepare();
      await expectLater(
        login.login('account', 'password', ''),
        throwsA(
          isA<CoolapkLoginException>().having(
            (e) => e.captchaRequired,
            'captcha required',
            isTrue,
          ),
        ),
      );
      response = _body({
        'status': -1,
        'messageStatus': 'err_request_captcha_v2',
      });
      await expectLater(
        login.login('account', 'password', ''),
        throwsA(
          isA<CoolapkLoginException>().having(
            (e) => e.webRequired,
            'web required',
            isTrue,
          ),
        ),
      );
      response = _body({'status': 1});
      await expectLater(
        login.login('account', 'password', ''),
        throwsA(isA<CoolapkLoginException>()),
      );
    },
  );

  test('a new attempt cannot reuse previous account tokens', () async {
    var attempt = 0;
    final adapter = _Adapter(
      (options) => options.method == 'GET'
          ? _prepare(options)
          : ++attempt == 1
          ? _body({'status': 1}, cookies: ['uid=123', 'token=previous'])
          : _body({'status': 1}, cookies: ['uid=456']),
    );
    final login = _login(adapter);
    addTearDown(login.close);
    await login.prepare();
    expect(
      await login.login('one', 'password', ''),
      contains('token=previous'),
    );
    await expectLater(
      login.login('two', 'password', ''),
      throwsA(isA<CoolapkLoginException>()),
    );
    expect(login.cookie, isNot(contains('previous')));
  });

  test('missing request hash cannot enable password submission', () async {
    final adapter = _Adapter((_) => _body('<html></html>'));
    final login = _login(adapter);
    addTearDown(login.close);
    await expectLater(login.prepare(), throwsA(isA<CoolapkLoginException>()));
    await expectLater(
      login.login('account', 'password', ''),
      throwsA(isA<CoolapkLoginException>()),
    );
    expect(adapter.requests.every((r) => r.method == 'GET'), isTrue);
  });

  Future<void> open(WidgetTester tester, _Api api, _Login login) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => OfficialLoginPage(api: api, login: login),
                ),
              ),
              child: const Text('打开登录'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'test-account');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    await tester.ensureVisible(find.text('登录并校验'));
    await tester.tap(find.text('登录并校验'));
    await tester.pump();
  }

  testWidgets(
    'new login supports narrow large text, validation failure and retry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = _Api()..failure = const CoolapkApiException('当前访问需要验证码');
      final login = _Login();
      await open(tester, api, login);
      await fill(tester);
      await tester.pumpAndSettle();
      expect(api.saved, isNull);
      expect(find.textContaining('当前访问需要验证码'), findsOneWidget);
      expect(find.text('test-account'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.failure = null;
      await tester.tap(find.text('登录并校验'));
      await tester.pumpAndSettle();
      expect(api.saved, 'uid=123; token=new-token');
      expect(find.text('打开登录'), findsOneWidget);
      expect(find.text('登录并校验'), findsNothing);
    },
  );

  testWidgets('leaving a pending login never commits its later response', (
    tester,
  ) async {
    final api = _Api();
    final login = _Login()..pending = Completer<String>();
    await open(tester, api, login);
    await fill(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    login.pending!.complete('uid=123; token=late-token');
    await tester.pumpAndSettle();
    expect(api.saved, isNull);
    expect(login.calls, 1);
  });

  testWidgets(
    'validation blocks duplicate submission and cancellation until commit',
    (tester) async {
      final api = _Api()..validation = Completer<void>();
      final login = _Login();
      await open(tester, api, login);
      await fill(tester);
      await tester.pump();
      await tester.pageBack();
      await tester.pump();
      expect(find.text('登录并校验'), findsOneWidget);
      expect(login.calls, 1);
      api.validation!.complete();
      await tester.pumpAndSettle();
      expect(api.saved, 'uid=123; token=new-token');
      expect(find.text('登录并校验'), findsNothing);
    },
  );
}
