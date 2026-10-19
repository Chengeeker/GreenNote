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
import 'package:shared_preferences/shared_preferences.dart';

import 'coolapk_image.dart';
import 'coolapk_captcha.dart';
import 'official_device_identity.dart';
import '../accounts/local_account.dart';

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
  CoolapkApi._(
    this._dio,
    this._auth,
    this._secureStorage,
    this._cookie,
    this.localAccount,
  );

  static const _apiCode = 2604201;
  static const _apiVersion = '16.2.0';
  final Dio _dio;
  _CoolapkAuth _auth;
  final FlutterSecureStorage _secureStorage;
  final LocalAccount localAccount;
  final _localUsers = <String, Map<String, dynamic>>{};
  String _cookie;
  String? guestSessionCookie;
  String? _officialSessionCookie, _officialSessionIdentity;
  String? _acceptedValidation, _acceptedValidationContext;
  DateTime? _validationExpires;

  String get _verificationIdentity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            _auth.deviceCode,
            isAnonymous,
            hasCookie,
            hasCookie ? _cookie : '',
          ]),
        ),
      )
      .toString();

  String get _captchaContext => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            _verificationIdentity,
            hasCookie
                ? (_officialSessionIdentity == _verificationIdentity
                      ? _officialSessionCookie
                      : null)
                : guestSessionCookie,
          ]),
        ),
      )
      .toString();

  static String _withCookie(String cookie, String name, String value) => [
    ...cookie
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part.split('=').first != name),
    if (value.isNotEmpty) '$name=$value',
  ].join('; ');

  Future<bool> _verificationIdentityMatches(String identity) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final stored = await _secureStorage.read(key: 'coolapk_cookie') ?? '';
    final anonymous = preferences.getBool('greennote.local.active') == true;
    final enabled = preferences.getBool('greennote.cookie.enabled') != false;
    final imported =
        preferences.getString(OfficialDeviceIdentity.storageKey) ?? '';
    final device = OfficialDeviceIdentity.fields(imported) != null
        ? imported
        : preferences.getString('guest_device_code');
    return identity == _verificationIdentity &&
        device == _auth.deviceCode &&
        anonymous == isAnonymous &&
        (!anonymous && enabled && stored.isNotEmpty) == hasCookie &&
        (!hasCookie || stored == _cookie);
  }

  bool _hasOfficialDeviceIdentity = false;
  bool get hasOfficialDeviceIdentity => _hasOfficialDeviceIdentity;
  String _currentUid = '';
  String _currentUserAvatar = '';
  String _currentUserNickname = '';
  Future<Map<String, String>>? _homeTabRoutes;
  Future<Map<String, dynamic>>? _mainInit;

  static Future<CoolapkApi> create({
    HttpClientAdapter? httpClientAdapter,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    var deviceCode = preferences.getString('guest_device_code');
    if (deviceCode == null || deviceCode.isEmpty) {
      deviceCode = _newUuid();
      await preferences.setString('guest_device_code', deviceCode);
    }
    final importedCode =
        preferences.getString(OfficialDeviceIdentity.storageKey) ?? '';
    final hasOfficial = OfficialDeviceIdentity.fields(importedCode) != null;
    if (hasOfficial) deviceCode = importedCode;
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
          // The API edge rejects a bare CoolMarket UA without the Android prefix.
          'User-Agent':
              'Dalvik/2.1.0 (Linux; U; Android 16) '
              '+CoolMarket/$_apiVersion-$_apiCode-universal',
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
    dio.httpClientAdapter =
        httpClientAdapter ??
        IOHttpClientAdapter(
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
      LocalAccount(preferences),
    ).._hasOfficialDeviceIdentity = hasOfficial;
  }

  Future<void> importOfficialDeviceIdentity(String text) async {
    final id = OfficialDeviceIdentity.parse(text);
    final previous = _auth.deviceCode;
    final profile = OfficialDeviceIdentity.fields(previous) == null
        ? await const MethodChannel('com.green.note/ui')
              .invokeMapMethod<String, dynamic>('getDeviceProfile')
        : null;
    final code = OfficialDeviceIdentity.encode(
      id,
      previous: previous,
      profile: profile ?? {},
    );
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(OfficialDeviceIdentity.storageKey, code)) {
      throw StateError('设备标识保存失败');
    }
    _applyDeviceCode(code, official: true);
  }

  Future<void> restoreOriginalDeviceIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    final original = preferences.getString('guest_device_code');
    if (original == null || original.isEmpty) {
      throw StateError('原设备码不存在，未修改设备标识');
    }
    if (!await preferences.remove(OfficialDeviceIdentity.storageKey)) {
      throw StateError('设备标识恢复失败');
    }
    _applyDeviceCode(original, official: false);
  }

  void _applyDeviceCode(String code, {required bool official}) {
    _auth = _CoolapkAuth(code, _auth.authBlob);
    _dio.options.headers['X-App-Device'] = code;
    _hasOfficialDeviceIdentity = official;
    guestSessionCookie = null;
    _homeTabRoutes = null;
    _mainInit = null;
  }

  bool get isAnonymous => localAccount.active;
  bool get hasAccount => isAnonymous || hasCookie;
  String get loginRequiredMessage => isAnonymous ? '当前为匿名登录，无法使用此功能' : '请先登录';
  bool get hasCookie =>
      !isAnonymous && localAccount.cookieEnabled && _cookie.isNotEmpty;
  String get currentUid => isAnonymous ? '' : _currentUid;
  String get currentUserAvatar => isAnonymous ? '' : _currentUserAvatar;
  String get currentUserNickname => isAnonymous
      ? (localAccount.publicIdentity?['username'] as String? ??
            localAccount.name)
      : _currentUserNickname;
  String token() => _auth.token();

  String get notificationSessionKey =>
      hasCookie ? sha256.convert(utf8.encode(_cookie)).toString() : '';

  Future<bool> notificationSessionMatches(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (preferences.getBool('greennote.local.active') == true ||
        preferences.getBool('greennote.cookie.enabled') == false) {
      return false;
    }
    final cookie = await _secureStorage.read(key: 'coolapk_cookie') ?? '';
    return cookie.isNotEmpty &&
        sha256.convert(utf8.encode(cookie)).toString() == key;
  }

  void close() {
    _dio.close(force: true);
    localAccount.dispose();
  }

  Map<String, String> imageHeadersFor() {
    final headers = <String, String>{
      for (final entry in _dio.options.headers.entries)
        entry.key: entry.value.toString(),
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'X-Requested-With': 'XMLHttpRequest',
      'X-App-Token': _auth.token(),
      'Referer': 'https://www.coolapk.com/',
    };
    if (hasCookie) headers['Cookie'] = _cookie;
    return headers;
  }

  Future<void> saveCookie(String cookie) async {
    final value = cookie.trim();
    if (value.isEmpty) throw const CoolapkApiException('Cookie 不能为空');
    if (value.contains('\r') || value.contains('\r\n')) {
      throw const CoolapkApiException('Cookie 格式无效');
    }
    await _secureStorage.write(key: 'coolapk_cookie', value: value);
    _cookie = value;
  }

  Future<void> validateAndSaveCookie(String cookie) async {
    final value = cookie.trim();
    if (value.isEmpty || value.contains('\r') || value.contains('\r\n')) {
      throw const CoolapkApiException('Cookie 格式无效');
    }
    final candidate = CoolapkApi._(
      _dio.clone(),
      _auth,
      _secureStorage,
      value,
      LocalAccount(await SharedPreferences.getInstance())
        ..active = false
        ..cookieEnabled = true,
    );
    await candidate.checkLogin();
    if (candidate._auth.deviceCode != _auth.deviceCode) {
      throw const CoolapkApiException('设备标识已变更，请重新登录');
    }
    if (candidate.currentUid.isEmpty) {
      throw const CoolapkApiException('Cookie 未返回有效账号');
    }
    await saveCookie(value);
    _currentUid = candidate.currentUid;
    _currentUserAvatar = candidate.currentUserAvatar;
    _currentUserNickname = candidate.currentUserNickname;
    await localAccount.setActive(false, enableCookie: true);
  }

  Future<void> logout() async {
    if (isAnonymous) {
      await localAccount.setActive(false);
      return;
    }
    try {
      if (hasCookie) {
        await request('https://account.coolapk.com/auth/logout');
      }
    } finally {
      _cookie = '';
      _currentUid = '';
      _currentUserAvatar = '';
      _currentUserNickname = '';
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
    _currentUserNickname = _string(
      result['username'] ??
          result['userName'] ??
          (user is Map ? user['username'] ?? user['userName'] : null),
    );
    return response;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
  }) => _request(path, method: method, query: query, body: body);

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
    String? validationProof,
    bool verificationReplay = false,
  }) async {
    if (isAnonymous &&
        (method.toUpperCase() != 'GET' ||
            const {
              '/v6/user/unfollow',
              '/v6/user/addToBlackList',
              '/v6/user/removeFromBlackList',
              '/v6/user/addToIgnoreList',
              '/v6/user/removeFromIgnoreList',
              '/v6/feed/favorite',
              '/v6/feed/unFavorite',
              '/v6/feed/followTag',
              '/v6/feed/unFollowTag',
            }.contains(path)) &&
        path != '/v6/player/getUrl') {
      throw CoolapkApiException(loginRequiredMessage);
    }
    if (isAnonymous &&
        (path.contains('/message/') ||
            path.contains('/notification/') ||
            path.contains('/account/'))) {
      throw CoolapkApiException(loginRequiredMessage);
    }
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
    final uri = Uri.parse(_dio.options.baseUrl).resolve(requestPath);
    final guestRequest =
        !hasCookie &&
        uri.scheme == 'https' &&
        const ['api.coolapk.com', 'api2.coolapk.com'].contains(uri.host);
    final requestSession = guestRequest ? guestSessionCookie : null;
    final requestDevice = _auth.deviceCode;
    final identity = _verificationIdentity;
    final trustedApi =
        uri.scheme == 'https' &&
        const ['api.coolapk.com', 'api2.coolapk.com'].contains(uri.host);
    final accepted =
        _acceptedValidationContext == _captchaContext &&
            (_validationExpires?.isAfter(DateTime.now()) ?? false)
        ? _acceptedValidation
        : null;
    final validation = trustedApi && method == 'GET'
        ? validationProof ?? accepted
        : null;

    void rememberSession(Response<dynamic> response) {
      if (identity != _verificationIdentity) return;
      if (response.realUri.scheme != 'https' ||
          !const [
            'api.coolapk.com',
            'api2.coolapk.com',
          ].contains(response.realUri.host)) {
        return;
      }
      if (guestRequest && requestDevice == _auth.deviceCode) {
        _rememberGuestSession(response, requestSession);
      } else if (hasCookie && trustedApi) {
        for (final value
            in response.headers['set-cookie'] ?? const <String>[]) {
          try {
            final cookie = Cookie.fromSetCookieValue(value);
            if (cookie.name != 'SESSID') continue;
            _officialSessionIdentity = identity;
            _officialSessionCookie =
                cookie.maxAge == 0 ||
                    (cookie.expires?.isBefore(DateTime.now().toUtc()) ?? false)
                ? ''
                : cookie.value;
          } on FormatException {
            // Other cookies never enter this API verification session.
          }
        }
      }
    }

    try {
      final headers = <String, String>{'X-App-Token': _auth.token()};
      if (hasCookie) {
        headers['Cookie'] = _cookie;
        if (_officialSessionIdentity == identity &&
            _officialSessionCookie != null) {
          headers['Cookie'] = _withCookie(
            _cookie,
            'SESSID',
            _officialSessionCookie!,
          );
        }
      } else if (requestSession != null) {
        headers['Cookie'] = requestSession;
      }
      if (validation != null) {
        headers['Cookie'] = _withCookie(
          headers['Cookie'] ?? '',
          'validate',
          Uri.encodeComponent(validation),
        );
      }
      final response = await _dio.request<dynamic>(
        requestPath,
        queryParameters: requestQuery,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          followRedirects: !verificationReplay && validation == null,
          contentType: body == null ? null : Headers.formUrlEncodedContentType,
        ),
      );
      rememberSession(response);
      if (identity != _verificationIdentity) {
        throw const CoolapkApiException('账号或设备已变更，已忽略旧请求');
      }
      final data = response.data;
      if (data is Map) {
        final root = Map<String, dynamic>.from(data);
        _checkBusinessStatus(root, sentValidation: validation);
        return root;
      }
      if (data is List) return {'data': data, 'status': 0};
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            final root = Map<String, dynamic>.from(decoded);
            _checkBusinessStatus(root, sentValidation: validation);
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
      if (error.response != null) rememberSession(error.response!);
      if (identity != _verificationIdentity) {
        throw const CoolapkApiException('账号或设备已变更，已忽略旧请求');
      }
      if (body is Map) {
        _checkBusinessStatus(
          Map<String, dynamic>.from(body),
          sentValidation: validation,
        );
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
            if (hasCookie) 'Cookie': _cookie,
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
    return parseDiscoveryTabRoutes(root);
  }

  static Map<String, String> parseDiscoveryTabRoutes(
    Map<String, dynamic> root,
  ) {
    final rows = root['data'];
    if (rows is! List) return const {};
    final routes = <String, String>{};
    for (final row in rows.whereType<Map>()) {
      if (!const {'发现', '发现TAB配置'}.contains(_string(row['title']))) {
        continue;
      }
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
    // Older server cards can still link to the removed personal-list route.
    if (path == '/v6/collection/myCollectionList') {
      path = '/v6/collection/list';
      query = {'uid': currentUid, 'showDefault': 1, ...query};
    }
    if (path == '/v6/member/recentHistoryList') {
      path = '/v6/user/recentHistoryList';
    }
    if (path == '/v6/topic/myFollowTopicList') {
      path = '/v6/page/dataList';
      query = {...query, 'url': '#/topic/userFollowTagList?&title=我关注的话题'};
    }
    final root = await _get(path, query);
    final followedUsers = path == '/v6/user/followList';
    final items = followedUsers
        ? parseUserFollowList(root)
        : _extractEntities(root);
    return ApiPage(
      items: items,
      total: _int(root['total']) ?? _int(root['totalCount']),
      page: _int(root['page']) ?? _int(query['page']) ?? 1,
      hasMore: _hasMore(
        root,
        followedUsers ? items.length : _paginationItemCount(items),
      ),
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

  Future<void> favoriteFeed(
    String id, {
    required bool favorited,
    CoolapkFeed? feed,
  }) async {
    if (isAnonymous) {
      if (feed == null) throw const CoolapkApiException('缺少本地收藏内容');
      await localAccount.toggle('favorites', id, {
        'id': id,
        'uid': feed.uid,
        'username': feed.username,
        'userAvatar': feed.avatar,
        'message': feed.raw['message'] is String
            ? feed.raw['message']
            : feed.message,
        'pic': feed.pictures.join(','),
        'dateline': '${feed.raw['dateline'] ?? ''}',
        'entityType': 'feed',
      });
      return;
    }
    await request(
      favorited ? '/v6/feed/unFavorite' : '/v6/feed/favorite',
      query: {'id': id},
    );
  }

  Future<void> forwardFeed(String id, String message) =>
      _post('/v6/feed/forward', body: {'id': id, 'message': message});

  Future<Map<String, dynamic>> submitVote(
    String id,
    List<String> optionIds, {
    bool anonymous = false,
  }) async {
    if (!hasCookie) throw CoolapkApiException(loginRequiredMessage);
    if (id.trim().isEmpty ||
        optionIds.isEmpty ||
        optionIds.any((value) => value.trim().isEmpty)) {
      throw const CoolapkApiException('请选择有效的投票选项');
    }
    final result = await request(
      '/v6/vote/createUserVote',
      method: 'POST',
      body: {
        'id': id,
        'anonymous_status': anonymous ? 1 : 0,
        for (var i = 0; i < optionIds.length; i++)
          'select_option[$i]': optionIds[i],
      },
    );
    return result is Map<String, dynamic> ? result : const {};
  }

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
    body: coolapkReplyForm(
      id,
      message,
      rid: rid,
      pic: pic,
      replyAndForward: replyAndForward,
    ),
  );

  Future<void> likeReply(String id, {required bool liked}) => _post(
    liked ? '/v6/feed/unLikeReply' : '/v6/feed/likeReply',
    query: {'id': id},
  );

  Future<void> deleteReply(String id) =>
      _post('/v6/feed/deleteReply', query: {'id': id});

  Future<void> followUser(String uid, {required bool following}) async {
    if (isAnonymous) {
      await localAccount.toggle(
        'follows',
        uid,
        _localUsers[uid] ??
            {'uid': uid, 'username': '酷友 $uid', 'userAvatar': ''},
      );
      return;
    }
    await request(
      following ? '/v6/user/unfollow' : '/v6/user/follow',
      method: following ? 'GET' : 'POST',
      query: {'uid': uid},
    );
  }

  Future<void> blockUser(String uid, {required bool blocked}) async {
    await request(
      blocked ? '/v6/user/removeFromBlackList' : '/v6/user/addToBlackList',
      query: {'uid': uid},
    );
  }

  Future<void> followTopic(String tag, {required bool following}) async {
    await request(
      following ? '/v6/feed/unFollowTag' : '/v6/feed/followTag',
      query: {'tag': tag},
    );
  }

  Future<void> followProduct(
    String productId, {
    required bool following,
    Map<String, dynamic>? product,
  }) async {
    if (isAnonymous) {
      await localAccount.toggle('productFollows', productId, {
        'id': productId,
        for (final key in const [
          'title',
          'pic',
          'logo',
          'cover',
          'hot_num',
          'votenum',
        ])
          if (product?[key] != null) key: product![key].toString(),
      });
      return;
    }
    await _post(
      '/v6/product/changeFollowStatus',
      query: {'id': productId, 'status': following ? 0 : 1},
    );
  }

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
      hasMore: _hasMore(root, items.length, allowShortPage: headline),
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
    final id = feedId.trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw const CoolapkApiException('动态标识无效，请从原帖链接重新打开');
    }
    final root = await _get('/v6/feed/detail', {'id': id});
    return _feedDetailData(root);
  }

  Future<Map<String, dynamic>> verifyFeedDetail(
    String feedId,
    CoolapkCaptchaException error,
    String validate,
  ) async {
    final identity = _verificationIdentity;
    if (error.contextKey != _captchaContext ||
        !await _verificationIdentityMatches(identity)) {
      throw const CoolapkApiException('账号、设备或会话已变更，请重新加载榜单');
    }
    final proof = error.challenge.proof(validate);
    if (proof == null) throw const CoolapkApiException('验证结果无效，请重试');
    // A single read-only replay; a second challenge returns to the user.
    final root = await _request(
      '/v6/feed/detail',
      query: {
        'id': feedId,
        if (error.challenge.field.isNotEmpty) error.challenge.field: proof,
      },
      validationProof: error.challenge.field.isEmpty ? proof : null,
      verificationReplay: true,
    );
    if (!await _verificationIdentityMatches(identity)) {
      throw const CoolapkApiException('账号或设备已变更，已忽略旧验证结果');
    }
    final data = _feedDetailData(root);
    if (error.challenge.field.isEmpty) {
      _acceptedValidation = proof;
      _acceptedValidationContext = _captchaContext;
      _validationExpires = DateTime.now().add(const Duration(hours: 1));
    }
    return data;
  }

  Map<String, dynamic> _feedDetailData(dynamic root) {
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
  }) async {
    final query = {
      'id': feedId,
      'listType': listType,
      'page': page,
      'discussMode': 1,
      'feedType': feedType.isEmpty ? 'feed' : feedType,
      'blockStatus': 0,
      'fromFeedAuthor': fromFeedAuthor ? 1 : 0,
      if (firstItem != null && firstItem.isNotEmpty) 'firstItem': firstItem,
      if (lastItem != null && lastItem.isNotEmpty) 'lastItem': lastItem,
    };
    try {
      return await getList(
        'https://api2.coolapk.com/v6/feed/replyList',
        query: query,
      );
    } catch (_) {
      return await getList('/v6/feed/replyList', query: query);
    }
  }

  Future<ApiPage> getHotReplyPage(String feedId, int page) async {
    final query = {'id': feedId, 'page': page, 'discussMode': 1};
    try {
      return await getList(
        'https://api2.coolapk.com/v6/feed/hotReplyList',
        query: query,
      );
    } catch (_) {
      return await getList('/v6/feed/hotReplyList', query: query);
    }
  }

  Future<Map<String, dynamic>> getReplyDetail(String replyId) =>
      _get('/v6/feed/replyDetail', {'id': replyId});

  Future<ApiPage> getUserPage(
    String route,
    String uid,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) => getList(
    route,
    query: {
      'uid': uid,
      'page': page,
      if (firstItem.isNotEmpty) 'firstItem': firstItem,
      if (lastItem.isNotEmpty) 'lastItem': lastItem,
    },
  );

  Future<FeedPage> getUserFeedPage(
    String uid,
    int page, {
    String firstItem = '',
    String lastItem = '',
  }) async {
    final root = await _get('/v6/user/feedList', {
      'uid': uid,
      'page': page,
      'firstItem': firstItem,
      'lastItem': lastItem,
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
  }) async {
    await officialMultipart(
      '/v6/collection/create',
      fields: {
        'title': title,
        'description': description,
        'isOpen': isOpen ? '1' : '0',
        'pic': '',
        'sourceId': '',
      },
    );
  }

  Future<Map<String, dynamic>> officialMultipart(
    String path, {
    Map<String, String> fields = const {},
    Map<String, dynamic> query = const {},
    Uint8List? avatar,
    String? expectedScope,
  }) async {
    final scope = expectedScope ?? notificationSessionKey;
    if (!hasCookie ||
        scope != notificationSessionKey ||
        !await notificationSessionMatches(scope) ||
        scope != notificationSessionKey) {
      throw const CoolapkApiException('请先使用酷安账号登录');
    }
    if (!const [
      '/v6/collection/create',
      '/v6/account/changeAvatar',
      '/v6/message/send',
      '/v6/feed/createFeed',
    ].contains(path)) {
      throw const CoolapkApiException('不支持的提交类型');
    }
    final form = FormData.fromMap({
      ...fields,
      if (avatar != null)
        'imgFile': MultipartFile.fromBytes(avatar, filename: 'avatar.png'),
    });
    final response = await _dio.post<dynamic>(
      path,
      data: form,
      queryParameters: query,
      options: Options(
        headers: {'Cookie': _cookie, 'X-App-Token': _auth.token()},
      ),
    );
    final root = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (root is! Map) throw const CoolapkApiException('服务器返回无效数据');
    final result = Map<String, dynamic>.from(root);
    _checkBusinessStatus(result);
    return result;
  }

  Future<void> sendMessage(String uid, String message, {String? pic}) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid) ||
        (message.trim().isEmpty && (pic?.isEmpty ?? true))) {
      throw const CoolapkApiException('私信内容或收件人无效');
    }
    await officialMultipart(
      '/v6/message/send',
      query: {'uid': uid, 'quick_reply': 1},
      fields: {
        'message': message,
        'message_pic': pic ?? '',
        'message_extra': '',
      },
    );
  }

  Future<String> uploadMessageImage(Uint8List bytes, String toUid) =>
      _uploadImage(bytes, toUid, message: true);

  Future<String> uploadReplyImage(Uint8List bytes) async {
    final session = notificationSessionKey;
    if (currentUid.isEmpty) await checkLogin();
    if (notificationSessionKey != session) {
      throw const CoolapkApiException('账号已变更');
    }
    return _uploadImage(bytes, currentUid, message: false);
  }

  Future<String> _uploadImage(
    Uint8List bytes,
    String toUid, {
    required bool message,
  }) async {
    final scope = notificationSessionKey;
    if (!hasCookie ||
        !RegExp(r'^[1-9]\d*$').hasMatch(toUid) ||
        bytes.length < 24 ||
        bytes.length > 16 * 1024 * 1024 ||
        bytes[0] != 137 ||
        bytes[1] != 80 ||
        !await notificationSessionMatches(scope)) {
      throw const CoolapkApiException('图片或登录状态无效');
    }
    final width = ByteData.sublistView(bytes).getUint32(16);
    final height = ByteData.sublistView(bytes).getUint32(20);
    final prepare = await request(
      '/v6/upload/ossUploadPrepare',
      method: 'POST',
      body: {
        'uploadBucket': message ? 'message' : 'image',
        'uploadDir': message ? 'message' : 'feed',
        'is_anonymous': 0,
        'uploadFileList': jsonEncode([
          {
            'name': message ? 'message.png' : 'feed.png',
            'resolution': '${width}x$height',
            'md5': md5.convert(bytes).toString(),
            'hdr': 0,
          },
        ]),
        'toUid': toUid,
        'feed_type': message ? '' : 'feed',
      },
    );
    if (!await notificationSessionMatches(scope)) {
      throw const CoolapkApiException('账号已变更');
    }
    final data = prepare is Map ? prepare['data'] : null;
    if (data is! Map ||
        data['fileInfo'] is! List ||
        (data['fileInfo'] as List).isEmpty ||
        data['uploadPrepareInfo'] is! Map) {
      throw const CoolapkApiException('未获得上传凭据');
    }
    final info = Map<String, dynamic>.from(
      (data['fileInfo'] as List).first as Map,
    );
    final credentials = Map<String, dynamic>.from(
      data['uploadPrepareInfo'] as Map,
    );
    String validImageUrl(String raw) {
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          !(uri.host.endsWith('.coolapk.com') ||
              uri.host.endsWith('.aliyuncs.com'))) {
        throw const CoolapkApiException('图片地址无效');
      }
      return uri.replace(scheme: 'https').toString();
    }

    if (info['url'] is String && (info['url'] as String).isNotEmpty) {
      return validImageUrl(info['url'] as String);
    }
    final key = '${info['uploadFileName'] ?? ''}';
    final endpoint = Uri.tryParse(
      '${credentials['endPoint']}'.startsWith('http')
          ? '${credentials['endPoint']}'
          : 'https://${credentials['endPoint']}',
    );
    final bucket = '${credentials['bucket'] ?? ''}';
    if (endpoint == null ||
        !endpoint.host.endsWith('.aliyuncs.com') ||
        endpoint.userInfo.isNotEmpty ||
        !RegExp(r'^[a-z0-9-]+$').hasMatch(bucket) ||
        key.isEmpty ||
        key.contains('..') ||
        key.startsWith('/')) {
      throw const CoolapkApiException('上传地址无效');
    }
    final accessId = '${credentials['accessKeyId'] ?? ''}';
    final secret = '${credentials['accessKeySecret'] ?? ''}';
    final securityToken = '${credentials['securityToken'] ?? ''}';
    if (accessId.isEmpty || secret.isEmpty || securityToken.isEmpty) {
      throw const CoolapkApiException('上传凭据不完整');
    }
    const callback =
        'eyJjYWxsYmFja0JvZHlUeXBlIjoiYXBwbGljYXRpb25cL2pzb24iLCJjYWxsYmFja0hvc3QiOiJhcGkuY29vbGFway5jb20iLCJjYWxsYmFja1VybCI6Imh0dHBzOlwvXC9hcGkuY29vbGFway5jb21cL3Y2XC9jYWxsYmFja1wvbW9iaWxlT3NzVXBsb2FkU3VjY2Vzc0NhbGxiYWNrP2NoZWNrQXJ0aWNsZUNvdmVyUmVzb2x1dGlvbj0wJnZlcnNpb25Db2RlPTIxMDIwMzEiLCJjYWxsYmFja0JvZHkiOiJ7XCJidWNrZXRcIjoke2J1Y2tldH0sXCJvYmplY3RcIjoke29iamVjdH0sXCJoYXNQcm9jZXNzXCI6JHt4OnZhcjF9fSJ9';
    const callbackVar = 'eyJ4OnZhcjEiOiJmYWxzZSJ9';
    final date = HttpDate.format(DateTime.now().toUtc());
    final digest = base64Encode(md5.convert(bytes).bytes);
    final sign =
        'PUT\n$digest\nimage/png\n$date\nx-oss-callback:$callback\nx-oss-callback-var:$callbackVar\nx-oss-security-token:$securityToken\n/$bucket/$key';
    final signature = base64Encode(
      Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(sign)).bytes,
    );
    final upload = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    try {
      await upload.putUri(
        Uri(scheme: 'https', host: '$bucket.${endpoint.host}', path: '/$key'),
        data: Stream.value(bytes),
        options: Options(
          followRedirects: false,
          headers: {
            'Authorization': 'OSS $accessId:$signature',
            'Content-MD5': digest,
            'Content-Type': 'image/png',
            'Content-Length': bytes.length,
            'Date': date,
            'x-oss-callback': callback,
            'x-oss-callback-var': callbackVar,
            'x-oss-security-token': securityToken,
          },
        ),
      );
    } finally {
      upload.close(force: true);
    }
    if (!await notificationSessionMatches(scope)) {
      throw const CoolapkApiException('账号已变更');
    }
    return validImageUrl(
      '${credentials['uploadImagePrefix'] ?? 'https://image.coolapk.com'}/$key',
    );
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
    if (data is Map<String, dynamic>) {
      if (path == '/v6/user/space' || path == '/v6/user/profile') {
        final raw = data['data'];
        if (raw is Map) {
          final nested = raw['userInfo'] ?? raw['user_info'];
          final user = nested is Map ? nested : raw;
          final uid = '${query['uid'] ?? ''}';
          _localUsers[uid] = {
            'uid': uid,
            'username':
                '${user['username'] ?? _localUsers[uid]?['username'] ?? '酷友 $uid'}',
            'userAvatar':
                '${user['userAvatar'] ?? user['avatar'] ?? _localUsers[uid]?['userAvatar'] ?? ''}',
          };
          if (_localUsers.length > 128) {
            _localUsers.remove(_localUsers.keys.first);
          }
        }
      }
      return data;
    }
    throw const CoolapkApiException('酷安返回了无法识别的响应');
  }

  String? _rememberGuestSession(Response<dynamic> response, String? previous) {
    final uri = response.realUri;
    if (uri.scheme != 'https' ||
        !const ['api.coolapk.com', 'api2.coolapk.com'].contains(uri.host)) {
      return previous;
    }
    for (final value in response.headers['set-cookie'] ?? const <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(value);
        if (cookie.name != 'SESSID') continue;
        final expired =
            cookie.maxAge == 0 ||
            (cookie.expires?.isBefore(DateTime.now().toUtc()) ?? false);
        final session = expired || cookie.value.isEmpty
            ? null
            : 'SESSID=${cookie.value}';
        if (guestSessionCookie == previous) guestSessionCookie = session;
        return session;
      } on FormatException {
        // Ignore malformed server cookies; never import account cookies here.
      }
    }
    return previous;
  }

  void _checkBusinessStatus(
    Map<String, dynamic> root, {
    String? sentValidation,
  }) {
    final challenge = CoolapkCaptchaChallenge.fromResponse(root);
    if (challenge != null) {
      if (sentValidation != null && _acceptedValidation == sentValidation) {
        _acceptedValidation = null;
      }
      throw CoolapkCaptchaException(
        challenge,
        _captchaContext,
        _string(root['message']).isEmpty
            ? '当前访问需要验证码'
            : _string(root['message']),
      );
    }
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
          return seen.add(coolapkEntityKey(item));
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> parseUserFollowList(
    Map<String, dynamic> root,
  ) {
    const containers = [
      'data',
      'entities',
      'rows',
      'list',
      'items',
      'cardRows',
      'card_rows',
      'entityList',
      'entity_list',
      'userInfo',
      'user_info',
      'user',
      'userEntity',
      'user_entity',
      'followUser',
      'follow_user',
    ];
    final users = <Map<String, dynamic>>[];
    final seen = <String>{};
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is! Map) return;
      final user = Map<String, dynamic>.from(value);
      final followedInfo = user['fUserInfo'];
      if (user.containsKey('fuid') || followedInfo is Map) {
        final followed = followedInfo is Map
            ? Map<String, dynamic>.from(followedInfo)
            : <String, dynamic>{};
        final uid = _string(user['fuid'] ?? followed['uid']);
        if (uid.isNotEmpty && seen.add(uid)) {
          users.add({
            ...followed,
            'uid': uid,
            'id': uid,
            'username': followed['username'] ?? user['fusername'] ?? '',
            'userAvatar': followed['userAvatar'] ?? user['fUserAvatar'] ?? '',
            'entityType': 'user',
          });
        }
        // Relationship rows use uid for the owner, fuid for the followed user.
        return;
      }
      final type = _string(user['entityType'] ?? user['entity_type'])
          .toLowerCase();
      final uid = _string(
        user['uid'] ??
            user['userId'] ??
            user['user_id'] ??
            (type.contains('user') || type == 'contacts' ? user['id'] : null),
      );
      final hasUserDetails =
          _string(user['username'] ?? user['userName'] ?? user['name'])
              .isNotEmpty ||
          _string(user['userAvatar'] ?? user['avatar']).isNotEmpty;
      final hasNestedEntities = containers.any(user.containsKey);
      if (uid.isNotEmpty &&
          (type.contains('user') ||
              type == 'contacts' ||
              hasUserDetails && !hasNestedEntities) &&
          seen.add(uid)) {
        user['uid'] = uid;
        user['entityType'] = 'user';
        users.add(user);
      }
      for (final key in containers) {
        if (user.containsKey(key)) visit(user[key]);
      }
    }

    visit(root['data']);
    return users;
  }

  static bool _hasMore(
    Map<String, dynamic> root,
    int itemCount, {
    bool allowShortPage = false,
  }) {
    final value = root['hasMore'] ?? root['has_more'] ?? root['hasNextPage'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == '1' || value == 'true') return true;
    if (value == '0' || value == 'false') return false;
    return allowShortPage ? itemCount > 0 : itemCount >= 10;
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

Map<String, dynamic> coolapkReplyForm(
  String id,
  String message, {
  String? rid,
  String? pic,
  bool replyAndForward = false,
}) {
  final target = rid != null && rid.isNotEmpty ? rid : id;
  if (target.trim().isEmpty ||
      (message.trim().isEmpty && (pic?.trim().isEmpty ?? true))) {
    throw const CoolapkApiException('评论内容或目标无效');
  }
  return {
    'id': target,
    'type': rid != null && rid.isNotEmpty ? 'reply' : 'feed',
    'message': message,
    if (pic != null && pic.isNotEmpty) 'pic': pic,
    if (replyAndForward) 'replyAndForward': '1',
  };
}

class ApiPage {
  const ApiPage({
    this.total,
    required this.items,
    required this.page,
    required this.hasMore,
    required this.firstItem,
    required this.lastItem,
  });

  final List<Map<String, dynamic>> items;
  final int? total;
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
    this.pictureMetadata = const {},
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
  final Map<String, Map<String, dynamic>> pictureMetadata;
  final String uid;
  final bool liked;
  final bool favorited;
  final Map<String, dynamic> raw;

  bool get isArticle {
    final entityType = (raw['entityType'] ?? raw['entity_type'] ?? '')
        .toString()
        .toLowerCase();
    final feedType = (raw['feedType'] ?? raw['feed_type'] ?? '')
        .toString()
        .toLowerCase();
    final entityTemplate =
        (raw['entityTemplate'] ?? raw['entity_template'] ?? '')
            .toString()
            .toLowerCase();
    return raw['isHtmlArticle'] == 1 ||
        raw['isHtmlArticle'] == '1' ||
        raw['is_html_article'] == 1 ||
        raw['is_html_article'] == '1' ||
        entityType == 'article' ||
        entityType == 'feedarticle' ||
        entityType == 'feed_article' ||
        entityType == 'dyharticle' ||
        entityType == 'news' ||
        feedType == 'feedarticle' ||
        feedType == 'feed_article' ||
        feedType == 'article' ||
        feedType == 'dyharticle' ||
        entityTemplate == 'feedarticle' ||
        entityTemplate == 'feed_article' ||
        entityTemplate == 'article' ||
        entityTemplate == 'dyharticle';
  }

  String get coverUrl {
    for (final key in [
      'message_cover',
      'cover',
      'coverPic',
      'cover_pic',
      'extra_pic',
      'header_image',
      'pic',
    ]) {
      final rawVal = raw[key];
      if (rawVal != null) {
        final s = rawVal.toString().trim();
        if (s.isNotEmpty) {
          final first = s.split(',').first.trim();
          if (first.isNotEmpty &&
              (first.startsWith('http://') ||
                  first.startsWith('https://') ||
                  first.startsWith('//') ||
                  first.startsWith('/'))) {
            return first;
          }
        }
      }
    }
    if (pictures.isNotEmpty) {
      return pictures.first;
    }
    return '';
  }

  static Map<String, Map<String, dynamic>> pictureMetadataFromJson(
    Map<String, dynamic> json,
  ) {
    final metadataByUrl = <String, Map<String, dynamic>>{};
    for (final key in ['picArr', 'imageUriList', 'image_uri_list']) {
      final entries = json[key];
      if (entries is! List) continue;
      for (final entry in entries) {
        if (entry is! Map) continue;
        final metadata = Map<String, dynamic>.from(entry);
        final url = _string(
          metadata['url'] ?? metadata['pic'] ?? metadata['image'],
        );
        if (_validImageUrl(url)) {
          metadataByUrl.update(
            url,
            (previous) => {...previous, ...metadata},
            ifAbsent: () => metadata,
          );
        }
      }
    }
    return metadataByUrl;
  }

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
    final single = _string(
      json['message_cover'] ??
          json['cover'] ??
          json['coverPic'] ??
          json['cover_pic'] ??
          json['pic'] ??
          json['extra_pic'] ??
          json['header_image'],
    );
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
      message: sanitizeCoolapkMessage(rawMessage),
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
      pictureMetadata: pictureMetadataFromJson(json),
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

class CoolapkCaptchaException extends CoolapkApiException {
  const CoolapkCaptchaException(this.challenge, this.contextKey, String message)
    : super(message);
  final CoolapkCaptchaChallenge challenge;
  final String contextKey;
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

String coolapkEntityKey(Map<String, dynamic> value) {
  String identity(Map row) {
    for (final key in ['id', 'uid', 'entityId', 'entity_id', 'url', 'pic']) {
      final candidate = _string(row[key]);
      if (candidate.isNotEmpty && candidate != '0') return candidate;
    }
    return _string(row['title']);
  }

  var id = identity(value);
  if (id.isEmpty && value['entities'] is List) {
    id = (value['entities'] as List).whereType<Map>().map(identity).join('|');
  }
  return '${_string(value['entityType'] ?? value['entity_type'])}:${_string(value['entityTemplate'] ?? value['entity_template'])}:$id:${_string(value['title'])}';
}

String sanitizeCoolapkMessage(String raw) {
  if (raw.isEmpty) return '';
  if (!raw.contains('<') && !raw.contains('&')) return raw.trim();

  var result = raw;
  result = result.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
    '',
  );
  result = result.replaceAll(
    RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
    '',
  );
  result = result.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  result = result.replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n');
  result = result.replaceAllMapped(
    RegExp(
      r'''<img[^>]*alt=["'](\[[^\]]+\])["'][^>]*>''',
      caseSensitive: false,
    ),
    (m) => m.group(1) ?? '',
  );
  result = result.replaceAll(
    RegExp(r'<(?!/?a\b)[^>]+>', caseSensitive: false),
    '',
  );
  return result.trim();
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
