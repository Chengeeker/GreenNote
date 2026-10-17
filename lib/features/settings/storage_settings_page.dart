import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/storage_path_resolver.dart';
import '../../core/utils/haptic_feedback_util.dart';
import '../../core/widgets/app_section_card.dart';

/// 存储设置页面 (管理图片与视频存储路径，参考 Review 规范)
class StorageSettingsPage extends ConsumerStatefulWidget {
  const StorageSettingsPage({required this.api, super.key});

  final CoolapkApi api;

  @override
  ConsumerState<StorageSettingsPage> createState() =>
      _StorageSettingsPageState();
}

class _StorageSettingsPageState extends ConsumerState<StorageSettingsPage> {
  void _showPathSelectorDialog(
    BuildContext context,
    AppSettingsNotifier notifier,
    int currentType,
    String myNickname, {
    required bool isVideo,
  }) {
    HapticFeedbackUtil.light();
    final title = isVideo ? '视频存储路径' : '图片存储路径';
    final baseDir = isVideo ? 'Movies' : 'Picture';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '保存${isVideo ? "视频" : "图片"}时，文件将自动归类并存储至相册对应文件夹下。',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                RadioGroup<int>(
                  groupValue: currentType,
                  onChanged: (val) async {
                    if (val != null) {
                      HapticFeedbackUtil.light();
                      Navigator.pop(ctx);
                      if (isVideo) {
                        await notifier.setVideoSavePathType(val);
                      } else {
                        await notifier.setImageSavePathType(val);
                      }
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Option 0: 默认路径
                      ListTile(
                        title: const Text(
                          '默认路径',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        subtitle: Text(
                          '$baseDir/GreenNote/',
                          style: const TextStyle(fontSize: 14),
                        ),
                        leading: const Radio<int>(value: 0),
                        onTap: () async {
                          HapticFeedbackUtil.light();
                          Navigator.pop(ctx);
                          if (isVideo) {
                            await notifier.setVideoSavePathType(0);
                          } else {
                            await notifier.setImageSavePathType(0);
                          }
                        },
                      ),

                      // Option 1: 按本人昵称前缀归类
                      ListTile(
                        title: const Text(
                          '按本人昵称前缀归类',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        subtitle: Text(
                          '$baseDir/GreenNote/$myNickname/',
                          style: const TextStyle(fontSize: 14),
                        ),
                        leading: const Radio<int>(value: 1),
                        onTap: () async {
                          HapticFeedbackUtil.light();
                          Navigator.pop(ctx);
                          if (isVideo) {
                            await notifier.setVideoSavePathType(1);
                          } else {
                            await notifier.setImageSavePathType(1);
                          }
                        },
                      ),

                      // Option 2: 按博主昵称前缀归类
                      ListTile(
                        title: const Text(
                          '按博主昵称前缀归类',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        subtitle: Text(
                          '$baseDir/GreenNote/该条动态发布用户昵称/',
                          style: const TextStyle(fontSize: 14),
                        ),
                        leading: const Radio<int>(value: 2),
                        onTap: () async {
                          HapticFeedbackUtil.light();
                          Navigator.pop(ctx);
                          if (isVideo) {
                            await notifier.setVideoSavePathType(2);
                          } else {
                            await notifier.setImageSavePathType(2);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final myNickname = widget.api.currentUserNickname.trim().isEmpty
        ? 'MyProfile'
        : widget.api.currentUserNickname.trim();

    final imagePathType = settings.imageSavePathType;
    final videoPathType = settings.videoSavePathType;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ReviewFrostedAppBar(title: const Text('存储设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
          16,
          12,
        ),
        children: [
          // 媒体保存路径卡片
          AppSectionCard(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.image_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text(
                    '图片存储路径',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  subtitle: Text(
                    StoragePathResolver.getPathSummary(
                      imagePathType,
                      myNickname,
                      isVideo: false,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showPathSelectorDialog(
                    context,
                    notifier,
                    imagePathType,
                    myNickname,
                    isVideo: false,
                  ),
                ),
                const Divider(height: 1, indent: 72),
                ListTile(
                  leading: Icon(
                    Icons.video_library_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text(
                    '视频存储路径',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  subtitle: Text(
                    StoragePathResolver.getPathSummary(
                      videoPathType,
                      myNickname,
                      isVideo: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showPathSelectorDialog(
                    context,
                    notifier,
                    videoPathType,
                    myNickname,
                    isVideo: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
