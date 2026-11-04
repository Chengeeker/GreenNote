import 'package:flutter/material.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_image.dart';
import '../../core/utils/coolapk_url_handler.dart';
import '../../core/widgets/cached_network_image.dart';
import 'api_list_page.dart';
import 'app_detail_page.dart';
import 'community_ui.dart';
import 'rating_square_page.dart' show ratingNodeScore;

String _countText(
  Map<String, dynamic> item,
  List<String> keys, {
  bool compact = true,
}) {
  var raw = communityText(item, keys);
  raw = raw.replaceFirst(RegExp(r'(条动态|讨论)$'), '').trim();
  final number = num.tryParse(raw);
  return compact && number != null && number >= 10000
      ? '${(number / 10000).toStringAsFixed(1)}万'
      : raw;
}

// Topic commentnum counts published discussions, not replies under a feed.
String accountTopicCount(Map<String, dynamic> item) => _countText(item, [
  'commentnum_txt',
  'commentNumTxt',
  'commentnumTxt',
  'comment_num_txt',
  'feedNumTxt',
  'feed_num_txt',
  'feednum_txt',
  'commentnum',
  'comment_num',
  'feednum',
  'feed_num',
  'feedNum',
  'feeds',
  'feed',
]);

String accountEntityCategory(Map<String, dynamic> item) {
  final declared = communityText(item, [
    'typeName',
    'entityTypeName',
    'type_name',
  ]);
  final url = communityText(item, ['url']);
  final uri = Uri.tryParse(url.startsWith('#/') ? url.substring(1) : url);
  for (final type in [
    declared,
    communityText(item, ['targetType', 'target_type']),
    communityText(item, ['entityType', 'entity_type']),
    uri?.path.split('/').where((part) => part.isNotEmpty).firstOrNull ?? '',
  ]) {
    final label = switch (type.toLowerCase()) {
      'product' || '数码' => '数码',
      'topic' || 'tag' || 't' || '话题' => '话题',
      'user' || 'u' || '用户' => '用户',
      'apk' || 'app' || '应用' => '应用',
      'feed' || '动态' => '动态',
      'collection' || '收藏单' => '收藏单',
      'dyh' || '看看号' => '看看号',
      _ => '',
    };
    if (label.isNotEmpty) return label;
  }
  return declared;
}

String _entityName(Map<String, dynamic> item) => communityText(item, [
  'title',
  'username',
  'userName',
  'name',
  'productName',
  'apkName',
  'tag',
  'tagName',
]);

