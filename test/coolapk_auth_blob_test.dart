import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';

class _MissingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('missing');
}

void main() {
  test(
    'a checkout without the local auth asset can still initialize config',
    () async {
      expect(await loadCoolapkAuthBlob(_MissingAssetBundle()), isEmpty);
    },
  );
}
