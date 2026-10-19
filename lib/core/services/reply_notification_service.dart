import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' as fg;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart' as wm;

import '../network/coolapk_api.dart';
import 'reply_notification_state.dart';

const _settingsKey = 'greennote.reply_notifications.settings';
const _historyKey = 'greennote.reply_notifications.history';
const _statusKey = 'greennote.reply_notifications.status';
const _leaseKey = 'greennote.reply_notifications.run';
const _visibleKey = 'greennote.reply_notifications.visible_until';
const _workName = 'greennote.reply-notifications';
const _notificationTag = 'greennote_replies';
final replyNotifications = FlutterLocalNotificationsPlugin();
bool _pollRunning = false;

Future<SharedPreferences> _preferences() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}

Map<String, dynamic> _readJson(SharedPreferences prefs, String key) {
  try {
    final value = jsonDecode(prefs.getString(key) ?? '{}');
    return value is Map ? Map<String, dynamic>.from(value) : {};
  } on FormatException {
    return {};
  }
}

Future<ReplyNotificationSettings> readReplyNotificationSettings() async =>
    ReplyNotificationSettings.fromJson(
      _readJson(await _preferences(), _settingsKey),
    );

Future<Map<String, dynamic>> readReplyNotificationStatus() async =>
    _readJson(await _preferences(), _statusKey);

Future<void> saveReplyNotificationSettings(
  ReplyNotificationSettings value,
) async {
  final prefs = await _preferences();
  final old = ReplyNotificationSettings.fromJson(
    _readJson(prefs, _settingsKey),
  );
  if (!old.enabled && value.enabled) await prefs.remove(_historyKey);
  await prefs.setString(
    _settingsKey,
    jsonEncode(
      value.copyWith(revision: DateTime.now().microsecondsSinceEpoch).toJson(),
    ),
  );
}

Future<void> _initializeNotifications({
  void Function(NotificationResponse)? onTap,
}) async {
  await replyNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_reply'),
    ),
    onDidReceiveNotificationResponse: onTap,
  );
}

Future<bool> replyNotificationPermissionGranted() async =>
    await replyNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled() ??
    false;

Future<bool> requestReplyNotificationPermission() async =>
    await replyNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission() ??
    false;

Future<void> clearReplyNotifications() async {
  for (final item in await replyNotifications.getActiveNotifications()) {
    final id = item.id;
    if (item.tag == _notificationTag && id != null) {
      await replyNotifications.cancel(id: id, tag: item.tag);
    }
  }
}

Future<void> _showReplyNotification(
  String scope,
  List<ReplyNotificationItem> items,
  bool preview,
) async {
  final ids = items.map((item) => item.id).toList()..sort();
  final digest = sha256
      .convert(utf8.encode('$scope:${ids.join(',')}'))
      .toString();
  final id = int.parse(digest.substring(0, 7), radix: 16) | 0x10000000;
  await replyNotifications.show(
    id: id,
    title: '收到 ${items.length} 条新评论或回复',
    body: preview && items.first.preview.isNotEmpty
        ? items.first.preview
        : '点按查看酷安回复消息',
    payload: 'reply:$scope',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'greennote_replies_v1',
        '评论与回复',
        channelDescription: '酷安官方账号的新评论和回复提醒',
        icon: 'ic_stat_reply',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.private,
        groupKey: 'greennote_replies',
        tag: _notificationTag,
        onlyAlertOnce: true,
      ),
    ),
  );
}

