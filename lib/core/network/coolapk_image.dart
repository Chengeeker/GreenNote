import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'coolapk_api.dart';

const _browserUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

String normalizeCoolapkImageUrl(String value) {
  var source = value.trim();
  if (source.isEmpty) return '';
  if (source.startsWith('//')) source = 'https:$source';

  final parsed = Uri.tryParse(source);
  if (parsed != null && parsed.hasScheme) {
    if (!const ['http', 'https'].contains(parsed.scheme) ||
        parsed.host.isEmpty) {
      return '';
    }
    return parsed.scheme == 'http'
        ? parsed.replace(scheme: 'https').toString()
        : source;
  }

  if (source.startsWith('api.coolapk.com/') ||
      source.startsWith('api2.coolapk.com/') ||
      source.startsWith('image.coolapk.com/') ||
      source.startsWith('avatar.coolapk.com/')) {
    return 'https://$source';
  }
  final host = source.startsWith('/v6/')
      ? 'api.coolapk.com'
      : 'image.coolapk.com';
  return Uri.parse(
    'https://$host${source.startsWith('/') ? source : '/$source'}',
  ).toString();
}

Map<String, String> coolapkImageHeaders(String url, {CoolapkApi? api}) {
  final uri = Uri.tryParse(normalizeCoolapkImageUrl(url));
  if (uri != null &&
      (uri.host == 'api.coolapk.com' || uri.host == 'api2.coolapk.com') &&
      api != null) {
    return api.imageHeadersFor();
  }
  return const {
    'User-Agent': _browserUserAgent,
    'Referer': 'https://www.coolapk.com/',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };
}

/// Pre-caches a single Coolapk image into memory & disk cache.
void precacheCoolapkImage(
  String rawUrl,
  BuildContext context, {
  CoolapkApi? api,
}) {
  final url = normalizeCoolapkImageUrl(rawUrl);
  if (url.isEmpty) return;
  try {
    precacheImage(
      ExtendedNetworkImageProvider(
        url,
        headers: coolapkImageHeaders(url, api: api),
        cache: true,
      ),
      context,
    );
  } catch (_) {}
}

/// Pre-caches avatars and preview thumbnails for a list of feeds or cards
/// to make scrolling and card rendering instantaneous.
void precacheFeedImages(
  Iterable<dynamic> items,
  BuildContext context, {
  CoolapkApi? api,
  int maxItems = 8,
}) {
  var count = 0;
  for (final item in items) {
    if (count >= maxItems) break;
    count++;
    if (item is CoolapkFeed) {
      if (item.avatar.isNotEmpty) {
        precacheCoolapkImage(item.avatar, context, api: api);
      }
      if (item.pictures.isNotEmpty) {
        precacheCoolapkImage(item.pictures.first, context, api: api);
      }
    } else if (item is Map) {
      final avatar = (item['userAvatar'] ?? item['avatar'] ?? '').toString();
      if (avatar.isNotEmpty) {
        precacheCoolapkImage(avatar, context, api: api);
      }
      final pic = (item['pic'] ?? item['cover'] ?? '').toString();
      if (pic.isNotEmpty) {
        precacheCoolapkImage(pic, context, api: api);
      } else {
        final picArr = item['picArr'];
        if (picArr is List && picArr.isNotEmpty) {
          final firstPic = picArr.first.toString();
          if (firstPic.isNotEmpty) {
            precacheCoolapkImage(firstPic, context, api: api);
          }
        }
      }
    }
  }
}

class HdrImageDetector {
  static final Set<String> _knownHdrUrls = <String>{};
  static final Set<String> _checkingHdrUrls = <String>{};
  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static bool isKnownHdr(String url) {
    if (url.isEmpty) return false;
    final normalized = normalizeCoolapkImageUrl(url);
    return _knownHdrUrls.contains(url) || _knownHdrUrls.contains(normalized);
  }

  static void markHdr(String url) {
    if (url.isEmpty) return;
    final normalized = normalizeCoolapkImageUrl(url);
    final added1 = _knownHdrUrls.add(url);
    final added2 = _knownHdrUrls.add(normalized);
    if (added1 || added2) {
      notifier.value++;
    }
  }

  static bool checkBytes(List<int> bytes) {
    if (bytes.length < 16) return false;
    final checkLen = math.min(bytes.length, 131072);
    final header = String.fromCharCodes(bytes.sublist(0, checkLen))
        .toLowerCase();
    return header.contains('hdrgm') ||
        header.contains('hdr-gain-map') ||
        header.contains('21496:1') ||
        header.contains('21496:-1') ||
        header.contains('gainmap') ||
        header.contains('ultrahdr');
  }

  static Future<void> detectFromCache(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (url.isEmpty || isKnownHdr(url)) return;
    final normalized = normalizeCoolapkImageUrl(url);
    if (normalized.isEmpty || isKnownHdr(normalized)) return;
    if (!_checkingHdrUrls.add(normalized)) return;
    try {
      Uint8List? data;
      try {
        data = await ExtendedNetworkImageProvider(
          url,
          headers: headers,
          cache: true,
          printError: false,
        ).getNetworkImageData();
      } catch (_) {}
      if (data == null && normalized != url) {
        try {
          data = await ExtendedNetworkImageProvider(
            normalized,
            headers: headers,
            cache: true,
            printError: false,
          ).getNetworkImageData();
        } catch (_) {}
      }
      if (data != null && checkBytes(data)) {
        markHdr(url);
      }
    } catch (_) {
    } finally {
      _checkingHdrUrls.remove(normalized);
    }
  }

  @visibleForTesting
  static void reset() {
    _knownHdrUrls.clear();
    _checkingHdrUrls.clear();
    notifier.value = 0;
  }
}
