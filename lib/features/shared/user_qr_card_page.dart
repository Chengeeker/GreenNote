import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/design_system/components/review_card.dart';
import '../../core/design_system/components/review_page_scaffold.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/app_avatar.dart';

void openUserQrCard(
  BuildContext context,
  CoolapkApi api, {
  required String uid,
  required String name,
  required String avatar,
}) {
  final id = uid.trim();
  if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
    AppToast.show(context, '请先登录并加载个人资料');
    return;
  }
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          UserQrCardPage(api: api, uid: id, name: name, avatar: avatar),
    ),
  );
}

class UserQrCardPage extends StatelessWidget {
  const UserQrCardPage({
    required this.api,
    required this.uid,
    required this.name,
    required this.avatar,
    super.key,
  });

  final CoolapkApi api;
  final String uid;
  final String name;
  final String avatar;

  String get profileUrl => 'https://www.coolapk.com/u/$uid';

  Future<void> _copyLink(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: profileUrl));
      if (context.mounted) AppToast.show(context, '已复制主页链接');
    } catch (_) {
      if (context.mounted) AppToast.show(context, '复制失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    title: '我的二维码名片',
    bodyBuilder: (context, insets) => SafeArea(
      top: false,
      child: Padding(
        padding: insets,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ReviewCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          AppAvatar(
                            api: api,
                            url: avatar,
                            name: name,
                            size: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.trim().isEmpty ? '酷安用户' : name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'UID $uid',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) => QrImageView(
                          data: profileUrl,
                          size: constraints.maxWidth.clamp(0.0, 240.0),
                          padding: const EdgeInsets.all(32),
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          semanticsLabel: '个人主页二维码，UID $uid',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '扫一扫二维码，查看我的个人主页',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => _copyLink(context),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('复制主页链接'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
