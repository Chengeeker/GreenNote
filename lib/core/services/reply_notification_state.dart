import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;

enum ReplyBackgroundMode { powerSaving, resident }

class ReplyNotificationSettings {
  const ReplyNotificationSettings({
    this.enabled = false,
    this.mode = ReplyBackgroundMode.powerSaving,
    this.intervalMinutes = 1,
    this.showPreview = false,
    this.revision = 0,
  });

  static const intervals = [1, 5, 15, 30, 60];
  final bool enabled;
  final ReplyBackgroundMode mode;
  final int intervalMinutes;
  final bool showPreview;
  final int revision;

  factory ReplyNotificationSettings.fromJson(Map<String, dynamic> json) =>
      ReplyNotificationSettings(
        enabled: json['enabled'] == true,
        mode: json['mode'] == 'resident'
            ? ReplyBackgroundMode.resident
            : ReplyBackgroundMode.powerSaving,
        intervalMinutes: intervals.contains(json['intervalMinutes'])
            ? json['intervalMinutes'] as int
            : 1,
        showPreview: json['showPreview'] == true,
        revision: json['revision'] is int ? json['revision'] as int : 0,
      );

  ReplyNotificationSettings copyWith({
    bool? enabled,
    ReplyBackgroundMode? mode,
    int? intervalMinutes,
    bool? showPreview,
    int? revision,
  }) => ReplyNotificationSettings(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    showPreview: showPreview ?? this.showPreview,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'intervalMinutes': intervalMinutes,
    'showPreview': showPreview,
    'revision': revision,
  };
}

class ReplyNotificationItem {
  ReplyNotificationItem(this.data)
    : id = _id(data),
      timestamp = _timestamp(data);

  final Map<String, dynamic> data;
  final String id;
  final int timestamp;

  static String _id(Map<String, dynamic> data) {
    final id = data['id'] ?? data['notificationId'] ?? data['nid'];
    if (id != null && '$id'.isNotEmpty && '$id' != '0') return '$id';
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              data['uid'] ?? data['fromuid'],
              data['dateline'] ?? data['lastupdate'],
              data['note'] ?? data['message'] ?? data['description'],
              data['url'],
            ]),
          ),
        )
        .toString();
  }

  static int _timestamp(Map<String, dynamic> data) {
    final raw = data['dateline'] ?? data['lastupdate'] ?? data['timestamp'];
    final value = int.tryParse('$raw') ?? 0;
    return value > 100000000000 ? value ~/ 1000 : math.max(0, value);
  }

  String get preview {
    final raw = data['note'] ?? data['message'] ?? data['description'] ?? '';
    final text = html.parseFragment('$raw').text ?? '';
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .runes
        .take(160)
        .map(String.fromCharCode)
        .join();
  }

  static List<ReplyNotificationItem> parse(dynamic response) {
    dynamic value = response is Map ? response['data'] : response;
    if (value is Map) value = value['list'] ?? value['items'] ?? value['data'];
    if (value is! List || value.any((item) => item is! Map)) {
      throw const FormatException('回复通知数据格式无效');
    }
    // shortcut: only the latest page is checked; paginate if high-volume accounts need full catch-up.
    return value
        .take(50)
        .map(
          (item) =>
              ReplyNotificationItem(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}

class ReplyNotificationHistory {
  const ReplyNotificationHistory({
    this.scope = '',
    this.seen = const [],
    this.watermark = 0,
  });

  final String scope;
  final List<String> seen;
  final int watermark;

  factory ReplyNotificationHistory.fromJson(Map<String, dynamic> json) =>
      ReplyNotificationHistory(
        scope: json['scope'] is String ? json['scope'] as String : '',
        seen: (json['seen'] is List ? json['seen'] as List : const [])
            .whereType<String>()
            .take(200)
            .toList(),
        watermark: json['watermark'] is int ? json['watermark'] as int : 0,
      );

  ({ReplyNotificationHistory history, List<ReplyNotificationItem> fresh}) merge(
    String currentScope,
    List<ReplyNotificationItem> items,
  ) {
    final sameSession = currentScope == scope && scope.isNotEmpty;
    final known = sameSession ? seen.toSet() : <String>{};
    final fresh = <ReplyNotificationItem>[];
    var newest = sameSession ? watermark : 0;
    for (final item in items) {
      if (sameSession &&
          !known.contains(item.id) &&
          (item.timestamp == 0 || item.timestamp >= watermark)) {
        fresh.add(item);
      }
      known.add(item.id);
      newest = math.max(newest, item.timestamp);
    }
    final ordered = <String>{
      if (sameSession) ...seen,
      ...items.reversed.map((item) => item.id),
    }.toList();
    return (
      history: ReplyNotificationHistory(
        scope: currentScope,
        seen: ordered.skip(math.max(0, ordered.length - 200)).toList(),
        watermark: newest,
      ),
      fresh: fresh,
    );
  }

  Map<String, dynamic> toJson() => {
    'scope': scope,
    'seen': seen,
    'watermark': watermark,
  };
}
