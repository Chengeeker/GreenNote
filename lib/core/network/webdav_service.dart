import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

class WebDavService {
  WebDavService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: false,
        ),
      );

  final Dio _dio;

  static String normalizeServerUrl(String value) {
    var input = value.trim();
    if (input.isEmpty) throw const FormatException('请输入 WebDAV 服务器地址');
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://$input';
    }
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('WebDAV 地址无效');
    }
    final loopback =
        uri.host == 'localhost' ||
        (InternetAddress.tryParse(uri.host)?.isLoopback ?? false);
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) {
      throw const FormatException('WebDAV 必须使用 HTTPS；HTTP 仅允许本机回环地址');
    }
    return uri
        .replace(
          path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
          query: null,
          fragment: null,
        )
        .toString();
  }

  static List<String> directorySegments(String value) {
    final segments = value
        .trim()
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.isEmpty ||
        segments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('\\') ||
              part.contains(RegExp(r'[\x00-\x1F]')),
        )) {
      throw const FormatException('备份目录无效');
    }
    return segments;
  }

  static bool isValidServerUrl(String value) {
    try {
      normalizeServerUrl(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  String _authorization(String username, String password) =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _baseUri(String serverUrl) => Uri.parse(normalizeServerUrl(serverUrl));

  Uri _withSegments(Uri base, List<String> segments) => base.replace(
    pathSegments: [...base.pathSegments, ...segments],
    query: null,
    fragment: null,
  );

  Options _options(
    String method,
    String authorization, {
    Map<String, String> headers = const {},
    ResponseType? responseType,
  }) => Options(
    method: method,
    followRedirects: false,
    responseType: responseType ?? ResponseType.plain,
    headers: {'Authorization': authorization, ...headers},
    validateStatus: (status) => status != null && status < 500,
  );

  Future<bool> testConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.request<void>(
        _baseUri(serverUrl).toString(),
        options: _options(
          'PROPFIND',
          _authorization(username, password),
          headers: const {'Depth': '0'},
          responseType: ResponseType.plain,
        ),
      );
      return response.statusCode == 200 || response.statusCode == 207;
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directory,
    required Map<String, dynamic> data,
  }) async {
    try {
      final base = _baseUri(serverUrl);
      final authorization = _authorization(username, password);
      final segments = directorySegments(directory);
      var current = base;
      for (var i = 0; i < segments.length; i++) {
        current = _withSegments(current, [segments[i]]);
        final response = await _dio.request<void>(
          current.toString(),
          options: _options('MKCOL', authorization),
        );
        if (response.statusCode != 200 &&
            response.statusCode != 201 &&
            response.statusCode != 405) {
          return false;
        }
      }
      final backupUri = _withSegments(current, [
        'greennote_settings_latest.json',
      ]);
      final response = await _dio.put<String>(
        backupUri.toString(),
        data: const JsonEncoder.withIndent('  ').convert(data),
        options: Options(
          headers: {
            'Authorization': authorization,
            'Content-Type': 'application/json; charset=utf-8',
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> downloadLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directory,
  }) async {
    try {
      final uri = _withSegments(
        _withSegments(_baseUri(serverUrl), directorySegments(directory)),
        ['greennote_settings_latest.json'],
      );
      final response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Authorization': _authorization(username, password)},
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode != 200 || response.data == null) return null;
      final decoded = jsonDecode(response.data!);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
