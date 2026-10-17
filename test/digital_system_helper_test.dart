import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/features/digital/utils/digital_system_helper.dart';

void main() {
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
