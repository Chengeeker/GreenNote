import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../network/coolapk_api.dart';
import '../utils/app_toast.dart';
import '../../features/feed/feed_pages.dart';
import '../../features/shared/api_list_page.dart';
import '../../features/shared/app_detail_page.dart';
import '../../features/shared/community_routes.dart';
import '../../features/shared/in_app_browser_page.dart';

String decodeCoolapkComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

String feedIdFromCoolapkUrl(String raw) {
  var url = raw.trim();
  if (url.startsWith('#/')) url = url.substring(1);
  final uri = Uri.tryParse(url);
  if (uri == null || uri.userInfo.isNotEmpty) return '';
  final official =
      uri.scheme == 'coolmarket' ||
      (!uri.hasAuthority && uri.scheme.isEmpty) ||
      (['http', 'https'].contains(uri.scheme) &&
          (uri.host == 'coolapk.com' || uri.host.endsWith('.coolapk.com')));
  if (!official) return '';
  final segments = [
    if (uri.scheme == 'coolmarket') uri.host,
    ...uri.pathSegments,
  ];
  if (segments.isEmpty ||
      segments.length > 2 ||
      !['feed', 'picture'].contains(segments.first)) {
    return '';
  }
  final id = segments.length == 2 && segments[1] != 'detail'
      ? segments[1]
      : uri.queryParameters['id'] ?? '';
  return RegExp(r'^[1-9]\d*$').hasMatch(id) ? id : '';
}

/// 酷安链接解析与全局分发路由
class CoolapkUrlHandler {
  const CoolapkUrlHandler._();

  static const _channel = MethodChannel('com.green.note/links');
  static bool _initialized = false;

  /// 初始化原生 Deep Link 监听（冷启动 + 热启动）
  static void initLinkListener(CoolapkApi api) {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink' && call.arguments is String) {
        final link = (call.arguments as String).trim();
        if (link.isNotEmpty) {
          await handleUrl(rootNavigatorKey.currentContext, api, link);
        }
      }
    });

    _channel
        .invokeMethod<String>('getInitialLink')
        .then((initial) {
          if (initial != null && initial.trim().isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              handleUrl(rootNavigatorKey.currentContext, api, initial.trim());
            });
          }
        })
        .catchError((_) {});
  }

  /// 判断是否为酷安官方链接或协议
  static bool isCoolapkUrl(String url) {
    final clean = url.trim().toLowerCase();
    if (clean.isEmpty) return false;
    if (clean.startsWith('coolmarket://')) return true;
    if (clean.startsWith('/')) return true;

    final uri = Uri.tryParse(clean);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'coolapk.com' ||
        host == 'm.coolapk.com' ||
        host == 'www.coolapk.com' ||
        host.endsWith('.coolapk.com');
  }

  /// 打开任意链接（酷安链接在应用内原生展示，网页链接在内置浏览器中打开）
  static Future<bool> handleUrl(
    BuildContext? context,
    CoolapkApi api,
    String rawUrl,
  ) async {
    var url = rawUrl.trim();
    if (url.isEmpty) return false;

    if (url.startsWith('#/')) url = url.substring(1);
    if (RegExp(r'^(feed|picture|u|user|t|topic|product|collection)/')
        .hasMatch(url)) {
      url = '/$url';
    }
    if (url.startsWith('/')) {
      url = 'https://www.coolapk.com$url';
    }

    final targetContext = context ?? rootNavigatorKey.currentContext;

    // HTTP(S) pages stay in-app; native Coolapk destinations are resolved below.
    if (!isCoolapkUrl(url)) {
      final uri = Uri.tryParse(url);
      if (uri != null && ['http', 'https'].contains(uri.scheme)) {
        if (targetContext == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return false;
        }
        Navigator.of(targetContext).push<void>(
          MaterialPageRoute(builder: (_) => InAppBrowserPage(url: url)),
        );
        return true;
      }
      if (uri == null || !['mailto', 'tel'].contains(uri.scheme)) return false;
      try {
        return await launchUrlString(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }

    if (targetContext == null) return false;
    final specialized = communityPageForUrl(api, url);
    if (specialized != null) {
      Navigator.of(targetContext)
          .push<void>(MaterialPageRoute(builder: (_) => specialized));
      return true;
    }

    // 2. 解析实体并进入对应原生页面
    final full = url;

    // 2.1 动态 / 图文 (Feed / Picture)
    // 匹配: /feed/12345, /picture/12345, coolmarket://feed/12345, coolmarket://feed/detail?id=12345
    final feedId = feedIdFromCoolapkUrl(full);
    if (feedId.isNotEmpty) {
      final id = feedId;
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FeedDetailPage(
            api: api,
            feed: CoolapkFeed.fromJson({'id': id, 'message': ''}),
          ),
        ),
      );
      return true;
    }

    // 2.2 用户主页 (User / Space)
    // 匹配: /u/12345, /u/username, /user/12345, coolmarket://u/12345
    final userRegex = RegExp(
      r'(?:/u/|/user/|coolmarket://u/|coolmarket://user/)([^/?#]+)',
      caseSensitive: false,
    );
    final userMatch = userRegex.firstMatch(full);
    if (userMatch != null) {
      final uid = decodeCoolapkComponent(userMatch.group(1)!).trim();
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UserSpacePage(api: api, uid: uid),
        ),
      );
      return true;
    }

    // 2.3 话题 / Tag (Topic / Super Topic)
    // 匹配: /t/xxx, /topic/xxx, coolmarket://topic/xxx
    final topicRegex = RegExp(
      r'(?:/t/|/topic/|coolmarket://topic/)([^/?#]+)',
      caseSensitive: false,
    );
    final topicMatch = topicRegex.firstMatch(full);
    if (topicMatch != null) {
      final tagRaw = topicMatch.group(1)!;
      final tag = decodeCoolapkComponent(tagRaw);
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicPage(api: api, tag: tag),
        ),
      );
      return true;
    }

    // 2.4 机型 / 数码产品 (Product)
    // 匹配: /product/12345, /product?id=12345, coolmarket://product/12345
    final productRegex = RegExp(
      r'(?:/product/|/product\?.*id=|coolmarket://product/)(\d+)',
      caseSensitive: false,
    );
    final productMatch = productRegex.firstMatch(full);
    if (productMatch != null) {
      final id = productMatch.group(1)!;
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProductPage(api: api, id: id, title: '机型详情'),
        ),
      );
      return true;
    }

    // 2.5 应用 / APK / 游戏 (App)
    // 匹配: /apk/com.example.app, /game/com.example.app, coolmarket://apk/com.example.app
    final appRegex = RegExp(
      r'(?:/apk/|/game/|coolmarket://apk/)([^/?#]+)',
      caseSensitive: false,
    );
    final appMatch = appRegex.firstMatch(full);
    if (appMatch != null) {
      final pkg = appMatch.group(1)!;
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AppDetailPage(api: api, id: pkg),
        ),
      );
      return true;
    }

    // Unmatched Coolapk web pages use the same browser without guessing a native route.
    final uri = Uri.tryParse(url);
    if (uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.userInfo.isEmpty) {
      Navigator.of(targetContext).push<void>(
        MaterialPageRoute(builder: (_) => InAppBrowserPage(url: url)),
      );
      return true;
    }
    return false;
  }
}
