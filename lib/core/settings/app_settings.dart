import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/haptic_feedback_util.dart';
import '../theme/app_theme.dart';

class AppSettingsState {
  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = false,
    this.themeSeedArgb = 0xFF2E7D32,
    this.enableHaptics = true,
    this.useFloatingNavBar = true,
    this.isPureBlackDark = false,
    this.useCustomFontWeight = false,
    this.customFontWeightDelta = 0,
    this.systemFontWeightAdjustment = 0,
    this.fontScale = 1.0,
  });

  final ThemeMode themeMode;
  final bool useDynamicColor;
  final int themeSeedArgb;
  final bool enableHaptics;
  final bool useFloatingNavBar;
  final bool isPureBlackDark;
  final bool useCustomFontWeight;
  final int customFontWeightDelta;
  final int systemFontWeightAdjustment;
  final double fontScale;
  int get effectiveFontWeightAdjustment =>
      useCustomFontWeight ? customFontWeightDelta : systemFontWeightAdjustment;
  int get themeColorIndex => AppTheme.themeColors.indexWhere(
    (item) => (item['color'] as Color).toARGB32() == themeSeedArgb,
  );

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    int? themeSeedArgb,
    bool? enableHaptics,
    bool? useFloatingNavBar,
    bool? isPureBlackDark,
    bool? useCustomFontWeight,
    int? customFontWeightDelta,
    int? systemFontWeightAdjustment,
    double? fontScale,
  }) => AppSettingsState(
    themeMode: themeMode ?? this.themeMode,
    useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    themeSeedArgb: themeSeedArgb ?? this.themeSeedArgb,
    enableHaptics: enableHaptics ?? this.enableHaptics,
    useFloatingNavBar: useFloatingNavBar ?? this.useFloatingNavBar,
    isPureBlackDark: isPureBlackDark ?? this.isPureBlackDark,
    useCustomFontWeight: useCustomFontWeight ?? this.useCustomFontWeight,
    customFontWeightDelta: customFontWeightDelta ?? this.customFontWeightDelta,
    systemFontWeightAdjustment:
        systemFontWeightAdjustment ?? this.systemFontWeightAdjustment,
    fontScale: fontScale ?? this.fontScale,
  );
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    _ready = _load();
    unawaited(_initSystemFontWeight());
  }

  static const _channel = MethodChannel('com.green.note/ui');
  static const _pureBlackKey = 'greennote.pure_black';
  static const _customFontKey = 'greennote.custom_font';
  static const _fontDeltaKey = 'greennote.font_delta';
  static const _fontScaleKey = 'greennote.font_scale';
  static const _themeModeKey = 'greennote.theme_mode';
  static const _dynamicColorKey = 'greennote.dynamic_color';
  static const _themeSeedKey = 'greennote.theme_seed_argb';
  static const _floatingKey = 'greennote.floating_nav';
  static const _hapticsKey = 'greennote.enable_haptics';
  static const _webDavUrlKey = 'greennote.webdav.url';
  static const _webDavUsernameKey = 'greennote.webdav.username';
  static const _webDavDirectoryKey = 'greennote.webdav.directory';

  late final Future<void> _ready;

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final modeIndex = preferences.getInt(_themeModeKey) ?? 0;
    final loaded = AppSettingsState(
      themeMode: switch (modeIndex) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      useDynamicColor: preferences.getBool(_dynamicColorKey) ?? false,
      themeSeedArgb:
          int.tryParse(preferences.getString(_themeSeedKey) ?? '', radix: 16) ??
          0xFF2E7D32,
      enableHaptics: preferences.getBool(_hapticsKey) ?? true,
      useFloatingNavBar: preferences.getBool(_floatingKey) ?? true,
      isPureBlackDark: preferences.getBool(_pureBlackKey) ?? false,
      useCustomFontWeight: preferences.getBool(_customFontKey) ?? false,
      customFontWeightDelta: preferences.getInt(_fontDeltaKey) ?? 0,
      systemFontWeightAdjustment: state.systemFontWeightAdjustment,
      fontScale: preferences.getDouble(_fontScaleKey) ?? 1.0,
    );
    HapticFeedbackUtil.isEnabled = loaded.enableHaptics;
    state = loaded;
  }

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  Future<void> _initSystemFontWeight() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFontWeightAdjustmentChanged' &&
          call.arguments is int &&
          mounted) {
        state = state.copyWith(
          systemFontWeightAdjustment: call.arguments as int,
        );
      }
    });
    try {
      final adjustment = await _channel.invokeMethod<int>(
        'getFontWeightAdjustment',
      );
      if (adjustment != null && mounted) {
        state = state.copyWith(systemFontWeightAdjustment: adjustment);
      }
    } on PlatformException {
      /* Native font adjustment is optional off Android. */
    } on MissingPluginException {
      /* Widget tests and non-Android hosts. */
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> setPureBlackDark(bool value) async {
    await _ready;
    final prefs = await _preferences;
    await prefs.setBool(_pureBlackKey, value);
    state = state.copyWith(isPureBlackDark: value);
  }

  Future<void> setUseCustomFontWeight(bool value) async {
    await _ready;
    final prefs = await _preferences;
    await prefs.setBool(_customFontKey, value);
    state = state.copyWith(useCustomFontWeight: value);
  }

  Future<void> setCustomFontWeightDelta(int value) async {
    if (!const [-100, 0, 100, 200, 300].contains(value)) {
      throw const FormatException('字体粗细无效');
    }
    await _ready;
    final prefs = await _preferences;
    await prefs.setInt(_fontDeltaKey, value);
    state = state.copyWith(customFontWeightDelta: value);
  }

  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.80, 1.30);
    await _ready;
    final prefs = await _preferences;
    await prefs.setDouble(_fontScaleKey, clamped);
    state = state.copyWith(fontScale: clamped);
  }

  Future<void> setThemeColorIndex(int index) =>
      setThemeSeed(AppTheme.getSeedColor(index).toARGB32());

  Future<void> setThemeMode(ThemeMode value) async {
    await _ready;
    final prefs = await _preferences;
    final index = switch (value) {
      ThemeMode.system => 0,
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
    };
    await prefs.setInt(_themeModeKey, index);
    state = state.copyWith(themeMode: value);
  }

  Future<void> setDynamicColor(bool value) async {
    await _ready;
    final prefs = await _preferences;
    await prefs.setBool(_dynamicColorKey, value);
    state = state.copyWith(useDynamicColor: value);
  }

  Future<void> setThemeSeed(int value) async {
    await _ready;
    final prefs = await _preferences;
    await prefs.setString(_themeSeedKey, value.toRadixString(16));
    state = state.copyWith(themeSeedArgb: value);
  }

  Future<void> setFloatingNavBar(bool value) async {
    await _ready;
    final prefs = await _preferences;
    await prefs.setBool(_floatingKey, value);
    state = state.copyWith(useFloatingNavBar: value);
  }

  Future<void> setHaptics(bool value) async {
    await _ready;
    HapticFeedbackUtil.isEnabled = value;
    final prefs = await _preferences;
    await prefs.setBool(_hapticsKey, value);
    state = state.copyWith(enableHaptics: value);
  }

  Future<Map<String, String>> loadWebDavConfig() async {
    final prefs = await _preferences;
    return {
      'url': prefs.getString(_webDavUrlKey) ?? '',
      'username': prefs.getString(_webDavUsernameKey) ?? '',
      'directory': prefs.getString(_webDavDirectoryKey) ?? 'Greennote',
    };
  }

  Future<void> saveWebDavConfig({
    required String url,
    required String username,
    required String directory,
  }) async {
    final prefs = await _preferences;
    await prefs.setString(_webDavUrlKey, url);
    await prefs.setString(_webDavUsernameKey, username);
    await prefs.setString(_webDavDirectoryKey, directory);
  }

  Future<Map<String, dynamic>> exportBackup({
    required String webDavUrl,
    required String webDavUsername,
    required String webDavDirectory,
  }) async {
    await _ready;
    return {
      'app': 'Greennote',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'preferences': {
        'themeMode': switch (state.themeMode) {
          ThemeMode.system => 0,
          ThemeMode.light => 1,
          ThemeMode.dark => 2,
        },
        'dynamicColor': state.useDynamicColor,
        'themeSeedArgb': state.themeSeedArgb,
        'enableHaptics': state.enableHaptics,
        'floatingNavBar': state.useFloatingNavBar,
        'pureBlackDark': state.isPureBlackDark,
        'useCustomFontWeight': state.useCustomFontWeight,
        'customFontWeightDelta': state.customFontWeightDelta,
        'webDavUrl': webDavUrl,
        'webDavUsername': webDavUsername,
        'webDavDirectory': webDavDirectory,
      },
    };
  }

  Future<Map<String, String>> restoreBackup(Map<String, dynamic> backup) async {
    await _ready;
    if (backup['app'] != 'Greennote' || backup['version'] != 1) {
      throw const FormatException('这不是兼容的 Greennote 设置备份');
    }
    final raw = backup['preferences'];
    if (raw is! Map) throw const FormatException('备份中缺少设置内容');
    if (raw.keys.any((key) => key is! String)) {
      throw const FormatException('备份中的设置格式无效');
    }

    final values = Map<String, dynamic>.from(raw);
    const requiredKeys = [
      'themeMode',
      'dynamicColor',
      'themeSeedArgb',
      'enableHaptics',
      'webDavUrl',
      'webDavUsername',
      'webDavDirectory',
    ];
    if (requiredKeys.any((key) => !values.containsKey(key))) {
      throw const FormatException('备份中的设置不完整');
    }
    final mode = values['themeMode'] ?? 0;
    final dynamicColor = values['dynamicColor'] ?? true;
    final seed = values['themeSeedArgb'] ?? 0xFF2E7D32;
    final haptics = values['enableHaptics'] ?? true;
    final floating = values.containsKey('floatingNavBar')
        ? values['floatingNavBar']
        : true;
    final pureBlack = values.containsKey('pureBlackDark')
        ? values['pureBlackDark']
        : false;
    final customFont = values.containsKey('useCustomFontWeight')
        ? values['useCustomFontWeight']
        : false;
    final fontDelta = values.containsKey('customFontWeightDelta')
        ? values['customFontWeightDelta']
        : 0;
    final url = values['webDavUrl'] ?? '';
    final username = values['webDavUsername'] ?? '';
    final directory = values['webDavDirectory'] ?? 'Greennote';
    if (mode is! int ||
        mode < 0 ||
        mode > 2 ||
        dynamicColor is! bool ||
        seed is! int ||
        seed < 0 ||
        seed > 0xFFFFFFFF ||
        haptics is! bool ||
        floating is! bool ||
        pureBlack is! bool ||
        customFont is! bool ||
        fontDelta is! int ||
        !const [-100, 0, 100, 200, 300].contains(fontDelta) ||
        url is! String ||
        url.length > 2048 ||
        username is! String ||
        username.length > 512 ||
        directory is! String ||
        directory.length > 256) {
      throw const FormatException('备份中的设置格式无效');
    }

    final prefs = await _preferences;
    await prefs.setInt(_themeModeKey, mode);
    await prefs.setBool(_dynamicColorKey, dynamicColor);
    await prefs.setString(_themeSeedKey, seed.toRadixString(16));
    await prefs.setBool(_hapticsKey, haptics);
    await prefs.setBool(_floatingKey, floating);
    await prefs.setBool(_pureBlackKey, pureBlack);
    await prefs.setBool(_customFontKey, customFont);
    await prefs.setInt(_fontDeltaKey, fontDelta);
    await prefs.setString(_webDavUrlKey, url);
    await prefs.setString(_webDavUsernameKey, username);
    await prefs.setString(_webDavDirectoryKey, directory);
    final restored = state.copyWith(
      themeMode: switch (mode) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      useDynamicColor: dynamicColor,
      themeSeedArgb: seed,
      enableHaptics: haptics,
      useFloatingNavBar: floating,
      isPureBlackDark: pureBlack,
      useCustomFontWeight: customFont,
      customFontWeightDelta: fontDelta,
    );
    HapticFeedbackUtil.isEnabled = haptics;
    state = restored;
    return {'url': url, 'username': username, 'directory': directory};
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>(
      (ref) => AppSettingsNotifier(),
    );
