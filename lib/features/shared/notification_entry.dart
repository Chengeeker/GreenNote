import '../feed/feed_pages.dart';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/coolapk_url_handler.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import 'community_ui.dart';
import 'reply_notifications_page.dart';

({String name, String uid, String avatar}) notificationActor(
  Map<String, dynamic> item,
  String path,
) {
  final like = path.endsWith('/feedLikeList');
  final user = communityMap(
    like ? item['likeUserInfo'] : item['fromUserInfo'] ?? item['userInfo'],
  );
  final name = communityText(
    item,
    like ? ['likeUsername'] : ['fromusername', 'username'],
  );
  final uid = communityText(
    item,
    like ? ['likeUid', 'likeuid'] : ['fromuid', 'uid'],
  );
  final avatar = communityText(
    item,
    like ? ['likeAvatar', 'likeUserAvatar'] : ['fromUserAvatar', 'userAvatar'],
  );
  return (
    name: name.isEmpty ? communityText(user, ['username']) : name,
    uid: uid.isEmpty ? communityText(user, ['uid']) : uid,
    avatar: avatar.isEmpty ? communityText(user, ['userAvatar']) : avatar,
  );
}

({String sender, String action, String content, bool system})
notificationTextParts(Map<String, dynamic> item, String path) {
  final actor = notificationActor(item, path);
  final sender = actor.name;
  final uid = actor.uid;
  final like = path.endsWith('/feedLikeList');
  final system = !like && sender.isEmpty && (uid.isEmpty || uid == '0');
  final note = communityText(item, ['note', 'infoHtml', 'description']);
  final fragment = html.parseFragment(note);
  final firstLink = fragment.querySelector('a');
  if (firstLink != null &&
      firstLink.text.trim() == sender &&
      sender.isNotEmpty) {
    firstLink.remove();
  }
  var content = fragment.outerHtml.trim();
  var action = '';
  final text = fragment.text?.trim() ?? '';
  final match = RegExp(
    r'^(评论了你的动态|回复了你的评论|回复了你|在动态中提到了你|在评论中提到了你|提到了你|赞了你的动态|赞了你的评论|关注了你)',
  ).firstMatch(text);
  if (match != null) {
    action = match[1]!;
    content = content
        .replaceFirst(action, '')
        .replaceFirst(RegExp(r'^[\s：:]+'), '');
  }
  final message = communityText(item, ['message']);
  if (message.isNotEmpty) content = message;
  if (content.isEmpty && action.isEmpty) content = note;
  // The feed link wraps the notification body; the whole row opens that target.
  for (final link in html.parseFragment(content).querySelectorAll('a[href]')) {
    final href = link.attributes['href'] ?? '';
    if (RegExp(r'/feed/[1-9]\d*').hasMatch(href)) {
      content = content.replaceFirst(link.outerHtml, link.innerHtml);
    }
  }
  if (like) {
    final type = sanitizeCoolapkMessage(
      communityText(item, ['feedTypeName', 'infoHtml']),
    );
    action = '赞了你的${type.isEmpty ? '动态' : type}';
    content = communityText(item, ['message']);
  }
  if (action.isEmpty && path.contains('contactsFollowList')) action = '关注了你';
  return (
    sender: system
        ? '系统消息'
        : sender.isEmpty
        ? '酷友'
        : sender,
    action: action,
    content: content,
    system: system,
  );
}

class NotificationEntry extends StatefulWidget {
  const NotificationEntry({
    super.key,
    required this.api,
    required this.item,
    required this.path,
  });
  final CoolapkApi api;
  final Map<String, dynamic> item;
  final String path;
  @override
  State<NotificationEntry> createState() => _NotificationEntryState();
}

class _NotificationEntryState extends State<NotificationEntry> {
  late final _session = widget.api.notificationSessionKey;
  bool _busy = false;
  late bool _liked = communityFlag(widget.item['isLiked']);

