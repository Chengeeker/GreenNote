import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/features/shell/main_pages.dart';
import 'package:greennote/features/shared/community_library_page.dart';
import 'package:greennote/features/shared/rating_square_page.dart';

class _Api implements CoolapkApi {
  _Api({this.preview = false});
  final bool preview;
  final reads = <String>[];
  final queries = <Map<String, dynamic>>[];
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  bool sessionValid = true;
  int uploads = 0;
  @override
  bool get hasCookie => true;
  @override
  String get currentUid => '7';
  @override
  String get notificationSessionKey => 'test-session';
  @override
  Future<bool> notificationSessionMatches(String session) async =>
      sessionValid && session == notificationSessionKey;
  @override
  String get loginRequiredMessage => '请先登录';
  @override
  Map<String, String> imageHeadersFor() => {};
  @override
  Future<String> uploadFeedImage(Uint8List bytes) async =>
      'https://image.coolapk.com/test-${++uploads}.png';
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    writes.add(Map.of(body ?? {}));
    if (fail) throw const CoolapkApiException('发布失败');
    return {
      'data': {'id': '123'},
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final route = '${query['url'] ?? ''}';
    reads.add(route);
    queries.add(Map.of(query));
    if (query['searchValue'] == 'OriginOS 7') {
      return ApiPage(
        items: [
          {
            'id': 'wrong',
            'entityType': 'topic',
            'title': 'Funtouch OS 17.0',
            'star_total_count': 10,
          },
          {
            'id': 'os7',
            'entityType': 'topic',
            'title': 'OriginOS7',
            'star_total_count': 99,
            'star_average_score': 7.6,
          },
          {
            'id': 'wrong-major',
            'entityType': 'topic',
            'title': 'OriginOS17',
            'star_total_count': 10,
          },
        ],
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
    }
    if (preview && ratingSquareRoutes.contains(route)) {
      final data = jsonDecode(
        File('tmp/publish-reference-20261103/$route.json').readAsStringSync(),
      );
      void clearImages(dynamic value) {
        if (value is Map) {
          value['logo'] = '';
          for (final child in value.values) {
            if (child is List || child is Map) clearImages(child);
          }
        } else if (value is List) {
          for (final child in value) {
            clearImages(child);
          }
        }
      }

      clearImages(data);
      return ApiPage(
        items: (data['data'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList(),
        page: 1,
        hasMore: false,
        firstItem: '',
        lastItem: '',
      );
    }
    final title = route.endsWith('GAME')
        ? 'PC'
        : route.endsWith('LIFE')
        ? '狗'
        : route.endsWith('RECOMMEND')
        ? '我的装备'
        : '手机';
    return ApiPage(
      items: [
        {
          'title': title,
          'entityTemplate': 'ratingNodeHorizonList',
          'url': '#/product/productList?id=1000',
          'entities': [
            for (var i = 0; i < 6; i++)
              {
                'id': '$i',
                'title': '$title对象$i',
                'entityType': title == 'PC' || title == '狗'
                    ? 'topic'
                    : 'product',
                'logo': '',
                'star_average_score': '8.5',
                'star_total_count': 12,
                if (i == 2) 'allow_rating': 0,
              },
          ],
        },
      ],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _avatar = MethodChannel('com.green.note/avatar');
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII=',
);

Future<void> _mount(
  WidgetTester tester,
  _Api api,
  String type, {
  double scale = 1,
  bool dark = true,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: capture == null
            ? (dark ? AppTheme.darkTheme() : AppTheme.lightTheme())
            : AppTheme.darkTheme().copyWith(
                textTheme: AppTheme.darkTheme().textTheme.apply(
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 40),
            viewPadding: const EdgeInsets.only(top: 40),
          ),
          child: child!,
        ),
        home: ComposeFeedPage(api: api, initialType: type),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _avatar,
          (call) async => call.method == 'pickTextDocument' ? '导入的文档正文' : _png,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_avatar, null),
  );

  for (final (type, label) in [
    ('article', '发布图文'),
    ('picture', '发布酷图'),
    ('ershou', '发布二手信息'),
    ('vote', '发起投票'),
    ('collection', '清单标题'),
    ('rank', '天梯榜标题'),
    ('rating', '搜索点评对象'),
  ]) {
    testWidgets(
      '$type opens its own form and handles narrow/large text layout',
      (tester) async {
        for (final dark in [true, false]) {
          await _mount(tester, _Api(), type, scale: 1.3, dark: dark);
          expect(find.text(label), findsWidgets);
          expect(find.text('大封面'), findsNothing);
          expect(find.text('分享你此刻的想法…'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('real picker routes each type to the distinct screen', (
    tester,
  ) async {
    final api = _Api();
    for (final (type, label, target) in [
      ('article', '图文', '发布图文'),
      ('rating', '点评广场', '搜索点评对象'),
      ('ershou', '二手', '发布二手信息'),
      ('picture', '酷图', '发布酷图'),
      ('collection', '清单', '清单标题'),
      ('rank', '天梯榜', '天梯榜标题'),
      ('vote', '投票', '发起投票'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(type),
          theme: AppTheme.darkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CoolapkPublishPickerSheet(api: api),
                ),
                child: const Text('打开发布'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(target), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'rating tabs request their exact routes once and preserve visited tabs',
    (tester) async {
      final api = _Api();
      await _mount(tester, api, 'rating');
      expect(api.reads, [ratingSquareRoutes[0]]);
      for (final (i, label) in ['推荐', '数码', '游戏', '生活'].indexed.skip(1)) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(api.reads.last, ratingSquareRoutes[i]);
      }
      await tester.tap(find.text('数码'));
      await tester.pumpAndSettle();
      expect(api.reads, ratingSquareRoutes);
      expect(find.text('手机'), findsOneWidget);
      expect(find.text('不可点评'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'article imports text, uploads separate cover and submits article title',
    (tester) async {
      final api = _Api()..fail = true;
      await _mount(tester, api, 'article');
      await tester.enterText(
        find.byKey(const ValueKey('publish-title')),
        '图文标题',
      );
      await tester.tap(find.text('＋添加题图'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('导入文档'));
      await tester.tap(find.text('导入文档'));
      await tester.pumpAndSettle();
      expect(find.text('导入的文档正文'), findsOneWidget);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(api.writes.single['type'], 'article');
      expect(api.writes.single['extra_title'], '图文标题');
      expect(api.writes.single['message'], '导入的文档正文');
      expect(api.writes.single['message_cover'], contains('test-1.png'));
      expect(api.uploads, 1);
      expect(find.text('图文标题'), findsOneWidget);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(api.uploads, 1);
      expect(api.writes.length, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'vote switch preserves options, adds/removes rows, sends actual options',
    (tester) async {
      final api = _Api()..fail = true;
      await _mount(tester, api, 'vote');
      await tester.enterText(
        find.byKey(const ValueKey('publish-title')),
        '选哪个',
      );
      await tester.enterText(find.byKey(const ValueKey('vote-option-0')), '甲');
      await tester.enterText(find.byKey(const ValueKey('vote-option-1')), '乙');
      await tester.tap(find.text('多选项模式'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('添加选项'));
      await tester.tap(find.text('添加选项'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vote-option-4')), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('删除选项5'));
      await tester.tap(find.byTooltip('删除选项5'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('PK模式'));
      await tester.tap(find.text('PK模式'));
      await tester.pumpAndSettle();
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(api.writes.single['vote_type'], '0');
      expect(api.writes.single['vote_option[0]'], '甲');
      expect(api.writes.single['vote_option[1]'], '乙');
      expect(api.writes.single.containsKey('vote_option[2]'), isFalse);
      expect(find.text('选哪个'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'rank form retains native album fields, selected targets and levels',
    () {
      final form = productAlbumForm(
        '榜单',
        '说明',
        [
          {'item_name': '产品', 'level': '5'},
        ],
        ranked: true,
        targetType: 'tag',
        targetId: '123',
      );
      expect(form['album_type'], 1);
      expect(form['productItems[0][level]'], '5');
      expect(form['targetId'], '123');
      expect(
        () => productAlbumForm('榜单', '', [
          {'item_name': '产品', 'level': '6'},
        ], ranked: true),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'secondhand price, seller and product link stay attached to its form',
    (tester) async {
      final api = _Api()..fail = true;
      await _mount(tester, api, 'ershou');
      await tester.enterText(
        find.byKey(const ValueKey('publish-title')),
        '闲置手机',
      );
      await tester.enterText(
        find.byKey(const ValueKey('publish-body')),
        '自用转手',
      );
      await tester.tap(find.byKey(const ValueKey('compose-media-add-box')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开个价'));
      await tester.tap(find.text('开个价'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '1999',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('商家'));
      await tester.tap(find.text('商家'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('商品链接'));
      await tester.tap(find.text('商品链接'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'https://example.com/item/1',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(api.writes.single['type'], 'ershou');
      expect(api.writes.single['ershou_price'], '1999');
      expect(api.writes.single['ershou_deal_type'], '1');
      expect(api.writes.single['ershou_link'], 'https://example.com/item/1');
      expect(api.writes.single['extra_title'], '闲置手机');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cool pictures reorder locally and submit the chosen category', (
    tester,
  ) async {
    final api = _Api()..fail = true;
    await _mount(tester, api, 'picture');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('compose-media-add-box')));
      await tester.pumpAndSettle();
    }
    final draggables = find.byWidgetPredicate((w) => w is LongPressDraggable);
    final second =
        (tester.widgetList(draggables).last as LongPressDraggable).data;
    final firstPos = tester.getCenter(draggables.first),
        secondPos = tester.getCenter(draggables.last);
    final drag = await tester.startGesture(firstPos);
    await tester.pump(const Duration(milliseconds: 600));
    await drag.moveTo(secondPos);
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(
      (tester.widgetList(draggables).first as LongPressDraggable).data,
      same(second),
    );
    await tester.ensureVisible(find.text('选择分类'));
    await tester.tap(find.text('选择分类'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '壁纸',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(api.writes.single['type'], 'picture');
    expect(api.writes.single['tag'], '壁纸');
    expect(api.uploads, 2);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('private scope never silently uploads a public article', (
    tester,
  ) async {
    final api = _Api();
    await _mount(tester, api, 'article');
    await tester.enterText(find.byKey(const ValueKey('publish-title')), '私密草稿');
    await tester.enterText(find.byKey(const ValueKey('publish-body')), '正文');
    await tester.tap(find.text('＋添加题图'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('谁可以看'));
    await tester.tap(find.text('谁可以看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅自己可见'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(api.uploads, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommendation resolves only an exact local device match', (
    tester,
  ) async {
    const channel = MethodChannel('com.green.note/ui');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'marketName': '手机对象0', 'osName': '未收录系统'},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final api = _Api();
    await _mount(tester, api, 'rating');
    expect(api.reads.length, 3);
    expect(find.text('手机对象0'), findsOneWidget);
    expect(find.text('未收录系统'), findsOneWidget);
    expect(find.text('暂无评分'), findsOneWidget);
  });

  testWidgets(
    'rating editor retains failed input and checks the original account',
    (tester) async {
      final api = _Api()..fail = true;
      await _mount(tester, api, 'rating');
      await tester.tap(find.text('去点评').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4星'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '使用体验');
      await tester.tap(find.text('发布点评'));
      await tester.pumpAndSettle();
      expect(api.writes.single['type'], 'rating');
      expect(api.writes.single['rating_score_1'], '4');
      expect(find.text('使用体验'), findsOneWidget);
      api.sessionValid = false;
      await tester.tap(find.text('发布点评'));
      await tester.pumpAndSettle();
      expect(api.writes.length, 1);
      expect(find.text('使用体验'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rank custom product preserves its tier and title when switching modes',
    (tester) async {
      final api = _Api()..fail = true;
      await _mount(tester, api, 'rank');
      await tester.enterText(find.byKey(const ValueKey('album-title')), '设备榜单');
      await tester.tap(find.text('添加产品').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义产品'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.first, '工作手机');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('清单'));
      await tester.pumpAndSettle();
      expect(find.text('工作手机'), findsOneWidget);
      expect(find.text('设备榜单'), findsOneWidget);
      await tester.tap(find.text('天梯榜'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(api.writes.single['album_type'], 1);
      expect(api.writes.single['productItems[0][level]'], '5');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'owner scores stay paired with owner counts instead of overall averages',
    () {
      final phone = {
        'owner_star_total_count': '1498',
        'owner_star_average_score': '9.0',
        'star_total_count': 3000,
        'rating_average_score': '8.5',
      };
      expect(ratingNodeScore(phone), 9);
      expect(ratingNodeCount(phone), 1498);
      expect(ratingNodeCountLabel(phone), '1498机主点评');
      expect(
        ratingNodeScore({'star_average_score': 9.6, 'star_total_count': 5}),
        9.6,
      );
      expect(ratingNodeCountLabel({'star_total_count': 5}), '5人点评');
    },
  );

  test(
    'recommendation title cards keep subsequent flat equipment in one section',
    () {
      final node = <String, dynamic>{
        'id': '123',
        'entityType': 'product',
        'title': '装备',
      };
      final cards = ratingSquareCards([
        {'entityTemplate': 'titleCard', 'title': '我的装备'},
        node,
        {'entityTemplate': 'configCard'},
      ]);
      expect(cards, hasLength(1));
      expect(cards.single['title'], '我的装备');
      expect(cards.single['entities'], [node]);
      expect(node.containsKey('entities'), isFalse);
    },
  );

  for (final type in [
    'feed',
    'article',
    'picture',
    'ershou',
    'vote',
    'collection',
    'rank',
  ]) {
    testWidgets('$type keeps fixed editor geometry during IME show and hide', (
      tester,
    ) async {
      await _mount(tester, _Api(), type);
      addTearDown(tester.view.resetViewInsets);
      final field = type == 'feed'
          ? find.byType(TextField).first
          : find.byKey(
              ValueKey(
                type == 'collection' || type == 'rank'
                    ? 'album-title'
                    : type == 'picture'
                    ? 'publish-body'
                    : 'publish-title',
              ),
            );
      final before = tester.getRect(field);
      Rect viewport() => tester.getRect(
        find.byWidget(
          tester.widget<Scaffold>(find.byType(Scaffold).last).body!,
        ),
      );
      final viewportBefore = viewport();
      await tester.showKeyboard(field);
      await tester.pump();
      for (final bottom in [80.0, 160.0, 240.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getRect(field), before);
        expect(viewport(), viewportBefore);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
    'IME composition and ordinary typing do not rebuild picture previews',
    (tester) async {
      await _mount(tester, _Api(), 'picture');
      await tester.tap(find.byKey(const ValueKey('compose-media-add-box')));
      await tester.pumpAndSettle();
      final body = find.byKey(const ValueKey('publish-body'));
      await tester.enterText(body, '初始正文');
      await tester.pump();
      final controller = tester.widget<TextField>(body).controller!;
      final picture = tester.widget<Image>(find.byType(Image).first);
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image).first), same(picture));
      await tester.enterText(body, '继续输入正文并保留图片');
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image).first), same(picture));
      expect(controller.text, '继续输入正文并保留图片');
    },
  );

  testWidgets(
    'obscured lower vote field can scroll above a fixed keyboard viewport',
    (tester) async {
      await _mount(tester, _Api(), 'vote');
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(find.text('多选项模式'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('vote-option-3'));
      await tester.ensureVisible(field);
      await tester.showKeyboard(field);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(field, '可见选项');
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final rect = editable.renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 4),
      );
      final bottom = editable.renderEditable.localToGlobal(rect.bottomRight).dy;
      expect(bottom, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'OriginOS 7.0 keeps the local name while matching the OriginOS7 topic',
    (tester) async {
      const channel = MethodChannel('com.green.note/ui');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {'marketName': '手机对象0', 'osName': 'OriginOS 7.0'},
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final api = _Api();
      await _mount(tester, api, 'rating');
      expect(find.text('OriginOS 7.0'), findsOneWidget);
      expect(
        api.queries.singleWhere((q) => q['type'] == 'feedTopic')['searchValue'],
        'OriginOS 7',
      );
      expect(find.text('99人点评'), findsOneWidget);
      expect(find.text('Funtouch OS 17.0'), findsNothing);
      expect(find.text('OriginOS17'), findsNothing);
    },
  );

  if (const bool.fromEnvironment('PUBLISH_PREVIEW')) {
    testWidgets('render official publish previews', (tester) async {
      await tester.runAsync(() async {
        for (final entry in {
          'Microsoft YaHei': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'D:/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(entry.key)..addFont(
                Future.value(
                  ByteData.sublistView(File(entry.value).readAsBytesSync()),
                ),
              ))
              .load();
        }
      });
      Directory('tmp/publish-previews').createSync(recursive: true);
      for (final type in [
        'article',
        'picture',
        'ershou',
        'vote',
        'collection',
        'rank',
        'rating',
      ]) {
        final capture = GlobalKey();
        await _mount(tester, _Api(preview: true), type, capture: capture);
        final shots = type == 'rating'
            ? ['推荐', '数码', '游戏', '生活']
            : type == 'vote'
            ? ['PK模式', '多选项模式']
            : [type];
        for (final shot in shots) {
          if (type == 'rating' || type == 'vote') {
            await tester.tap(find.text(shot));
            await tester.pumpAndSettle();
          }
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('tmp/publish-previews/$type-${shots.indexOf(shot)}.png')
                .writeAsBytesSync(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
