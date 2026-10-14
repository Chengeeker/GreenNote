import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/components/review_card.dart';
import '../../../core/network/coolapk_api.dart';
import '../../../core/network/coolapk_image.dart';
import '../../../core/utils/haptic_feedback_util.dart';
import '../../../core/widgets/cached_network_image.dart';
import '../../shared/api_list_page.dart';
import '../utils/digital_system_helper.dart';

class DigitalDeviceOverview extends StatefulWidget {
  const DigitalDeviceOverview({
    this.api,
    required this.onOpenPhones,
    required this.onOpenSystems,
    super.key,
  });

  final CoolapkApi? api;
  final VoidCallback onOpenPhones;
  final VoidCallback onOpenSystems;

  @override
  State<DigitalDeviceOverview> createState() => _DigitalDeviceOverviewState();
}

class _DigitalDeviceOverviewState extends State<DigitalDeviceOverview> {
  static const _channel = MethodChannel('com.green.note/ui');
  late final Future<Map<String, dynamic>> _profile = _loadProfile();

  Future<Map<String, dynamic>> _loadProfile() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'getDeviceProfile',
      );
      return value ?? const {};
    } on PlatformException {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _profile,
    builder: (context, snapshot) {
      final profile = snapshot.data ?? const <String, dynamic>{};
      final marketName = (profile['marketName'] ?? '').toString().trim();
      final osName = (profile['osName'] ?? '').toString().trim();
      final manufacturer = (profile['manufacturer'] ?? '').toString().trim();
      final model = (profile['model'] ?? '').toString().trim();
      final display = (profile['display'] ?? '').toString().trim();
      final android = (profile['androidVersion'] ?? '').toString().trim();
      final hardwareModel = [
        manufacturer,
        model,
      ].where((value) => value.isNotEmpty).toSet().join(' ');
      final deviceName = marketName.isNotEmpty ? marketName : hardwareModel;
      final systemName = osName.isNotEmpty
          ? osName
          : (display.isNotEmpty
                ? display
                : (android.isNotEmpty ? 'Android $android' : ''));

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: _OfficialDeviceCard(
                api: widget.api,
                headerTitle: '我的机型',
                name: deviceName,
                isWaiting: snapshot.connectionState == ConnectionState.waiting,
                fallbackIcon: Icons.smartphone_rounded,
                isPhone: true,
                defaultOnTap: widget.onOpenPhones,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OfficialSystemCard(
                api: widget.api,
                headerTitle: '我的系统',
                name: systemName,
                isWaiting: snapshot.connectionState == ConnectionState.waiting,
                fallbackIcon: Icons.system_update_alt_rounded,
                isPhone: false,
                defaultOnTap: widget.onOpenSystems,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _OfficialDeviceCard extends StatefulWidget {
  const _OfficialDeviceCard({
    required this.api,
    required this.headerTitle,
    required this.name,
    required this.isWaiting,
    required this.fallbackIcon,
    required this.isPhone,
    required this.defaultOnTap,
  });

  final CoolapkApi? api;
  final String headerTitle;
  final String name;
  final bool isWaiting;
  final IconData fallbackIcon;
  final bool isPhone;
  final VoidCallback defaultOnTap;

  @override
  State<_OfficialDeviceCard> createState() => _OfficialDeviceCardState();
}

class _OfficialDeviceCardState extends State<_OfficialDeviceCard> {
  DigitalProductInfo _info = const DigitalProductInfo();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _OfficialDeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.api != widget.api) {
      _load();
    }
  }

  Future<void> _load() async {
    final api = widget.api;
    final name = widget.name.trim();
    if (api == null || name.isEmpty) return;

    final info = await DigitalSystemHelper.resolveDeviceProduct(api, name);
    if (mounted) setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isWaiting
        ? '读取中…'
        : widget.name.isNotEmpty
        ? (_info.title ?? widget.name)
        : '无法读取机型';

    return _OfficialOverviewCard(
      api: widget.api,
      headerTitle: widget.headerTitle,
      title: title,
      icon: widget.fallbackIcon,
      logoUrl: _info.logo,
      score: _info.score ?? 7.7,
      commentCount: _info.commentCount ?? '3541',
      commentUnit: '机主点评',
      onTap: () {
        final api = widget.api;
        final productId = _info.productId;
        if (api != null && productId != null && productId.isNotEmpty) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ProductPage(api: api, id: productId, title: title),
            ),
          );
        } else {
          widget.defaultOnTap();
        }
      },
    );
  }
}

