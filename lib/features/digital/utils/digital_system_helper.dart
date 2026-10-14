import 'dart:async';

import '../../../core/network/coolapk_api.dart';

class DigitalProductInfo {
  const DigitalProductInfo({
    this.logo,
    this.productId,
    this.title,
    this.score,
    this.commentCount,
  });

  final String? logo;
  final String? productId;
  final String? title;
  final double? score;
  final String? commentCount;
}

class DigitalSystemHelper {
  static final Map<String, DigitalProductInfo> _deviceInfoCache = {};
  static final Map<String, DigitalProductInfo> _systemInfoCache = {};

  /// Known official Coolapk CDN logos for major mobile operating systems.
  static final Map<String, String> _presetSystemLogos = {
    'originos': 'http://image.coolapk.com/feed_tag/2026/0911/15/20260911-152643-127887-o_1k27lphhmdpnkrph8sms17071v-uid-658442@1080x1080.png',
    'hyperos': 'http://image.coolapk.com/feed_tag/2023/1026/16/20231026-161822-680482-o_1hd8e5gvi1qbb1l2e1kspk0c1q7g1a-uid-1060130@1080x1080.png',
    'coloros': 'http://image.coolapk.com/feed_tag/2023/1116/17/20231116-173629-873619-o_1hf77f24p171f11q91f3v100p10m81a-uid-453007@1080x1080.png',
    'harmonyos': 'http://image.coolapk.com/feed_tag/2024/0118/16/20240118-164741-943015-o_1hki865j51p1m131n1g9k165i1uon1a-uid-453007@1080x1080.png',
    'magicos': 'http://image.coolapk.com/feed_tag/2024/0111/16/20240111-164539-748439-o_1hk3o5k9v1v4u101u17s91q2j1j5v1a-uid-453007@1080x1080.png',
    'oneui': 'http://image.coolapk.com/feed_tag/2024/0118/16/20240118-163236-407632-o_1hki77jov1sqb13e91u5r173413861a-uid-453007@1080x1080.png',
    'realmeui': 'http://image.coolapk.com/feed_tag/2023/1208/17/20231208-171850-241517-o_1hhaek9a81e3s1e7q1i5r17091q421a-uid-453007@1080x1080.png',
    'flyme': 'http://image.coolapk.com/feed_tag/2023/1130/17/20231130-175231-866418-o_1hgh01fhn1v3i1g5g1bfl1l4b1l4c1a-uid-453007@1080x1080.png',
    'ios': 'http://image.coolapk.com/feed_tag/2024/0611/09/20240611-094132-841961-o_1i05q40j0109919f91a561g2c199k1a-uid-453007@1080x1080.png',
    'android': 'http://image.coolapk.com/feed_tag/2023/0511/10/20230511-100412-887714-o_1h04d3j5e1o161c6h1h9k1l1h1a-uid-453007@1080x1080.png',
    'redmagic': 'http://image.coolapk.com/feed_tag/2023/1124/15/20231124-152843-855734-o_1hfs9f7431e217vd1lre13g318261a-uid-453007@1080x1080.png',
    'rog': 'http://image.coolapk.com/feed_tag/2023/0414/15/20230414-153825-976451-o_1gu1evpfe1329b3c10cf17c1m191a-uid-453007@1080x1080.png',
    'moto': 'http://image.coolapk.com/feed_tag/2023/0602/15/20230602-152014-984443-o_1h1u9c6jh1s931j22b8214191s5j1a-uid-453007@1080x1080.png',
  };

  /// Returns preset official Coolapk logo for a given system name/title if recognized.
  static String? getSystemPresetLogo(String systemName) {
    final lower = systemName
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    if (lower.isEmpty) return null;

    if (lower.contains('originos') ||
        lower.contains('funtouch') ||
        lower.contains('vivo') ||
        lower.contains('iqoo')) {
      return _presetSystemLogos['originos'];
    }
    if (lower.contains('hyperos') ||
        lower.contains('澎湃') ||
        lower.contains('miui') ||
        lower.contains('xiaomi')) {
      return _presetSystemLogos['hyperos'];
    }
    if (lower.contains('coloros') ||
        lower.contains('oppo') ||
        lower.contains('oneplus') ||
        lower.contains('一加')) {
      return _presetSystemLogos['coloros'];
    }
    if (lower.contains('harmonyos') ||
        lower.contains('鸿蒙') ||
        lower.contains('emui') ||
        lower.contains('huawei')) {
      return _presetSystemLogos['harmonyos'];
    }
    if (lower.contains('magicos') ||
        lower.contains('magicui') ||
        lower.contains('honor') ||
        lower.contains('荣耀')) {
      return _presetSystemLogos['magicos'];
    }
    if (lower.contains('oneui') ||
        lower.contains('samsung') ||
        lower.contains('三星')) {
      return _presetSystemLogos['oneui'];
    }
    if (lower.contains('realme') || lower.contains('真我')) {
      return _presetSystemLogos['realmeui'];
    }
    if (lower.contains('flyme') ||
        lower.contains('meizu') ||
        lower.contains('魅族')) {
      return _presetSystemLogos['flyme'];
    }
    if (lower.contains('ios') ||
        lower.contains('ipados') ||
        lower.contains('apple') ||
        lower.contains('苹果')) {
      return _presetSystemLogos['ios'];
    }
    if (lower.contains('redmagic') ||
        lower.contains('红魔') ||
        lower.contains('nubia') ||
        lower.contains('努比亚')) {
      return _presetSystemLogos['redmagic'];
    }
    if (lower.contains('rog') ||
        lower.contains('asus') ||
        lower.contains('华硕') ||
        lower.contains('zenui')) {
      return _presetSystemLogos['rog'];
    }
    if (lower.contains('moto') ||
        lower.contains('myui') ||
        lower.contains('lenovo') ||
        lower.contains('联想')) {
      return _presetSystemLogos['moto'];
    }
    if (lower.contains('aosp') ||
        lower.contains('原生') ||
        lower.contains('pixel') ||
        lower.contains('lineage') ||
        lower.contains('android')) {
      return _presetSystemLogos['android'];
    }
    return null;
  }

