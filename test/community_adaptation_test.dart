import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/accounts/local_account.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/coolapk_captcha.dart';
import 'package:greennote/core/utils/coolapk_url_handler.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart'
    show UserSpacePage;
import 'package:greennote/features/shared/community_detail_page.dart';
import 'package:greennote/features/shared/discovery_channel_page.dart';
import 'package:greennote/features/shared/community_library_page.dart';
import 'package:greennote/features/shared/community_routes.dart';
import 'package:greennote/features/shared/community_ui.dart';
import 'package:greennote/features/shared/following_page.dart';
import 'package:greennote/features/shared/goods_ranking_body.dart';
import 'package:greennote/features/shared/download_center_page.dart';
import 'package:greennote/features/shared/reply_notifications_page.dart';
import 'package:greennote/features/settings/official_profile_page.dart';
import 'package:greennote/features/shell/main_pages.dart'
    show MessageChatPage, MessageCenterPage;

class _Api implements CoolapkApi {
  _Api(this.localAccount);
  @override
  final LocalAccount localAccount;
  bool cookie = true;
  String scope = 'a' * 64;
  final calls =
      <
        ({
          String path,
          String method,
          Map<String, dynamic> query,
          Map<String, dynamic>? body,
        })
      >[];
  bool failAnswer = false;
  bool failDetail = false;
  CoolapkCaptchaException? captcha;
  final detailRequests = <String>[];
  final detail = <String, dynamic>{
    'id': '100',
    'uid': '10',
    'username': '测试作者',
    'title': '日常工作与数码设备清单',
    'description': '参照上游的信息层级，展示资料、内容和操作。',
    'message': '这是一段用于检查手机布局、正文换行和大字体的内容。',
    'isOpen': 1,
    'follownum': 25,
    'replynum': 8,
    'answernum': 3,
    'productItems': [
      {'item_name': '日常使用的设备', 'item_description': '适合日常工作和阅读。'},
    ],
    'liveStatus': 0,
  };
  @override
  bool get hasCookie => cookie;
  @override
  bool get isAnonymous => !cookie;
  @override
  bool get hasAccount => cookie;
  @override
  String get currentUid => '10';
  @override
  String get notificationSessionKey => scope;
  @override
  Future<bool> notificationSessionMatches(String key) async =>
      cookie && key == scope;
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<Map<String, dynamic>> getFeedDetail(String id) async {
    detailRequests.add(id);
    if (captcha != null) throw captcha!;
    if (failDetail) throw const CoolapkApiException('当前访问需要验证码');
    return {...detail, 'id': id};
  }

  @override
  Future<Map<String, dynamic>> getReplyDetail(String id) async => {
    'data': {
      'id': id,
      'feedId': '333',
      'username': '回复人',
      'message': '这就是通知对应的评论',
    },
  };
  @override
  Future<Map<String, dynamic>> getUserProfile(String uid) async => {
    'data': {...detail, 'bio': '这是一条个性签名'},
  };
  @override
  Future<Map<String, dynamic>> getUserSpace(String uid) async => {
    'data': {...detail, 'uid': uid, 'isSpecialFollow': 1, 'username': '接口测试酷友'},
  };
  @override
  Future<String> uploadMessageImage(Uint8List bytes, String toUid) async {
    calls.add((
      path: '/upload',
      method: 'PUT',
      query: {'toUid': toUid},
      body: null,
    ));
    return 'https://image.coolapk.com/test.png';
  }

  @override
  Future<void> sendMessage(String uid, String message, {String? pic}) async {
    calls.add((
      path: '/message/send',
      method: 'POST',
      query: {'uid': uid},
      body: {'message': message, 'pic': pic},
    ));
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    calls.add((path: path, method: method, query: query, body: body));
    return {
      'data': {...detail},
    };
  }

