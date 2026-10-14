import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';

import 'coolapk_image.dart';

Future<Uint8List> loadCoolapkAuthBlob(AssetBundle bundle) async {
  try {
    return base64.decode(
      (await bundle.loadString('assets/coolapk_auth_blob.b64')).trim(),
    );
  } on FlutterError {
    return Uint8List(0);
  }
}

final coolapkApiProvider = FutureProvider<CoolapkApi>((ref) async {
  return CoolapkApi.create();
});

class CoolapkApi {
  CoolapkApi._(this._dio, this._auth, this._secureStorage, this._cookie);

  static const _apiCode = 2604201;
  static const _apiVersion = '16.2.0';
  final Dio _dio;
  final _CoolapkAuth _auth;
  final FlutterSecureStorage _secureStorage;
  String _cookie;
  String _currentUid = '';
  String _currentUserAvatar = '';
  Future<Map<String, String>>? _homeTabRoutes;
  Future<Map<String, dynamic>>? _mainInit;

  static Future<CoolapkApi> create() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceCode = preferences.getString('guest_device_code');
    if (deviceCode == null || deviceCode.isEmpty) {
      deviceCode = _newUuid();
      await preferences.setString('guest_device_code', deviceCode);
    }
    final auth = _CoolapkAuth(
      deviceCode,
      await loadCoolapkAuthBlob(rootBundle),
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.coolapk.com',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'User-Agent': 'CoolMarket/$_apiVersion-$_apiCode-universal',
          'X-App-Id': 'com.coolapk.market',
          'X-App-Version': _apiVersion,
          'X-App-Code': '$_apiCode',
          'X-App-Supported': '$_apiCode',
          'X-Api-Version': '16',
          'X-App-Device': deviceCode,
          'X-Dark-Mode': '0',
          'X-App-Mode': 'universal',
          'X-App-Channel': 'coolapk',
          'X-Sdk-Int': '36',
          'X-Sdk-Locale': 'zh-CN',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.maxConnectionsPerHost = 32;
        client.idleTimeout = const Duration(seconds: 30);
        client.connectionTimeout = const Duration(seconds: 15);
        return client;
      },
    );
    const secureStorage = FlutterSecureStorage();
    return CoolapkApi._(
      dio,
      auth,
      secureStorage,
      await secureStorage.read(key: 'coolapk_cookie') ?? '',
    );
  }

  bool get hasCookie => _cookie.isNotEmpty;
  String get currentUid => _currentUid;
  String get currentUserAvatar => _currentUserAvatar;

  Map<String, String> imageHeadersFor() {
    final headers = <String, String>{
      for (final entry in _dio.options.headers.entries)
        entry.key: entry.value.toString(),
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'X-Requested-With': 'XMLHttpRequest',
      'X-App-Token': _auth.token(),
      'Referer': 'https://www.coolapk.com/',
    };
    if (_cookie.isNotEmpty) headers['Cookie'] = _cookie;
    return headers;
  }

  Future<void> saveCookie(String cookie) async {
    final value = cookie.trim();
    if (value.isEmpty) throw const CoolapkApiException('Cookie 不能为空');
    if (value.contains('\r') || value.contains('\n')) {
      throw const CoolapkApiException('Cookie 格式无效');
    }
    await _secureStorage.write(key: 'coolapk_cookie', value: value);
    _cookie = value;
  }

  Future<void> validateAndSaveCookie(String cookie) async {
    final previous = _cookie;
    final previousUid = _currentUid;
    await saveCookie(cookie);
    _currentUid = '';
    try {
      await checkLogin();
    } catch (_) {
      _cookie = previous;
      _currentUid = previousUid;
      if (previous.isEmpty) {
        await _secureStorage.delete(key: 'coolapk_cookie');
      } else {
        await _secureStorage.write(key: 'coolapk_cookie', value: previous);
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      if (_cookie.isNotEmpty) {
        await request('https://account.coolapk.com/auth/logout');
      }
    } finally {
      _cookie = '';
      _currentUid = '';
      _currentUserAvatar = '';
      await _secureStorage.delete(key: 'coolapk_cookie');
    }
  }

  Future<Map<String, dynamic>> checkLogin() async {
    final response = await _get('/v6/account/checkLoginInfo', const {});
    final data = response['data'];
    final result = data is Map ? Map<String, dynamic>.from(data) : response;
    final user = result['userInfo'] ?? result['user_info'];
    _currentUid = _string(
      result['uid'] ??
          result['userId'] ??
          result['id'] ??
          (user is Map ? user['uid'] ?? user['id'] : null),
    );
    _currentUserAvatar = _string(
      result['userAvatar'] ??
          result['avatar'] ??
          (user is Map ? user['userAvatar'] ?? user['avatar'] : null),
    );
    return response;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    var requestPath = path;
    var requestQuery = Map<String, dynamic>.from(query);
    if (requestPath == '/v6/product/feedList' ||
        requestPath == '/product/feedList') {
      requestPath = '/v6/page/dataList';
      if (!requestQuery.containsKey('url')) {
        requestQuery['url'] = '/page?url=/product/feedList';
      }
      if (requestQuery['type'] == 'picture') {
        requestQuery['type'] = 'article';
      } else if (requestQuery['type'] == 'ershou') {
        requestQuery['type'] = 'trade';
      }
    }
    try {
      final headers = <String, String>{'X-App-Token': _auth.token()};
      if (_cookie.isNotEmpty) headers['Cookie'] = _cookie;
      final response = await _dio.request<dynamic>(
        requestPath,
        queryParameters: requestQuery,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          contentType: body == null ? null : Headers.formUrlEncodedContentType,
        ),
      );
      final data = response.data;
      if (data is Map) {
        final root = Map<String, dynamic>.from(data);
        _checkBusinessStatus(root);
        return root;
      }
      if (data is List) return {'data': data, 'status': 0};
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            final root = Map<String, dynamic>.from(decoded);
            _checkBusinessStatus(root);
            return root;
          }
          if (decoded is List) return {'data': decoded, 'status': 0};
        } on FormatException {
          return data;
        }
      }
      throw const CoolapkApiException('酷安返回了无法识别的响应');
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map) {
        final message = _string(body['message']);
        if (message.isNotEmpty) throw CoolapkApiException(message);
      }
      if (error.response?.statusCode == 403) {
        throw const CoolapkApiException('酷安暂时拒绝了请求，可能触发了访问限制');
      }
      if (error.response?.statusCode == 401) {
        throw const CoolapkApiException('登录状态已失效，请重新登录');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const CoolapkApiException('连接酷安超时，请检查网络后重试');
      }
      throw const CoolapkApiException('暂时无法连接酷安，请稍后重试');
    }
  }

  Future<Uri> resolveApkDownloadUrl({
    required String packageName,
    required String appId,
    required String versionCode,
  }) async {
    if (packageName.trim().isEmpty ||
        appId.trim().isEmpty ||
        versionCode.trim().isEmpty) {
      throw const CoolapkApiException('应用缺少下载所需的版本信息');
    }
    try {
      final response = await _dio.post<dynamic>(
        '/v6/apk/download',
        queryParameters: {
          'extra': '',
          'pn': packageName,
          'aid': appId,
          'vc': versionCode,
        },
        options: Options(
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
          headers: {
            'X-App-Token': _auth.token(),
            if (_cookie.isNotEmpty) 'Cookie': _cookie,
          },
        ),
      );
      final location = response.headers.value('location');
      final uri = location == null
          ? null
          : Uri.parse('https://api.coolapk.com').resolve(location);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const CoolapkApiException('酷安没有返回有效的下载地址');
      }
      return uri;
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        throw const CoolapkApiException('酷安暂时拒绝了下载请求');
      }
      throw const CoolapkApiException('暂时无法获取应用下载地址');
    }
  }

  Future<Map<String, String>> loadHomeTabRoutes() =>
      _homeTabRoutes ??= _readHomeTabRoutes();

  Future<Map<String, String>> loadDiscoveryTabRoutes() async {
    final root = await (_mainInit ??= _readMainInit());
    final rows = root['data'];
    if (rows is! List) return const {};
    final routes = <String, String>{};
    for (final row in rows.whereType<Map>()) {
      if (_string(row['title']) != '发现TAB配置') continue;
      final entities = row['entities'];
      if (entities is! List) return const {};
      for (final entity in entities.whereType<Map>()) {
        final rawTitle = _string(entity['title']);
        final title = rawTitle == '好物' ? '好物榜' : rawTitle;
        final route = _string(entity['url']).isNotEmpty
            ? _string(entity['url'])
            : _string(entity['page_name']);
        if (const {
              '酷品',
              '生活',
              '二手',
              '酷图',
              '宠物',
              '运动',
              '看看号',
              '商家',
              '好物榜',
            }.contains(title) &&
            route.isNotEmpty) {
          routes[title] = route;
        }
      }
      return routes;
    }
    return const {};
  }

  Future<Map<String, dynamic>> _readMainInit() async {
    final response = await request(
      '/v6/main/init',
      query: const {'appVersionCode': 2604201},
    );
    return response is Map ? Map<String, dynamic>.from(response) : const {};
  }

  Future<Map<String, String>> _readHomeTabRoutes() async {
    final root = await (_mainInit ??= _readMainInit());
    final rows = root['data'];
    if (rows is! List) return const {};
    final titles = {
      '话题': 'topic',
      '关注': 'follow',
      '头条': 'headline',
      '热榜': 'hot',
      '教程': 'tutorial',
      '视频': 'video',
      '快讯': 'news',
      '新机': 'new_device',
      '汽车': 'car',
      '开箱': 'unboxing',
      '摄影': 'photo',
      '游戏': 'game',
      '外设': 'peripherals',
      '美化': 'theme',
      '直播': 'live',
      '问答': 'qa',
      '神券': 'coupons',
    };
    for (final row in rows.whereType<Map>()) {
      final cardTitle = _string(row['title']);
      if (cardTitle != '首页TAB配置' && cardTitle != '首页') continue;
      final entities = row['entities'];
      if (entities is! List) return const {};
      final routes = <String, String>{};
      for (final entity in entities.whereType<Map>()) {
        final id = titles[_string(entity['title'])];
        final route = _string(entity['url']);
        if (id != null && route.isNotEmpty) {
          routes[id] = id == 'headline'
              ? '/v6/main/headline'
              : route == '/main/headline'
              ? '/v6/main/headline'
              : route;
        }
      }
      return routes;
    }
    return const {};
  }

  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final root = await _get(path, query);
    final items = _extractEntities(root);
    return ApiPage(
      items: items,
      page: _int(root['page']) ?? _int(query['page']) ?? 1,
      hasMore: _hasMore(root, _paginationItemCount(items)),
      firstItem: _string(root['firstItem']).isNotEmpty
          ? _string(root['firstItem'])
          : _cursorItem(items),
      lastItem: _string(root['lastItem']).isNotEmpty
          ? _string(root['lastItem'])
          : _cursorItem(items, first: false),
    );
  }

  static String _cursorItem(
    List<Map<String, dynamic>> items, {
    bool first = true,
  }) {
    final orderedItems = first ? items : items.reversed;
    for (final item in orderedItems) {
      final raw = item['entities'];
      final nested = raw is List ? raw.whereType<Map>() : const <Map>[];
      final candidates = first ? nested : nested.toList().reversed;
      for (final candidate in candidates) {
        final id = _string(candidate['id'] ?? candidate['uid']);
        if (id.isNotEmpty) return id;
      }
      final id = _string(item['id'] ?? item['uid']);
      if (id.isNotEmpty) return id;
    }
    return '';
  }

  static int _paginationItemCount(List<Map<String, dynamic>> items) =>
      items.fold(0, (count, item) {
        final entities = item['entities'];
        return count + 1 + (entities is List ? entities.length : 0);
      });

  Future<ApiPage> search(
    String keyword,
    String type,
    int page, {
    String sortType = 'default',
  }) => getList(
    '/v6/search',
    query: {
      'type': type,
      'searchValue': keyword,
      'page': page,
      'sort': sortType == 'exact' ? 'default' : sortType,
      'sortType': sortType,
      if (sortType == 'exact') 'isExact': 1,
      'show_flag': 1,
    },
  );

  Future<Map<String, dynamic>> getSearchSuggestions(String keyword) async =>
      _get('/v6/search/suggest', {'key': keyword});

  Future<Map<String, dynamic>> getHotSearch({bool refresh = false}) async =>
      _get('/v6/search', {
        'type': 'hotSearch',
        'refresh': refresh ? 1 : 0,
        'returnType': 'all',
      });

  Future<void> likeFeed(String id, {required bool liked}) =>
      _post(liked ? '/v6/feed/unlike' : '/v6/feed/like', query: {'id': id});

  Future<void> favoriteFeed(String id, {required bool favorited}) => _post(
    favorited ? '/v6/feed/unfavorite' : '/v6/feed/favorite',
    query: {'id': id},
  );

  Future<void> forwardFeed(String id, String message) =>
      _post('/v6/feed/forward', body: {'id': id, 'message': message});

  Future<void> deleteFeed(String id) =>
      _post('/v6/feed/deleteFeed', body: {'id': id});

  Future<void> createFeed(
    String message, {
    String? pic,
    String type = 'feed',
    String? extraTitle,
    String? tag,
    String? location,
    String? productId,
    String? voteId,
  }) => _post(
    '/v6/feed/createFeed',
    body: {
      'message': message,
      'type': type,
      if (pic != null && pic.isNotEmpty) 'pic': pic,
      if (extraTitle != null && extraTitle.isNotEmpty)
        'extra_title': extraTitle,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (location != null && location.isNotEmpty) 'location': location,
      if (productId != null && productId.isNotEmpty) 'product_id': productId,
      if (voteId != null && voteId.isNotEmpty) 'vote_id': voteId,
    },
  );

  Future<void> reply(
    String id,
    String message, {
    String? rid,
    String? pic,
    bool replyAndForward = false,
  }) => _post(
    '/v6/feed/reply',
    body: {
      'id': id,
      'type': 'feed',
      'message': message,
      if (rid != null && rid.isNotEmpty) 'rid': rid,
      if (pic != null && pic.isNotEmpty) 'pic': pic,
      if (replyAndForward) 'replyAndForward': '1',
    },
  );

  Future<void> likeReply(String id, {required bool liked}) => _post(
    liked ? '/v6/feed/unLikeReply' : '/v6/feed/likeReply',
    query: {'id': id},
  );

  Future<void> deleteReply(String id) =>
      _post('/v6/feed/deleteReply', query: {'id': id});

  Future<void> followUser(String uid, {required bool following}) => _post(
    following ? '/v6/user/unfollow' : '/v6/user/follow',
    query: {'uid': uid},
  );

  Future<void> blockUser(String uid, {required bool blocked}) => _post(
    blocked ? '/v6/user/unblock' : '/v6/user/block',
    query: {'uid': uid},
  );

  Future<void> followTopic(String tag, {required bool following}) => _post(
    following ? '/v6/topic/unfollowTag' : '/v6/topic/followTag',
    query: {'tag': tag},
  );

  Future<void> followProduct(String productId, {required bool following}) =>
      _post(
        '/v6/product/changeFollowStatus',
        query: {'id': productId, 'status': following ? 0 : 1},
      );

  Future<Map<String, dynamic>> getProductDetail(String productId) async {
    final response = await _get('/v6/product/detail', {'id': productId});
    final data = response['data'];
    return data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
  }

  Future<void> postReply(String id, String message, {String? rid}) =>
      reply(id, message, rid: rid);

  Future<FeedPage> getFeedPage(
    FeedCategory category,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    final path = category == FeedCategory.recommended
        ? '/v6/main/indexV8'
        : '/v6/page/dataList';
    final query = category == FeedCategory.recommended
        ? <String, dynamic>{
            'page': page,
            'firstLaunch': 0,
            'installTime': 0,
            'firstItem': firstItem,
            'lastItem': lastItem,
            'ids': '',
          }
        : <String, dynamic>{
            'url': category.route,
            'page': page,
            'firstItem': firstItem,
            'lastItem': lastItem,
          };
    final root = await _get(path, query);
    final items = _extractFeeds(root);
    return FeedPage(
      items: items,
      firstItem: _string(root['firstItem']).isNotEmpty
          ? _string(root['firstItem'])
          : items.firstOrNull?.id ?? '',
      lastItem: _string(root['lastItem']).isNotEmpty
          ? _string(root['lastItem'])
          : items.lastOrNull?.id ?? '',
      hasMore: _hasMore(root, items.length),
    );
  }

  Future<FeedPage> getHomeChannelPage(
    String route,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    final headline = route == '/v6/main/headline' || route == '/main/headline';
    final cardsFuture = headline && page == 1
        ? _get('/v6/main/indexV8', {
                'page': 1,
                'firstLaunch': 0,
                'installTime': 0,
                'firstItem': '',
                'lastItem': '',
                'ids': '',
              })
              .then(_extractCards)
              .catchError((Object _) => <Map<String, dynamic>>[])
        : Future.value(<Map<String, dynamic>>[]);

    final String path;
    final Map<String, dynamic> query = {
      'page': page,
      'firstItem': firstItem,
      'lastItem': lastItem,
    };

    if (headline) {
      path = '/v6/main/headline';
    } else if (route.startsWith('#/')) {
      path = '/v6/page/dataList';
      query['url'] = route;
    } else if (route.startsWith('/page')) {
      path = '/v6/page/dataList';
      final uri = Uri.tryParse(route);
      if (uri != null && uri.queryParameters.isNotEmpty) {
        query.addAll(uri.queryParameters);
      } else {
        query['url'] = route;
      }
    } else if (route.startsWith('/v6/')) {
      final uri = Uri.tryParse(route);
      path = uri?.path ?? route;
      if (uri != null && uri.queryParameters.isNotEmpty) {
        query.addAll(uri.queryParameters);
      }
    } else {
      path = '/v6/page/dataList';
      query['url'] = route;
    }

    final root = await _get(path, query);
    final items = _extractFeeds(root);
    final List<Map<String, dynamic>> channelCards;
    if (page == 1) {
      final rootCards = _extractCards(root);
      if (rootCards.isNotEmpty) {
        channelCards = rootCards;
      } else if (headline) {
        final v8Cards = await cardsFuture;
        channelCards = v8Cards.isNotEmpty ? v8Cards : rootCards;
      } else {
        channelCards = rootCards;
      }
    } else {
      channelCards = const [];
    }
    return FeedPage(
      items: items,
      cards: channelCards,
      firstItem: _string(root['firstItem']).isNotEmpty
          ? _string(root['firstItem'])
          : items.firstOrNull?.id ?? '',
      lastItem: _string(root['lastItem']).isNotEmpty
          ? _string(root['lastItem'])
          : items.lastOrNull?.id ?? '',
      hasMore: _hasMore(root, items.length),
    );
  }

  List<Map<String, dynamic>> _extractCards(Map<String, dynamic> root) {
    final cards = <Map<String, dynamic>>[];
    final data = root['data'];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final type = _string(m['entityType'] ?? m['entity_type'])
              .toLowerCase();
          final template = _string(m['entityTemplate'] ?? m['entity_template'])
              .toLowerCase();
          final entities = m['entities'];
          final isCard =
              type == 'card' ||
              template.contains('card') ||
              template.startsWith('image') ||
              type == 'image_1' ||
              (entities is List && entities.isNotEmpty && type != 'feed');
          if (isCard && type != 'feed') {
            if (entities is List &&
                entities.isEmpty &&
                !template.contains('banner') &&
                type != 'image_1') {
              continue;
            }
            cards.add(m);
          }
        }
      }
    }
    return cards;
  }

  Future<FeedPage> searchFeeds(String query, int page) async {
    final root = await _get('/v6/search', {
      'type': 'feed',
      'searchValue': query,
      'page': page,
      'sortType': 'default',
      'show_flag': 1,
    });
    final items = _extractFeeds(root);
    return FeedPage(
      items: items,
      firstItem: _string(root['firstItem']).isNotEmpty
          ? _string(root['firstItem'])
          : items.firstOrNull?.id ?? '',
      lastItem: _string(root['lastItem']).isNotEmpty
          ? _string(root['lastItem'])
          : items.lastOrNull?.id ?? '',
      hasMore: _hasMore(root, items.length),
    );
  }

  Future<Map<String, dynamic>> getFeedDetail(String feedId) async {
    final root = await _get('/v6/feed/detail', {'id': feedId});
    final data = root['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty && data.first is Map) {
      return Map<String, dynamic>.from(data.first as Map);
    }
    throw const CoolapkApiException('酷安没有返回这条动态的详情');
  }

  Future<Map<String, dynamic>> resolveVideoUrl(String requestParams) async {
    final params = requestParams.trim();
    if (params.isEmpty) throw const CoolapkApiException('视频解析参数为空');
    final result = await request(
      '/v6/player/getUrl',
      method: 'POST',
      body: {'params': params},
    );
    if (result is Map<String, dynamic>) return result;
    throw const CoolapkApiException('酷安没有返回可识别的视频地址');
  }

  Future<List<CoolapkFeed>> getReplies(String feedId) async {
    final root = await _get('/v6/feed/replyList', {
      'id': feedId,
      'listType': 'lastupdate_desc',
      'page': 1,
      'discussMode': 1,
      'feedType': 'feed',
      'blockStatus': 0,
    });
    return _extractFeeds(root);
  }

  Future<ApiPage> getReplyPage(
    String feedId,
    int page, {
    String listType = 'lastupdate_desc',
    String? firstItem,
    String? lastItem,
    String feedType = 'feed',
    bool fromFeedAuthor = false,
  }) => getList(
    '/v6/feed/replyList',
    query: {
      'id': feedId,
      'listType': listType,
      'page': page,
      'discussMode': 1,
      'feedType': feedType,
      'blockStatus': 0,
      'fromFeedAuthor': fromFeedAuthor ? 1 : 0,
      if (firstItem != null && firstItem.isNotEmpty) 'firstItem': firstItem,
      if (lastItem != null && lastItem.isNotEmpty) 'lastItem': lastItem,
    },
  );

  Future<ApiPage> getHotReplyPage(String feedId, int page) => getList(
    '/v6/feed/hotReplyList',
    query: {'id': feedId, 'page': page, 'discussMode': 1},
  );

  Future<Map<String, dynamic>> getReplyDetail(String replyId) =>
      _get('/v6/feed/replyDetail', {'id': replyId});

  Future<ApiPage> getUserPage(String route, String uid, int page) =>
      getList(route, query: {'uid': uid, 'page': page});

  Future<Map<String, dynamic>> getUserSpace(String uid) =>
      _get('/v6/user/space', {'uid': uid});

  Future<Map<String, dynamic>> getUserProfile(String uid) =>
      _get('/v6/user/profile', {'uid': uid});

  Future<Map<String, dynamic>> getTopicDetail(String tag) =>
      _get('/v6/topic/newTagDetail', {'tag': tag});

  Future<void> createCollection(
    String title, {
    String description = '',
    bool isOpen = true,
  }) => _post(
    '/v6/collection/create',
    body: {
      'title': title,
      'description': description,
      'is_open': isOpen ? 1 : 0,
    },
  );

  Future<void> sendMessage(String uid, String message, {String? pic}) async {
    final body = <String, dynamic>{'uid': uid, 'message': message};
    if (pic != null && pic.isNotEmpty) body['pic'] = pic;
    await _post('/v6/message/send', query: {'uid': uid}, body: body);
  }

  Future<void> _post(
    String path, {
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) async {
    await request(path, method: 'POST', query: query, body: body);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    final data = await request(path, query: query);
    if (data is Map<String, dynamic>) return data;
    throw const CoolapkApiException('酷安返回了无法识别的响应');
  }

  void _checkBusinessStatus(Map<String, dynamic> root) {
    final status = _int(root['status']);
    final code = _int(root['code']);
    final resultCode = status ?? code;
    final failed = resultCode != null && resultCode != 0 && resultCode != 200;
    if (failed) {
      final message = _string(root['message']);
      throw CoolapkApiException(
        message.isEmpty ? '酷安接口返回错误（${status ?? code}）' : message,
      );
    }
  }

  List<CoolapkFeed> _extractFeeds(Map<String, dynamic> root) {
    final data = root['data'];
    final rows = <Map<String, dynamic>>[];

    void visit(dynamic value) {
      if (value is! Map) return;
      final item = Map<String, dynamic>.from(value);
      final type = _string(item['entityType'] ?? item['entity_type']);
      final skipped = const {'card', 'header', 'card_title', 'banner'};
      if (!skipped.contains(type.toLowerCase()) &&
          (item.containsKey('message') ||
              item.containsKey('username') ||
              item.containsKey('userInfo') ||
              item.containsKey('user_info'))) {
        rows.add(item);
      }
      final children = item['entities'];
      if (children is List) {
        for (final child in children) {
          visit(child);
        }
      }
    }

    if (data is List) {
      for (final item in data) {
        visit(item);
      }
    } else if (data is Map) {
      visit(data);
      final entities = data['entities'];
      if (entities is List) {
        for (final item in entities) {
          visit(item);
        }
      }
    }
    final seen = <String>{};
    return rows
        .map(CoolapkFeed.fromJson)
        .where((feed) => feed.id.isNotEmpty && seen.add(feed.id))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _extractEntities(Map<String, dynamic> root) {
    final rows = <Map<String, dynamic>>[];
    final containers = const [
      'data',
      'entities',
      'rows',
      'list',
      'items',
      'cardRows',
      'card_rows',
      'entityList',
      'entity_list',
    ];
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is! Map) return;
      final item = Map<String, dynamic>.from(value);
      final type = _string(item['entityType'] ?? item['entity_type']);
      final isEntity =
          type.isNotEmpty ||
          item.containsKey('id') ||
          item.containsKey('title') ||
          item.containsKey('message') ||
          item.containsKey('username');
      if (isEntity) rows.add(item);
      // Server card rows already own their nested entities. Flattening both
      // levels displays the same content twice and loses the card template.
      if (type.toLowerCase() == 'card') return;
      for (final key in containers) {
        if (item.containsKey(key)) visit(item[key]);
      }
    }

    visit(root['data']);
    final seen = <String>{};
    return rows
        .where((item) {
          final id = _string(item['id'] ?? item['uid'] ?? item['url']);
          final type = _string(item['entityType'] ?? item['entity_type']);
          final key = '$type:$id:${_string(item['title'])}';
          return seen.add(key);
        })
        .toList(growable: false);
  }

  static bool _hasMore(Map<String, dynamic> root, int itemCount) {
    final value = root['hasMore'] ?? root['has_more'] ?? root['hasNextPage'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return itemCount >= 10;
  }
}

