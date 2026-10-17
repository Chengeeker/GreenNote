import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/utils/coolapk_url_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoolapkUrlHandler Tests', () {
    test('isCoolapkUrl recognizes valid Coolapk URLs and protocols', () {
      // Standard HTTP/HTTPS
      expect(CoolapkUrlHandler.isCoolapkUrl('https://coolapk.com/feed/12345'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('http://coolapk.com/feed/12345'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://m.coolapk.com/feed/67890'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://www.coolapk.com/u/10001'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://api.coolapk.com/v6/feed/detail'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://m.coolapk.com/product/123'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://m.coolapk.com/apk/com.coolapk.market'), isTrue);

      // Custom scheme
      expect(CoolapkUrlHandler.isCoolapkUrl('coolmarket://feed/12345'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('coolmarket://u/10001'), isTrue);
      expect(CoolapkUrlHandler.isCoolapkUrl('coolmarket://topic/测试话题'), isTrue);

      // Invalid / non-Coolapk URLs
      expect(CoolapkUrlHandler.isCoolapkUrl('https://www.bilibili.com/video/BV123'), isFalse);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://github.com/flutter/flutter'), isFalse);
      expect(CoolapkUrlHandler.isCoolapkUrl('https://notcoolapk.com'), isFalse);
      expect(CoolapkUrlHandler.isCoolapkUrl(''), isFalse);
      expect(CoolapkUrlHandler.isCoolapkUrl('   '), isFalse);
      expect(CoolapkUrlHandler.isCoolapkUrl('javascript:alert(1)'), isFalse);
    });
  });
}
