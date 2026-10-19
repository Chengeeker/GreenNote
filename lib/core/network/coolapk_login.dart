import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

/// An isolated, short-lived account session. Never persist passwords or log Dio errors.
class CoolapkLogin {
  CoolapkLogin({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: 'https://account.coolapk.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
      responseType: ResponseType.plain,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Version/4.0 Chrome/131.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://account.coolapk.com/auth/loginByCoolApk',
      },
    );
  }

  final Dio _dio;
  final _cookies = <String, String>{};
  String? _requestHash;
  final _cancel = CancelToken();

  Future<Response<dynamic>> _request(
    String path, {
    Map<String, String>? data,
    bool bytes = false,
    int redirects = 0,
  }) async {
    final uri = Uri.parse('https://account.coolapk.com').resolve(path);
    if (uri.scheme != 'https' ||
        uri.host != 'account.coolapk.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        redirects > 4) {
      throw const CoolapkLoginException('登录页面跳转异常，请使用官方网页登录');
    }
    final response = await _dio.request<dynamic>(
      uri.toString(),
      data: data,
      cancelToken: _cancel,
      options: Options(
        method: data == null ? 'GET' : 'POST',
        responseType: bytes ? ResponseType.bytes : ResponseType.plain,
        contentType: data == null ? null : Headers.formUrlEncodedContentType,
        headers: {
          'Cookie': cookie,
          'X-Requested-With': data == null
              ? 'com.coolapk.market'
              : 'XMLHttpRequest',
        },
      ),
    );
    for (final header in response.headers['set-cookie'] ?? <String>[]) {
      try {
        final parsed = Cookie.fromSetCookieValue(header);
        final domain = parsed.domain?.replaceFirst(RegExp(r'^\.'), '');
        if (domain != null && domain != 'coolapk.com' && domain != uri.host) {
          continue;
        }
        if (RegExp(r'[\x00-\x20\x7f;,]').hasMatch(parsed.name + parsed.value)) {
          continue;
        }
        if ((parsed.maxAge != null && parsed.maxAge! <= 0) ||
            (parsed.expires?.isBefore(DateTime.now()) ?? false)) {
          _cookies.remove(parsed.name);
        } else {
          _cookies[parsed.name] = parsed.value;
        }
      } on FormatException {
        // An invalid optional cookie must not erase the existing session.
      }
    }
    if ((response.statusCode ?? 0) >= 300) {
      // Never replay a password POST, even when a server redirects it.
      if (data != null) {
        throw const CoolapkLoginException('请使用官方网页完成登录', webRequired: true);
      }
      final location = response.headers.value('location');
      if (location == null) throw const CoolapkLoginException('登录页面缺少跳转地址');
      return _request(
        uri.resolve(location).toString(),
        bytes: bytes,
        redirects: redirects + 1,
      );
    }
    return response;
  }

  String get cookie =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> prepare() async {
    _requestHash = null;
    _cookies.clear();
    await _request('/auth/login?type=mobile');
    final response = await _request('/auth/loginByCoolApk');
    _requestHash = html
        .parse(response.data.toString())
        .body
        ?.attributes['data-request-hash'];
    if (_requestHash == null ||
        _requestHash!.isEmpty ||
        !_cookies.containsKey('SESSID')) {
      throw const CoolapkLoginException('无法获取登录参数，请重试或使用官方网页登录');
    }
  }

  Future<Uint8List> captcha() async {
    final response = await _request(
      '/auth/showCaptchaImage?${DateTime.now().millisecondsSinceEpoch}',
      bytes: true,
    );
    final bytes = Uint8List.fromList((response.data as List).cast<int>());
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const CoolapkLoginException('验证码图片无效，请重新获取');
    }
    return bytes;
  }

  Future<String> login(String account, String password, String captcha) async {
    if (_requestHash == null) throw const CoolapkLoginException('请先重新加载登录参数');
    for (final key in ['uid', 'username', 'token']) {
      _cookies.remove(key);
    }
    final response = await _request(
      '/auth/loginByCoolApk',
      data: {
        'submit': '1',
        'randomNumber': Random().nextDouble().toString().replaceAll(
          '.',
          'undefined',
        ),
        'requestHash': _requestHash!,
        'login': account,
        'password': password,
        'captcha': captcha,
        'code': '',
      },
    );
    dynamic body;
    try {
      body = jsonDecode(response.data.toString());
    } on FormatException {
      throw const CoolapkLoginException('登录响应异常，请使用官方网页登录', webRequired: true);
    }
    if (body is! Map) throw const CoolapkLoginException('登录响应格式错误');
    if (body['status'].toString() == '1') {
      if (!hasAccountCookie(cookie)) {
        throw const CoolapkLoginException('登录响应缺少账号凭据，请使用官方网页登录');
      }
      return cookie;
    }
    final message = body['message'] is String
        ? body['message'] as String
        : '登录失败，请重试';
    throw CoolapkLoginException(
      message,
      captchaRequired:
          message.contains('图形验证码') ||
          (captcha.isNotEmpty && message == '密码错误'),
      webRequired:
          message.contains('人机') ||
          body['messageStatus'] == 'err_request_captcha_v2',
    );
  }

  static bool hasAccountCookie(String cookie) {
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(cookie)) return false;
    final values = <String, String>{};
    for (final part in cookie.split(';')) {
      final index = part.indexOf('=');
      if (index > 0) {
        values[part.substring(0, index).trim()] = part
            .substring(index + 1)
            .trim();
      }
    }
    final uid = values['uid'] ?? '';
    final token = values['token'] ?? '';
    return RegExp(r'^\d+$').hasMatch(uid) &&
        uid != '0' &&
        uid != '10000' &&
        token.isNotEmpty &&
        !RegExp(r'\s').hasMatch(token) &&
        !const ['deleted', 'expired'].contains(token.toLowerCase());
  }

  void close() {
    _cancel.cancel();
    _dio.close(force: true);
    _cookies.clear();
    _requestHash = null;
  }
}

class CoolapkLoginException implements Exception {
  const CoolapkLoginException(
    this.message, {
    this.captchaRequired = false,
    this.webRequired = false,
  });
  final String message;
  final bool captchaRequired;
  final bool webRequired;
  @override
  String toString() => message;
}
