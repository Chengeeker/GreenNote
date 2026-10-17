import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 独立的匿名账户实体
class AnonymousProfile {
  AnonymousProfile({
    required this.id,
    required this.name,
    this.avatar = '',
    this.publicIdentity,
    Map<String, dynamic>? follows,
    Map<String, dynamic>? productFollows,
    Map<String, dynamic>? favorites,
    int? createdAt,
  })  : follows = follows != null ? Map<String, dynamic>.from(follows) : <String, dynamic>{},
        productFollows = productFollows != null ? Map<String, dynamic>.from(productFollows) : <String, dynamic>{},
        favorites = favorites != null ? Map<String, dynamic>.from(favorites) : <String, dynamic>{},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  String avatar;
  Map<String, dynamic>? publicIdentity;
  Map<String, dynamic> follows;
  Map<String, dynamic> productFollows;
  Map<String, dynamic> favorites;
  final int createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    if (publicIdentity != null) 'publicIdentity': publicIdentity,
    'follows': follows,
    'productFollows': productFollows,
    'favorites': favorites,
    'createdAt': createdAt,
  };

  factory AnonymousProfile.fromJson(Map<String, dynamic> json) => AnonymousProfile(
    id: json['id'] as String? ?? 'anon_1',
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : '匿名酷友',
    avatar: json['avatar'] as String? ?? '',
    publicIdentity: json['publicIdentity'] is Map
        ? Map<String, dynamic>.from(json['publicIdentity'] as Map)
        : null,
    follows: json['follows'] is Map
        ? Map<String, dynamic>.from(json['follows'] as Map)
        : null,
    productFollows: json['productFollows'] is Map
        ? Map<String, dynamic>.from(json['productFollows'] as Map)
        : null,
    favorites: json['favorites'] is Map
        ? Map<String, dynamic>.from(json['favorites'] as Map)
        : null,
    createdAt: json['createdAt'] as int?,
  );

  AnonymousProfile copyWith({
    String? id,
    String? name,
    String? avatar,
    Map<String, dynamic>? publicIdentity,
    Map<String, dynamic>? follows,
    Map<String, dynamic>? productFollows,
    Map<String, dynamic>? favorites,
    int? createdAt,
  }) =>
      AnonymousProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        publicIdentity: publicIdentity ??
            (this.publicIdentity != null
                ? Map<String, dynamic>.from(this.publicIdentity!)
                : null),
        follows: follows ?? Map<String, dynamic>.from(this.follows),
        productFollows: productFollows ??
            Map<String, dynamic>.from(this.productFollows),
        favorites: favorites ?? Map<String, dynamic>.from(this.favorites),
        createdAt: createdAt ?? this.createdAt,
      );
}

/// 支持多匿名账户容器管理与切换的本地账户服务；Cookie 与凭据绝不进入此文件。
class LocalAccount extends ChangeNotifier {
  LocalAccount(this._prefs) {
    _loadFromPreferences();
    active = _prefs.getBool('greennote.local.active') ?? false;
    cookieEnabled = _prefs.getBool('greennote.cookie.enabled') ?? true;
  }

  static const storageKey = 'greennote.local.account';
  static const activeProfileIdKey = 'greennote.local.active_profile_id';
  final SharedPreferences _prefs;

  List<AnonymousProfile> _profiles = [];
  String _activeProfileId = 'anon_1';
  bool active = false;
  bool cookieEnabled = true;

  Future<void> _pending = Future.value();

