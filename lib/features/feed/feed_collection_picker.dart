import 'package:flutter/material.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/utils/app_toast.dart';

Future<bool?> showFeedCollectionPicker(
  BuildContext context,
  CoolapkApi api,
  CoolapkFeed feed,
) async {
  if (!api.hasCookie) {
    AppToast.show(
      context,
      api.isAnonymous ? '匿名账户仅支持本地收藏，暂不支持收藏夹' : api.loginRequiredMessage,
    );
    return null;
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => _CollectionPicker(api: api, feed: feed),
  );
}

class _CollectionPicker extends StatefulWidget {
  const _CollectionPicker({required this.api, required this.feed});
  final CoolapkApi api;
  final CoolapkFeed feed;

  @override
  State<_CollectionPicker> createState() => _CollectionPickerState();
}

class _CollectionPickerState extends State<_CollectionPicker> {
  late final _scope = widget.api.notificationSessionKey;
  List<FeedCollection>? _items;
  final _selected = <String>{};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await widget.api.getFeedCollections(
        widget.feed.id,
        scope: _scope,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.addAll(
          items.where((item) => item.selected).map((item) => item.id),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cancelled = _items!
          .where((item) => item.selected && !_selected.contains(item.id))
          .map((item) => item.id)
          .toList();
      await widget.api.updateFeedCollections(
        widget.feed.id,
        selected: _selected.toList(),
        cancelled: cancelled,
        scope: _scope,
        feed: widget.feed,
      );
      if (mounted) Navigator.pop(context, _selected.isNotEmpty);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                '选择收藏夹',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: _items == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!),
                                    TextButton(
                                      onPressed: _load,
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    )
                  : _items!.isEmpty
                  ? const Center(child: Text('暂无可用收藏夹，请先在“我的收藏”中新建'))
                  : ListView.builder(
                      itemCount: _items!.length,
                      itemBuilder: (context, index) {
                        final item = _items![index];
                        return CheckboxListTile(
                          title: Text(item.title),
                          subtitle: item.isDefault ? const Text('默认收藏夹') : null,
                          value: _selected.contains(item.id),
                          onChanged: _saving
                              ? null
                              : (checked) => setState(() {
                                  checked == true
                                      ? _selected.add(item.id)
                                      : _selected.remove(item.id);
                                }),
                        );
                      },
                    ),
            ),
            if (_items != null && _error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving || _items == null || _items!.isEmpty
                        ? null
                        : _save,
                    child: Text(_saving ? '保存中…' : '完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