class AccountTopicListPage extends StatelessWidget {
  const AccountTopicListPage({
    required this.api,
    required this.followedTopics,
    super.key,
  });
  final CoolapkApi api;
  final bool followedTopics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final panel = dark ? const Color(0xFF1E1E1E) : theme.colorScheme.surface;
    return Scaffold(
      backgroundColor: dark
          ? const Color(0xFF101010)
          : theme.colorScheme.surfaceContainerLow,
      appBar: ReviewFrostedAppBar(
        backgroundColor: panel,
        showBottomBorder: false,
        centerTitle: false,
        title: Text(
          followedTopics ? '我关注的话题' : '我的常去',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: ColoredBox(
            color: panel,
            child: ApiListPage(
              api: api,
              title: followedTopics ? '我关注的话题' : '我的常去',
              path: followedTopics
                  ? '/v6/topic/myFollowTopicList'
                  : '/v6/user/recentHistoryList',
              showAppBar: false,
              padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemFilter: (item) => _entityName(item).isNotEmpty,
              itemBuilder: (_, item) => _AccountTopicRow(
                api: api,
                item: item,
                followedTopics: followedTopics,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTopicRow extends StatelessWidget {
  const _AccountTopicRow({
    required this.api,
    required this.item,
    required this.followedTopics,
  });
  final CoolapkApi api;
  final Map<String, dynamic> item;
  final bool followedTopics;

  void _open(BuildContext context) {
    final url = communityText(item, ['url']);
    if (url.isNotEmpty) {
      CoolapkUrlHandler.handleUrl(context, api, url);
      return;
    }
    final id = communityText(item, [
      'uid',
      'id',
      'entityId',
      'productId',
      'packageName',
    ]);
    final title = _entityName(item);
    final category = accountEntityCategory(item);
    final Widget page;
    if (category == '话题' || followedTopics) {
      final tag = ApiEntityCard.extractTopicTag(item);
      if (tag.isEmpty) return;
      page = TopicPage(
        api: api,
        tag: tag,
        initialTitle: title,
        initialLogo: communityText(item, ['logo', 'icon', 'pic']),
      );
    } else if (category == '用户' && id.isNotEmpty) {
      page = UserSpacePage(api: api, uid: id);
    } else if (category == '数码' && id.isNotEmpty) {
      page = ProductPage(api: api, id: id, title: title);
    } else if (category == '应用' && id.isNotEmpty) {
      page = AppDetailPage(api: api, id: id, initialEntity: item);
    } else {
      page = RawEntityPage(api: api, entity: item);
    }
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  String _visitStats() {
    final follow = _countText(item, [
      'follownum',
      'follow_num',
      'followNum',
      'follow',
      'follownum_txt',
      'followNumTxt',
    ], compact: false);
    final users = accountEntityCategory(item) == '用户';
    final count = _countText(
      item,
      users
          ? [
              'fans',
              'fansnum',
              'fans_num',
              'fansNum',
              'fansnum_txt',
              'fansNumTxt',
            ]
          : [
              'commentnum',
              'comment_num',
              'feed_num',
              'feedNum',
              'commentnum_txt',
              'feedCommentNumTxt',
            ],
      compact: false,
    );
    return [
      if (follow.isNotEmpty) '$follow关注',
      if (count.isNotEmpty) '$count${users ? '粉丝' : '讨论'}',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFCCCCCC) : scheme.onSurface;
    final secondary = dark ? const Color(0xFFB8B8B8) : scheme.onSurfaceVariant;
    final category = accountEntityCategory(item);
    final title = _entityName(item);
    final logo = normalizeCoolapkImageUrl(
      communityText(item, [
        'logo',
        'userAvatar',
        'avatar',
        'icon',
        'pic',
        'cover',
      ]),
    );
    final size = followedTopics ? 56.0 : 48.0;
    final score = ratingNodeScore(item);
    final rated = followedTopics && score > 0 && score <= 10;
    final count = accountTopicCount(item);
    final heat = _countText(item, [
      'hot_num_txt',
      'hotNumTxt',
      'hot_num',
      'hotNum',
    ]);
    final stats = followedTopics
        ? [
            if (heat.isNotEmpty) '$heat热度',
            if (count.isNotEmpty) '$count讨论',
          ].join(' ')
        : _visitStats();
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: followedTopics ? 8 : 12,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(followedTopics ? 12 : 8),
              child: SizedBox.square(
                dimension: size,
                child: logo.isEmpty
                    ? Icon(Icons.image_outlined, color: secondary)
                    : CachedNetworkImage(
                        logo,
                        headers: coolapkImageHeaders(logo, api: api),
                        width: size,
                        height: size,
                        fit: category == '数码' ? BoxFit.contain : BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.image_outlined, color: secondary),
                      ),
              ),
            ),
            SizedBox(width: followedTopics ? 12 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        if (!followedTopics && category.isNotEmpty)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFF32988E),
                                    width: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    category,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      height: 1.2,
                                      color: Color(0xFF32988E),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        TextSpan(text: title),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      color: foreground,
                    ),
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (followedTopics && heat.isNotEmpty) ...[
                          const Icon(
                            Icons.local_fire_department_outlined,
                            size: 12,
                            color: Color(0xFFF44336),
                          ),
                          const SizedBox(width: 2),
                        ],
                        Expanded(
                          child: Text(
                            stats,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: followedTopics ? 12 : 14,
                              height: 1.3,
                              color: secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (rated)
              SizedBox(
                width: 76,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.1,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var star = 0; star < 5; star++)
                          Padding(
                            padding: EdgeInsets.only(right: star == 4 ? 0 : 3),
                            child: Container(
                              width: 10.5,
                              height: 10.5,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: const Color(0xFF777777),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: (score / 2 - star).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      child: const ColoredBox(
                                        color: Color(0xFFD99F18),
                                      ),
                                    ),
                                  ),
                                  const Center(
                                    child: Icon(
                                      Icons.star,
                                      size: 8.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 24, color: secondary),
          ],
        ),
      ),
    );
  }
}
