import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components/review_page_scaffold.dart';
import '../../core/design_system/components/review_preference_tile.dart';
import '../../core/services/cache_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/widgets/app_section_card.dart';

class CacheManagementPage extends ConsumerStatefulWidget {
  const CacheManagementPage({super.key});

  @override
  ConsumerState<CacheManagementPage> createState() =>
      _CacheManagementPageState();
}

class _CacheManagementPageState extends ConsumerState<CacheManagementPage> {
  CacheBreakdown _stats = CacheBreakdown.empty;
  bool _loading = true;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final stats = await CacheService.getCacheStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _handleClearCache() async {
    if (_clearing) return;
    HapticFeedbackUtil.light();

    if (_stats.totalBytes <= 0) {
      AppToast.show(context, '当前没有可清理的缓存');
      return;
    }

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理所有缓存？'),
        content: Text(
          '将彻底物理清理应用内的图片、媒体、网络及运行时临时缓存文件（共计 ${CacheBreakdown.formatBytes(_stats.totalBytes)}）。\n\n清理后系统「设置 -> 应用信息 -> 存储和缓存」也将同步减少。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    HapticFeedbackUtil.medium();

    final clearedBytes = await CacheService.clearCache();
    await _loadStats();

    if (!mounted) return;
    setState(() => _clearing = false);
    HapticFeedbackUtil.medium();
    AppToast.show(
      context,
      '缓存清理完毕，已释放 ${CacheBreakdown.formatBytes(clearedBytes > 0 ? clearedBytes : _stats.totalBytes)} 空间',
    );
  }

  void _showThresholdSelector(BuildContext context, int currentThreshold) {
    HapticFeedbackUtil.light();
    const options = [
      {'label': '不限制（从不自动清理）', 'value': 0},
      {'label': '50 MB', 'value': 50},
      {'label': '100 MB', 'value': 100},
      {'label': '200 MB', 'value': 200},
      {'label': '500 MB', 'value': 500},
      {'label': '1 GB (1024 MB)', 'value': 1024},
      {'label': '2 GB (2048 MB)', 'value': 2048},
    ];

    showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择自动清理阈值'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: RadioGroup<int>(
          groupValue: currentThreshold,
          onChanged: (val) {
            if (val == null) return;
            HapticFeedbackUtil.light();
            ref
                .read(appSettingsProvider.notifier)
                .setAutoClearCacheThresholdMb(val);
            Navigator.pop(ctx);
            AppToast.show(
              context,
              val == 0
                  ? '已关闭自动清理'
                  : '已设置缓存阈值为 ${val >= 1024 ? '${val ~/ 1024} GB' : '$val MB'}',
            );
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final label = opt['label'] as String;
                final val = opt['value'] as int;
                return RadioListTile<int>(
                  title: Text(label),
                  value: val,
                  dense: true,
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  String _formatThreshold(int mb) {
    if (mb <= 0) {
      return '不限制（从不自动清理）';
    }
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1)} GB';
    }
    return '$mb MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(appSettingsProvider);

    return ReviewPageScaffold(
      title: '缓存管理',
      bodyBuilder: (context, contentInsets) {
        return ListView(
          padding:
              contentInsets +
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _buildOverviewCard(context, colorScheme),
            const SizedBox(height: 16),
            _buildActionCard(context, colorScheme),
            const SizedBox(height: 24),
            _sectionTitle(context, '自动清理规则'),
            const SizedBox(height: 12),
            _buildThresholdCard(
              context,
              colorScheme,
              settings.autoClearCacheThresholdMb,
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, '物理清理保障'),
            const SizedBox(height: 12),
            _buildTipCard(context, colorScheme),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildOverviewCard(BuildContext context, ColorScheme colorScheme) {
    final total = _stats.totalBytes;
    final images = _stats.imageBytes;
    final network = _stats.networkBytes;
    final system = _stats.systemBytes;

    final imageRatio = total > 0 ? (images / total).clamp(0.0, 1.0) : 0.0;
    final networkRatio = total > 0 ? (network / total).clamp(0.0, 1.0) : 0.0;
    final systemRatio = total > 0 ? (system / total).clamp(0.0, 1.0) : 0.0;

    final imageColor = colorScheme.primary;
    final networkColor = colorScheme.tertiary;
    final systemColor = colorScheme.secondary;

    return AppSectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cleaning_services_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : Text(
                    CacheBreakdown.formatBytes(total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              '当前应用缓存占用',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // Multi-segment progress bar (Telegram style)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 10,
                color: colorScheme.surfaceContainerHighest,
                child: total <= 0
                    ? null
                    : Row(
                        children: [
                          if (imageRatio > 0)
                            Expanded(
                              flex: (imageRatio * 1000).toInt().clamp(1, 1000),
                              child: Container(color: imageColor),
                            ),
                          if (networkRatio > 0)
                            Expanded(
                              flex: (networkRatio * 1000).toInt().clamp(
                                1,
                                1000,
                              ),
                              child: Container(color: networkColor),
                            ),
                          if (systemRatio > 0)
                            Expanded(
                              flex: (systemRatio * 1000).toInt().clamp(1, 1000),
                              child: Container(color: systemColor),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            // Breakdown Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(
                  color: imageColor,
                  label: '图片与媒体',
                  size: CacheBreakdown.formatBytes(images),
                  colorScheme: colorScheme,
                ),
                _buildLegendItem(
                  color: networkColor,
                  label: '网络与临时',
                  size: CacheBreakdown.formatBytes(network),
                  colorScheme: colorScheme,
                ),
                _buildLegendItem(
                  color: systemColor,
                  label: '系统运行时',
                  size: CacheBreakdown.formatBytes(system),
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String size,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          size,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, ColorScheme colorScheme) {
    return AppSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: (_loading || _clearing) ? null : _handleClearCache,
              icon: _clearing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_sweep_rounded),
              label: Text(_clearing ? '正在深度清理...' : '一键清理所有缓存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdCard(
    BuildContext context,
    ColorScheme colorScheme,
    int thresholdMb,
  ) {
    return AppSectionCard(
      child: Column(
        children: [
          ReviewPreferenceTile(
            leading: Icon(
              Icons.auto_delete_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            title: '自动清理缓存阈值',
            subtitle: '达到设定阈值并在启动时检测到将自动静默清理',
            trailing: Text(
              _formatThreshold(thresholdMb),
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _showThresholdSelector(context, thresholdMb),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(BuildContext context, ColorScheme colorScheme) {
    return AppSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_outlined, color: colorScheme.primary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '真实物理清理',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'GreenNote 调用底层物理擦除机制彻底清空应用的内部及外部缓存文件。\n清理后进入系统「设置 -> 应用信息 -> 存储和缓存」，即可肉眼可见缓存占用减少，非仅在 UI 上做表面数字重置。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: colorScheme.onSurfaceVariant,
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

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}