enum FeedCategory {
  recommended('推荐', ''),
  hot('热榜', '#/feed/hotList'),
  latest('最新', '#/feed/newestList'),
  digest('精选', '#/feed/digestList?type=1'),
  coolPicture('酷图', '#/feed/coolPictureRankList'),
  editorChoice('编辑精选', '#/feed/editorChoiceList'),
  questions('问答', '#/feed/myQaFeedList');

  const FeedCategory(this.label, this.route);
  final String label;
  final String route;
}

class FeedPage {
  const FeedPage({
    required this.items,
    this.cards = const [],
    required this.firstItem,
    required this.lastItem,
    required this.hasMore,
  });

  final List<CoolapkFeed> items;
  final List<Map<String, dynamic>> cards;
  final String firstItem;
  final String lastItem;
  final bool hasMore;
}

class ApiPage {
  const ApiPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.firstItem,
    required this.lastItem,
  });

  final List<Map<String, dynamic>> items;
  final int page;
  final bool hasMore;
  final String firstItem;
  final String lastItem;
}

class CoolapkFeed {
  const CoolapkFeed({
    required this.id,
    required this.username,
    required this.avatar,
    required this.message,
    required this.date,
    required this.likeCount,
    required this.replyCount,
    required this.pictures,
    this.uid = '',
    this.liked = false,
    this.favorited = false,
    this.raw = const {},
  });

