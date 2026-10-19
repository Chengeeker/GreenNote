import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../core/network/coolapk_api.dart';
import '../../core/utils/coolapk_url_handler.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import 'api_list_page.dart';
import 'community_ui.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../feed/feed_pages.dart';

({String feedId, String replyId, String url}) notificationTarget(
  Map<String, dynamic> data,
) {
  final target = communityMap(data['targetRow']);
  final feed = communityMap(data['feedInfo'] ?? data['targetFeed']);
  final sources = [data, target, feed];
  String feedId = '', replyId = '', url = '';
  for (final source in sources) {
    for (final field in ['note', 'message', 'infoHtml', 'url', 'targetUrl']) {
      final text = '${source[field] ?? ''}'.replaceAll('&amp;', '&');
      final links = html.parseFragment(text).querySelectorAll('a[href]').map((node) => node.attributes['href']!).toList();
      if (field == 'url' || field == 'targetUrl') links.add(text);
      for (final link in links) {
        final uri = Uri.tryParse(link);
        if (uri == null || link.isEmpty) continue;
        if (url.isEmpty && ['http', 'https'].contains(uri.scheme)) url = link;
        final official = uri.scheme == 'coolmarket' || (!uri.hasAuthority && link.startsWith('/')) ||
          uri.host == 'coolapk.com' || uri.host.endsWith('.coolapk.com');
        if (!official) continue;
        if (url.isEmpty) url = link;
        final path = uri.scheme == 'coolmarket' ? '/${uri.host}${uri.path}' : uri.path;
        final feedMatch = RegExp(r'/feed/([1-9]\d*)(?:/|$)').firstMatch(path);
        if (feedId.isEmpty && feedMatch != null) { feedId = feedMatch[1]!; url = link; }
        final replyMatch = RegExp(r'(?:/feed/reply/|/reply/)([1-9]\d*)').firstMatch(path);
        final reply = uri.queryParameters['rid'] ?? uri.queryParameters['replyId'] ?? uri.queryParameters['reply_id'] ?? replyMatch?[1] ?? '';
        if (replyId.isEmpty && RegExp(r'^[1-9]\d*$').hasMatch(reply)) { replyId = reply; url = link; }
      }
    }
    if (replyId.isEmpty) {
      replyId = communityText(source, ['replyId', 'reply_id']);
    }
    if (feedId.isEmpty) {
      feedId = communityText(source, ['feedId', 'feed_id', 'fid']);
    }
  }
  if (feedId.isEmpty && feed.isNotEmpty) feedId = communityText(feed, ['id']);
  final type = '${data['targetType'] ?? data['target_type'] ?? ''}';
  if (replyId.isEmpty && RegExp('reply|comment').hasMatch(type)) {
    replyId = communityText(data, ['targetId', 'target_id']);
  }
  return (feedId: RegExp(r'^[1-9]\d*$').hasMatch(feedId) ? feedId : '', replyId: RegExp(r'^[1-9]\d*$').hasMatch(replyId) ? replyId : '', url: url);
}

