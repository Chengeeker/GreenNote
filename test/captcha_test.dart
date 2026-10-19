import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/coolapk_captcha.dart';

const _id = '5fc4c10eccd64d178982bc560da43a91';
Map<String, dynamic> _challenge({String field = ''}) => {
  'code': 403,
  'message': '当前访问需要验证码',
  'messageStatus': 'err_request_captcha_v2',
  'messageExtra': jsonEncode({
    'captchaType': 'NEC',
    'captchaId': _id,
    'captchaField': field,
  }),
};

ResponseBody _body(Object data, {int status = 200, String? session}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        'content-type': ['application/json'],
        if (session != null) 'set-cookie': ['SESSID=$session; Path=/; Secure'],
      },
    );

class _Adapter implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  late FutureOr<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
  late String storedCookie;
  late int secureWrites;
  setUp(() {
    adapter = _Adapter();
    storedCookie = 'uid=10; token=synthetic; SESSID=original';
    secureWrites = 0;
    SharedPreferences.setMockInitialValues({
      'guest_device_code': 'synthetic-device',
      'greennote.local.active': false,
      'greennote.cookie.enabled': true,
    });
    rootBundle.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (utf8.decode(message!.buffer.asUint8List()) !=
          'assets/coolapk_auth_blob.b64') {
        return null;
      }
      // Synthetic signing bytes: no account or production signing material.
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(base64Encode(List.filled(1024, 65)))),
      );
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return storedCookie;
        secureWrites++;
        return null;
      },
    );
  });
  tearDown(() {
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  Future<CoolapkApi> create() async {
    final api = await CoolapkApi.create(httpClientAdapter: adapter);
    addTearDown(api.close);
    return api;
  }

  test('detail rejects missing history IDs and preserves the exact trimmed query ID', () async {
    adapter.respond = (_) => _body({
      'data': {'id': '12345', 'message': '原帖正文'},
    });
    final api = await create();
    for (final id in ['', 'detail', 'null', '0']) {
      await expectLater(
        api.getFeedDetail(id),
        throwsA(isA<CoolapkApiException>()),
      );
    }
    expect(adapter.calls, isEmpty);
    await api.getFeedDetail(' 12345 ');
    expect(adapter.calls.single.queryParameters, {'id': '12345'});
  });

  test(
    'headline continues on short page and honors explicit string end flag',
    () async {
      adapter.respond = (_) => _body({
        'data': [
          {'id': '1', 'entityType': 'feed', 'message': '短分页'},
        ],
      });
      final api = await create();
      expect(
        (await api.getHomeChannelPage(
          '/v6/main/headline',
          2,
          lastItem: '100',
        )).hasMore,
        isTrue,
      );
      expect(adapter.calls.last.queryParameters['lastItem'], '100');
      adapter.respond = (_) => _body({
        'hasMore': '0',
        'data': [
          {'id': '2', 'message': '最后一页'},
        ],
      });
      expect(
        (await api.getHomeChannelPage('/v6/main/headline', 3)).hasMore,
        isFalse,
      );
    },
  );

  test('reply image uses image feed preparation while message upload retains its bucket', () async {
    adapter.respond = (call) => _body({
      'data': call.path.contains('checkLoginInfo')
          ? {'uid': '10'}
          : {
              'fileInfo': [
                {'url': 'https://image.coolapk.com/feed/photo.png'},
              ],
              'uploadPrepareInfo': {},
            },
    });
    final api = await create();
    final png = Uint8List(24)
      ..[0] = 137
      ..[1] = 80;
    ByteData.sublistView(png).setUint32(16, 1);
    ByteData.sublistView(png).setUint32(20, 1);
    expect(
      await api.uploadReplyImage(png),
      'https://image.coolapk.com/feed/photo.png',
    );
    var fields = adapter.calls.last.data as Map;
    expect(fields['uploadBucket'], 'image');
    expect(fields['uploadDir'], 'feed');
    expect(fields['feed_type'], 'feed');
    expect(fields['toUid'], '10');
    await api.uploadMessageImage(png, '20');
    fields = adapter.calls.last.data as Map;
    expect(fields['uploadBucket'], 'message');
    expect(fields['uploadDir'], 'message');
    expect(fields['toUid'], '20');
    expect(
      coolapkReplyForm(
        '100',
        '',
        pic: 'https://image.coolapk.com/feed/photo.png',
      )['pic'],
      isNotEmpty,
    );
  });

  test('list pagination preserves optional server total', () async {
    adapter.respond = (_) => _body({
      'total': 34,
      'hasMore': true,
      'data': [
        {'uid': '21', 'username': '名单用户'},
      ],
    });
    final api = await create();
    final page = await api.getList('/v6/user/blackList');
    expect(page.total, 34);
    expect(page.hasMore, isTrue);
  });

  test(
    'legacy personal collection cards use the supported UID list endpoint',
    () async {
      adapter.respond = (call) => _body({
        'data': call.path.contains('checkLoginInfo')
            ? {'uid': '10'}
            : <dynamic>[],
      });
      final api = await create();
      await api.checkLogin();
      await api.getList('/v6/collection/myCollectionList', query: {'page': 2});
      final call = adapter.calls.last;
      expect(call.path, '/v6/collection/list');
      expect(call.queryParameters, {'uid': '10', 'showDefault': 1, 'page': 2});
      expect(secureWrites, 0);
    },
  );

  Future<CoolapkCaptchaException> challenge(CoolapkApi api) async {
    try {
      await api.getFeedDetail('38916622');
    } on CoolapkCaptchaException catch (error) {
      return error;
    }
    throw StateError('Expected a challenge');
  }

  test(
    'personal legacy reads preserve pagination on supported routes',
    () async {
      adapter.respond = (_) => _body({'data': <dynamic>[]});
      final api = await create();
      await api.getList('/v6/member/recentHistoryList', query: {'page': 3});
      expect(adapter.calls.last.path, '/v6/user/recentHistoryList');
      expect(adapter.calls.last.queryParameters['page'], 3);
      await api.getList('/v6/topic/myFollowTopicList', query: {'page': 2});
      expect(adapter.calls.last.path, '/v6/page/dataList');
      expect(adapter.calls.last.queryParameters, {
        'page': 2,
        'url': '#/topic/userFollowTagList?&title=我关注的话题',
      });
    },
  );

  test(
    'official relation and favorite actions use correct paths and methods',
    () async {
      adapter.respond = (_) => _body({'data': <dynamic>[]});
      final api = await create();
      await api.followUser('21', following: false);
      expect(adapter.calls.last.path, '/v6/user/follow');
      expect(adapter.calls.last.method, 'POST');
      await api.followUser('21', following: true);
      expect(adapter.calls.last.path, '/v6/user/unfollow');
      expect(adapter.calls.last.method, 'GET');
      await api.blockUser('21', blocked: false);
      expect(adapter.calls.last.path, '/v6/user/addToBlackList');
      await api.blockUser('21', blocked: true);
      expect(adapter.calls.last.path, '/v6/user/removeFromBlackList');
      await api.favoriteFeed('123', favorited: false);
      expect(adapter.calls.last.path, '/v6/feed/favorite');
      await api.favoriteFeed('123', favorited: true);
      expect(adapter.calls.last.path, '/v6/feed/unFavorite');
      await api.followTopic('测试话题', following: false);
      expect(adapter.calls.last.path, '/v6/feed/followTag');
      await api.followTopic('测试话题', following: true);
      expect(adapter.calls.last.path, '/v6/feed/unFollowTag');
      for (final call in adapter.calls.skip(1)) {
        expect(call.method, 'GET');
      }
      expect(secureWrites, 0);
      await api.localAccount.setActive(true);
      final previous = adapter.calls.length;
      await expectLater(
        api.blockUser('21', blocked: false),
        throwsA(isA<CoolapkApiException>()),
      );
      await expectLater(
        api.followTopic('测试话题', following: false),
        throwsA(isA<CoolapkApiException>()),
      );
      expect(adapter.calls.length, previous);
    },
  );

  test(
    'challenge parser respects blank field and rejects unsafe parameters',
    () {
      final parsed = CoolapkCaptchaChallenge.fromResponse(_challenge())!;
      expect(parsed.field, '');
      expect(
        parsed.proof('synthetic-validate'),
        'NEC:5fc4c10e:synthetic-validate',
      );
      expect(parsed.proof('bad\nvalue'), isNull);
      expect(
        CoolapkCaptchaChallenge.fromResponse({
          ..._challenge(),
          'messageExtra': '{broken',
        }),
        isNull,
      );
      expect(
        CoolapkCaptchaChallenge.fromResponse({
          ..._challenge(),
          'messageExtra': {'captchaId': "bad');alert(1)", 'captchaField': ''},
        }),
        isNull,
      );
      expect(const CoolapkCaptchaChallenge('short', '').proof('value'), isNull);
      expect(
        CoolapkCaptchaChallenge.fromResponse(_challenge(field: 'Cookie')),
        isNull,
      );
    },
  );

  for (final guest in [false, true]) {
    test(
      '${guest ? 'guest' : 'official'} verification binds SESSID and reuses only accepted proof',
      () async {
        if (guest) storedCookie = '';
        adapter.respond = (_) => adapter.calls.length == 1
            ? _body(_challenge(), status: 403, session: 'challenged')
            : _body({
                'data': {
                  'id': '38916622',
                  'goodsListInfo': {'title': '鼠标榜'},
                },
              }, session: 'accepted');
        final api = await create();
        final error = await challenge(api);
        final data = await api.verifyFeedDetail(
          '38916622',
          error,
          'synthetic-validate',
        );
        expect(data['goodsListInfo']['title'], '鼠标榜');
        final cookie = '${adapter.calls[1].headers['Cookie']}';
        expect(cookie, contains('SESSID=challenged'));
        expect(
          cookie,
          contains('validate=NEC%3A5fc4c10e%3Asynthetic-validate'),
        );
        expect(adapter.calls[1].queryParameters, {'id': '38916622'});
        expect(adapter.calls[1].followRedirects, isFalse);
        await api.getFeedDetail('38916622');
        expect(
          '${adapter.calls.last.headers['Cookie']}',
          contains('SESSID=accepted'),
        );
        expect(
          '${adapter.calls.last.headers['Cookie']}',
          contains('validate='),
        );
        expect(secureWrites, 0);
        expect(
          (await SharedPreferences.getInstance()).getKeys().any(
            (key) => key.contains('validate'),
          ),
          false,
        );
      },
    );
  }

  test(
    'legacy field submits GET proof once without retaining a validation Cookie',
    () async {
      adapter.respond = (_) => adapter.calls.length == 1
          ? _body(_challenge(field: '_v2_post_token'))
          : _body({
              'data': {'id': '38916622'},
            });
      final api = await create();
      final error = await challenge(api);
      await api.verifyFeedDetail('38916622', error, 'proof');
      expect(
        adapter.calls.last.queryParameters['_v2_post_token'],
        'NEC:5fc4c10e:proof',
      );
      expect(
        '${adapter.calls.last.headers['Cookie']}',
        isNot(contains('validate=')),
      );
      await api.getFeedDetail('38916622');
      expect(adapter.calls.last.queryParameters, {'id': '38916622'});
    },
  );

  test('a second challenge stops after a single replay and does not cache its proof', () async {
    adapter.respond = (_) => _body(_challenge());
    final api = await create();
    final error = await challenge(api);
    await expectLater(
      api.verifyFeedDetail('38916622', error, 'proof'),
      throwsA(isA<CoolapkCaptchaException>()),
    );
    expect(adapter.calls.length, 2);
    await expectLater(
      api.getFeedDetail('38916622'),
      throwsA(isA<CoolapkCaptchaException>()),
    );
    expect(
      '${adapter.calls.last.headers['Cookie']}',
      isNot(contains('validate=')),
    );
  });

  for (final change in ['account', 'device', 'anonymous']) {
    test(
      '$change change rejects the old proof before making another request',
      () async {
        adapter.respond = (_) => _body(_challenge());
        final api = await create();
        final error = await challenge(api);
        final preferences = await SharedPreferences.getInstance();
        if (change == 'account') storedCookie = 'uid=20; token=another';
        if (change == 'device') {
          await preferences.setString('guest_device_code', 'another-device');
        }
        if (change == 'anonymous') {
          await preferences.setBool('greennote.local.active', true);
        }
        await expectLater(
          api.verifyFeedDetail('38916622', error, 'proof'),
          throwsA(isA<CoolapkApiException>()),
        );
        expect(adapter.calls.length, 1);
      },
    );
  }

  test(
    'account change while replay is in flight discards the result',
    () async {
      adapter.respond = (_) {
        if (adapter.calls.length == 1) return _body(_challenge());
        storedCookie = 'uid=20; token=another';
        return _body({
          'data': {'id': '38916622'},
        });
      };
      final api = await create();
      final error = await challenge(api);
      await expectLater(
        api.verifyFeedDetail('38916622', error, 'proof'),
        throwsA(isA<CoolapkApiException>()),
      );
      expect(secureWrites, 0);
    },
  );
}