  final String id;
  final String username;
  final String avatar;
  final String message;
  final String date;
  final String likeCount;
  final String replyCount;
  final List<String> pictures;
  final String uid;
  final bool liked;
  final bool favorited;
  final Map<String, dynamic> raw;

  factory CoolapkFeed.fromJson(Map<String, dynamic> json) {
    final user = json['userInfo'] ?? json['user_info'] ?? json['user'];
    final userInfo = user is Map ? Map<String, dynamic>.from(user) : const {};
    final isFeedHdr =
        json['is_hdr'] == 1 ||
        json['is_hdr'] == '1' ||
        json['is_hdr'] == true ||
        json['hdr'] == 1 ||
        json['hdr'] == '1' ||
        json['hdr'] == true ||
        json['isHdr'] == 1 ||
        json['isHdr'] == '1' ||
        json['isHdr'] == true;
    final images = <String>[];
    for (final key in ['picArr', 'imageUriList', 'image_uri_list']) {
      final raw = json[key];
      if (raw is List) {
        for (final image in raw) {
          final url = image is Map
              ? _string(image['url'] ?? image['pic'] ?? image['image'])
              : _string(image);
          if (_validImageUrl(url) && !images.contains(url)) {
            images.add(url);
            if (isFeedHdr) {
              HdrImageDetector.markHdr(url);
            } else if (image is Map) {
              final imgHdr = image['is_hdr'] ?? image['isHdr'] ?? image['hdr'];
              if (imgHdr == 1 || imgHdr == '1' || imgHdr == true) {
                HdrImageDetector.markHdr(url);
              }
            }
          }
        }
      }
    }
    final single = _string(json['pic'] ?? json['cover'] ?? json['coverPic']);
    if (images.isEmpty && single.isNotEmpty) {
      for (final value
          in single
              .split(',')
              .map((value) => value.trim())
              .where(_validImageUrl)) {
        if (!images.contains(value)) images.add(value);
        if (isFeedHdr) {
          HdrImageDetector.markHdr(value);
        }
      }
    }
    final rawMessage = _string(
      json['message'] ??
          json['description'] ??
          json['subTitle'] ??
          json['title'],
    );
    final dateline = _string(
      json['dateline'] ?? json['createTime'] ?? json['create_time'],
    );
    return CoolapkFeed(
      id: _string(json['id'] ?? json['feedId'] ?? json['feed_id']),
      uid: _string(json['uid'] ?? userInfo['uid'] ?? userInfo['id']),
      username: _string(
        json['username'] ??
            json['user_name'] ??
            userInfo['username'] ??
            userInfo['name'] ??
            json['author'] ??
            json['source'],
      ),
      avatar: _imageUrl(
        json['userAvatar'] ??
            json['user_avatar'] ??
            json['avatar'] ??
            userInfo['userAvatar'] ??
            userInfo['avatar'],
      ),
      message: html.parse(rawMessage).body?.text.trim() ?? rawMessage,
      date: _relativeTime(dateline),
      likeCount: _string(
        json['likenum'] ?? json['likeNum'] ?? json['like_num'],
      ),
      replyCount: _string(
        json['replynum'] ??
            json['replyNum'] ??
            json['reply_num'] ??
            json['commentnum'],
      ),
      pictures: images.toList(growable: false),
      liked:
          json['isLike'] == true ||
          json['is_like'] == true ||
          _int(json['isLike'] ?? json['is_like']) == 1,
      favorited:
          json['isFavorite'] == true ||
          json['is_favorite'] == true ||
          _int(json['isFavorite'] ?? json['is_favorite']) == 1,
      raw: json,
    );
  }
}