class _OfficialSystemCard extends StatefulWidget {
  const _OfficialSystemCard({
    required this.api,
    required this.headerTitle,
    required this.name,
    required this.isWaiting,
    required this.fallbackIcon,
    required this.isPhone,
    required this.defaultOnTap,
  });

  final CoolapkApi? api;
  final String headerTitle;
  final String name;
  final bool isWaiting;
  final IconData fallbackIcon;
  final bool isPhone;
  final VoidCallback defaultOnTap;

  @override
  State<_OfficialSystemCard> createState() => _OfficialSystemCardState();
}

class _OfficialSystemCardState extends State<_OfficialSystemCard> {
  DigitalProductInfo _info = const DigitalProductInfo();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _OfficialSystemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.api != widget.api) {
      _load();
    }
  }

  Future<void> _load() async {
    final name = widget.name.trim();
    if (name.isEmpty) return;

    final api = widget.api;
    if (api != null) {
      final info = await DigitalSystemHelper.resolveSystemProduct(api, name);
      if (mounted) {
        setState(() => _info = info);
        return;
      }
    }

    final preset = DigitalSystemHelper.getSystemPresetLogo(name);
    if (preset != null && mounted) {
      setState(() => _info = DigitalProductInfo(logo: preset));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isWaiting
        ? '读取中…'
        : widget.name.isNotEmpty
        ? (_info.title ?? widget.name)
        : '无法读取系统';

    return _OfficialOverviewCard(
      api: widget.api,
      headerTitle: widget.headerTitle,
      title: title,
      icon: widget.fallbackIcon,
      logoUrl:
          _info.logo ?? DigitalSystemHelper.getSystemPresetLogo(widget.name),
      score: _info.score ?? 3.7,
      commentCount: _info.commentCount ?? '2410',
      commentUnit: '人点评',
      onTap: () {
        final api = widget.api;
        final productId = _info.productId;
        if (api != null && productId != null && productId.isNotEmpty) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ProductPage(api: api, id: productId, title: title),
            ),
          );
        } else {
          widget.defaultOnTap();
        }
      },
    );
  }
}

class _OfficialOverviewCard extends StatelessWidget {
  const _OfficialOverviewCard({
    required this.api,
    required this.headerTitle,
    required this.title,
    required this.icon,
    this.logoUrl,
    required this.score,
    required this.commentCount,
    required this.commentUnit,
    required this.onTap,
  });

  final CoolapkApi? api;
  final String headerTitle;
  final String title;
  final IconData icon;
  final String? logoUrl;
  final double score;
  final String commentCount;
  final String commentUnit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = logoUrl != null && logoUrl!.trim().isNotEmpty;
    final filledStars = (score / 2.0).round().clamp(0, 5);

    return ReviewCard(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedbackUtil.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headerTitle,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: hasImage
                          ? CachedNetworkImage(
                              normalizeCoolapkImageUrl(logoUrl!),
                              headers: api != null
                                  ? coolapkImageHeaders(logoUrl!, api: api)
                                  : const {},
                              width: 38,
                              height: 38,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  Icon(icon, color: colors.primary, size: 24),
                            )
                          : Icon(icon, color: colors.primary, size: 24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 1; i <= 5; i++)
                              Icon(
                                Icons.star_rounded,
                                size: 12.5,
                                color: i <= filledStars
                                    ? const Color(0xFFFFB300)
                                    : colors.outlineVariant.withValues(
                                        alpha: 0.4,
                                      ),
                              ),
                            const SizedBox(width: 4),
                            Text(
                              score.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFFFFB300),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(
                height: 1,
                thickness: 0.5,
                color: colors.outlineVariant.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$commentCount$commentUnit',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '去点评',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
