import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAdapter implements HttpClientAdapter {
  Map<String, dynamic> Function(RequestOptions options)? handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final responseMap = handler != null
        ? handler!(options)
        : <String, dynamic>{'data': <Map<String, dynamic>>[]};
    final jsonStr = jsonEncode(responseMap);
    return ResponseBody.fromString(
      jsonStr,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _MockScaffoldApi implements CoolapkApi {
  _MockScaffoldApi({
    required this.localAccount,
    this.currentUserAvatar = 'https://example.com/user_avatar.jpg',
  });

  @override
  final LocalAccount localAccount;
  @override
  final String currentUserAvatar;
  @override
  final ValueNotifier<int> accountProfileRevision = ValueNotifier<int>(0);
  @override
  bool get isAnonymous => false;
  @override
  bool get hasCookie => true;
  @override
  String get currentUid => '123456';
  @override
  String get currentUserNickname => '测试用户';
  @override
  String get loginRequiredMessage => '请先登录';
  @override
  String get notificationSessionKey => 'mock-session';
  @override
  Map<String, String> imageHeadersFor([String? url]) => {};
  @override
  Future<Map<String, String>> loadHomeTabRoutes() async => {};
  @override
  Future<Map<String, dynamic>> checkLogin() async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockAdapter adapter;

  setUp(() {
    adapter = _MockAdapter();
    SharedPreferences.setMockInitialValues({
      'guest_device_code': 'synthetic-device',
      'greennote.local.active': false,
      'greennote.cookie.enabled': true,
      'cached_user_uid': '123456',
      'cached_user_avatar': 'https://example.com/user_avatar.jpg',
      'cached_user_nickname': '测试用户',
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (File(key).existsSync()) {
        final bytes = File(key).readAsBytesSync();
        return ByteData.sublistView(bytes);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return 'uid=123456; token=mock-token';
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.example.greennote/deep_link'),
      (call) async => null,
    );
  });

  test('CoolapkApi.create restores cached avatar immediately on cold start', () async {
    final api = await CoolapkApi.create(httpClientAdapter: adapter);
    expect(api.hasCookie, isTrue);
    expect(api.currentUid, '123456');
    expect(api.currentUserAvatar, 'https://example.com/user_avatar.jpg');
    expect(api.currentUserNickname, '测试用户');
  });

  test('headline channel page 1 merges indexV8 cards and feeds with hasMore true', () async {
    adapter.handler = (options) {
      if (options.path.contains('indexV8')) {
        return {
          'data': [
            {
              'entityType': 'card',
              'entityTemplate': 'imageCarouselCard_1',
              'entities': [
                {'pic': 'https://example.com/banner.jpg', 'title': '轮播'},
              ],
            },
            {
              'id': '101',
              'entityType': 'feed',
              'message': '推荐动态 101',
            },
            {
              'id': '102',
              'entityType': 'feed',
              'message': '推荐动态 102',
            },
          ],
          'lastItem': '102',
        };
      }
      if (options.path.contains('headline')) {
        return {
          'data': [
            {
              'id': '201',
              'entityType': 'feed',
              'message': '头条专刊 201',
            },
          ],
          'lastItem': '201',
        };
      }
      return {'data': []};
    };

    final api = await CoolapkApi.create(httpClientAdapter: adapter);
    final page1 = await api.getHomeChannelPage('/v6/main/headline', 1);

    expect(page1.cards, isNotEmpty);
    expect(page1.items.length, 3);
    expect(page1.items.map((f) => f.id).toList(), containsAll(['201', '101', '102']));
    expect(page1.hasMore, isTrue);
  });

  test('headline channel page 2 continues infinite pagination via indexV8', () async {
    adapter.handler = (options) {
      expect(options.path, contains('indexV8'));
      expect(options.queryParameters['page'], 2);
      expect(options.queryParameters['lastItem'], '102');
      return {
        'data': [
          {
            'id': '301',
            'entityType': 'feed',
            'message': '推荐分页 301',
          },
          {
            'id': '302',
            'entityType': 'feed',
            'message': '推荐分页 302',
          },
        ],
        'lastItem': '302',
      };
    };

    final api = await CoolapkApi.create(httpClientAdapter: adapter);
    final page2 = await api.getHomeChannelPage('/v6/main/headline', 2, lastItem: '102');

    expect(page2.items.length, 2);
    expect(page2.items.first.id, '301');
    expect(page2.hasMore, isTrue);
  });

  testWidgets('MainScaffold displays user avatar from frame 1 when logged in', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final mockApi = _MockScaffoldApi(
      localAccount: LocalAccount(prefs),
      currentUserAvatar: 'https://example.com/user_avatar.jpg',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coolapkApiProvider.overrideWith((ref) => mockApi),
        ],
        child: const MaterialApp(
          home: MainScaffold(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widgetList<AppAvatar>(find.byType(AppAvatar))
          .any((a) => a.url == 'https://example.com/user_avatar.jpg'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