/// Each worker reads the current credentials locally; no Cookie enters task data.
Future<String> checkForReplyNotifications({
  CoolapkApi? api,
  bool force = false,
  Future<bool> Function()? canNotify,
  Future<void> Function(String, List<ReplyNotificationItem>, bool)? deliver,
}) async {
  if (_pollRunning) return '正在检查回复';
  _pollRunning = true;
  CoolapkApi? client;
  String? scope;
  String? lease;
  ReplyNotificationSettings? settings;
  final now = DateTime.now().millisecondsSinceEpoch;
  var status = <String, dynamic>{};
  Future<bool> stillCurrent() async {
    final prefs = await _preferences();
    final current = ReplyNotificationSettings.fromJson(
      _readJson(prefs, _settingsKey),
    );
    return current.enabled &&
        current.revision == settings!.revision &&
        prefs.getString(_leaseKey) == lease &&
        await client!.notificationSessionMatches(scope!);
  }

  try {
    final prefs = await _preferences();
    settings = ReplyNotificationSettings.fromJson(
      _readJson(prefs, _settingsKey),
    );
    if (!settings.enabled) return '自动检查已关闭';
    client = api ?? await CoolapkApi.create();
    scope = client.notificationSessionKey;
    if (!client.hasCookie || scope.isEmpty) return '请使用酷安账号登录';
    status = _readJson(prefs, _statusKey);
    if (status['scope'] != scope) status = {};
    final failures = status['failures'] is int ? status['failures'] as int : 0;
    final delay = math.min(
      60,
      settings.intervalMinutes * (1 << math.min(failures, 4)),
    );
    final lastAttempt = status['lastAttempt'] is int
        ? status['lastAttempt'] as int
        : 0;
    if (!force && now - lastAttempt < Duration(minutes: delay).inMilliseconds) {
      return '等待下次检查';
    }
    if (!await (canNotify ?? replyNotificationPermissionGranted)()) {
      return '系统通知权限未开启';
    }
    lease = '$now-${math.Random.secure().nextInt(1 << 30)}';
    await prefs.setString(_leaseKey, lease);
    final response = await client.request(
      '/v6/notification/list',
      query: {'page': 1},
    );
    final items = ReplyNotificationItem.parse(response);
    if (!await stillCurrent()) return '会话或设置已变更，已丢弃旧检查';
    final history = ReplyNotificationHistory.fromJson(
      _readJson(prefs, _historyKey),
    );
    final result = history.merge(scope, items);
    if (result.fresh.isNotEmpty) {
      if (!await (canNotify ?? replyNotificationPermissionGranted)()) {
        return '系统通知权限未开启';
      }
      if (!await stillCurrent()) return '会话或设置已变更';
      await (deliver ?? _showReplyNotification)(
        scope,
        result.fresh,
        settings.showPreview,
      );
    }
    if (!await stillCurrent()) return '会话或设置已变更';
    await prefs.setString(_historyKey, jsonEncode(result.history.toJson()));
    final message = history.scope != scope
        ? '已建立检查基线，已有消息不会重复提醒'
        : result.fresh.isEmpty
        ? '检查成功，暂无新回复'
        : '已提醒 ${result.fresh.length} 条新回复';
    await prefs.setString(
      _statusKey,
      jsonEncode({
        'scope': scope,
        'lastAttempt': now,
        'lastSuccess': now,
        'failures': 0,
        'message': message,
      }),
    );
    return message;
  } catch (_) {
    const message = '检查失败，请确认网络正常且官方 Cookie 未过期；将自动降低检查频率';
    try {
      if (scope != null && lease != null && await stillCurrent()) {
        final prefs = await _preferences();
        await prefs.setString(
          _statusKey,
          jsonEncode({
            ...status,
            'scope': scope,
            'lastAttempt': now,
            'failures': math.min(5, (status['failures'] as int? ?? 0) + 1),
            'message': message,
          }),
        );
      }
    } catch (_) {
      // Storage may be unavailable while Android tears down a worker.
    }
    return message;
  } finally {
    _pollRunning = false;
    if (api == null) client?.close();
  }
}

@pragma('vm:entry-point')
void replyNotificationWorker() {
  wm.Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != _workName) return true;
    try {
      final prefs = await _preferences();
      if ((prefs.getInt(_visibleKey) ?? 0) >
              DateTime.now().millisecondsSinceEpoch ||
          await fg.FlutterForegroundTask.isRunningService) {
        return true;
      }
      await _initializeNotifications();
      await checkForReplyNotifications();
      return true;
    } catch (_) {
      return false;
    }
  });
}

