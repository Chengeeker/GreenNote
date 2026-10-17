import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'package:flutter/material.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../../core/widgets/review_refresh_header.dart';
import '../../../core/widgets/coolapk_rich_text.dart';
import '../../feed/feed_pages.dart';
import 'digital_cards.dart';

List<Map<String, dynamic>> digitalHomeEntities(Map<String, dynamic> card) =>
    (card['entities'] is List ? card['entities'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

Map<String, dynamic> digitalHomeExtra(Map<String, dynamic> card) {
  final value = card['extraDataArr'] ?? card['extraData'];
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      /* Older responses omit structured metadata. */
    }
  }
  return const {};
}

String digitalNewsTitle(Map<String, dynamic> item) {
  final title = (item['message_title'] ?? '').toString().trim();
  if (title.isNotEmpty) return html.parseFragment(title).text ?? title;
  final text =
      html.parseFragment((item['message'] ?? '').toString()).text?.trim() ?? '';
  if (text.isNotEmpty) return text.split('\n').first;
  return (item['title'] ?? '').toString();
}

Widget _image(
  CoolapkApi api,
  Map<String, dynamic> item,
  double size, {
  BoxFit fit = BoxFit.contain,
}) {
  final url = (item['logo'] ?? item['pic'] ?? item['message_cover'] ?? '')
      .toString();
  return SizedBox(
    width: size,
    height: size,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        normalizeCoolapkImageUrl(url),
        headers: coolapkImageHeaders(url, api: api),
        width: size,
        fit: fit,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );
}

class DigitalHomeCarousel extends StatefulWidget {
  const DigitalHomeCarousel({
    required this.api,
    required this.card,
    required this.onTap,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> card;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  State<DigitalHomeCarousel> createState() => _DigitalHomeCarouselState();
}

class _DigitalHomeCarouselState extends State<DigitalHomeCarousel> {
  int _index = 0;
  final _pages = PageController();
  Timer? _timer;
  bool _enabled = true;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final count = digitalHomeEntities(widget.card).length;
      if (!_enabled ||
          count < 2 ||
          !_pages.hasClients ||
          _pages.position.isScrollingNotifier.value ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _pages.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _enabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    final items = digitalHomeEntities(widget.card);
    if (items.isEmpty && (widget.card['pic'] ?? '').toString().isNotEmpty) {
      items.add(widget.card);
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return ReviewCard(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4.5,
        child: Stack(
          children: [
            protectHorizontalDragFromVerticalRefresh(
              PageView.builder(
                controller: _pages,
                itemCount: items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => InkWell(
                  onTap: () => widget.onTap(items[i]),
                  child: LayoutBuilder(
                    builder: (context, size) => _image(
                      widget.api,
                      items[i],
                      size.maxWidth,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            if (items.length > 1)
              Positioned(
                right: 8,
                bottom: 6,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Container(
                        key: ValueKey('digital-banner-dot-$i'),
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: i == _index ? 1 : .35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DigitalHomeListCard extends StatelessWidget {
  const DigitalHomeListCard({
    required this.api,
    required this.card,
    required this.onTap,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> card;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  Widget build(BuildContext context) {
    final items = digitalHomeEntities(card);
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ReviewCard(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onTap(card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${card['title'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${card['subTitle'] ?? '更多'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          for (final item in items)
            if (item['feedType'] == 'rating')
              FeedCard(
                api: api,
                feed: CoolapkFeed.fromJson(item),
                officialLayout: true,
                body: DigitalHomeRatingBody(api: api, item: item, onTap: onTap),
              )
            else if (item['entityType'] == 'feed')
              InkWell(
                onTap: () => onTap(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              digitalNewsTitle(item),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${item['username'] ?? ''} ${item['replynum'] ?? 0}评论 ${CoolapkFeed.fromJson(item).date}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        height: 74,
                        child: _image(api, item, 100, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                ),
              )
            else
              InkWell(
                onTap: () => onTap(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _image(api, item, 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item['title'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${formatDigitalHot(item['hot_num_txt'] ?? item['hot_num'])}热度  ${formatDigitalHot(item['feed_comment_num'])}讨论',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _Score(item: item),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final score = num.tryParse(
      '${item['star_average_score'] ?? item['score'] ?? ''}',
    );
    if (score == null || !score.isFinite || score <= 0) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Text(
          score.toStringAsFixed(1),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        _Stars(score: score.toDouble(), size: 10),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.score, this.size = 14});
  final double score;
  final double size;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: i < score / 2
                ? const Color(0xFFDCA400)
                : Colors.grey.shade700,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Icon(
            score / 2 > i && score / 2 < i + 1
                ? Icons.star_half_rounded
                : Icons.star_rounded,
            color: Colors.white,
            size: size,
          ),
        ),
    ],
  );
}

class DigitalHomeRatingBody extends StatelessWidget {
  const DigitalHomeRatingBody({
    required this.api,
    required this.item,
    required this.onTap,
    super.key,
  });
  final CoolapkApi api;
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>> onTap;
  @override
  Widget build(BuildContext context) {
    final score = num.tryParse('${item['rating_score']}');
    final dimensions = item['rating_item_info'] is List
        ? (item['rating_item_info'] as List).whereType<Map>()
        : const <Map>[];
    Map fields = const {};
    final message = item['v4_rating_message'];
    if (message is Map) fields = message;
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map) fields = decoded;
      } on FormatException {
        /* Fall back to legacy review fields. */
      }
    }
    if (fields.isEmpty) {
      fields = {
        for (final entry in {
          '优点': 'comment_good',
          '缺点': 'comment_bad',
          '总结': 'comment_general',
        }.entries)
          if ((item[entry.value] ?? '').toString().trim().isNotEmpty)
            entry.key: item[entry.value],
      };
    }
    final target = item['targetRow'] is Map
        ? Map<String, dynamic>.from(item['targetRow'] as Map)
        : const <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (score != null && score.isFinite)
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                color: const Color(0xFFDCA400),
                child: const Text(
                  '评分',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              _Stars(score: score.toDouble()),
              Text(
                score >= 9
                    ? '😍非常好'
                    : score >= 7
                    ? '😊较好'
                    : score >= 5
                    ? '😐一般'
                    : '较差',
                style: const TextStyle(fontSize: 12, color: Color(0xFFDCA400)),
              ),
            ],
          ),
        if (dimensions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final d in dimensions)
                  Text(
                    '${d['name']} ${((num.tryParse('${d['v4_score']}') ?? 0) / 2).toStringAsFixed(0)}☆',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        for (final field in fields.entries) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF009688),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '${field.key}',
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CoolapkRichText(
              api: api,
              text: '${field.value}'.replaceAll('<!--break-->', '\n'),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
        ],
        if (fields.isEmpty)
          Text(
            '${item['message'] ?? ''}',
            style: const TextStyle(fontSize: 16),
          ),
        if (target.isNotEmpty)
          InkWell(
            onTap: () => onTap(target),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2C2C2C)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _image(api, target, 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${target['title'] ?? ''}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          '${target['star_total_count'] ?? ''}人点评',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _Score(item: target),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
