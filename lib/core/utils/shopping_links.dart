import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

String goodsTarget(Map<String, dynamic> item) {
  for (final key in ['goods_url', 'goods_buy_url', 'url']) {
    final value = '${item[key] ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

Future<bool> launchShoppingUrl(Uri uri) async {
  for (var depth = 0; depth < 5; depth++) {
    if (!(uri.host == 'coolapk.com' || uri.host.endsWith('.coolapk.com')) ||
        uri.path != '/link') {
      break;
    }
    final nested = Uri.tryParse(uri.queryParameters['url'] ?? '');
    if (nested == null || !nested.hasScheme) break;
    uri = nested;
  }
  if (![
        'https',
        'http',
        'openapp.jdmobile',
        'taobao',
        'pinduoduo',
      ].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  try {
    if (await const MethodChannel('com.green.note/links')
            .invokeMethod<bool>('openShoppingLink', uri.toString()) ==
        true) {
      return true;
    }
  } on MissingPluginException {
    // Other hosts can still open the original URL.
  } on PlatformException {
    // Keep the original destination when the shopping app is unavailable.
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