class CoolapkApiException implements Exception {
  const CoolapkApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _CoolapkAuth {
  const _CoolapkAuth(this.deviceCode, this.authBlob);

  static const _appId = 'com.coolapk.market';
  static const _appCode = 2604201;
  static const _base64Alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  static const _bcryptAlphabet =
      './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  final String deviceCode;
  final Uint8List authBlob;

  String token() {
    if (authBlob.isEmpty) {
      throw StateError('缺少本地酷安签名素材，请配置 assets/coolapk_auth_blob.b64');
    }
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    Object? lastError;
    for (var offset = 0; offset <= 15; offset++) {
      try {
        return _tokenAt(timestamp + offset);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('酷安签名生成失败: $lastError');
  }

  String _tokenAt(int timestamp) {
    final start = (((timestamp + _appCode) % 100) * 4 + 0x80);
    if (start < 0 || start + 0x80 > authBlob.length) {
      throw const FormatException('auth blob segment out of range');
    }
    final segment = utf8.decode(
      base64.decode(ascii.decode(authBlob.sublist(start, start + 0x80))),
      allowMalformed: true,
    );
    final plain = '$_appId&$segment&${_md5(deviceCode)}&$timestamp&$_appCode';
    final password = _md5(base64.encode(utf8.encode(plain)));
    final timestampHex = timestamp.toRadixString(16);
    final saltSource = base64
        .encode(utf8.encode('$timestampHex/${_md5(plain)}'))
        .replaceAll('=', '');
    final salt22 = _shiftLast(saltSource.substring(0, 22), -5);
    final rawSalt = _decodeBcryptBase64(salt22);
    if (rawSalt.length != 16) {
      throw const FormatException('invalid bcrypt salt');
    }
    final salt = _encodeBcryptBase64(rawSalt);
    final hash = BCrypt.hashpw(password, '\$2y\$04\$$salt');
    return 'v3${base64.encode(utf8.encode(hash)).replaceAll('=', '')}';
  }

  static String _md5(String value) =>
      md5.convert(utf8.encode(value)).toString();

  static String _shiftLast(String source, int shift) {
    final index = _base64Alphabet.indexOf(source[source.length - 1]);
    if (index < 0) throw const FormatException('invalid salt character');
    final shifted = (index + shift) % 64;
    return '${source.substring(0, source.length - 1)}${_base64Alphabet[shifted < 0 ? shifted + 64 : shifted]}';
  }

  static Uint8List _decodeBcryptBase64(String source) {
    final output = <int>[];
    var index = 0;
    while (index < source.length) {
      final first = _bcryptAlphabet.indexOf(source[index++]);
      if (first < 0 || index >= source.length) break;
      final second = _bcryptAlphabet.indexOf(source[index++]);
      if (second < 0) break;
      output.add(((first << 2) | ((second & 0x30) >> 4)) & 0xff);
      if (index >= source.length) break;
      final third = _bcryptAlphabet.indexOf(source[index++]);
      if (third < 0) break;
      output.add((((second & 0x0f) << 4) | ((third & 0x3c) >> 2)) & 0xff);
      if (index >= source.length) break;
      final fourth = _bcryptAlphabet.indexOf(source[index++]);
      if (fourth < 0) break;
      output.add((((third & 0x03) << 6) | fourth) & 0xff);
    }
    return Uint8List.fromList(output);
  }

  static String _encodeBcryptBase64(List<int> bytes) {
    final output = StringBuffer();
    var index = 0;
    while (index < bytes.length) {
      var first = bytes[index++] & 0xff;
      output.write(_bcryptAlphabet[(first >> 2) & 0x3f]);
      first = (first & 0x03) << 4;
      if (index >= bytes.length) {
        output.write(_bcryptAlphabet[first & 0x3f]);
        break;
      }
      final second = bytes[index++] & 0xff;
      first |= (second >> 4) & 0x0f;
      output.write(_bcryptAlphabet[first & 0x3f]);
      first = (second & 0x0f) << 2;
      if (index >= bytes.length) {
        output.write(_bcryptAlphabet[first & 0x3f]);
        break;
      }
      final third = bytes[index++] & 0xff;
      first |= (third >> 6) & 0x03;
      output.write(_bcryptAlphabet[first & 0x3f]);
      output.write(_bcryptAlphabet[third & 0x3f]);
    }
    return output.toString();
  }
}

String _newUuid() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _string(dynamic value) => value == null ? '' : value.toString().trim();

int? _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_string(value));

bool _validImageUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

String _imageUrl(dynamic value) {
  final url = _string(value);
  if (url.isEmpty) return '';
  return url.startsWith('//') ? 'https:$url' : url;
}

String formatRelativeTime(String value) {
  final timestamp = int.tryParse(value);
  if (timestamp == null || timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp > 1000000000000 ? timestamp : timestamp * 1000,
  );
  final difference = DateTime.now().difference(date);
  if (difference.isNegative) return '';
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  if (difference.inDays < 30) return '${difference.inDays}天前';
  return '${date.month}月${date.day}日';
}

String _relativeTime(String value) => formatRelativeTime(value);