  /// Resolves the device's official product picture, ID, score and comment count from Coolapk.
  static Future<DigitalProductInfo> resolveDeviceProduct(
    CoolapkApi api,
    String deviceName,
  ) async {
    final query = deviceName.trim();
    if (query.isEmpty) return const DigitalProductInfo();

    if (_deviceInfoCache.containsKey(query)) {
      return _deviceInfoCache[query]!;
    }

    try {
      final res = await api.getList(
        '/v6/search',
        query: {'type': 'product', 'searchValue': query, 'page': 1},
      );
      for (final item in res.items) {
        final logo =
            (item['logo'] ?? item['cover'] ?? item['pic'] ?? item['icon'] ?? '')
                .toString()
                .trim();
        final id = (item['id'] ?? item['productId'] ?? '').toString().trim();
        final title = (item['title'] ?? item['name'] ?? '').toString().trim();
        final scoreRaw =
            (item['star_average_score'] ??
                    item['score'] ??
                    item['star_score'] ??
                    '')
                .toString()
                .trim();
        final score = double.tryParse(scoreRaw);
        final commentCount =
            (item['feedCommentNumTxt'] ??
                    item['feed_comment_num'] ??
                    item['commentnum'] ??
                    item['commentNum'] ??
                    item['hot_num_txt'] ??
                    '')
                .toString()
                .trim();

        if (logo.isNotEmpty || id.isNotEmpty) {
          final info = DigitalProductInfo(
            logo: logo.isNotEmpty ? logo : null,
            productId: id.isNotEmpty ? id : null,
            title: title.isNotEmpty ? title : null,
            score: score,
            commentCount: commentCount.isNotEmpty ? commentCount : null,
          );
          _deviceInfoCache[query] = info;
          return info;
        }
      }
    } catch (_) {}

    return const DigitalProductInfo();
  }

  /// Resolves the official system logo, score and comment count from Coolapk.
  static Future<DigitalProductInfo> resolveSystemProduct(
    CoolapkApi api,
    String systemName,
  ) async {
    final query = systemName.trim();
    if (query.isEmpty) return const DigitalProductInfo();

    if (_systemInfoCache.containsKey(query)) {
      return _systemInfoCache[query]!;
    }

    final presetLogo = getSystemPresetLogo(query);

    // 1. First attempt: search product catalog (many ROMs have full rating cards)
    try {
      final res = await api.getList(
        '/v6/search',
        query: {'type': 'product', 'searchValue': query, 'page': 1},
      );
      for (final item in res.items) {
        final logo =
            (item['logo'] ?? item['cover'] ?? item['pic'] ?? item['icon'] ?? '')
                .toString()
                .trim();
        final id = (item['id'] ?? item['productId'] ?? '').toString().trim();
        final title = (item['title'] ?? item['name'] ?? '').toString().trim();
        final scoreRaw =
            (item['star_average_score'] ??
                    item['score'] ??
                    item['star_score'] ??
                    '')
                .toString()
                .trim();
        final score = double.tryParse(scoreRaw);
        final commentCount =
            (item['feedCommentNumTxt'] ??
                    item['feed_comment_num'] ??
                    item['commentnum'] ??
                    item['commentNum'] ??
                    item['hot_num_txt'] ??
                    '')
                .toString()
                .trim();

        if (logo.isNotEmpty || id.isNotEmpty || score != null) {
          final info = DigitalProductInfo(
            logo: logo.isNotEmpty ? logo : presetLogo,
            productId: id.isNotEmpty ? id : null,
            title: title.isNotEmpty ? title : null,
            score: score,
            commentCount: commentCount.isNotEmpty ? commentCount : null,
          );
          _systemInfoCache[query] = info;
          return info;
        }
      }
    } catch (_) {}

    // 2. Second attempt: search topic catalog
    try {
      final res = await api.getList(
        '/v6/search',
        query: {'type': 'feedTopic', 'searchValue': query, 'page': 1},
      );
      for (final item in res.items) {
        final logo =
            (item['logo'] ?? item['cover'] ?? item['pic'] ?? item['icon'] ?? '')
                .toString()
                .trim();
        final id = (item['tag'] ?? item['id'] ?? '').toString().trim();
        final title = (item['title'] ?? item['name'] ?? '').toString().trim();
        final scoreRaw = (item['score'] ?? '').toString().trim();
        final score = double.tryParse(scoreRaw);
        final commentCount =
            (item['commentnum'] ??
                    item['feed_comment_num'] ??
                    item['hot_num_txt'] ??
                    '')
                .toString()
                .trim();

        final resolvedLogo = logo.isNotEmpty ? logo : presetLogo;
        if (resolvedLogo != null || id.isNotEmpty) {
          final info = DigitalProductInfo(
            logo: resolvedLogo,
            productId: id.isNotEmpty ? id : null,
            title: title.isNotEmpty ? title : null,
            score: score,
            commentCount: commentCount.isNotEmpty ? commentCount : null,
          );
          _systemInfoCache[query] = info;
          return info;
        }
      }
    } catch (_) {}

    // 3. Fallback to preset
    if (presetLogo != null) {
      final info = DigitalProductInfo(logo: presetLogo);
      _systemInfoCache[query] = info;
      return info;
    }

    return const DigitalProductInfo();
  }
}
