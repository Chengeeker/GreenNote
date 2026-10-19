import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/design_system/components/review_page_scaffold.dart';
import '../../core/design_system/components/review_preference_tile.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/services/reply_notification_service.dart';
import '../../core/services/reply_notification_state.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_section_card.dart';
import '../shared/reply_notifications_page.dart';

class ReplyNotificationSettingsPage extends StatefulWidget {
  const ReplyNotificationSettingsPage({
    super.key,
    required this.api,
    this.requestPermission = requestReplyNotificationPermission,
  });
  final CoolapkApi api;
  final Future<bool> Function() requestPermission;

  @override
  State<ReplyNotificationSettingsPage> createState() =>
      _ReplyNotificationSettingsPageState();
}

class _ReplyNotificationSettingsPageState
    extends State<ReplyNotificationSettingsPage> {
  ReplyNotificationSettings? _settings;
  String _status = '尚未检查';
  bool _permission = false;
  bool _resident = false;
  bool _working = false;
  final _runtime = ReplyNotificationRuntime.instance;

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_refresh);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _runtime.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final settings = await readReplyNotificationSettings();
    final status = await readReplyNotificationStatus();
    final permission =
        _runtime.initialized && await replyNotificationPermissionGranted();
    final resident =
        _runtime.initialized && await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    final success = status['lastSuccess'];
    setState(() {
      _settings = settings;
      _permission = permission;
      _resident = resident;
      _status = status['scope'] == widget.api.notificationSessionKey
          ? '${status['message'] ?? '尚未检查'}${success is int ? '\n上次成功：${DateTime.fromMillisecondsSinceEpoch(success).toLocal().toString().split('.').first}' : ''}'
          : '尚未检查；首次检查只建立基线，不提醒已有消息';
    });
  }

  Future<void> _save(ReplyNotificationSettings settings) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (settings.enabled &&
          !_settings!.enabled &&
          !await widget.requestPermission()) {
        if (mounted) AppToast.show(context, '未获得通知权限，自动检查未开启');
        return;
      }
      await saveReplyNotificationSettings(settings);
      await _runtime.configure();
      await _refresh();
    } catch (_) {
      if (mounted) AppToast.show(context, '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _check() async {
    setState(() => _working = true);
    try {
      final result = await _runtime.checkNow();
      if (mounted) AppToast.show(context, result);
      await _refresh();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    title: '回复提醒设置',
    bodyBuilder: (context, insets) {
      final settings = _settings;
      if (settings == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final official = widget.api.hasCookie;
      return ListView(
        padding: const EdgeInsets.all(16).add(insets),
        children: [
          Text(
            official
                ? '酷安官方 Cookie 账号的评论与回复提醒'
                : '请先使用酷安账号登录；匿名账户与 UID 绑定不支持私有回复提醒。',
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('自动检查新回复'),
                  subtitle: const Text('首次开启或切换 Cookie 后不提醒已有消息'),
                  value: settings.enabled,
                  onChanged: _working || (!official && !settings.enabled)
                      ? null
                      : (value) => _save(settings.copyWith(enabled: value)),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<ReplyBackgroundMode>(
                        initialValue: settings.mode,
                        decoration: const InputDecoration(labelText: '后台检查方式'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: ReplyBackgroundMode.powerSaving,
                            child: Text('省电后台检查'),
                          ),
                          DropdownMenuItem(
                            value: ReplyBackgroundMode.resident,
                            child: Text('常驻后台检查'),
                          ),
                        ],
                        onChanged: _working
                            ? null
                            : (mode) {
                                if (mode != null) {
                                  unawaited(
                                    _save(settings.copyWith(mode: mode)),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        settings.mode == ReplyBackgroundMode.powerSaving
                            ? '后台至少每 15 分钟检查一次，由 Android 调度，省电或断网时可能延迟。'
                            : '显示持续通知并增加耗电。Android 15 及以上限制 dataSync 后台服务累计时长（约 6 小时/24 小时）；停止后转为省电检查，打开应用后重试。',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: settings.intervalMinutes,
                        decoration: const InputDecoration(labelText: '检查间隔'),
                        items: ReplyNotificationSettings.intervals
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value 分钟'),
                              ),
                            )
                            .toList(),
                        onChanged: _working
                            ? null
                            : (value) {
                                if (value != null) {
                                  unawaited(
                                    _save(
                                      settings.copyWith(intervalMinutes: value),
                                    ),
                                  );
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      const Text('应用可见及常驻模式使用所选间隔；省电后台最短 15 分钟。'),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('显示回复内容预览'),
                  subtitle: const Text('默认关闭；开启后通知可能显示回复内容'),
                  value: settings.showPreview,
                  onChanged: _working
                      ? null
                      : (value) => _save(settings.copyWith(showPreview: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Column(
              children: [
                ReviewPreferenceTile(
                  title: '系统通知权限',
                  subtitle: _permission ? '已允许' : '未允许',
                  onTap: () async {
                    await replyNotifications.openAppNotificationSettings();
                  },
                ),
                ReviewPreferenceTile(
                  title: '运行状态',
                  onTap: null,
                  trailing: const SizedBox.shrink(),
                  subtitle:
                      _runtime.runtimeError ??
                      (!settings.enabled
                          ? '已关闭'
                          : !official
                          ? '等待酷安账号登录'
                          : !_permission
                          ? '等待通知权限'
                          : _resident
                          ? '常驻服务运行中，省电检查作为后备'
                          : '省电调度已安排；实际执行时间由系统决定'),
                ),
                ReviewPreferenceTile(
                  title: '检查记录',
                  subtitle: _status,
                  onTap: null,
                  trailing: const SizedBox.shrink(),
                ),
                ReviewPreferenceTile(
                  title: _working ? '正在处理…' : '立即检查',
                  onTap: official && settings.enabled && !_working
                      ? _check
                      : null,
                ),
                ReviewPreferenceTile(
                  title: '查看评论与回复',
                  onTap: !official
                      ? null
                      : () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReplyNotificationsPage(api: widget.api),
                            ),
                          );
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('仅在本机检查回复；不上传 Cookie 或通知内容。强行停止应用后需重新打开，后台及时性取决于系统限制。'),
        ],
      );
    },
  );
}
