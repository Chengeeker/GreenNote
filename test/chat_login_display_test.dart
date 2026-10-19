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
import 'package:greennote/core/network/coolapk_login.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/features/account/local_account_page.dart';
import 'package:greennote/features/account/official_login_page.dart';
import 'package:greennote/features/settings/app_settings_page.dart';
import 'package:greennote/features/shared/message_chat_content.dart';
import 'package:greennote/features/shared/notification_entry.dart';
import 'package:greennote/features/shared/reply_notifications_page.dart';
import 'package:greennote/features/shell/main_pages.dart';

class _ReadyLogin extends CoolapkLogin {
  @override
  Future<void> prepare() async {}
}

class _Api implements CoolapkApi {
  _Api(this.localAccount);
  @override
  final LocalAccount localAccount;
  @override
  bool get isAnonymous => false;
  @override
  bool get hasCookie => true;
  @override
  bool get hasAccount => true;
  String uid = '10';
  @override
  String get currentUid => uid;
  @override
  Future<Map<String, dynamic>> checkLogin() async {
    calls.add('/checkLogin');
    uid = '10';
    return {
      'data': {'uid': '10'},
    };
  }

  @override
  String get currentUserAvatar => 'https://avatar.invalid/self.jpg';
  @override
  String get currentUserNickname => '自己的昵称';
  @override
  String get notificationSessionKey => 'session-a';
  @override
  Future<bool> notificationSessionMatches(String key) async =>
      key == 'session-a';
  @override
  Map<String, String> imageHeadersFor() => {};
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async => {'data': {}};
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    calls.add(path);
    return ApiPage(
      items: path.endsWith('feedLikeList')
          ? [
              {
                'entityType': 'feed',
                'id': '333',
                'username': '自己',
                'fromusername': '自己',
                'userAvatar': 'https://avatar.invalid/self.jpg',
                'likeUsername': '给我点赞的酷友',
                'likeUid': '20',
                'likeAvatar': 'https://avatar.invalid/peer.jpg',
                'message': '我发布的动态正文',
              },
            ]
          : path.endsWith('/chat')
          ? [
              {
                'entityType': 'messageExtra',
                'entityTemplate': 'float',
                'title': '你还未关注此人，点击关注',
              },
              {
                'entityType': 'messageExtra',
                'entityTemplate': 'time',
                'title': '09月02日 16:02',
              },
              {
                'entityType': 'message',
                'id': '101',
                'fromuid': '10',
                'username': '自己的昵称',
                'fromUserAvatar': 'https://avatar.invalid/self.jpg',
                'message': '这是我发出的消息',
              },
              {
                'entityType': 'messageExtra',
                'entityTemplate': 'notice',
                'title': '对方48小时内可以与你无限制聊天，关注对方即可让TA与你无限畅聊',
              },
              {
                'entityType': 'messageExtra',
                'entityTemplate': 'time',
                'title': '09月02日 16:37',
              },
              {
                'entityType': 'message',
                'id': '102',
                'fromuid': '20',
                'username': '对方昵称',
                'fromUserAvatar': 'https://avatar.invalid/peer.jpg',
                'message': '老哥加油',
              },
              {'entityType': 'message', 'id': '103', 'message': ''},
            ]
          : [],
      page: 1,
      hasMore: false,
      firstItem: '101',
      lastItem: '102',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  setUp(() async {
    // Legacy source metadata must not misclassify an existing official account.
    SharedPreferences.setMockInitialValues({
      'greennote.official.login_method': 'cookie',
    });
    api = _Api(LocalAccount(await SharedPreferences.getInstance()));
  });
  tearDown(() => api.localAccount.dispose());
  setUpAll(() async {
    for (final entry in {
      'PreviewCJK': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons': 'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });

  test('chat entity kinds, independent notice keys, private pictures and session actor fields', () {
    final partner = messagePartner({
      'uid': '10',
      'username': '自己',
      'userAvatar': 'self',
      'messageUid': '20',
      'messageUsername': '徐逸',
      'messageUserAvatar': 'peer',
    });
    expect(partner, (uid: '20', name: '徐逸', avatar: 'peer'));
    expect(
      chatRowKind({'entityType': 'messageExtra', 'entityTemplate': 'float'}),
      'follow',
    );
    expect(
      chatRowKind({'entityType': 'messageExtra', 'entityTemplate': 'time'}),
      'time',
    );
    expect(chatRowKind({'entityType': 'message', 'message': ''}), 'hidden');
    expect(
      chatRowKey({'entityType': 'messageExtra', 'id': '', 'title': '16:02'}),
      isNot(
        chatRowKey({'entityType': 'messageExtra', 'id': '', 'title': '16:37'}),
      ),
    );
    expect(
      chatPictureUrl({'id': '55', 'message_pic': 'private/picture.jpg'}),
      'https://api.coolapk.com/v6/message/showImage?id=55&type=n',
    );
    expect(chatPictureUrl({'pic': 'javascript:alert(1)'}), isEmpty);
  });

  testWidgets(
    'official account label, two categories and nested Cookie entry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => AppSettingsPage(
              api: api,
              onOpenCookieManager: () => showLoginOptions(context, api),
              onAccountChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前登录方式：账号登录'), findsOneWidget);
      await tester.tap(find.text('登录方式与账号管理'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie 登录'), findsNothing);
      expect(find.text('账号登录'), findsOneWidget);
      expect(find.text('匿名登录'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialLoginPage(api: api, login: _ReadyLogin()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cookie 登录'));
      await tester.pumpAndSettle();
      expect(find.byType(CookieLoginPage), findsOneWidget);
      expect(find.text('酷安 Cookie'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(OfficialLoginPage), findsOneWidget);
    },
  );

  testWidgets('received likes identify the liker rather than the post author', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ReplyNotificationsPage(
            api: api,
            title: '收到的赞',
            path: '/v6/notification/feedLikeList',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, ['/v6/notification/feedLikeList']);
    expect(
      find.textContaining('给我点赞的酷友 赞了你的动态', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('自己 赞了', findRichText: true), findsNothing);
    final avatar = tester.widget<AppAvatar>(find.byType(AppAvatar));
    expect(avatar.url, 'https://avatar.invalid/peer.jpg');
    expect(
      notificationActor({
        'username': '自己',
        'userAvatar': 'self',
      }, '/v6/notification/feedLikeList').name,
      isEmpty,
    );
    expect(
      notificationTarget({'entityType': 'feed', 'id': '333'}).feedId,
      '333',
    );
  });

  for (final dark in [true, false]) {
    testWidgets(
      'chat avatars, direction, time and notices ${dark ? 'dark' : 'light large text'}',
      (tester) async {
        tester.view.physicalSize = Size(dark ? 420 : 360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (dark) api.uid = '';
        final capture = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'PreviewCJK',
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(dark ? 1 : 1.5)),
                  child: child!,
                ),
                home: MessageChatPage(
                  api: api,
                  uid: '20',
                  ukey: '10_20',
                  username: '徐逸',
                  avatar: 'https://avatar.invalid/peer.jpg',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('徐逸'), findsOneWidget);
        if (dark) expect(api.calls.first, '/checkLogin');
        expect(find.byType(AppAvatar), findsNWidgets(2));
        expect(find.text('自己的昵称'), findsNothing);
        expect(find.byType(ChatMessageRow), findsNWidgets(5));
        expect(find.text('你还未关注此人，点击关注'), findsOneWidget);
        final avatars = tester
            .widgetList<AppAvatar>(find.byType(AppAvatar))
            .map((a) => a.url)
            .toList();
        expect(
          avatars,
          containsAll([
            'https://avatar.invalid/self.jpg',
            'https://avatar.invalid/peer.jpg',
          ]),
        );
        if (dark) {
          expect(
            tester.getTopLeft(find.text('09月02日 16:02')).dy,
            lessThan(tester.getTopLeft(find.text('这是我发出的消息')).dy),
          );
          expect(
            tester.getTopLeft(find.text('这是我发出的消息')).dy,
            lessThan(tester.getTopLeft(find.text('老哥加油')).dy),
          );
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('tmp/chat-official-preview-dark.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byTooltip('表情'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('🙂'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '🙂',
        );
        expect(find.byTooltip('发送私信'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
