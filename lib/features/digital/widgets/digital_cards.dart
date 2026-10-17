import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/design_system/components/review_frosted_app_bar.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/utils/app_toast.dart';
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
    this.emptyText,
    this.onEmptyTap,
    super.key,
  });

  final CoolapkApi api;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onMoreTap;
  final String? emptyText;
  final VoidCallback? onEmptyTap;

  @override
  Widget build(BuildContext context) {
    if (api.isAnonymous) {
      return ListenableBuilder(
        listenable: api.localAccount,
        builder: (context, _) => _buildCard(
          context,
          api.localAccount.productFollows.values
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
              .reversed
              .take(2)
              .toList(),
        ),
      );
    }
    return _buildCard(context, items);
  }

  Widget _buildCard(
    BuildContext context,
    List<Map<String, dynamic>> effectiveItems,
  ) {
    if (effectiveItems.isEmpty && emptyText == null) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return ReviewCard(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '我的关注',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedbackUtil.selection();
                    if (onMoreTap != null) {
                      onMoreTap!();
                    } else if (api.isAnonymous) {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DigitalLocalProductFollowsPage(api: api),
                        ),
                      );
                    } else if (api.hasCookie) {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => ApiListPage(
                            api: api,
                            title: '我的关注',
                            path: '/v6/page/dataList',
                            query: const {'url': '#/product/followProductList'},
                          ),
                        ),
                      );
                    } else {
                      AppToast.show(context, api.loginRequiredMessage);
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
            const SizedBox(height: 8),
            if (effectiveItems.isEmpty)
              InkWell(
                onTap: onEmptyTap,
                child: Text(
                  emptyText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Row(
                children: [
                  for (final item in effectiveItems)
                    Expanded(
                      child: _FollowChip(
                        api: api,
                        id: (item['id'] ?? item['productId'] ?? '').toString(),
                        title: (item['title'] ?? item['name'] ?? '设备')
                            .toString(),
                        logo: (item['logo'] ?? item['pic'] ?? '').toString(),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DigitalLocalProductFollowsPage extends StatelessWidget {
  const DigitalLocalProductFollowsPage({required this.api, super.key});

  final CoolapkApi api;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(title: const Text('我的关注')),
    body: ListenableBuilder(
      listenable: api.localAccount,
      builder: (context, _) {
        final entries = api.localAccount.productFollows.entries
            .toList()
            .reversed
            .toList();
        if (entries.isEmpty) return const Center(child: Text('还没有关注的机型'));
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final item = Map<String, dynamic>.from(entry.value as Map);
            final id = entry.key;
            final title = (item['title'] ?? id).toString();
            final pic = (item['logo'] ?? item['pic'] ?? item['cover'] ?? '')
                .toString();
            final hot = item['hot_num'];
            return ListTile(
              leading: pic.isEmpty
                  ? const Icon(Icons.devices_rounded)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        normalizeCoolapkImageUrl(pic),
                        headers: coolapkImageHeaders(pic, api: api),
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.devices_rounded),
                      ),
                    ),
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: hot == null
                  ? null
                  : Text('热度 ${formatDigitalHot(hot)}'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ProductPage(api: api, id: id, title: title),
                ),
              ),
              trailing: IconButton(
                tooltip: '取消本地关注',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () async {
                  try {
                    await api.localAccount.toggle('productFollows', id, item);
                  } catch (error) {
                    if (context.mounted) AppToast.show(context, '$error');
                  }
                },
              ),
            );
          },
        );
      },
    ),
  );
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  normalizeCoolapkImageUrl(logo),
                  headers: coolapkImageHeaders(logo, api: api),
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.devices_rounded, size: 20),
                ),
              )
            else
              const Icon(Icons.devices_rounded, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
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
            const SizedBox(height: 8),
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
              width: 38,
              height: 38,
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
                        width: 38,
                        height: 38,
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
            const SizedBox(height: 4),
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
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    this.items = const [],
    this.onMoreTap,
    this.showRanking = true,
    this.onItemTap,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final String subTitle;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onMoreTap;
  final bool showRanking;
  final ValueChanged<Map<String, dynamic>>? onItemTap;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return ReviewCard(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w500, fontSize: 14),
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
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: i < list.length
                        ? _RankProductItem(
                            api: api,
                            rank: showRanking ? i + 1 : 0,
                            item: list[i],
                            onTap: onItemTap,
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            if (list.length > 4) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 4; i < 8; i++)
                    Expanded(
                      child: i < list.length
                          ? _RankProductItem(
                              api: api,
                              rank: showRanking ? i + 1 : 0,
                              item: list[i],
                              onTap: onItemTap,
                            )
                          : const SizedBox.shrink(),
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

class _RankProductItem extends StatelessWidget {
  const _RankProductItem({
    required this.api,
    required this.rank,
    required this.item,
    this.onTap,
  });

  final CoolapkApi api;
  final int rank;
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>>? onTap;

  @override
  Widget build(BuildContext context) {
    final id = (item['id'] ?? item['productId'] ?? item['entityId'] ?? '')
        .toString();
    final title =
        (item['title'] ?? item['name'] ?? item['productTitle'] ?? '产品')
            .toString();
    final logo = (item['logo'] ?? item['pic'] ?? item['icon'] ?? '').toString();
    final hot = formatDigitalHot(
      item['hot_num_txt'] ??
          item['hot_num'] ??
          item['hotNum'] ??
          item['subTitle'] ??
          '',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final topic = item['entityType'] == 'topic';
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedbackUtil.selection();
        if (onTap != null) {
          onTap!(item);
          return;
        }
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
                  height: 50,
                  alignment: Alignment.center,
                  child: logo.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(topic ? 6 : 0),
                          child: CachedNetworkImage(
                            normalizeCoolapkImageUrl(logo),
                            headers: coolapkImageHeaders(logo, api: api),
                            height: 48,
                            width: 48,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.smartphone_rounded, size: 34),
                          ),
                        )
                      : const Icon(Icons.smartphone_rounded, size: 34),
                ),
                if (rank > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: RankRibbon(
                      rank: rank,
                      width: 10 * textScale,
                      height: 14 * textScale,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: (topic ? 16 : 32) * textScale,
              child: Text(
                title,
                maxLines: topic ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 2),
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
                  Flexible(
                    child: Text(
                      hot.replaceAll('热度', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
    this.onMoreTap,
    super.key,
  });

  final CoolapkApi api;
  final String title;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return ReviewCard(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                InkWell(
                  onTap: onMoreTap,
                  child: const Row(
                    children: [
                      Text('更多', style: TextStyle(fontSize: 12)),
                      Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
    final hot = (item['entityTemplate'] ?? '') == 'productTimeline'
        ? ''
        : formatDigitalHot(item['hot_num_txt'] ?? item['hot_num'] ?? '');
    final dateParts = RegExp(r'^(\d{4})年(\d{1,2})月(?:(\d{1,2})日)?')
        .firstMatch(release);
    final date = dateParts == null
        ? release
        : dateParts.group(3) == null
        ? '${dateParts[2]}月'
        : '${dateParts[2]!.padLeft(2, '0')}.${dateParts[3]!.padLeft(2, '0')}';
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (release.isNotEmpty) ...[
              SizedBox(
                width: 42,
                child: Column(
                  children: [
                    Text(date, style: const TextStyle(fontSize: 12)),
                    if (dateParts != null)
                      Text(
                        dateParts[1]!,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 10,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: .3),
                    ),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: 8),
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
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () {
        HapticFeedbackUtil.selection();
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
