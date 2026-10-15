import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One device-local identity; cookies and API credentials never enter this file.
class LocalAccount extends ChangeNotifier {
  LocalAccount(this._prefs) {
    final saved = _prefs.getString(storageKey);
    if (saved != null) _data = validate(jsonDecode(saved));
    active = _prefs.getBool('greennote.local.active') ?? false;
    cookieEnabled = _prefs.getBool('greennote.cookie.enabled') ?? true;
  }

  static const storageKey = 'greennote.local.account';
  final SharedPreferences _prefs;
  Map<String, dynamic> _data = {
    'version': 1,
    'name': '匿名酷友',
    'avatar': '',
    'follows': <String, dynamic>{},
    'favorites': <String, dynamic>{},
  };
  bool active = false;
  bool cookieEnabled = true;
  void reload() {
    final saved = _prefs.getString(storageKey);
    if (saved != null) _data = validate(jsonDecode(saved));
    notifyListeners();
  }

  Future<void> _pending = Future.value();
  String get name => _data['name'] as String;
  String get avatar => _data['avatar'] as String;
  Map<String, dynamic>? get publicIdentity {
    final identity = _data['publicIdentity'];
    return identity is Map ? Map<String, dynamic>.from(identity) : null;
  }

  Map<String, dynamic> get follows =>
      Map<String, dynamic>.from(_data['follows'] as Map);
  Map<String, dynamic> get favorites =>
      Map<String, dynamic>.from(_data['favorites'] as Map);
  Map<String, dynamic> export() =>
      jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;

  static Map<String, dynamic> validate(dynamic raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['name'] is! String ||
        (raw['name'] as String).trim().isEmpty ||
        (raw['name'] as String).length > 40 ||
        raw['avatar'] is! String ||
        (raw['avatar'] as String).length > 400000) {
      throw const FormatException('匿名账户资料无效');
    }
    final avatar = raw['avatar'] as String;
    if (avatar.isNotEmpty) {
      final bytes = base64Decode(avatar);
      if (bytes.length > 300000 ||
          bytes.length < 24 ||
          !(bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47)) {
        throw const FormatException('匿名头像必须是压缩后的 PNG 图片');
      }
      final header = ByteData.sublistView(bytes);
      final width = header.getUint32(16);
      final height = header.getUint32(20);
      if (width < 1 || height < 1 || width > 512 || height > 512) {
        throw const FormatException('备份头像尺寸无效');
      }
    }
    final result = <String, dynamic>{
      'version': 1,
      'name': (raw['name'] as String).trim(),
      'avatar': avatar,
    };
    if (raw.containsKey('publicIdentity')) {
      final identity = raw['publicIdentity'];
      if (identity != null) {
        if (identity is! Map ||
            identity['uid'] is! String ||
            !RegExp(r'^\d{1,30}$').hasMatch(identity['uid'] as String) ||
            identity['username'] is! String ||
            (identity['username'] as String).trim().isEmpty ||
            (identity['username'] as String).length > 40 ||
            identity['userAvatar'] is! String ||
            (identity['userAvatar'] as String).length > 2048) {
          throw const FormatException('公开主页身份资料无效');
        }
        final avatarUrl = identity['userAvatar'] as String;
        final uri = Uri.tryParse(avatarUrl);
        if (avatarUrl.isNotEmpty &&
            (uri == null ||
                !const ['http', 'https'].contains(uri.scheme) ||
                uri.host.isEmpty)) {
          throw const FormatException('公开主页头像地址无效');
        }
        result['publicIdentity'] = {
          'uid': identity['uid'],
          'username': (identity['username'] as String).trim(),
          'userAvatar': avatarUrl,
        };
      }
    }
    for (final field in ['follows', 'favorites']) {
      final entries = raw[field];
      if (entries is! Map || entries.length > 10000) {
        throw const FormatException('匿名账户列表无效或超过 10000 条');
      }
      final checked = <String, dynamic>{};
      for (final entry in entries.entries) {
        if (entry.key is! String ||
            !RegExp(r'^\d{1,30}$').hasMatch(entry.key as String) ||
            entry.value is! Map) {
          throw const FormatException('匿名账户条目无效');
        }
        final item = entry.value as Map;
        final clean = <String, dynamic>{};
        for (final key
            in field == 'follows'
                ? ['uid', 'username', 'userAvatar']
                : [
                    'id',
                    'uid',
                    'username',
                    'userAvatar',
                    'message',
                    'pic',
                    'dateline',
                    'entityType',
                  ]) {
          final value = item[key];
          if (value != null) {
            if (value is! String || value.length > 100000) {
              throw const FormatException('匿名账户条目字段无效');
            }
            clean[key] = value;
          }
        }
        if (clean[field == 'follows' ? 'uid' : 'id'] != entry.key) {
          throw const FormatException('匿名账户条目 ID 不匹配');
        }
        checked[entry.key as String] = clean;
      }
      result[field] = checked;
    }
    if (utf8.encode(jsonEncode(result)).length > 16 * 1024 * 1024) {
      throw const FormatException('匿名账户超过 16 MB，请减少收藏后重试');
    }
    return result;
  }

  Future<void> _update(Map<String, dynamic> Function() change) {
    final operation = _pending.then((_) async {
      final next = validate(change());
      if (!await _prefs.setString(storageKey, jsonEncode(next))) {
        throw StateError('本地账户保存失败');
      }
      _data = next;
      notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> setActive(bool value, {bool enableCookie = false}) async {
    if (!await _prefs.setBool('greennote.cookie.enabled', enableCookie)) {
      throw StateError('账户模式保存失败');
    }
    if (!await _prefs.setBool('greennote.local.active', value)) {
      throw StateError('账户模式保存失败');
    }
    active = value;
    cookieEnabled = enableCookie;
    notifyListeners();
  }

  Future<void> profile(
    String name,
    String avatar, {
    Map<String, dynamic>? publicIdentity,
    bool clearPublicIdentity = false,
  }) => _update(() {
    final next = {..._data, 'name': name.trim(), 'avatar': avatar};
    if (clearPublicIdentity) next.remove('publicIdentity');
    if (publicIdentity != null) next['publicIdentity'] = publicIdentity;
    return next;
  });
  Future<void> setPublicIdentity({
    required String uid,
    required String username,
    required String userAvatar,
  }) => _update(() {
    return {
      ..._data,
      'publicIdentity': {
        'uid': uid,
        'username': username,
        'userAvatar': userAvatar,
      },
    };
  });

  Future<void> clearPublicIdentity() => _update(() {
    return Map<String, dynamic>.from(_data)..remove('publicIdentity');
  });

  Future<void> toggle(String field, String id, Map<String, dynamic> item) =>
      _update(() {
        final entries = Map<String, dynamic>.from(_data[field] as Map);
        if (entries.containsKey(id)) {
          entries.remove(id);
        } else {
          entries[id] = item;
        }
        return {..._data, field: entries};
      });

  Future<void> restore(Map<String, dynamic> data) => _update(() {
    return validate(data);
  });

  Future<void> restoreWithRollback(Map<String, dynamic> data) async {
    final checked = validate(data);
    await _pending;
    if (!await _prefs.setString(
      '$storageKey.before_restore',
      jsonEncode(_data),
    )) {
      throw StateError('无法保留恢复前副本');
    }
    await restore(checked);
  }

  bool get canRollback => _prefs.containsKey('$storageKey.before_restore');
  Future<void> rollback() async {
    final previous = _prefs.getString('$storageKey.before_restore');
    if (previous == null) throw StateError('没有恢复前副本');
    await restoreWithRollback(validate(jsonDecode(previous)));
  }
}
