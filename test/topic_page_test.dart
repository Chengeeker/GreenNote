import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/shared/api_list_page.dart';

class _MockCoolapkApi extends Fake implements CoolapkApi {
  @override
  Future<Map<String, dynamic>> getTopicDetail(String tag) async {
    if (tag.contains('ColorOS')) {
      return {
        'data': {
          'title': 'ColorOS17',
          'tag': 'ColorOS17',
          'logo': 'http://image.coolapk.com/logo_coloros.png',
          'cover': 'http://image.coolapk.com/cover_coloros.png',
          'follow_num': '48000',
          'feed_num': '34000',
          'hot_num_txt': '226.0万热度',
        },
      };
    }
    if (tag.contains('柔光玻璃')) {
      return {
        'data': {
          'title': 'HyperOS4柔光玻璃',
          'tag': 'HyperOS4柔光玻璃',
          'logo': 'http://image.coolapk.com/logo_glass.png',
          'creator_name': '叫我小张',
          'follow_num': '30',
          'feed_num': '184',
          'hot_num_txt': '8055热度',
          'description': '随光而变的柔光玻璃，随心编排的空间，处处顺手的柔性框架。',
        },
      };
    }
    return {
      'data': {
        'title': tag,
        'tag': tag,
        'follow_num': '100',
        'feed_num': '50',
      },
    };
  }

  @override
  Future<ApiPage> getList(String path, {Map<String, dynamic>? query}) async {
    return const ApiPage(
      items: [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }
}

void main() {
  group('System & Feature Topic Profile Tests', () {
    test('resolveSystemProfile identifies ColorOS 17 with 8 dimensions and purple atmosphere', () {
      final profile = resolveSystemProfile('ColorOS17', 'ColorOS17');
      expect(profile.isSystem, isTrue);
      expect(profile.hasRating, isTrue);
      expect(profile.score, 9.4);
      expect(profile.dimensions.length, 8);
      expect(profile.dimensions, contains('美观度'));
      expect(profile.dimensions, contains('流畅性'));
      expect(profile.dimensions, contains('更新维护'));
      expect(profile.activityTitle, contains('宝藏功能大赏'));
      expect(profile.brandName, contains('OPPO'));
      expect(profile.primaryBg, const Color(0xFF18102A));
    });

    test('resolveSystemProfile identifies HyperOS4柔光玻璃 as feature with 5-star distribution', () {
      final profile = resolveSystemProfile('HyperOS4柔光玻璃', 'HyperOS4柔光玻璃');
      expect(profile.isSystem, isFalse);
      expect(profile.isFeature, isTrue);
      expect(profile.hasRating, isTrue);
      expect(profile.score, 9.6);
      expect(profile.starCounts.length, 5);
      expect(profile.starCounts[0], 24); // 5-star count
      expect(profile.primaryBg, const Color(0xFF13161C));
    });

    test('resolveSystemProfile identifies OriginOS, HarmonyOS, iOS, One UI, Flyme', () {
      final origin = resolveSystemProfile('OriginOS 5', 'OriginOS 5');
      expect(origin.isSystem, isTrue);
      expect(origin.score, 9.5);
      expect(origin.brandName, contains('vivo'));

      final harmony = resolveSystemProfile('HarmonyOS NEXT', 'HarmonyOS NEXT');
      expect(harmony.isSystem, isTrue);
      expect(harmony.score, 9.5);
      expect(harmony.brandName, contains('华为'));

      final ios = resolveSystemProfile('iOS 18', 'iOS 18');
      expect(ios.isSystem, isTrue);
      expect(ios.score, 9.4);
      expect(ios.brandName, 'Apple');

      final oneui = resolveSystemProfile('One UI 7', 'One UI 7');
      expect(oneui.isSystem, isTrue);
      expect(oneui.score, 9.3);

      final flyme = resolveSystemProfile('Flyme 11', 'Flyme 11');
      expect(flyme.isSystem, isTrue);
      expect(flyme.score, 9.3);
    });

    test('resolveSystemProfile identifies feature topics: 灵动岛, 流体云, 自由小窗', () {
      final island = resolveSystemProfile('灵动岛', '灵动岛');
      expect(island.hasRating, isTrue);
      expect(island.isFeature, isTrue);

      final fluid = resolveSystemProfile('流体云', '流体云');
      expect(fluid.hasRating, isTrue);
      expect(fluid.isFeature, isTrue);

      final window = resolveSystemProfile('自由小窗', '自由小窗');
      expect(window.hasRating, isTrue);
      expect(window.isFeature, isTrue);
    });

    test('resolveSystemProfile returns plain profile for normal topic', () {
      final plain = resolveSystemProfile('日常摄影', '日常摄影');
      expect(plain.isSystem, isFalse);
      expect(plain.isFeature, isFalse);
      expect(plain.hasRating, isFalse);
    });
  });

  group('TopicPage Widget Tests', () {
    testWidgets('renders ColorOS17 system topic with 8-dimension rating card and 4 tabs', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: TopicPage(
            api: mockApi,
            tag: 'ColorOS17',
            initialTitle: 'ColorOS17',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check title and rating elements
      expect(find.text('ColorOS17'), findsWidgets);
      expect(find.text('酷安评分'), findsOneWidget);
      expect(find.text('9.4'), findsAtLeastNWidgets(1));
      expect(find.text('用户评分'), findsOneWidget);

      // Check 8-dimension items
      expect(find.text('美观度'), findsOneWidget);
      expect(find.text('流畅性'), findsOneWidget);
      expect(find.text('更新维护'), findsOneWidget);

      // Check tabs for OS: 新特性, 讨论, 机型区, 点评
      expect(find.text('新特性'), findsOneWidget);
      expect(find.text('讨论'), findsOneWidget);
      expect(find.text('机型区'), findsOneWidget);
      expect(find.text('点评'), findsOneWidget);

      // Check sub-filter row: 全部讨论 and 默认/最新/热度
      expect(find.text('全部讨论'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('热度'), findsOneWidget);

      // Check FAB
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('renders HyperOS4柔光玻璃 feature topic with 5-star distribution and 2 tabs', (tester) async {
      final mockApi = _MockCoolapkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: TopicPage(
            api: mockApi,
            tag: 'HyperOS4柔光玻璃',
            initialTitle: 'HyperOS4柔光玻璃',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check title and rating elements
      expect(find.text('HyperOS4柔光玻璃'), findsWidgets);
      expect(find.text('酷安评分'), findsOneWidget);
      expect(find.text('9.6'), findsOneWidget);

      // Check 5-star distribution rows
      expect(find.text('5星'), findsOneWidget);
      expect(find.text('4星'), findsOneWidget);
      expect(find.text('1星'), findsOneWidget);

      // Check tabs for feature: 讨论, 点评
      expect(find.text('讨论'), findsOneWidget);
      expect(find.text('点评'), findsOneWidget);
      expect(find.text('机型区'), findsNothing);

      // Check creator row
      expect(find.textContaining('叫我小张 创建'), findsOneWidget);
    });
  });
}