  @override
  Future<Map<String, dynamic>> officialMultipart(
    String path, {
    Map<String, String> fields = const {},
    Map<String, dynamic> query = const {},
    Uint8List? avatar,
    String? expectedScope,
  }) async {
    calls.add((path: path, method: 'MULTIPART', query: query, body: fields));
    if (failAnswer) throw StateError('network');
    return {
      'data': {'id': '200'},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    calls.add((path: path, method: 'GET', query: query, body: null));
    final List<Map<String, dynamic>> items;
    if (path == '/v6/message/list') {
      items = [
        {
          'ukey': 'session-21',
          'uid': '21',
          'username': '待删除的会话',
          'lastMessage': '消息内容',
        },
      ];
    } else if (path.contains('answerList')) {
      items = [
        {
          'id': '201',
          'username': '回答作者',
          'message': '这是一个真实布局的回答摘要。',
          'entityType': 'feed',
          'feedType': 'answer',
        },
      ];
    } else if (path.contains('blackList') ||
        path.contains('ignoreList') ||
        path.contains('limitList')) {
      items = [
        {'uid': '21', 'username': '名单中的酷友', 'bio': '资料简介'},
      ];
    } else if (path.contains('followList') || path.contains('fansList')) {
      items = [
        {
          'uid': '10',
          'fuid': '21',
          'fUserInfo': {
            'uid': '21',
            'username': '关注的酷友',
            'follow': 9,
            'fans': 1595,
            'lastlogin_text': '10小时前活跃',
            'bio': '认真做好每一件事',
          },
        },
      ];
    } else if (path.contains('goodsList')) {
      items = [];
    } else {
      items = [];
    }
    return ApiPage(
      items: items,
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final chinese = File(
      '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
    );
    if (chinese.existsSync()) {
      await (FontLoader('PreviewCJK')..addFont(
            Future.value(ByteData.sublistView(chinese.readAsBytesSync())),
          ))
          .load();
    }
    final icons = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });
  late _Api api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _Api(LocalAccount(await SharedPreferences.getInstance()));
  });
  tearDown(() => api.localAccount.dispose());
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    double scale = 1.0,
    bool dark = false,
    GlobalKey? capture,
  }) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'PreviewCJK',
              colorSchemeSeed: Colors.teal,
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'business routes reject foreign hosts, recognize reply and answer targets',
    () {
      expect(
        communityPageForUrl(api, 'https://evil.example/collection/123'),
        isNull,
      );
      expect(
        communityPageForUrl(api, 'https://www.coolapk.com/feed/333?rid=222'),
        isA<ReplyThreadPage>(),
      );
      expect(
        (communityPageForUrl(
          api,
          'coolmarket://collection/detail?id=123',
        ) as CommunityDetailPage).id,
        '123',
      );
      expect(
        (communityPageForEntity(api, {
          'id': '201',
          'entityType': 'question_answer',
          'questionId': '100',
        }) as FeedDetailPage).questionId,
        '100',
      );
      expect(decodeCoolapkComponent('暗影双生'), '暗影双生');
      expect(decodeCoolapkComponent('bad%name'), 'bad%name');
    },
  );

  test(
    'recommendation vote metadata does not turn a normal feed into a ranking',
    () {
      expect(
        communityPageForEntity(api, {
          'id': '999',
          'entityType': 'feed',
          'feedType': 'feed',
          'goodsListInfo': {'item_id': '2619', 'vote_num': 432},
        }),
        isNull,
      );
      expect(
        communityPageForEntity(api, {
          'id': '999',
          'entityType': 'goodsListItem',
          'goodsListInfo': {'item_id': '2619', 'vote_num': 432},
        }),
        isNull,
      );
    },
  );

  testWidgets(
    'discovery product preview opens its parent ranking and retains flat metadata',
    (tester) async {
      api.failDetail = true;
      final row = <String, dynamic>{
        'id': '777',
        'entityType': 'feed',
        'feedType': 'goodsList',
        'title': '大学生开学鼠标榜',
        'item_num': 28,
        'vote_num': 252,
        'goodsListItem': [
          {
            'id': '999',
            'entityType': 'feed',
            'feedType': 'feed',
            'product_goods_title': '预览鼠标',
            'price': '149.00',
            'goodsListInfo': {'item_id': '2619', 'vote_num': 432},
          },
        ],
      };
      await mount(
        tester,
        Scaffold(
          body: DiscoveryGoodsRanking(api: api, row: row),
        ),
      );
      await tester.tap(find.text('预览鼠标'));
      await tester.pumpAndSettle();
      expect(api.detailRequests, ['777']);
      expect(find.text('大学生开学鼠标榜'), findsOneWidget);
      expect(find.textContaining('28个好物'), findsOneWidget);
      expect(find.textContaining('252人投票'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a ranking without preview offers human verification instead of empty zero statistics',
    (tester) async {
      api.captcha = const CoolapkCaptchaException(
        CoolapkCaptchaChallenge('5fc4c10eccd64d178982bc560da43a91', ''),
        'synthetic-context',
        '当前访问需要验证码',
      );
      await mount(
        tester,
        CommunityDetailPage(api: api, id: '777', kind: CommunityKind.goods),
      );
      expect(find.text('完成验证并加载榜单'), findsOneWidget);
      expect(find.text('当前访问需要验证码'), findsOneWidget);
      expect(find.byType(GoodsRankingBody), findsNothing);
      expect(find.textContaining('0个好物'), findsNothing);
    },
  );

  test('friend queries use server categories and nested target user', () {
    expect(relationQuery('10', 0), {
      'uid': '10',
      'isSpecialFollow': -1,
      'isFriend': 0,
    });
    expect(relationQuery('10', 1), {'uid': '10', 'isSpecialFollow': 1});
    expect(relationQuery('10', 2), {'uid': '10', 'isFriend': 1});
    expect(relationQuery('10', 3), {'uid': '10'});
    expect(
      followingAuthor(
        CoolapkFeed.fromJson({
          'id': '1',
          'userInfo': {'isFollow': 1},
        }),
      ),
      isTrue,
    );
    expect(
      followingAuthor(
        CoolapkFeed.fromJson({
          'id': '2',
          'userInfo': {'isFollow': 0},
        }),
      ),
      isFalse,
    );
    expect(
      relationUser({
        'uid': '10',
        'fuid': '21',
        'fUserInfo': {'username': '酷友'},
      })['uid'],
      '21',
    );
    expect(
      followFilterRoute('/page?url=V15_HOME_TAB_FOLLOW', 'circle'),
      '/page?url=V15_HOME_TAB_FOLLOW&type=circle',
    );
    expect(
      followFilterRoute('/page?url=V15_HOME_TAB_FOLLOW&type=topic', ''),
      '/page?url=V15_HOME_TAB_FOLLOW',
    );
    expect(
      rankingProduct({
        'title': '推荐动态',
        'extra_entities': [
          {'product_goods_title': '鼠标', 'price': '149.00'},
        ],
      })['price'],
      '149.00',
    );
  });

  testWidgets(
    'ranking keeps official preview and exposes captcha instead of network error',
    (tester) async {
      api.failDetail = true;
      final initial = {
        ...api.detail,
        'title': '300元以下推荐购买的鼠标',
        'likenum': 201,
        'replynum': 370,
        'goodsListInfo': {
          'title': '300元以下推荐购买的鼠标',
          'message': '欢迎酷友推荐好用的鼠标，也欢迎大家投票。',
          'item_num': 45,
          'vote_num': 1269,
          'is_open_vote': 1,
          'is_allow_recommend_goods': 1,
        },
        'goodsListItem': [
          {
            'id': 2619,
            'product_goods_title': '罗技 G304 无线鼠标',
            'price': '149.00',
            'mall_name': '京东',
            'product_goods_url': 'https://item.m.jd.com/product/123.html',
            'note': '好用',
            'vote_num': 432,
            'isVote': 0,
            'userInfo': {'username': '菩提语'},
          },
        ],
      };
      final capture = GlobalKey();
      await mount(
        tester,
        CommunityDetailPage(
          api: api,
          id: '38916622',
          kind: CommunityKind.goods,
          initial: initial,
        ),
        capture: capture,
        dark: true,
      );
      expect(find.text('当前访问需要验证码'), findsOneWidget);
      expect(find.text('当前展示入口预览，完整榜单尚未加载'), findsOneWidget);
      expect(find.textContaining('45个好物'), findsOneWidget);
      expect(find.text('¥149.00'), findsOneWidget);
      expect(find.text('详情加载失败，请检查网络或登录状态'), findsNothing);
      await tester.runAsync(() async {
        final directory = Directory('tmp/official-ui-previews')
          ..createSync(recursive: true);
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/ranking.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(api.calls.last.path, '/v6/goodsList/vote');
      expect(api.calls.last.body, {
        'id': '38916622',
        'item_id': '2619',
        'value': 1,
      });
      expect(find.text('433'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cool friend tabs show nested profile and request real categories',
    (tester) async {
      await mount(
        tester,
        CoolFriendListPage(api: api, uid: '10'),
        scale: 1.5,
        dark: true,
      );
      expect(find.text('关注的酷友'), findsOneWidget);
      expect(find.textContaining('1595粉丝'), findsOneWidget);
      expect(find.text('私信'), findsOneWidget);
      await tester.tap(find.text('特别关注'));
      await tester.pumpAndSettle();
      expect(api.calls.last.query['isSpecialFollow'], 1);
      await tester.tap(find.text('互相关注'));
      await tester.pumpAndSettle();
      expect(api.calls.last.query['isFriend'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'following recent avatars sort by publication, preserve server order and filter callback',
    (tester) async {
      final feeds = [
        CoolapkFeed.fromJson({
          'id': '1',
          'uid': '1',
          'username': '较早更新',
          'dateline': 100,
        }),
        CoolapkFeed.fromJson({
          'id': '2',
          'uid': '2',
          'username': '最新更新',
          'dateline': 200,
        }),
      ];
      expect(recentFollowingUsers([], feeds).first['uid'], '2');
      expect(
        recentFollowingUsers([
          {
            'title': '最近更新',
            'entities': [
              {'entityType': 'user', 'uid': '1'},
              {'entityType': 'user', 'uid': '2'},
            ],
          },
        ], feeds).first['uid'],
        '1',
      );
      var filter = '';
      await mount(
        tester,
        Scaffold(
          body: FollowingChannelHeader(
            api: api,
            cards: const [],
            feeds: feeds,
            selected: '',
            onSelect: (value) => filter = value,
          ),
        ),
        scale: 1.5,
      );
      await tester.tap(find.text('好友关注'));
      await tester.pumpAndSettle();
      expect(filter, 'circle');
      expect(find.text('最近更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'notification record IDs never become feed IDs; note keeps target reply',
    () {
      expect(notificationTarget({'id': '99'}).feedId, '');
      expect(
        notificationTarget({
          'note': '<a href="https://evil.example/feed/333?rid=222">link</a>',
        }).replyId,
        '',
      );
      final target = notificationTarget({
        'id': '99',
        'note': '评论：<a href="/feed/333?rid=222">查看</a>',
      });
      expect(target.feedId, '333');
      expect(target.replyId, '222');
    },
  );
  test(
    'product album form uses indexed native fields and validates limits',
    () {
      final body = productAlbumForm(' 清单 ', '说明', [
        {'item_name': '手机', 'item_description': '工作用'},
      ]);
      expect(body['title'], '清单');
      expect(body['productItems[0][item_name]'], '手机');
      expect(body['productItems[0][display_order]'], '0');
      expect(() => productAlbumForm('', '', []), throwsFormatException);
      expect(
        () => productAlbumForm('清单', '', [
          {'item_name': ''},
        ]),
        throwsFormatException,
      );
      expect(
        () => productAlbumForm('清单', 'a' * 1001, []),
        throwsFormatException,
      );
    },
  );
  test('reply form targets feed or reply using the upstream contract', () {
    expect(coolapkReplyForm('333', '回复内容'), {
      'id': '333',
      'type': 'feed',
      'message': '回复内容',
    });
    final reply = coolapkReplyForm(
      '333',
      '楼中楼',
      rid: '222',
      pic: 'image',
      replyAndForward: true,
    );
    expect(reply['id'], '222');
    expect(reply['type'], 'reply');
    expect(reply.containsKey('rid'), false);
    expect(reply['pic'], 'image');
    expect(reply['replyAndForward'], '1');
    expect(
      () => coolapkReplyForm('', '内容'),
      throwsA(isA<CoolapkApiException>()),
    );
  });
  test('official write guard drops stale or anonymous sessions', () async {
    final scope = api.scope;
    api.scope = 'b' * 64;
    await expectLater(
      communityRequest(api, scope, '/v6/collection/delete', method: 'POST'),
      throwsStateError,
    );
    api.cookie = false;
    await expectLater(
      communityRequest(api, api.scope, '/v6/collection/delete', method: 'POST'),
      throwsStateError,
    );
    expect(api.calls, isEmpty);
  });

  for (final kind in CommunityKind.values) {
    testWidgets('${kind.name} details render on narrow large-text screen', (
      tester,
    ) async {
      await mount(
        tester,
        CommunityDetailPage(api: api, id: '100', kind: kind),
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('日常工作与数码设备清单'), findsOneWidget);
    });
  }
  testWidgets('question sort issues a distinct answer request', (tester) async {
    await mount(
      tester,
      CommunityDetailPage(api: api, id: '100', kind: CommunityKind.question),
    );
    await tester.tap(find.text('高赞'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any(
        (call) =>
            call.path == '/v6/question/answerList' &&
            call.query['sort'] == 'like',
      ),
      true,
    );
  });
  testWidgets('collection edit uses form ID and retains failed answer draft', (
    tester,
  ) async {
    await mount(
      tester,
      CommunityDetailPage(api: api, id: '100', kind: CommunityKind.collection),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '新的收藏单标题');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final call = api.calls.firstWhere(
      (call) => call.path == '/v6/collection/update',
    );
    expect(call.query, isEmpty);
    expect(call.body!['id'], '100');
    expect(call.body!['title'], '新的收藏单标题');
  });
  testWidgets('failed answer preserves draft for retry', (tester) async {
    api.failAnswer = true;
    await mount(
      tester,
      CommunityDetailPage(api: api, id: '100', kind: CommunityKind.question),
    );
    await tester.tap(find.text('添加回答'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '这是一段还没有发布成功的回答');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加回答'));
    await tester.pumpAndSettle();
    expect(find.text('这是一段还没有发布成功的回答'), findsOneWidget);
    final call = api.calls.firstWhere(
      (call) => call.path == '/v6/feed/createFeed',
    );
    expect(call.method, 'MULTIPART');
    expect(call.body!['fid'], '100');
    expect(call.body!['type'], 'answer');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('blacklist requires confirmation and sends only selected user', (
    tester,
  ) async {
    await mount(
      tester,
      CommunityLibraryPage(api: api, library: CommunityLibrary.blacklist),
    );
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(api.calls.where((call) => call.method == 'POST'), isEmpty);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any(
        (call) =>
            call.path == '/v6/user/removeFromBlackList' &&
            call.method == 'GET' &&
            call.query['uid'] == '21',
      ),
      true,
    );
  });
  testWidgets(
    'special follow cancellation and remarks send the intended fields',
    (tester) async {
      await mount(tester, UserSpacePage(api: api, uid: '21'));
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消特别关注'));
      await tester.pumpAndSettle();
      final special = api.calls.firstWhere(
        (call) => call.path == '/v6/user/specialFollowUser',
      );
      expect(special.method, 'POST');
      expect(special.query, {'uid': '21', 'special': 0});
      expect(
        api.calls.any((call) => call.path.contains('cancelFollower')),
        false,
      );
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置备注'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新的备注');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final remark = api.calls.firstWhere(
        (call) => call.path == '/v6/user/updateRemark',
      );
      expect(remark.body, {'uid': '21', 'name': '新的备注'});
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'album apps come from detail without calling a nonexistent apkList API',
    (tester) async {
      api.detail['apkList'] = [
        {'id': '88', 'title': '应用集内的应用', 'packageName': 'example.app'},
      ];
      await mount(
        tester,
        CommunityDetailPage(api: api, id: '100', kind: CommunityKind.album),
      );
      expect(find.text('应用集内的应用'), findsOneWidget);
      expect(api.calls.any((call) => call.path == '/v6/album/apkList'), false);
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      expect(api.calls.any((call) => call.path == '/v6/album/replyList'), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('message deletion confirms before using deleteChat GET', (
    tester,
  ) async {
    await mount(tester, Scaffold(body: MessageCenterPage(api: api)));
    expect(find.text('待删除的会话'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除会话'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any((call) => call.path == '/v6/message/deleteChat'),
      false,
    );
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    final call = api.calls.firstWhere(
      (call) => call.path == '/v6/message/deleteChat',
    );
    expect(call.method, 'GET');
    expect(call.query, {'ukey': 'session-21'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('old page cannot write after account changes', (tester) async {
    await mount(
      tester,
      CommunityLibraryPage(api: api, library: CommunityLibrary.blacklist),
    );
    api.scope = 'b' * 64;
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(api.calls.where((call) => call.method == 'POST'), isEmpty);
  });
  testWidgets('download center shows native progress and install action', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          downloadChannel,
          (call) async => call.method == 'list'
              ? [
                  {
                    'id': 3,
                    'title': '测试应用',
                    'status': 8,
                    'bytes': 1048576,
                    'total': 1048576,
                  },
                ]
              : true,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(downloadChannel, null),
    );
    await mount(tester, const DownloadCenterPage(), scale: 1.5);
    expect(find.text('测试应用'), findsOneWidget);
    expect(find.text('安装'), findsOneWidget);
    expect(find.textContaining('下载完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('official profile exposes avatar and signature controls', (
    tester,
  ) async {
    await mount(tester, OfficialProfilePage(api: api), scale: 1.5);
    expect(find.text('更换头像'), findsOneWidget);
    expect(find.text('修改签名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('chat picks a local image without uploading until send', (
    tester,
  ) async {
    const picker = MethodChannel('com.green.note/avatar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          picker,
          (call) async => File('assets/greennote_icon.png').readAsBytesSync(),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, null),
    );
    await mount(tester, MessageChatPage(api: api, uid: '20', ukey: 'test'));
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pumpAndSettle();
    expect(find.text('图片将在点击发送后上传'), findsOneWidget);
    expect(api.calls.where((call) => call.path == '/upload'), isEmpty);
    await tester.tap(find.byTooltip('发送私信'));
    await tester.pumpAndSettle();
    expect(
      api.calls.any(
        (call) => call.path == '/upload' && call.query['toUid'] == '20',
      ),
      true,
    );
    expect(
      api.calls.any(
        (call) => call.path == '/message/send' && call.query['uid'] == '20',
      ),
      true,
    );
    expect(find.text('图片将在点击发送后上传'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('export representative adapted screen previews', (tester) async {
    for (final kind in [
      CommunityKind.question,
      CommunityKind.collection,
      CommunityKind.goods,
    ]) {
      final capture = GlobalKey();
      await mount(
        tester,
        CommunityDetailPage(
          key: ValueKey(kind),
          api: api,
          id: '100',
          kind: kind,
        ),
        capture: capture,
        dark: kind == CommunityKind.goods,
      );
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('tmp/community-previews').createSync(recursive: true);
        File('tmp/community-previews/${kind.name}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
