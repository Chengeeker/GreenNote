import 'package:flutter/material.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';

class DeviceIdentityGuidePage extends StatelessWidget {
  const DeviceIdentityGuidePage({super.key});

  static const _sections = [
    (
      '1. 准备官方酷安',
      '先安装并正常打开 Android 官方酷安。回到 GreenNote 的“导入官方设备标识”页，点击“打开酷安 OAID 界面”，进入官方的“检查日志和测试”页面。\n\n'
          '如果没有安装官方酷安，需要先安装。已经安装却打不开时，请确认应用已启用，更新后再试；不同版本的入口可能有所变化。此次导入不需要 root，也不需要提供账号密码。',
    ),
    (
      '2. 在同一页面复制 5 次',
      '在官方“检查日志和测试”页面向下找到“复制 OAID”，留在这个页面，慢慢累计点击 5 次。\n\n'
          '前几次可能只有 OAID，或者提示没有 OAID。第 5 次才会复制包含多个字段的完整文本。不要只复制普通 OAID，也不要在中途退出这个页面。',
    ),
    (
      '3. 确认包含 ShuzlmID',
      '完整复制内容通常包含下面这些字段（省略号只是示意，并非可用的标识）：\n\n'
          '设备ID: …\nShuzlmID: …\nAndroidID: …\nUUID: …\n\n'
          '按钮虽然叫“复制 OAID”，GreenNote 实际使用的是 ShuzlmID（数盟 ID）。OAID、AndroidID、UUID 和随机字符串都不能代替它。请保留整段复制内容，不必自己挑出某个值。',
    ),
    (
      '4. 返回 GreenNote 识别并保存',
      '回到“导入官方设备标识”页，点击“粘贴并识别”。也可以长按输入框粘贴完整内容，再点击“识别输入内容”。\n\n'
          '出现“已识别数盟 ID”后，点击“保存并应用”。仅识别还不会生效，必须保存；看到保存成功提示后，再返回动态或评论页刷新。识别成功后，原始复制文本会自动从输入框清除。',
    ),
    (
      '常见问题',
      '提示找不到 ShuzlmID：可能复制的仍是普通 OAID。重新进入官方同一页面，累计点击 5 次，再复制完整内容。\n\n'
          '提示 ID 为空或格式不正确：先正常打开官方酷安，等它完成加载后重新获取。不要拿 AndroidID、UUID 或随意生成的内容补填。\n\n'
          '提示不止一个 ShuzlmID：不要拼接多份内容，只粘贴最近一次完整复制的文本。\n\n'
          '保存后仍要求验证：设备标识可能失效，也可能受到账号、网络或接口访问条件影响。可以重新获取并导入；仍有验证时，按服务端要求完成验证。此功能不能保证长期免验证或所有接口恢复。\n\n'
          '想撤销导入：在导入页点击“恢复原设备码”并确认。现有登录状态、匿名资料和收藏会保留。\n\n'
          '找不到导入入口：请使用包含此功能的 GreenNote 版本，旧安装包不会自动增加入口。跨设备及桌面端的效果尚未验证。',
    ),
    (
      '标识与隐私',
      'GreenNote 只提取所需的数盟 ID，并按请求协议保存设备编码；复制内容中的其他标识不会保存。已有设备参数保持原值，历史版本仅有随机设备码时，会在首次导入时使用本机厂商、品牌、型号和系统构建信息补齐格式。\n\n'
          '应用不会为了此功能读取 IMEI、硬件序列号、AndroidID 或 OAID，也不会在后台读取剪贴板。已保存的设备编码在本机使用并随请求发送给酷安，不会加入 WebDAV 备份。\n\n'
          '请勿把完整复制内容、真实 ID 或含有这些信息的截图发送到公开群聊、Issue 或仓库。导入设备标识不等于账号登录，有效期与验证要求仍由酷安服务端决定。',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ReviewFrostedAppBar(title: Text('设备标识导入教程')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('操作说明已保存在应用内，可离线阅读。'),
                  for (final (title, body) in _sections) ...[
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(body),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回导入页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