@pragma('vm:entry-point')
void replyResidentCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  fg.FlutterForegroundTask.setTaskHandler(_ReplyResidentTask());
}

class _ReplyResidentTask extends fg.TaskHandler {
  Future<void> _check() async {
    try {
      final settings = await readReplyNotificationSettings();
      if (!settings.enabled || settings.mode != ReplyBackgroundMode.resident) {
        await fg.FlutterForegroundTask.stopService();
        return;
      }
      final message = await checkForReplyNotifications();
      if (message == '请使用酷安账号登录' || message == '系统通知权限未开启') {
        await fg.FlutterForegroundTask.stopService();
      }
      fg.FlutterForegroundTask.sendDataToMain(message);
    } catch (_) {
      fg.FlutterForegroundTask.sendDataToMain('常驻检查暂不可用，省电检查仍保留');
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, fg.TaskStarter starter) async {
    await _initializeNotifications();
    await _check();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_check());

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (isTimeout) {
      const message = '常驻检查被系统限时停止，省电检查继续运行';
      try {
        final prefs = await _preferences();
        await prefs.setString(
          _statusKey,
          jsonEncode({..._readJson(prefs, _statusKey), 'message': message}),
        );
      } catch (_) {}
      fg.FlutterForegroundTask.sendDataToMain(message);
    }
  }
}