  Future<void> _open() async {
    final target = notificationTarget(widget.item);
    var feedId = target.feedId;
    Map<String, dynamic> reply = {};
    try {
      if (target.replyId.isNotEmpty && feedId.isEmpty) {
        reply = communityData(await widget.api.getReplyDetail(target.replyId));
        feedId = communityText(reply, ['feedId', 'feed_id', 'fid']);
        if (feedId.isEmpty) throw StateError('未返回原帖信息，无法定位评论');
      }
      if (!mounted) return;
      if (feedId.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FeedDetailPage(
              api: widget.api,
              feed: CoolapkFeed.fromJson({'id': feedId}),
              initialReplyId: target.replyId,
              initialReply: reply,
            ),
          ),
        );
      } else if (target.url.isNotEmpty) {
        CoolapkUrlHandler.handleUrl(context, widget.api, target.url);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '无法打开通知：$error');
    }
  }

  Future<void> _like(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!widget.api.hasCookie ||
          !await widget.api.notificationSessionMatches(_session) ||
          widget.api.notificationSessionKey != _session) {
        throw StateError('登录账号已改变');
      }
      await widget.api.likeReply(id, liked: _liked);
      if (mounted && widget.api.notificationSessionKey == _session) {
        setState(() => _liked = !_liked);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '点赞失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final parts = notificationTextParts(item, widget.path);
    final actor = notificationActor(item, widget.path);
    final avatar = actor.avatar;
    final targetRow = communityMap(item['targetRow']);
    final preview = communityMap(
      item['feedInfo'] ??
          item['targetFeed'] ??
          targetRow['feed'] ??
          item['feed'] ??
          item['targetRow'],
    );
    final quote = communityMap(item['replyRow'] ?? targetRow['replyRow']);
    final previewText = communityText(preview, [
      'message',
      'title',
      'description',
    ]);
    final target = notificationTarget(item);
    final replyId = target.replyId.isNotEmpty
        ? target.replyId
        : targetRow['entityType'] == 'feed_reply'
        ? communityText(targetRow, ['id'])
        : '';
    final hasReply = RegExp(r'^[1-9]\d*$').hasMatch(replyId);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? const Color(0xFFCCCCCC) : const Color(0xFF292929);
    final muted = dark ? const Color(0xFF8C8C8C) : const Color(0xFF888888);
    final uid = actor.uid;
    final bodyStyle = TextStyle(fontSize: 14, height: 1.35, color: textColor);
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parts.system)
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFA767FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              )
            else
              GestureDetector(
                onTap: uid.isEmpty
                    ? null
                    : () => CoolapkUrlHandler.handleUrl(
                        context,
                        widget.api,
                        '/u/$uid',
                      ),
                child: AppAvatar(
                  api: widget.api,
                  url: avatar,
                  name: parts.sender,
                  size: 38,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: parts.sender,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: textColor,
                                    ),
                                  ),
                                  if (parts.action.isNotEmpty)
                                    TextSpan(
                                      text: ' ${parts.action}',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.normal,
                                        color: muted,
                                      ),
                                    ),
                                ],
                              ),
                              style: TextStyle(
                                height: 1.3,
                                color: textColor,
                              ),
                            ),
                            if (parts.content.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: CoolapkRichText(
                                  api: widget.api,
                                  text: parts.content,
                                  style: bodyStyle,
                                  maxLines: parts.system ? 2 : 4,
                                ),
                              ),
                            if (quote.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 5),
                                padding: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: muted.withValues(alpha: .3),
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                                child: CoolapkRichText(
                                  api: widget.api,
                                  text: communityText(quote, [
                                    'message',
                                    'note',
                                  ]),
                                  style: bodyStyle.copyWith(
                                    fontSize: 13,
                                    color: muted,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!parts.system && previewText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: SizedBox(
                            width: 68,
                            child: Text(
                              html.parseFragment(previewText).text ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.25,
                                color: muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatRelativeTime(
                            communityText(item, [
                              'dateline',
                              'lastupdate',
                              'timestamp',
                            ]),
                          ),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                      if (!parts.system &&
                          hasReply &&
                          !widget.path.endsWith('/feedLikeList')) ...[
                        IconButton(
                          tooltip: _liked ? '取消点赞评论' : '点赞评论',
                          onPressed: _busy ? null : () => _like(replyId),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            _liked
                                ? Icons.thumb_up_alt_rounded
                                : Icons.thumb_up_alt_outlined,
                            size: 18,
                            color: _liked
                                ? Theme.of(context).colorScheme.primary
                                : muted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '回复评论',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReplyThreadPage(api: widget.api, id: replyId),
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.chat_outlined,
                            size: 18,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: muted.withValues(alpha: .13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
