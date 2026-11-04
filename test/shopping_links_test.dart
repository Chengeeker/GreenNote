import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/utils/shopping_links.dart';
import 'package:greennote/features/shared/api_list_page.dart';

import 'discovery_channel_test.dart' show DiscoveryApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('com.green.note/links');
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final nativeUrls = <String>[];
  final webUrls = <String>[];
  var available = true;
  setUp(() {
    nativeUrls.clear();
    webUrls.clear();
    available = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
          nativeUrls.add(call.arguments as String);
          return available;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          webUrls.add(call.arguments['url'] as String);
          return true;
        });
  });
  tearDown(() {
    for (final channel in [native, launcher]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  test(
    'app first, preserves coupon query, web fallback and unsafe rejection',
    () async {
      const url = 'https://u.jd.com/example?coupon=123&sku=456';
      expect(
        await launchShoppingUrl(
          Uri.https('www.coolapk.com', '/link', {'url': url}),
        ),
        isTrue,
      );
      expect(nativeUrls, [url]);
      expect(webUrls, isEmpty);
      available = false;
      expect(await launchShoppingUrl(Uri.parse(url)), isTrue);
      expect(webUrls, [url]);
      expect(
        await launchShoppingUrl(Uri.parse('https://evil@jd.com/x')),
        isFalse,
      );
      expect(
        await launchShoppingUrl(Uri.parse('javascript:alert(1)')),
        isFalse,
      );
      expect(nativeUrls, hasLength(2));
    },
  );
  testWidgets('secondary pear goods opens buy URL when goods URL is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiEntityCard(
            api: DiscoveryApi(),
            entity: const {
              'entityType': 'pear_goods',
              'goods_title': '专属礼金商品',
              'goods_url': '',
              'goods_buy_url': 'https://u.jd.com/coupon?sku=123',
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('专属礼金商品'));
    await tester.pump();
    expect(nativeUrls, ['https://u.jd.com/coupon?sku=123']);
    expect(webUrls, isEmpty);
  });
}
