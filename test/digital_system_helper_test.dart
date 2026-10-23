import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/digital/utils/digital_system_helper.dart';

class _SystemSearchApi extends Fake implements CoolapkApi {
  _SystemSearchApi(this.products, [this.topics = const []]);
  final List<Map<String, dynamic>> products, topics;
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async => ApiPage(
    items: query['type'] == 'product' ? products : topics,
    page: 1,
    hasMore: false,
    firstItem: '',
    lastItem: '',
  );
}

void main() {
  test(
    'system lookup rejects phone and other OS version before matching ROM',
    () async {
      final api = _SystemSearchApi([
        {'id': 'phone', 'title': 'vivo X300 Pro', 'logo': 'phone.png'},
        {'id': 'old-os', 'title': 'OriginOS 8', 'score': '9'},
        {'id': 'correct-os', 'title': 'OriginOS 9', 'score': '8'},
      ]);
      final info = await DigitalSystemHelper.resolveSystemProduct(
        api,
        'OriginOS 9.3',
      );
      expect(info.productId, 'correct-os');
      expect(info.title, 'OriginOS 9');
    },
  );

  test(
    'system topic fallback keeps its entity type and HarmonyOS alias',
    () async {
      final api = _SystemSearchApi(
        [
          {'id': 'phone', 'title': '华为 Mate 90', 'logo': 'phone.png'},
        ],
        [
          {'id': 'wrong', 'title': 'iOS 27'},
          {'id': 'topic-id', 'title': '鸿蒙8', 'tag': '鸿蒙8'},
        ],
      );
      final info = await DigitalSystemHelper.resolveSystemProduct(
        api,
        'HarmonyOS 8',
      );
      expect(info.productId, isNull);
      expect(info.topicTag, '鸿蒙8');
    },
  );

  test('unmatched system search never uses a phone as a fallback', () async {
    final api = _SystemSearchApi([
      {'id': 'phone', 'title': '小米17 Pro', 'logo': 'phone.png'},
    ]);
    final info = await DigitalSystemHelper.resolveSystemProduct(
      api,
      'Android 99',
    );
    expect(info.productId, isNull);
    expect(info.title, isNull);
  });
  group('DigitalSystemHelper Tests', () {
    test('getSystemPresetLogo identifies all major mobile systems', () {
      expect(DigitalSystemHelper.getSystemPresetLogo('OriginOS 7'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('OriginOS'), isNotNull);
      expect(
        DigitalSystemHelper.getSystemPresetLogo('vivo OriginOS 5'),
        isNotNull,
      );
      expect(DigitalSystemHelper.getSystemPresetLogo('HyperOS 2.0'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('小米澎湃OS'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('ColorOS 15'), isNotNull);
      expect(
        DigitalSystemHelper.getSystemPresetLogo('HarmonyOS NEXT'),
        isNotNull,
      );
      expect(DigitalSystemHelper.getSystemPresetLogo('华为鸿蒙4.2'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('MagicOS 9'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('One UI 7'), isNotNull);
      expect(
        DigitalSystemHelper.getSystemPresetLogo('realme UI 6.0'),
        isNotNull,
      );
      expect(DigitalSystemHelper.getSystemPresetLogo('Flyme 11'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('iOS 18'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('Android 15'), isNotNull);
      expect(DigitalSystemHelper.getSystemPresetLogo('Pixel 原生'), isNotNull);
    });

    test('getSystemPresetLogo returns null for unknown names', () {
      expect(DigitalSystemHelper.getSystemPresetLogo(''), isNull);
      expect(
        DigitalSystemHelper.getSystemPresetLogo('SomeUnknownCustomOS'),
        isNull,
      );
    });
  });
}
