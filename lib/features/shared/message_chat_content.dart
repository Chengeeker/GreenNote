import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import 'community_ui.dart';

({String uid, String name, String avatar}) messagePartner(
  Map<String, dynamic> row,
) {
  final user = communityMap(row['messageUserInfo'] ?? row['fromUserInfo']);
  final uid = communityText(row, [
    'messageUid',
    'fromuid',
    'toUid',
    'targetUid',
    'uid',
  ]);
  final name = communityText(row, [
    'messageUsername',
    'fromusername',
    'username',
    'userName',
    'title',
  ]);
  final avatar = communityText(row, ['messageUserAvatar', 'fromUserAvatar']);
  return (
    uid: uid.isEmpty ? communityText(user, ['uid']) : uid,
    name: name.isEmpty ? communityText(user, ['username']) : name,
    avatar: avatar.isEmpty ? communityText(user, ['userAvatar']) : avatar,
  );
}

String chatRowKind(Map<String, dynamic> row) {
  final type = communityText(row, ['entityType', 'entity_type']);
  if (type == 'messageExtra') {
    return switch (communityText(row, ['entityTemplate', 'entity_template'])) {
      'float' => 'follow',
      'time' => 'time',
      _ => 'notice',
    };
  }
  if (type.isNotEmpty && type != 'message') return 'hidden';
  return communityText(row, [
        'message',
        'content',
        'text',
        'message_pic',
        'messagePic',
        'pic',
        'picture',
        'image',
        'imageUrl',
      ]).isEmpty
      ? 'hidden'
      : 'message';
}

String chatRowKey(Map<String, dynamic> row) {
  final id = communityText(row, [
    'messageId',
    'message_id',
    'mid',
    'id',
    'ukey',
  ]);
  if (id.isNotEmpty && id != '0') return '${chatRowKind(row)}:$id';
  return '${chatRowKind(row)}:${communityText(row, ['entityId', 'entity_id'])}:${row['dateline']}:${row['title']}:${row['message']}';
}

String chatPictureUrl(Map<String, dynamic> row) {
  final private = communityText(row, ['message_pic', 'messagePic']);
  final id = communityText(row, ['id']);
  if (private.isNotEmpty && RegExp(r'^[1-9]\d*$').hasMatch(id)) {
    return 'https://api.coolapk.com/v6/message/showImage?id=$id&type=n';
  }
  final url = normalizeCoolapkImageUrl(
    private.isNotEmpty
        ? private
        : communityText(row, ['pic', 'picture', 'image', 'imageUrl']),
  );
  final uri = Uri.tryParse(url);
  return uri?.scheme == 'https' && uri!.host.isNotEmpty ? url : '';
}

class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.api,
    required this.row,
    required this.partnerName,
    required this.partnerAvatar,
  });
  final CoolapkApi api;
  final Map<String, dynamic> row;
  final String partnerName, partnerAvatar;

  @override
  Widget build(BuildContext context) {
    final kind = chatRowKind(row);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const muted = Color(0xFF888888);
    if (kind == 'hidden' || kind == 'follow') return const SizedBox.shrink();
    if (kind == 'time' || kind == 'notice') {
      final title = communityText(row, ['title', 'message', 'text']);
      if (title.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 18),
        child: Center(
          child: Container(
            padding: kind == 'notice'
                ? const EdgeInsets.all(8)
                : EdgeInsets.zero,
            decoration: kind == 'notice'
                ? BoxDecoration(
                    color: dark
                        ? const Color(0xFF262626)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: CoolapkRichText(
              api: api,
              text: title,
              textAlign: kind == 'time' ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: kind == 'time' ? 13 : 12,
                height: 1.3,
                color: muted,
              ),
            ),
          ),
        ),
      );
    }
    final fromUid = communityText(row, ['fromuid', 'fromUid', 'uid']);
    final mine = api.currentUid.isNotEmpty && fromUid == api.currentUid;
    final user = communityMap(row['fromUserInfo']);
    final sourceAvatar = communityText(row, ['fromUserAvatar', 'userAvatar']);
    final avatar = sourceAvatar.isNotEmpty
        ? sourceAvatar
        : communityText(user, ['userAvatar']);
    final name = mine ? api.currentUserNickname : partnerName;
    final picture = chatPictureUrl(row);
    final message = communityText(row, ['message', 'content', 'text']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final photo = AppAvatar(
            api: api,
            url: avatar.isNotEmpty
                ? avatar
                : mine
                ? api.currentUserAvatar
                : partnerAvatar,
            name: name.isEmpty ? (mine ? '我' : '酷友') : name,
            size: 44,
          );
          final bubble = Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .76),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? const Color(0xFF009688)
                      : dark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF1F1F1),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(mine ? 18 : 4),
                    topRight: Radius.circular(mine ? 4 : 18),
                    bottomLeft: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (picture.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          picture,
                          headers: coolapkImageHeaders(picture, api: api),
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Text(
                            '图片加载失败',
                            style: TextStyle(
                              color: mine ? Colors.white : muted,
                            ),
                          ),
                        ),
                      ),
                    if (picture.isNotEmpty && message.isNotEmpty)
                      const SizedBox(height: 8),
                    if (message.isNotEmpty)
                      CoolapkRichText(
                        api: api,
                        text: message,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.45,
                          color: mine
                              ? Colors.white
                              : dark
                              ? const Color(0xFFCCCCCC)
                              : const Color(0xFF222222),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          return Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: mine
                ? [bubble, const SizedBox(width: 12), photo]
                : [photo, const SizedBox(width: 12), bubble],
          );
        },
      ),
    );
  }
}