class ReplyNotificationsPage extends StatelessWidget {
  const ReplyNotificationsPage({
    super.key,
    required this.api,
    this.showAppBar = true,
    this.title = '评论与回复',
    this.path = '/v6/notification/list',
  });
  final CoolapkApi api;
  final bool showAppBar;
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) => ApiListPage(
    api: api,
    title: title,
    path: path,
    showAppBar: showAppBar,
    showAccessErrors: true,
    itemBuilder: (context, item) {
      final like = path.contains('Like');
      final sender = like
          ? item['likeUsername'] ??
                communityMap(item['likeUserInfo'])['username'] ??
                '酷友'
          : item['fromusername'] ??
                communityMap(item['fromUserInfo'])['username'] ??
                item['username'] ??
                '酷友';
      final content =
          item['note'] ??
          item['message'] ??
          item['infoHtml'] ??
          item['description'] ??
          '';
      final target = notificationTarget(item);
      final preview = communityMap(item['targetRow'] ?? item['feedInfo']);
      return ListTile(
        title: Text('$sender'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoolapkRichText(api: api, text: '$content'),
            if (preview.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: CoolapkRichText(
                  api: api,
                  text: communityText(preview, ['message', 'title']),
                  maxLines: 3,
                ),
              ),
          ],
        ),
        trailing:
            target.url.isEmpty &&
                target.feedId.isEmpty &&
                target.replyId.isEmpty
            ? null
            : const Icon(Icons.chevron_right),
        onTap:
            target.url.isEmpty &&
                target.feedId.isEmpty &&
                target.replyId.isEmpty
            ? null
            : () {
                if (target.replyId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ReplyThreadPage(api: api, id: target.replyId),
                    ),
                  );
                } else if (target.feedId.isNotEmpty) {
                  CoolapkUrlHandler.handleUrl(
                    context,
                    api,
                    '/feed/${target.feedId}',
                  );
                } else {
                  CoolapkUrlHandler.handleUrl(context, api, target.url);
                }
              },
      );
    },
  );
}

class ReplyThreadPage extends StatefulWidget {
  const ReplyThreadPage({
    super.key,
    required this.api,
    required this.id,
    this.initial = const {},
  });
  final CoolapkApi api;
  final String id;
  final Map<String, dynamic> initial;
  @override
  State<ReplyThreadPage> createState() => _ReplyThreadPageState();
}

class _ReplyThreadPageState extends State<ReplyThreadPage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _revision = 0;
  late final String _session;
  @override
  void initState() {
    super.initState();
    _session = widget.api.notificationSessionKey;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = communityData(await widget.api.getReplyDetail(widget.id));
      if (mounted) {
        setState(() {
          _data = {...widget.initial, ...data};
          _error = null;
          _revision++;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '评论详情加载失败，点击重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: const Text('评论详情')),
    body: _data == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : TextButton(onPressed: _load, child: Text(_error!)),
          )
        : ApiListPage(
            key: ValueKey(_revision),
            api: widget.api,
            title: '楼中楼回复',
            path: '/v6/feed/replyList',
            query: {'id': widget.id, 'feedType': 'feed_reply'},
            showAppBar: false,
            showAccessErrors: true,
            header: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    communityText(_data!, ['username']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  CoolapkRichText(
                    api: widget.api,
                    text: communityText(_data!, ['message', 'note']),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      CommunityAction(
                        api: widget.api,
                        label: '回复这条评论',
                        icon: Icons.reply,
                        action: () async {
                          final values = await editCommunityFields(
                            context,
                            '回复评论',
                            {'内容': ''},
                            limits: {'内容': 5000},
                          );
                          if (values == null) return;
                          if (widget.api.notificationSessionKey != _session ||
                              !await widget.api.notificationSessionMatches(
                                _session,
                              )) {
                            throw StateError('Account changed');
                          }
                          await widget.api.reply(
                            communityText(_data!, ['feedId', 'feed_id', 'fid']),
                            values['内容']!,
                            rid: widget.id,
                          );
                          await _load();
                        },
                      ),
                      if (communityText(_data!, [
                        'feedId',
                        'feed_id',
                        'fid',
                      ]).isNotEmpty)
                        OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FeedDetailPage(
                                api: widget.api,
                                feed: CoolapkFeed.fromJson({
                                  'id': communityText(_data!, [
                                    'feedId',
                                    'feed_id',
                                    'fid',
                                  ]),
                                }),
                              ),
                            ),
                          ),
                          child: const Text('查看原动态'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            itemBuilder: (context, item) => ListTile(
              title: Text(communityText(item, ['username'])),
              subtitle: CoolapkRichText(
                api: widget.api,
                text: communityText(item, ['message']),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReplyThreadPage(
                    api: widget.api,
                    id: communityText(item, ['id']),
                    initial: item,
                  ),
                ),
              ),
            ),
          ),
  );
}