  void _loadFromPreferences() {
    final saved = _prefs.getString(storageKey);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved);
        _applyData(validate(decoded));
        return;
      } catch (_) {}
    }
    final initial = AnonymousProfile(id: 'anon_1', name: '匿名酷友');
    _profiles = [initial];
    _activeProfileId = 'anon_1';
  }

  void _applyData(Map<String, dynamic> data) {
    if (data.containsKey('profiles') && data['profiles'] is List) {
      _profiles = (data['profiles'] as List)
          .map((p) => AnonymousProfile.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();
      final prefActiveId = _prefs.getString(activeProfileIdKey);
      if (prefActiveId != null && _profiles.any((p) => p.id == prefActiveId)) {
        _activeProfileId = prefActiveId;
      } else {
        _activeProfileId = data['activeProfileId'] as String? ??
            (_profiles.isNotEmpty ? _profiles.first.id : 'anon_1');
      }
    } else {
      _profiles = [
        AnonymousProfile(
          id: 'anon_1',
          name: data['name'] as String? ?? '匿名酷友',
          avatar: data['avatar'] as String? ?? '',
          publicIdentity: data['publicIdentity'] is Map
              ? Map<String, dynamic>.from(data['publicIdentity'])
              : null,
          follows: data['follows'],
          productFollows: data['productFollows'],
          favorites: data['favorites'],
        ),
      ];
      _activeProfileId = 'anon_1';
    }
  }

  void reload() {
    _loadFromPreferences();
    active = _prefs.getBool('greennote.local.active') ?? false;
    cookieEnabled = _prefs.getBool('greennote.cookie.enabled') ?? true;
    notifyListeners();
  }

  /// 所有保存的匿名账户列表
  List<AnonymousProfile> get profiles => List.unmodifiable(_profiles);

  /// 当前激活的匿名账户 ID
  String get activeProfileId => _activeProfileId;

  /// 当前激活的匿名账户对象
  AnonymousProfile get activeProfile {
    final found = _profiles.where((p) => p.id == _activeProfileId);
    if (found.isNotEmpty) return found.first;
    if (_profiles.isNotEmpty) return _profiles.first;
    final fallback = AnonymousProfile(id: 'anon_1', name: '匿名酷友');
    _profiles.add(fallback);
    _activeProfileId = fallback.id;
    return fallback;
  }

  // --- 向后兼容的当前激活账户属性 ---
  String get name => activeProfile.name;
  String get avatar => activeProfile.avatar;
  Map<String, dynamic>? get publicIdentity => activeProfile.publicIdentity != null
      ? Map<String, dynamic>.from(activeProfile.publicIdentity!)
      : null;
  Map<String, dynamic> get follows => Map<String, dynamic>.from(activeProfile.follows);
  Map<String, dynamic> get productFollows =>
      Map<String, dynamic>.from(activeProfile.productFollows);
  Map<String, dynamic> get favorites =>
      Map<String, dynamic>.from(activeProfile.favorites);

  /// 导出全量多匿名账户数据（包含当前账户镜像以完全兼容 v1 恢复与测试）
  Map<String, dynamic> export() {
    final current = activeProfile;
    return {
      'version': 2,
      'activeProfileId': _activeProfileId,
      'profiles': _profiles.map((p) => p.toJson()).toList(),
      'name': current.name,
      'avatar': current.avatar,
      if (current.publicIdentity != null)
        'publicIdentity': current.publicIdentity,
      'follows': current.follows,
      'productFollows': current.productFollows,
      'favorites': current.favorites,
    };
  }

  /// 校验单个账户的资料完整性与限制
  static Map<String, dynamic> _validateSingleProfile(dynamic raw, {String? defaultId}) {
    if (raw is! Map ||
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
      'id': raw['id'] as String? ?? defaultId ?? 'anon_1',
      'name': (raw['name'] as String).trim(),
      'avatar': avatar,
      'createdAt': raw['createdAt'] is int ? raw['createdAt'] : DateTime.now().millisecondsSinceEpoch,
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
    for (final field in ['follows', 'productFollows', 'favorites']) {
      final entries = raw[field] ?? (field == 'productFollows' ? {} : null);
      if (entries is! Map || entries.length > 10000) {
        throw const FormatException('匿名账户列表无效或超过 10000 条');
      }
      final checked = <String, dynamic>{};
      final idField = switch (field) {
        'follows' => 'uid',
        'productFollows' => 'id',
        _ => 'id',
      };
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
                : field == 'productFollows'
                ? ['id', 'title', 'pic', 'logo', 'cover', 'hot_num', 'votenum']
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
        if (clean[idField] != entry.key) {
          throw const FormatException('匿名账户条目 ID 不匹配');
        }
        checked[entry.key as String] = clean;
      }
      result[field] = checked;
    }
    return result;
  }

  /// 校验与清洗匿名账户资料（同时支持单账户与多账户格式）
  static Map<String, dynamic> validate(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('匿名账户资料无效');
    }
    // 多账户格式 (version 2)
    if (raw.containsKey('profiles') && raw['profiles'] is List) {
      final list = raw['profiles'] as List;
      if (list.isEmpty || list.length > 50) {
        throw const FormatException('匿名账户列表必须包含 1 至 50 个账户');
      }
      final validatedProfiles = <Map<String, dynamic>>[];
      for (int i = 0; i < list.length; i++) {
        validatedProfiles.add(
          _validateSingleProfile(list[i], defaultId: 'anon_${i + 1}'),
        );
      }
      final activeId = raw['activeProfileId'] as String? ??
          validatedProfiles.first['id'] as String;
      final activeIndex = validatedProfiles.indexWhere((p) => p['id'] == activeId);
      final activeMap = activeIndex != -1 ? validatedProfiles[activeIndex] : validatedProfiles.first;

      // 若外部直接在顶层修改了镜像字段（例如测试中的 backup..['name'] = 'xxx'，或修改了 publicIdentity、favorites 等），
      // 需要统一校验并同步至 activeMap，确保顶层镜像修改得到完整校验与生效
      final topLevelCandidate = <String, dynamic>{
        'name': raw.containsKey('name') ? raw['name'] : activeMap['name'],
        'avatar': raw.containsKey('avatar') ? raw['avatar'] : activeMap['avatar'],
        if (raw.containsKey('publicIdentity'))
          'publicIdentity': raw['publicIdentity']
        else if (activeMap.containsKey('publicIdentity'))
          'publicIdentity': activeMap['publicIdentity'],
        'follows': raw.containsKey('follows') ? raw['follows'] : activeMap['follows'],
        'productFollows': raw.containsKey('productFollows') ? raw['productFollows'] : activeMap['productFollows'],
        'favorites': raw.containsKey('favorites') ? raw['favorites'] : activeMap['favorites'],
      };
      final validatedActive = _validateSingleProfile(
        topLevelCandidate,
        defaultId: activeMap['id'] as String?,
      );
      validatedProfiles[activeIndex != -1 ? activeIndex : 0] = validatedActive;

      final result = <String, dynamic>{
        'version': 2,
        'activeProfileId': validatedActive['id'],
        'profiles': validatedProfiles,
        'name': validatedActive['name'],
        'avatar': validatedActive['avatar'],
        if (validatedActive.containsKey('publicIdentity'))
          'publicIdentity': validatedActive['publicIdentity'],
        'follows': validatedActive['follows'],
        'productFollows': validatedActive['productFollows'],
        'favorites': validatedActive['favorites'],
      };
      if (utf8.encode(jsonEncode(result)).length > 32 * 1024 * 1024) {
        throw const FormatException('匿名账户超过 32 MB，请减少收藏后重试');
      }
      return result;
    }

    // 单账户旧格式 (version 1)
    if (raw['version'] != 1 && raw['version'] != null) {
      throw const FormatException('匿名账户资料版本无效');
    }
    final single = _validateSingleProfile(raw, defaultId: 'anon_1');
    final result = <String, dynamic>{
      'version': 1,
      'name': single['name'],
      'avatar': single['avatar'],
      if (single.containsKey('publicIdentity'))
        'publicIdentity': single['publicIdentity'],
      'follows': single['follows'],
      'productFollows': single['productFollows'],
      'favorites': single['favorites'],
      'profiles': [single],
      'activeProfileId': single['id'],
    };
    if (utf8.encode(jsonEncode(result)).length > 16 * 1024 * 1024) {
      throw const FormatException('匿名账户超过 16 MB，请减少收藏后重试');
    }
    return result;
  }

  Future<void> _save() {
    final operation = _pending.then((_) async {
      final exportData = export();
      final validated = validate(exportData);
      if (!await _prefs.setString(storageKey, jsonEncode(validated))) {
        throw StateError('本地账户保存失败');
      }
      await _prefs.setString(activeProfileIdKey, _activeProfileId);
      _applyData(validated);
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

  /// 创建新的匿名账户
  Future<AnonymousProfile> createProfile({
    String? name,
    String? avatar,
    Map<String, dynamic>? publicIdentity,
    bool switchNow = true,
  }) async {
    final nextIndex = _profiles.length + 1;
    final cleanName = (name ?? '').trim().isNotEmpty
        ? name!.trim()
        : '匿名账户$nextIndex';
    final newId = 'anon_${DateTime.now().millisecondsSinceEpoch}_$nextIndex';
    final profile = AnonymousProfile(
      id: newId,
      name: cleanName,
      avatar: avatar ?? '',
      publicIdentity: publicIdentity,
    );
    _profiles.add(profile);
    if (switchNow) {
      _activeProfileId = newId;
      await _prefs.setString(activeProfileIdKey, newId);
      await setActive(true);
    }
    await _save();
    return profile;
  }

  /// 切换至指定的匿名账户
  Future<void> switchProfile(String id) async {
    if (!_profiles.any((p) => p.id == id)) {
      throw ArgumentError('不存在该匿名账户: $id');
    }
    _activeProfileId = id;
    await _prefs.setString(activeProfileIdKey, id);
    await setActive(true);
    await _save();
  }

  /// 删除指定的匿名账户
  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) {
      // 最后一个账户被删除时，重置为崭新的匿名账户
      _profiles = [AnonymousProfile(id: 'anon_1', name: '匿名酷友')];
      _activeProfileId = 'anon_1';
      await _prefs.setString(activeProfileIdKey, 'anon_1');
      await _save();
      return;
    }
    _profiles.removeWhere((p) => p.id == id);
    if (_activeProfileId == id) {
      _activeProfileId = _profiles.first.id;
      await _prefs.setString(activeProfileIdKey, _activeProfileId);
    }
    await _save();
  }

  /// 更新指定匿名账户的信息
  Future<void> updateProfile(
    String id, {
    String? name,
    String? avatar,
    Map<String, dynamic>? publicIdentity,
    bool clearPublicIdentity = false,
  }) async {
    final index = _profiles.indexWhere((p) => p.id == id);
    if (index == -1) throw ArgumentError('不存在该匿名账户: $id');
    final p = _profiles[index];
    final candidate = AnonymousProfile(
      id: p.id,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : p.name,
      avatar: avatar ?? p.avatar,
      publicIdentity: clearPublicIdentity
          ? null
          : (publicIdentity ??
              (p.publicIdentity != null
                  ? Map<String, dynamic>.from(p.publicIdentity!)
                  : null)),
      follows: Map<String, dynamic>.from(p.follows),
      productFollows: Map<String, dynamic>.from(p.productFollows),
      favorites: Map<String, dynamic>.from(p.favorites),
      createdAt: p.createdAt,
    );
    _validateSingleProfile(candidate.toJson(), defaultId: candidate.id);
    _profiles[index] = candidate;
    await _save();
  }

  /// 更新当前激活匿名账户资料
  Future<void> profile(
    String name,
    String avatar, {
    Map<String, dynamic>? publicIdentity,
    bool clearPublicIdentity = false,
  }) =>
      updateProfile(
        _activeProfileId,
        name: name,
        avatar: avatar,
        publicIdentity: publicIdentity,
        clearPublicIdentity: clearPublicIdentity,
      );

  /// 为当前激活匿名账户绑定公开主页 UID
  Future<void> setPublicIdentity({
    required String uid,
    required String username,
    required String userAvatar,
  }) =>
      updateProfile(
        _activeProfileId,
        publicIdentity: {
          'uid': uid,
          'username': username,
          'userAvatar': userAvatar,
        },
      );

  /// 清除当前激活匿名账户的公开主页 UID
  Future<void> clearPublicIdentity() =>
      updateProfile(_activeProfileId, clearPublicIdentity: true);

  /// 在当前激活匿名账户中添加/移除关注或收藏
  Future<void> toggle(String field, String id, Map<String, dynamic> item) async {
    final p = activeProfile;
    final map = switch (field) {
      'follows' => p.follows,
      'productFollows' => p.productFollows,
      _ => p.favorites,
    };
    if (map.containsKey(id)) {
      map.remove(id);
    } else {
      map[id] = item;
    }
    await _save();
  }

  Future<void> restore(Map<String, dynamic> data) async {
    final validated = validate(data);
    _applyData(validated);
    await _save();
  }

  Future<void> restoreWithRollback(Map<String, dynamic> data) async {
    final checked = validate(data);
    await _pending;
    if (!await _prefs.setString(
      '$storageKey.before_restore',
      jsonEncode(export()),
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
