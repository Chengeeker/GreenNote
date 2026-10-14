import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../shared/api_list_page.dart';
import 'rank_ribbon.dart';

/// Formats a raw number or string into a Coolapk-style hot count (e.g. 102.9万).
String formatDigitalHot(dynamic raw) {
  if (raw == null) return '';
  final str = raw.toString().trim();
  if (str.isEmpty) return '';
  if (str.contains('万') || str.contains('k') || str.contains('K')) return str;
  final numVal = num.tryParse(str);
  if (numVal == null) return str;
  if (numVal >= 10000) {
    final wan = (numVal / 10000).toStringAsFixed(1);
    return '${wan.endsWith('.0') ? wan.substring(0, wan.length - 2) : wan}万';
  }
  return numVal.toString();
}

/// "我的关注" 设备卡片
class DigitalFollowCard extends StatelessWidget {
  const DigitalFollowCard({
    required this.api,
    this.items = const [],
    this.onMoreTap,
    super.key,
  });

  final CoolapkApi api;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final effectiveItems = items;
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '我的关注',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.selection();
                    if (onMoreTap != null) {
                      onMoreTap!();
                    } else {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ApiListPage(
                            api: api,
                            title: '我的关注',
                            path: '/v6/user/myProductList',
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '更多',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final item in effectiveItems)
                  _FollowChip(
                    api: api,
                    id: (item['id'] ?? item['productId'] ?? '').toString(),
                    title: (item['title'] ?? item['name'] ?? '设备').toString(),
                    logo: (item['logo'] ?? item['pic'] ?? '').toString(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowChip extends StatelessWidget {
  const _FollowChip({
    required this.api,
    required this.id,
    required this.title,
    required this.logo,
  });

  final CoolapkApi api;
  final String id;
  final String title;
  final String logo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedbackUtil.selection();
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ProductPage(api: api, id: id, title: title),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(logo),
                  headers: coolapkImageHeaders(logo, api: api),
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.devices_rounded, size: 20),
                ),
              )
            else
              const Icon(Icons.devices_rounded, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// 10个品类5列网格卡片 (iconLinkGridCard)
class DigitalCategoryGridCard extends StatelessWidget {
  const DigitalCategoryGridCard({
    required this.api,
    this.items,
    this.onCategoryTap,
    super.key,
  });

  final CoolapkApi api;
  final List<Map<String, dynamic>>? items;
  final void Function(String title, Map<String, dynamic> item)? onCategoryTap;

  static const defaultCategories = [
    {
      'title': '手机',
      'icon': Icons.smartphone_rounded,
      'color': Color(0xFFEF5350),
    },
    {
      'title': '平板',
      'icon': Icons.tablet_mac_rounded,
      'color': Color(0xFF26A69A),
    },
    {
      'title': '耳机',
      'icon': Icons.headphones_rounded,
      'color': Color(0xFF7E57C2),
    },
    {
      'title': '笔记本',
      'icon': Icons.laptop_chromebook_rounded,
      'color': Color(0xFF42A5F5),
    },
    {
      'title': '智能家居',
      'icon': Icons.home_work_outlined,
      'color': Color(0xFFFFA726),
    },
    {'title': '穿戴设备', 'icon': Icons.watch_rounded, 'color': Color(0xFFAB47BC)},
    {'title': '数码配件', 'icon': Icons.cable_rounded, 'color': Color(0xFF26C6DA)},
    {
      'title': '游戏',
      'icon': Icons.sports_esports_rounded,
      'color': Color(0xFFFF7043),
    },
    {'title': '路由器', 'icon': Icons.router_rounded, 'color': Color(0xFF78909C)},
    {
      'title': '全部',
      'icon': Icons.grid_view_rounded,
      'color': Color(0xFF66BB6A),
    },
  ];

  @override
  Widget build(BuildContext context) {
    final list = items ?? defaultCategories;
    if (list.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: i < list.length
                        ? _CategoryItem(
                            api: api,
                            item: list[i],
                            colorScheme: colorScheme,
                            onTap: onCategoryTap,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 5; i < 10; i++)
                  Expanded(
                    child: i < list.length
                        ? _CategoryItem(
                            api: api,
                            item: list[i],
                            colorScheme: colorScheme,
                            onTap: onCategoryTap,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.api,
    required this.item,
    required this.colorScheme,
    this.onTap,
  });

  final CoolapkApi api;
  final Map<String, dynamic> item;
  final ColorScheme colorScheme;
  final void Function(String title, Map<String, dynamic> item)? onTap;

  @override
  Widget build(BuildContext context) {
    final title = (item['title'] ?? item['name'] ?? '').toString();
    final pic = (item['pic'] ?? item['logo'] ?? item['iconUrl'] ?? '')
        .toString();
    final iconData = item['icon'] as IconData?;
    final color = item['color'] as Color? ?? colorScheme.primaryContainer;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedbackUtil.selection();
        if (onTap != null) {
          onTap!(title, item);
        } else {
          final url = (item['url'] ?? '').toString();
          if (url.isNotEmpty) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ApiListPage(
                  api: api,
                  title: title,
                  path: '/v6/page/dataList',
                  query: {'url': url},
                ),
              ),
            );
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: pic.isNotEmpty
                    ? CachedNetworkImage(
                        normalizeCoolapkImageUrl(pic),
                        headers: coolapkImageHeaders(pic, api: api),
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          iconData ?? Icons.devices_rounded,
                          size: 22,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(
                        iconData ?? Icons.devices_rounded,
                        size: 22,
                        color: colorScheme.primary,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// 宣传横幅卡片 (imageCarouselCard / imageCard)
class DigitalBannerCard extends StatelessWidget {
  const DigitalBannerCard({
    required this.api,
    this.imageUrl,
    this.title = 'EDC 精选装备',
    this.targetUrl,
    super.key,
  });

  final CoolapkApi api;
  final String? imageUrl;
  final String title;
  final String? targetUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) return const SizedBox.shrink();
    final effectiveUrl = imageUrl!;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      clipBehavior: Clip.antiAlias,
      onTap: () {
        HapticFeedbackUtil.selection();
        if (targetUrl != null && targetUrl!.isNotEmpty) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ApiListPage(
                api: api,
                title: title,
                path: '/v6/page/dataList',
                query: {'url': targetUrl!},
              ),
            ),
          );
        }
      },
      child: AspectRatio(
        aspectRatio: _parseBannerAspectRatio(effectiveUrl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              normalizeCoolapkImageUrl(effectiveUrl),
              headers: coolapkImageHeaders(effectiveUrl, api: api),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flash_on_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

  static double _parseBannerAspectRatio(String url) {
    if (url.isEmpty) return 4.5;
    final match = RegExp(r'@(\d+)x(\d+)').firstMatch(url);
    if (match != null) {
      final w = double.tryParse(match.group(1)!);
      final h = double.tryParse(match.group(2)!);
      if (w != null && h != null && w > 0 && h > 0) {
        final rawRatio = w / h;
        if (rawRatio < 3.4) {
          return 3.338;
        }
        return rawRatio.clamp(3.338, 4.5);
      }
    }
    return 4.5;
  }
}

/// "今日热门" 8款机型榜单卡片 (iconMiniGridCard / iconLongTitleGridCard)
class DigitalRankGridCard extends StatelessWidget {
  const DigitalRankGridCard({
    required this.api,
    this.title = '今日热门',
    this.subTitle = '榜单',
    this.items,
    this.onMoreTap,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String subTitle;
  final List<Map<String, dynamic>>? items;
  final VoidCallback? onMoreTap;

  static const defaultRankItems = [
    {
      'id': '34676',
      'title': '一加16',
      'hot_num_txt': '102.9万',
      'logo': 'https://img.coolapk.com/picture/2024/1031/17/303108_1730367252_0179.png',
    },
    {
      'id': '34677',
      'title': '荣耀 Magic9 Pro',
      'hot_num_txt': '29.7万',
      'logo': 'https://img.coolapk.com/picture/2024/1030/19/303108_1730286820_0834.png',
    },
    {
      'id': '34678',
      'title': '小米18 Pro Max',
      'hot_num_txt': '25.2万',
      'logo': 'https://img.coolapk.com/picture/2024/1029/20/303108_1730203598_0987.png',
    },
    {
      'id': '34679',
      'title': 'iPhone 18 Pro Max',
      'hot_num_txt': '22.9万',
      'logo': 'https://img.coolapk.com/picture/2024/0910/02/303108_1725906234_0123.png',
    },
    {
      'id': '34680',
      'title': '华为Mate 90 Pro Max',
      'hot_num_txt': '21.5万',
      'logo': 'https://img.coolapk.com/picture/2024/0910/02/303108_1725906234_0123.png',
    },
    {
      'id': '34681',
      'title': '一加15',
      'hot_num_txt': '19.8万',
      'logo': 'https://img.coolapk.com/picture/2024/1031/17/303108_1730367252_0179.png',
    },
    {
      'id': '34682',
      'title': 'REDMI K100 Pro',
      'hot_num_txt': '18.2万',
      'logo': 'https://img.coolapk.com/picture/2024/1029/20/303108_1730203598_0987.png',
    },
    {
      'id': '34683',
      'title': 'OPPO Find X8 Ultra',
      'hot_num_txt': '16.9万',
      'logo': 'https://img.coolapk.com/picture/2024/1024/18/303108_1729764512_0456.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final list = items ?? defaultRankItems;
    if (list.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.selection();
                    if (onMoreTap != null) {
                      onMoreTap!();
                    } else {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ApiListPage(
                            api: api,
                            title: '数码排行榜',
                            path: '/v6/page/dataList',
                            query: const {'url': 'V10_CHANNEL_SMB_TOP'},
                          ),
                        ),
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: i < list.length
                        ? _RankProductItem(api: api, rank: i + 1, item: list[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 4; i < 8; i++)
                  Expanded(
                    child: i < list.length
                        ? _RankProductItem(api: api, rank: i + 1, item: list[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankProductItem extends StatelessWidget {
  const _RankProductItem({
    required this.api,
    required this.rank,
    required this.item,
  });

  final CoolapkApi api;
  final int rank;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final id = (item['id'] ?? item['productId'] ?? item['entityId'] ?? '')
        .toString();
    final title =
        (item['title'] ?? item['name'] ?? item['productTitle'] ?? '产品')
            .toString();
    final logo = (item['logo'] ?? item['pic'] ?? item['icon'] ?? '').toString();
    final hot = formatDigitalHot(
      item['hot_num_txt'] ?? item['hot_num'] ?? item['hotNum'] ?? '',
    );
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedbackUtil.selection();
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ProductPage(api: api, id: id, title: title),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: logo.isNotEmpty
                      ? CachedNetworkImage(
                          normalizeCoolapkImageUrl(logo),
                          headers: coolapkImageHeaders(logo, api: api),
                          height: 52,
                          width: 46,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.smartphone_rounded, size: 38),
                        )
                      : const Icon(Icons.smartphone_rounded, size: 38),
                ),
                Positioned(left: 0, top: 0, child: RankRibbon(rank: rank)),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (hot.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    hot,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// 产品时间线卡片 (productTimelineListCard)
class DigitalTimelineCard extends StatelessWidget {
  const DigitalTimelineCard({
    required this.api,
    this.title = '新品日历',
    this.items = const [],
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            for (final item in items) _TimelineRow(api: api, item: item),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.api, required this.item});

  final CoolapkApi api;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final id = (item['id'] ?? item['productId'] ?? '').toString();
    final title = (item['title'] ?? item['name'] ?? '新品').toString();
    final logo = (item['logo'] ?? item['pic'] ?? '').toString();
    final release = (item['release_time'] ?? item['releaseTime'] ?? '')
        .toString();
    final hot = formatDigitalHot(item['hot_num_txt'] ?? item['hot_num'] ?? '');
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedbackUtil.selection();
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ProductPage(api: api, id: id, title: title),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (release.isNotEmpty)
              Container(
                width: 60,
                padding: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Text(
                  release,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            if (logo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(logo),
                  headers: coolapkImageHeaders(logo, api: api),
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            if (hot.isNotEmpty) ...[
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    hot,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 简单栏目跳转卡片 (例如 "热门系统", "评分榜")
class DigitalSectionHeaderCard extends StatelessWidget {
  const DigitalSectionHeaderCard({required this.title, this.onTap, super.key});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ReviewCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onTap: () {
        HapticFeedbackUtil.selection();
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