class ReplyNotificationRuntime extends ChangeNotifier
    with WidgetsBindingObserver {
  ReplyNotificationRuntime._();
  static final instance = ReplyNotificationRuntime._();
  bool initialized = false;
  String? runtimeError;
  CoolapkApi? _api;
  Timer? _timer;
  Future<void> _configuration = Future.value();
  String? _pendingPayload;
  String _scope = '';
  void Function(bool replies)? _open;

  Future<void> initialize() async {
    if (!Platform.isAndroid || initialized) return;
    try {
      await _initializeNotifications(
        onTap: (response) {
          _pendingPayload = response.payload;
          _openPending();
        },
      );
      await wm.Workmanager().initialize(replyNotificationWorker);
      fg.FlutterForegroundTask.initCommunicationPort();
      fg.FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      final launch = await replyNotifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pendingPayload = launch?.notificationResponse?.payload;
      }
      WidgetsBinding.instance.addObserver(this);
      initialized = true;
    } catch (_) {
      runtimeError = '通知服务初始化失败，请重新启动应用后重试';
    }
  }

  void attach(CoolapkApi api, void Function(bool replies) open) {
    if (!initialized) return;
    if (!identical(_api, api)) {
      _api?.localAccount.removeListener(_accountChanged);
      _api = api;
      api.localAccount.addListener(_accountChanged);
    }
    _open = open;
    unawaited(configure());
    _openPending();
  }

  void _openPending() {
    final payload = _pendingPayload;
    if (_api == null || _open == null || payload == null) return;
    _pendingPayload = null;
    if (!RegExp(r'^reply:[0-9a-f]{64}$').hasMatch(payload)) return;
    _open!(
      payload == 'reply:${_api!.notificationSessionKey}' && _api!.hasCookie,
    );
  }

  void _accountChanged() => unawaited(configure());

  void detach(CoolapkApi? api) {
    if (!identical(_api, api)) return;
    _api?.localAccount.removeListener(_accountChanged);
    _api = null;
    _open = null;
    _timer?.cancel();
  }

  void _onTaskData(Object data) {
    if (data is String && data.contains('系统限时')) runtimeError = data;
    notifyListeners();
  }

  Future<void> configure() {
    _configuration = _configuration
        .catchError((_) {})
        .then((_) async {
          if (!initialized || _api == null) return;
          _timer?.cancel();
          runtimeError = null;
          final settings = await readReplyNotificationSettings();
          final newScope = _api!.notificationSessionKey;
          final allowed =
              settings.enabled &&
              _api!.hasCookie &&
              await replyNotificationPermissionGranted();
          var resident = await fg.FlutterForegroundTask.isRunningService;
          if (resident &&
              (!allowed ||
                  settings.mode != ReplyBackgroundMode.resident ||
                  newScope != _scope)) {
            await fg.FlutterForegroundTask.stopService();
            resident = false;
          }
          if (newScope != _scope || !allowed || !settings.showPreview) {
            await clearReplyNotifications();
          }
          _scope = newScope;
          if (!allowed) {
            await wm.Workmanager().cancelByUniqueName(_workName);
            await (await _preferences()).setInt(_visibleKey, 0);
            notifyListeners();
            return;
          }
          await wm.Workmanager().registerPeriodicTask(
            _workName,
            _workName,
            frequency: Duration(
              minutes: math.max(15, settings.intervalMinutes),
            ),
            initialDelay: Duration(
              minutes: math.max(15, settings.intervalMinutes),
            ),
            existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update,
            constraints: wm.Constraints(networkType: wm.NetworkType.connected),
          );
          if (_isVisible &&
              settings.mode == ReplyBackgroundMode.resident &&
              !resident) {
            fg.FlutterForegroundTask.init(
              androidNotificationOptions: fg.AndroidNotificationOptions(
                channelId: 'greennote_reply_monitor',
                channelName: '后台回复检查',
                channelDescription: '用户开启的常驻回复检查服务',
                channelImportance: fg.NotificationChannelImportance.LOW,
                priority: fg.NotificationPriority.LOW,
              ),
              iosNotificationOptions: const fg.IOSNotificationOptions(),
              foregroundTaskOptions: fg.ForegroundTaskOptions(
                eventAction: fg.ForegroundTaskEventAction.repeat(60000),
                autoRunOnBoot: false,
                allowAutoRestart: false,
                stopWithTask: true,
                allowWakeLock: true,
              ),
            );
            final result = await fg.FlutterForegroundTask.startService(
              serviceId: 9127,
              serviceTypes: [fg.ForegroundServiceTypes.dataSync],
              notificationTitle: 'GreenNote 正在检查回复',
              notificationIcon: const fg.NotificationIcon(
                metaDataName: 'greennote_reply_icon',
              ),
              notificationText: '每 ${settings.intervalMinutes} 分钟检查；可在通知中心关闭',
              callback: replyResidentCallback,
            );
            if (result is fg.ServiceRequestFailure) {
              runtimeError = '常驻服务未能启动，省电检查仍已安排；可重新打开应用后重试';
            }
          } else if (resident) {
            await fg.FlutterForegroundTask.updateService(
              notificationText: '每 ${settings.intervalMinutes} 分钟检查；可在通知中心关闭',
            );
          }
          if (_isVisible) {
            _timer = Timer.periodic(
              const Duration(minutes: 1),
              (_) => unawaited(_tick()),
            );
            unawaited(_tick());
          }
          notifyListeners();
        })
        .catchError((_) {
          runtimeError = '通知调度失败，请检查系统通知权限并重试';
          notifyListeners();
        });
    return _configuration;
  }

  bool get _isVisible =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _tick() async {
    if (!_isVisible) return;
    try {
      await (await _preferences()).setInt(
        _visibleKey,
        DateTime.now().add(const Duration(seconds: 90)).millisecondsSinceEpoch,
      );
      if (!await fg.FlutterForegroundTask.isRunningService) {
        await checkForReplyNotifications();
        notifyListeners();
      }
    } catch (_) {
      runtimeError = '前台检查暂不可用，请稍后重试';
      notifyListeners();
    }
  }

  Future<String> checkNow() async {
    final message = await checkForReplyNotifications(force: true);
    notifyListeners();
    return message;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(configure());
    } else {
      _timer?.cancel();
      unawaited(_preferences().then((prefs) => prefs.setInt(_visibleKey, 0)));
    }
  }
}
