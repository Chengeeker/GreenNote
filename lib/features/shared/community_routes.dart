import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import 'community_detail_page.dart';
import 'community_ui.dart';
import 'reply_notifications_page.dart';
import '../feed/feed_pages.dart';

Widget? communityPageForEntity(CoolapkApi api, Map<String, dynamic> data) {
  final feedType = communityText(data, ['feedType', 'feed_type']).toLowerCase();
  final entityType = communityText(data, [
    'entityType',
    'entity_type',
  ]).toLowerCase();
  final type =
      '${data['entityType'] ?? ''} ${data['feedType'] ?? ''} ${data['targetType'] ?? ''}'
          .toLowerCase();
  final id = communityText(data, ['id', 'entityId']);
  if (id.isEmpty) return null;
  if (type.contains('answer')) {
    return FeedDetailPage(
      api: api,
      feed: CoolapkFeed.fromJson(data),
      adaptCommunity: false,
      questionId: communityText(data, ['questionId', 'question_id', 'fid']),
    );
  }
  final CommunityKind? kind;
  if (type.contains('question')) {
    kind = CommunityKind.question;
  } else if (type.trim() == 'live' || type.contains('livecard')) {
    kind = CommunityKind.live;
  } else if (type.contains('productalbum') || type.contains('anylist')) {
    kind = CommunityKind.anylist;
  } else if (feedType == 'goodslist' ||
      entityType == 'goodslist' ||
      type.contains('goodsrank') ||
      (feedType.isEmpty &&
          communityMap(data['goodsListInfo']).keys.any(
            (key) => const ['title', 'item_num', 'is_open_vote'].contains(key),
          ))) {
    kind = CommunityKind.goods;
  } else if (type.contains('collection')) {
    kind = CommunityKind.collection;
  } else if (type.contains('dyh') && !type.contains('article')) {
    kind = CommunityKind.dyh;
  } else if (type.trim() == 'album') {
    kind = CommunityKind.album;
  } else {
    kind = null;
  }
  return kind == null
      ? null
      : CommunityDetailPage(api: api, id: id, kind: kind, initial: data);
}

Widget? communityPageForUrl(
  CoolapkApi api,
  String value, {
  Map<String, dynamic> initial = const {},
}) {
  var raw = value.trim();
  if (raw.startsWith('#/')) raw = raw.substring(1);
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.hasAuthority &&
      uri.scheme != 'coolmarket' &&
      uri.host != 'coolapk.com' &&
      !uri.host.endsWith('.coolapk.com')) {
    return null;
  }
  var parts = uri.pathSegments;
  if (uri.scheme == 'coolmarket') parts = [uri.host, ...parts];
  if (parts.length < 2) return null;
  final id = parts[1] == 'detail' ? uri.queryParameters['id'] ?? '' : parts[1];
  final replyId =
      uri.queryParameters['rid'] ?? uri.queryParameters['replyId'] ?? '';
  if (parts[0] == 'reply' ||
      (parts[0] == 'feed' && parts[1] == 'reply' && parts.length > 2)) {
    final target = parts[0] == 'reply' ? id : parts[2];
    if (RegExp(r'^[1-9]\d*$').hasMatch(target)) {
      return ReplyThreadPage(api: api, id: target);
    }
  }
  if (parts[0] == 'feed' && RegExp(r'^[1-9]\d*$').hasMatch(replyId)) {
    return ReplyThreadPage(api: api, id: replyId);
  }
  final kind = switch (parts[0]) {
    'question' => CommunityKind.question,
    'live' => CommunityKind.live,
    'collection' => CommunityKind.collection,
    'dyh' => CommunityKind.dyh,
    'album' => CommunityKind.album,
    'anylist' || 'productAlbum' => CommunityKind.anylist,
    'goods' when parts.length > 2 && (id == 'lists' || id == 'ranking') =>
      CommunityKind.goods,
    _ => null,
  };
  if (kind == null) return null;
  final target = parts[0] == 'goods' ? parts[2] : id;
  if (!RegExp(r'^[1-9]\d*$').hasMatch(target)) return null;
  return CommunityDetailPage(
    api: api,
    id: target,
    kind: kind,
    initial: initial,
  );
}
