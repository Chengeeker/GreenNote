import 'package:flutter/material.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';
import 'community_ui.dart';
import 'reply_notifications_page.dart';

/// Snapshot IDs before deleting so pagination cannot skip rows as they disappear.
Future<int> clearInboxNotifications(CoolapkApi api, String session) async {
  final ids = <String>{};
  var first = '', last = '';
  for (var page = 1; ; page++) {
    if (page > 100) throw StateError('通知超过单次处理范围，未执行删除');
    if (!api.hasCookie || !await api.notificationSessionMatches(session)) {
      throw StateError('登录账号已改变，请重新打开通知中心');
    }
    final result = await api.getList(
      '/v6/notification/list',
      query: {
        'page': page,
        if (first.isNotEmpty) 'firstItem': first,
        if (last.isNotEmpty) 'lastItem': last,
      },
    );
    final before = ids.length;
    for (final item in result.items) {
      final id = communityText(item, ['id', 'notificationId', 'nid']);
      if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
        throw StateError('通知标识无效，未执行清除');
      }
      ids.add(id);
    }
    if (!result.hasMore || result.items.isEmpty) break;
    if (before == ids.length) throw StateError('通知分页重复，未执行清除');
    if (result.firstItem.isNotEmpty) first = result.firstItem;
    last = result.lastItem;
  }
  for (final id in ids) {
    await communityRequest(
      api,
      session,
      '/v6/notification/delete',
      method: 'POST',
      query: {'id': id},
    );
  }
  return ids.length;
}

class OfficialNotificationCenterPage extends StatefulWidget {
  const OfficialNotificationCenterPage({
    super.key,
    required this.api,
    required this.messagesBuilder,
  });
  final CoolapkApi api;
  final WidgetBuilder messagesBuilder;

  @override
  State<OfficialNotificationCenterPage> createState() =>
      _OfficialNotificationCenterPageState();
}

class _OfficialNotificationCenterPageState
    extends State<OfficialNotificationCenterPage> {
  late final String _session = widget.api.notificationSessionKey;
  Map<String, dynamic> _counts = {};
  bool _working = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    if (!widget.api.hasCookie) return;
    try {
      final response = await communityRequest(
        widget.api,
        _session,
        '/v6/notification/checkCount',
      );
      if (mounted && widget.api.notificationSessionKey == _session) {
        setState(() => _counts = communityData(response));
      }
    } catch (_) {
      // A failed badge query must not hide the independently loaded inbox.
    }
  }

  Future<void> _action({required bool clear}) async {
    if (_working) return;
    if (clear &&
        !await confirmCommunityAction(
          context,
          '清除通知',
          '清除通知中心的全部系统消息和评论回复通知？此操作无法撤销，不会删除评论、动态或私信。',
        )) {
      return;
    }
    if (!mounted || _working) return;
    setState(() => _working = true);
    try {
      if (clear) {
        final count = await clearInboxNotifications(widget.api, _session);
        if (mounted) {
          AppToast.show(context, count == 0 ? '暂无可清除的通知' : '已清除 $count 条通知');
        }
      } else {
        await communityRequest(
          widget.api,
          _session,
          '/v6/notification/clearCount',
          method: 'POST',
          query: {'type': 'all'},
        );
        if (mounted) {
          setState(() => _counts = {});
          AppToast.show(context, '已设为全部已读');
        }
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, '${clear ? '清除未完成' : '设为已读失败'}：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _revision++;
        });
        _loadCounts();
      }
    }
  }

  Future<void> _open(String title, WidgetBuilder builder) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: ReviewFrostedAppBar(title: Text(title)),
          body: builder(context),
        ),
      ),
    );
    if (mounted) _loadCounts();
  }

  Widget _shortcut(
    String title,
    IconData icon,
    Color color,
    String countKey,
    VoidCallback onTap,
  ) {
    final count = int.tryParse('${_counts[countKey]}') ?? 0;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF1E1E1E) : Colors.white;
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          onSurface: dark ? const Color(0xFFCCCCCC) : const Color(0xFF292929),
          onSurfaceVariant: dark
              ? const Color(0xFFBBBBBB)
              : const Color(0xFF666666),
        ),
      ),
      child: Scaffold(
        backgroundColor: background,
        appBar: ReviewFrostedAppBar(
          title: const Text('通知中心'),
          centerTitle: false,
          backgroundColor: background,
          showBottomBorder: false,
          toolbarHeight: 64,
          titleTextStyle: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontSize: 23,
            color: dark ? const Color(0xFFD1D1D1) : const Color(0xFF222222),
          ),
          actions: [
            IconButton(
              tooltip: '设为全部已读',
              onPressed: _working || !widget.api.hasCookie
                  ? null
                  : () => _action(clear: false),
              icon: const _ReadAllIcon(),
            ),
            IconButton(
              tooltip: '清除通知',
              onPressed: _working || !widget.api.hasCookie
                  ? null
                  : () => _action(clear: true),
              icon: const Icon(Icons.delete_outline_rounded, size: 27),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (_working) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ReplyNotificationsPage(
                key: ValueKey(_revision),
                api: widget.api,
                showAppBar: false,
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
                  child: Row(
                    children: [
                      _shortcut(
                        '点赞',
                        Icons.thumb_up_alt_rounded,
                        const Color(0xFFF44336),
                        'feedlike',
                        () => _open(
                          '收到的赞',
                          (_) => ReplyNotificationsPage(
                            api: widget.api,
                            showAppBar: false,
                            path: '/v6/notification/feedLikeList',
                          ),
                        ),
                      ),
                      _shortcut(
                        '关注',
                        Icons.person_rounded,
                        const Color(0xFF2196F3),
                        'contacts_follow',
                        () => _open(
                          '关注',
                          (_) => ReplyNotificationsPage(
                            api: widget.api,
                            showAppBar: false,
                            path: '/v6/notification/contactsFollowList',
                          ),
                        ),
                      ),
                      _shortcut(
                        '私信',
                        Icons.mail_rounded,
                        const Color(0xFFFF9800),
                        'message',
                        () => _open('私信', widget.messagesBuilder),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadAllIcon extends StatelessWidget {
  const _ReadAllIcon();
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 28),
    painter: _ReadAllPainter(IconTheme.of(context).color ?? Colors.grey),
  );
}

class _ReadAllPainter extends CustomPainter {
  _ReadAllPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(3, 14)
        ..lineTo(9, 23)
        ..lineTo(20, 4),
      paint,
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(21 - i * 2, 16 + i * 4),
        Offset(25, 16 + i * 4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ReadAllPainter oldDelegate) => oldDelegate.color != color;
}
