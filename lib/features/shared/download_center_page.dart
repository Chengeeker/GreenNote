import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/utils/app_toast.dart';
import 'community_ui.dart';
import 'app_detail_page.dart';

const downloadChannel = MethodChannel('com.green.note/downloads');

Future<void> enqueueAppDownload(
  BuildContext context,
  Uri url,
  String name,
) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw const FormatException('下载地址无效');
  }
  await downloadChannel.invokeMethod<int>('enqueue', {
    'url': url.toString(),
    'name': name,
  });
  if (context.mounted) {
    AppToast.show(context, '已加入下载管理');
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DownloadCenterPage()),
    );
  }
}

class DownloadCenterPage extends StatefulWidget {
  const DownloadCenterPage({
    super.key,
    this.packages = false,
    this.showAppBar = true,
    this.active = true,
  });
  final bool packages;
  final bool showAppBar;
  final bool active;
  @override
  State<DownloadCenterPage> createState() => _DownloadCenterPageState();
}

class _DownloadCenterPageState extends State<DownloadCenterPage> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  Timer? _timer;
  bool _loading = false;
  int _filter = 0;
  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          widget.active &&
          !widget.packages &&
          (_items?.any((item) => item['status'] != 8 && item['status'] != 16) ??
              false) &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DownloadCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final values = await downloadChannel.invokeListMethod<dynamic>(
        widget.packages ? 'packages' : 'list',
      );
      if (mounted) {
        setState(() {
          _items = (values ?? []).whereType<Map>().map(communityMap).toList();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取下载记录，点击重试');
    } finally {
      _loading = false;
    }
  }

  Future<void> _action(String method, Map<String, dynamic> item) async {
    try {
      if (method == 'cancel' &&
          !await confirmCommunityAction(context, '移除下载？', '任务及对应的下载文件将被移除。')) {
        return;
      }
      await downloadChannel.invokeMethod<dynamic>(
        method,
        widget.packages ? {'path': item['path']} : {'id': item['id']},
      );
      await _load();
    } on PlatformException catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          error.code == 'INSTALL_PERMISSION' ? '请允许安装应用后再次点击安装' : '操作失败，请稍后重试',
        );
      }
    }
  }

  String _size(dynamic bytes) =>
      '${((bytes is num ? bytes.toDouble() : 0) / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) {
    final items = (_items ?? [])
        .where(
          (item) =>
              widget.packages ||
              _filter == 0 ||
              (_filter == 1
                  ? item['status'] != 8 && item['status'] != 16
                  : item['status'] == 8 || item['status'] == 16),
        )
        .toList();
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.packages
                ? '应用下载目录中的 APK；点按安装后仍需系统确认。'
                : '下载由 Android 系统管理；离开应用后继续。可在此取消、重试和安装。',
          ),
        ),
        if (!widget.packages)
          Wrap(
            spacing: 8,
            children: [
              for (final entry in ['全部', '进行中', '已结束'].indexed)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _filter == entry.$1,
                  onSelected: (_) => setState(() => _filter = entry.$1),
                ),
            ],
          ),
        if (_error != null) TextButton(onPressed: _load, child: Text(_error!)),
        Expanded(
          child: _items == null && _error == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('暂无记录')),
                        ),
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['title']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.packages
                                    ? '${item['version']} · ${_size(item['bytes'])}'
                                    : '${switch (item['status']) {
                                        1 => '等待中',
                                        2 => '下载中',
                                        4 => '等待系统恢复',
                                        8 => '下载完成',
                                        16 => '下载失败',
                                        _ => '未知状态',
                                      }} · ${_size(item['bytes'])}${(item['total'] as num? ?? 0) > 0 ? ' / ${_size(item['total'])}' : ''}',
                              ),
                              if (!widget.packages && item['status'] == 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(
                                    value: (item['total'] as num? ?? 0) > 0
                                        ? ((item['bytes'] as num) /
                                                  (item['total'] as num))
                                              .clamp(0.0, 1.0)
                                        : null,
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (widget.packages || item['status'] == 8)
                                    TextButton.icon(
                                      onPressed: () => _action('install', item),
                                      icon: const Icon(Icons.install_mobile),
                                      label: const Text('安装'),
                                    ),
                                  if (!widget.packages && item['status'] == 16)
                                    TextButton.icon(
                                      onPressed: () => _action('retry', item),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('重试'),
                                    ),
                                  if (!widget.packages)
                                    TextButton(
                                      onPressed: () => _action('cancel', item),
                                      child: Text(
                                        item['status'] == 8 ||
                                                item['status'] == 16
                                            ? '移除'
                                            : '取消下载',
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
    return widget.showAppBar
        ? Scaffold(
            appBar: ReviewFrostedAppBar(
              title: Text(widget.packages ? '安装包' : '下载管理'),
            ),
            body: body,
          )
        : body;
  }
}

class InstalledUpdatesPage extends StatefulWidget {
  const InstalledUpdatesPage({
    super.key,
    required this.api,
    required this.apps,
    this.active = true,
  });
  final CoolapkApi api;
  final List<Map<String, dynamic>> apps;
  final bool active;
  @override
  State<InstalledUpdatesPage> createState() => _InstalledUpdatesPageState();
}

class _InstalledUpdatesPageState extends State<InstalledUpdatesPage> {
  final _updates = <Map<String, dynamic>>[];
  bool _checking = false;
  int _checked = 0, _failed = 0, _generation = 0;
  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _check() async {
    if (!await confirmCommunityAction(
      context,
      '检查应用更新？',
      '将向酷安逐项查询已安装第三方应用的包名，不发送应用内数据。',
    )) {
      return;
    }
    if (!mounted) return;
    final apps = widget.apps.where((app) => app['isSystem'] != true).toList();
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _checked = 0;
      _failed = 0;
      _updates.clear();
    });
    for (var offset = 0; offset < apps.length; offset += 3) {
      if (!mounted || generation != _generation) break;
      if (!widget.active || ModalRoute.of(context)?.isCurrent != true ||
          !TickerMode.valuesOf(context).enabled ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        break;
      }
      final results = await Future.wait(
        apps.skip(offset).take(3).map((app) async {
          try {
            final data = communityData(
              await widget.api.request(
                '/v6/apk/detail',
                query: {'id': app['packageName']},
              ),
            );
            final latest = int.tryParse(
              '${data['apkversioncode'] ?? data['versionCode']}',
            );
            final installed = app['versionCode'] as num?;
            if (latest == null || installed == null) {
              return (data: <String, dynamic>{}, failed: true);
            }
            return (
              data: latest > installed
                  ? {
                      ...data,
                      '_installedVersion': app['version'],
                      'packageName': app['packageName'],
                    }
                  : <String, dynamic>{},
              failed: false,
            );
          } catch (_) {
            return (data: <String, dynamic>{}, failed: true);
          }
        }),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _checked += results.length;
        _failed += results.where((result) => result.failed).length;
        _updates.addAll(
          results
              .where((result) => result.data.isNotEmpty)
              .map((result) => result.data),
        );
      });
    }
    if (mounted && generation == _generation) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('只比较已安装第三方应用的版本号。查询由你手动发起，最多三个并发请求，酷安未收录或查询失败的应用不算作已是最新。'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _checking
            ? () => setState(() {
                _generation++;
                _checking = false;
              })
            : _check,
        child: Text(_checking ? '停止检查（$_checked 项）' : '检查更新'),
      ),
      if (_checking)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      Text('已检查 $_checked 项 · ${_updates.length} 项更新 · $_failed 项无法确认'),
      for (final item in _updates)
        ListTile(
          title: Text(communityText(item, ['title', 'apkname', 'packageName'])),
          subtitle: Text(
            '${item['_installedVersion']} → ${item['apkversionname'] ?? item['versionName'] ?? ''}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailPage(
                api: widget.api,
                id: '${item['packageName']}',
                initialEntity: item,
              ),
            ),
          ),
        ),
    ],
  );
}
