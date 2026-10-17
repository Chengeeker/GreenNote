import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/feed/feed_pages.dart';
import 'package:greennote/features/shared/activity_pages.dart';
import 'package:greennote/features/shared/api_list_page.dart';
import 'package:greennote/features/shared/home_destination_page.dart';

import 'home_destination_test.dart' as fixture;

const _registration = 'https://wj.qq.com/s2/28127199/d7n4/?openid=1086,0,,';
const _discussion = '#/topic/tagFeedList?id=72606&title=人像摄影&withSortCard=1';

class ActivityApi extends fixture.HomeApi {
  ActivityApi({super.hasCookie});
  final queriedTags = <String>[];
  Map<String, dynamic> event = {};
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    if (path != '/v6/event/detail') throw StateError('Unexpected $path');
    return {'data': event};
  }

  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async {
    queriedTags.add(tag);
    if (tag != 'MagicOS11开放麦' && tag != '人像摄影') {
      throw const CoolapkApiException('话题不存在');
    }
    return {
      'data': {
        'title': tag,
        'hot_num_txt': '14.5万',
        'commentnum_txt': '1.5万',
        'follownum_txt': '1.4万',
        'intro': tag == '人像摄影' ? '大声告诉我，人像三要素：\n____、____、____！' : '活动简介',
        'userAction': {'follow': 1},
        'selectedTab': tag == '人像摄影' ? 'lastupdate_desc' : 'activity',
        'tabList': tag == '人像摄影'
            ? [
                {
                  'title': '精选',
                  'page_name': 'Top',
                  'url': '#/article/includeFeedList?dyhId=4988',
                },
                {
                  'title': '讨论',
                  'page_name': 'lastupdate_desc',
                  'url': _discussion,
                },
              ]
            : [
                {
                  'title': '讨论',
                  'page_name': 'lastupdate_desc',
                  'url': '#/topic/tagFeedList?id=141600',
                },
                {
                  'title': '活动详情',
                  'page_name': 'activity',
                  'url': 'https://m.coolapk.com/activity/MagicOS_11_20261012',
                },
              ],
        'recommendRows': tag == '人像摄影'
            ? [
                {
                  'entities': [
                    {
                      'entityTypeName': '⚠️',
                      'title': '严禁不文明/不礼貌/盗图行为',
                      'url': '/page?url=V11_ATTENTION_20210130',
                    },
                  ],
                },
              ]
            : [],
      },
    };
  }

  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final route = '${query['url'] ?? path}';
    requests.add(route);
    return ApiPage(
      page: 1,
      firstItem: '',
      lastItem: '',
      hasMore: false,
      items: [
        if (route.contains('tagFeedList') && !route.contains('sortField='))
          {
            'entityType': 'card',
            'entityTemplate': 'sortSelectCard',
            'entities': [
              {'title': '默认', 'url': _discussion},
              {'title': '最新', 'url': '$_discussion&sortField=dateline_desc'},
              {'title': '热度', 'url': '$_discussion&sortField=hot'},
            ],
          },
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

void _activityTest(String name, Future<void> Function(WidgetTester) callback) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'URL topic identity wins over carousel labels, including raw Chinese',
    () {
      for (final url in [
        '/t/MagicOS11开放麦',
        '/t/MagicOS11%E5%BC%80%E6%94%BE%E9%BA%A6',
        'https://www.coolapk.com/t/MagicOS11开放麦?type=0',
      ]) {
        expect(
          ApiEntityCard.extractTopicTag({
            'url': url,
            'title': '首页轮播_MagicOS11开放麦',
            'tag': '错误装饰标题',
          }),
          'MagicOS11开放麦',
        );
      }
      expect(
        ApiEntityCard.extractTopicTag({
          'url': '/topic/detail?tag=人像摄影',
          'title': '轮播标题',
        }),
        '人像摄影',
      );
    },
  );

  test(
    'observed stage 2 waits for the list; published list uses server URL',
    () {
      final result = crowdTestAction({
        'stage_status': 2,
        'time_reg_start': 1791770400,
        'time_reg_end': 1792116000,
        'time_end': 1794412800,
        'prize_user': '',
        'action_url': _registration,
      }, nowSeconds: 1792134000);
      expect(result.label, '暂未公布众测名单');
      expect(result.canRegister, isFalse);
      final published = crowdTestAction({
        'stage_status': 3,
        'prizeUserUrl': '#/event/prizeUserList?id=1085',
      });
      expect(published.label, '查看众测名单');
      expect(published.winnersUrl, '#/event/prizeUserList?id=1085');
      expect(published.canRegister, isFalse);
    },
  );

  test('registration requires an open window and a usable HTTPS action', () {
    final event = {
      'stage_status': 1,
      'time_reg_start': 100,
      'time_reg_end': 200,
      'action_url': _registration,
    };
    expect(crowdTestAction(event, nowSeconds: 150).canRegister, isTrue);
    expect(crowdTestAction(event, nowSeconds: 150).actionUrl, _registration);
    expect(crowdTestAction(event, nowSeconds: 90).label, '报名未开始');
    expect(crowdTestAction(event, nowSeconds: 201).canRegister, isFalse);
    expect(
      crowdTestAction({
        ...event,
        'action_url': '',
      }, nowSeconds: 150).canRegister,
      isFalse,
    );
    expect(
      crowdTestAction({
        ...event,
        'action_url': 'javascript:void(0)',
      }, nowSeconds: 150).canRegister,
      isFalse,
    );
    expect(
      crowdTestAction({...event, 'is_join_status': 1}, nowSeconds: 150).label,
      '已报名',
    );
  });

  _activityTest('online activity banner requests its real Chinese topic', (
    tester,
  ) async {
    final api = ActivityApi();
    await tester.pumpWidget(
      fixture.app(
        Scaffold(
          body: HomeChannelCard(
            api: api,
            destination: HomeDestination.activities,
            entity: const {
              'entityType': 'card',
              'entityTemplate': 'imageCarouselCard_1',
              'title': '✨ MagicOS11开放麦',
              'entities': [
                {'title': '首页轮播_MagicOS11开放麦', 'url': '/t/MagicOS11开放麦'},
              ],
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell).first);
    await _pump(tester);
    expect(api.queriedTags, ['MagicOS11开放麦']);
    expect(find.text('话题不存在'), findsNothing);
    expect(find.text('活动详情'), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(find.text('酷安评分'), findsNothing);
  });

  _activityTest(
    'generic carousel route also prefers URL over injected bad tag',
    (tester) async {
      final api = ActivityApi();
      await tester.pumpWidget(
        fixture.app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openHeadlineTarget(context, api, {
                  'title': '首页轮播_MagicOS11开放麦',
                  'tag': '首页轮播_MagicOS11开放麦',
                  'url': '/t/MagicOS11开放麦',
                }),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      expect(api.queriedTags, ['MagicOS11开放麦']);
      expect(find.text('话题不存在'), findsNothing);
      expect(find.text('活动详情'), findsOneWidget);
    },
  );

  _activityTest(
    'portrait shortcut uses server tabs, intro, notice and sort routes',
    (tester) async {
      final api = ActivityApi();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        fixture.app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openHeadlineTarget(context, api, {
                  'title': '人像摄影',
                  'url': '/page?url=V9_PORTRAIT_PHOTO',
                }),
                child: const Text('open'),
              ),
            ),
          ),
          scale: 1.3,
        ),
      );
      await tester.tap(find.text('open'));
      await _pump(tester);
      expect(api.queriedTags, ['人像摄影']);
      expect(find.text('精选'), findsOneWidget);
      expect(find.text('讨论'), findsOneWidget);
      expect(find.textContaining('人像三要素', findRichText: true), findsOneWidget);
      expect(find.textContaining('严禁不文明', findRichText: true), findsOneWidget);
      expect(find.text('已关注'), findsOneWidget);
      expect(find.text('全部讨论'), findsOneWidget);
      expect(api.requests, contains(_discussion));
      final initialSortRowTop = tester.getTopLeft(find.text('全部讨论')).dy;
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        const Color(0xFF63643C),
      );
      await tester.tap(find.text('最新'));
      await _pump(tester);
      expect(api.requests, contains('$_discussion&sortField=dateline_desc'));
      expect(
        tester.getTopLeft(find.text('全部讨论')).dy,
        closeTo(initialSortRowTop, .1),
      );
      expect(find.text('全部讨论'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('热度'), findsOneWidget);

      final sortPill = find
          .ancestor(of: find.text('热度'), matching: find.byType(DecoratedBox))
          .last;
      expect(tester.getRect(sortPill).right, lessThanOrEqualTo(360));
      await tester.tap(find.text('热度'));
      await _pump(tester);
      expect(api.requests, contains('$_discussion&sortField=hot'));
      expect(
        tester.getTopLeft(find.text('全部讨论')).dy,
        closeTo(initialSortRowTop, .1),
      );
      expect(find.text('全部讨论'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('热度'), findsOneWidget);

      await tester.tap(find.text('默认'));
      await _pump(tester);
      expect(api.requests, contains(_discussion));
      expect(
        tester.getTopLeft(find.text('全部讨论')).dy,
        closeTo(initialSortRowTop, .1),
      );
      expect(find.text('全部讨论'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('热度'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _activityTest('open registration button launches the exact server form URL', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final api = ActivityApi()
      ..event = {
        'title': '众测测试',
        'stage_status': 1,
        'time_reg_start': now - 3600,
        'time_reg_end': now + 3600,
        'action_url': _registration,
      };
    await tester.pumpWidget(fixture.app(CrowdTestPage(api: api, id: '1086')));
    await _pump(tester);
    await tester.tap(find.text('立即报名'));
    await _pump(tester);
    expect(calls.where((call) => call.method == 'launch'), hasLength(1));
    final args = calls.single.arguments as Map;
    expect(args['url'], _registration);
    expect(args['useWebView'], isTrue);
    expect(args['headers'], isEmpty);
  });

  _activityTest(
    'waiting-for-list button is disabled and does not open signup',
    (tester) async {
      final api = ActivityApi()
        ..event = {
          'title': '最新众测',
          'stage_status': 2,
          'time_reg_end': 1792116000,
          'action_url': _registration,
        };
      await tester.pumpWidget(fixture.app(CrowdTestPage(api: api, id: '1086')));
      await _pump(tester);
      expect(find.text('活动进行中'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '暂未公布众测名单'),
      );
      expect(button.onPressed, isNull);
    },
  );
  _activityTest('event sponsor and prize arrays retain their visible content', (
    tester,
  ) async {
    final api = ActivityApi()
      ..event = {
        'title': '众测测试',
        'stage_status': 2,
        'sponsorUser': [
          {'uid': 434513, 'username': '酷安数码', 'userAvatar': ''},
        ],
        'sponsorPrize': [
          {'title': '荣耀Earbuds 4', 'logo': ''},
        ],
      };
    await tester.pumpWidget(fixture.app(CrowdTestPage(api: api, id: '1086')));
    await _pump(tester);
    expect(find.text('主办方'), findsOneWidget);
    expect(find.text('酷安数码'), findsOneWidget);
    expect(find.text('活动奖品'), findsOneWidget);
    expect(find.text('荣耀Earbuds 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
