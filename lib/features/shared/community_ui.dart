import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_dialog.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/coolapk_rich_text.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/network/coolapk_image.dart';

Map<String, dynamic> communityMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
Map<String, dynamic> communityData(dynamic response) {
  final root = communityMap(response);
  return root['data'] is Map ? communityMap(root['data']) : root;
}

String communityText(Map<String, dynamic> data, List<String> fields) {
  for (final field in fields) {
    final value = data[field]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

bool communityFlag(dynamic value) =>
    value == true || value == 1 || value == '1';

Future<dynamic> communityRequest(
  CoolapkApi api,
  String scope,
  String path, {
  String method = 'GET',
  Map<String, dynamic> query = const {},
  Map<String, dynamic>? body,
}) async {
  if (!api.hasCookie ||
      scope.isEmpty ||
      api.notificationSessionKey != scope ||
      !await api.notificationSessionMatches(scope) ||
      api.notificationSessionKey != scope) {
    throw StateError('Official account changed');
  }
  return api.request(path, method: method, query: query, body: body);
}

Future<bool> confirmCommunityAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ==
    true;

Future<Map<String, String>?> editCommunityFields(
  BuildContext context,
  String title,
  Map<String, String> values, {
  Map<String, int> limits = const {},
}) async {
  final controllers = values.map(
    (key, value) => MapEntry(key, TextEditingController(text: value)),
  );
  final formKey = GlobalKey<FormState>();
  final result = await showAppDialog<Map<String, String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: entry.value,
                    maxLines: entry.key == '内容' || entry.key == '说明' ? 5 : 1,
                    maxLength: limits[entry.key],
                    decoration: InputDecoration(labelText: entry.key),
                    validator: (value) =>
                        entry.key == '说明' || (value?.trim().isNotEmpty ?? false)
                        ? null
                        : '请填写${entry.key}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                controllers.map(
                  (key, value) => MapEntry(key, value.text.trim()),
                ),
              );
            }
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
  // Dialog's exit animation still uses its text fields.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}

class CommunityAction extends StatefulWidget {
  const CommunityAction({
    super.key,
    required this.api,
    required this.label,
    required this.action,
    this.onSuccess,
    this.icon = Icons.add,
    this.danger = false,
  });
  final CoolapkApi api;
  final String label;
  final Future<void> Function() action;
  final VoidCallback? onSuccess;
  final IconData icon;
  final bool danger;
  @override
  State<CommunityAction> createState() => _CommunityActionState();
}

class _CommunityActionState extends State<CommunityAction> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    style: widget.danger ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.errorContainer,
      foregroundColor: Theme.of(context).colorScheme.onErrorContainer) : null,
    icon: _busy
        ? const Icon(Icons.hourglass_empty)
        : Icon(widget.icon),
    label: Text(_busy ? '处理中…' : widget.label),
    onPressed: _busy
        ? null
        : () async {
            if (!widget.api.hasCookie) {
              AppToast.show(context, '请先使用酷安官方 Cookie 登录');
              return;
            }
            setState(() => _busy = true);
            try {
              await widget.action();
              if (mounted) widget.onSuccess?.call();
            } catch (_) {
              if (mounted) AppToast.show(this.context, '操作失败，请确认登录有效、网络正常后重试');
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}

class CommunityHero extends StatelessWidget {
  const CommunityHero({
    super.key,
    required this.api,
    required this.data,
    required this.kind,
    this.actions = const [],
    this.children = const [],
  });
  final CoolapkApi api;
  final Map<String, dynamic> data;
  final String kind;
  final List<Widget> actions;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final title = communityText(data, [
      'extra_title',
      'title',
      'name',
      'message_title',
      'goods_title',
    ]);
    final description = communityText(data, [
      'description',
      'intro',
      'message',
    ]);
    final image = communityText(data, [
      'cover',
      'pic',
      'logo',
      'icon',
      'cover_pic',
    ]);
    final author = communityText(data, ['username', 'userName']);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    normalizeCoolapkImageUrl(image),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    headers: coolapkImageHeaders(image, api: api),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Text(
                  title.isEmpty ? kind : title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(author),
            ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CoolapkRichText(api: api, text: description),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'follownum': '关注',
                'replynum': '回复',
                'answernum': '回答',
                'apknum': '应用',
                'itemnum': '内容',
              }.entries)
                if (data[entry.key] != null)
                  Text('${data[entry.key]} ${entry.value}'),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: actions),
            ),
          ...children,
        ],
      ),
    );
  }
}
