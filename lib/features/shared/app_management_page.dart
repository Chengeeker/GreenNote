import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/utils/app_toast.dart';

class AppManagementPage extends StatefulWidget {
  const AppManagementPage({super.key});

  @override
  State<AppManagementPage> createState() => _AppManagementPageState();
}

class _AppManagementPageState extends State<AppManagementPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('com.green.note/app_manager');
  static const _tabs = ['更新', '下载管理', '安装包'];

  late final TabController _tabsController = TabController(
    length: _tabs.length + 1,
    vsync: this,
  );
  List<Map<String, dynamic>> _apps = const [];
  bool _showSystemApps = false;
  bool _loading = true;
  String? _error;
  String _sort = 'recent';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadApps();
  }

  Future<void> _loadApps() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await _channel.invokeListMethod<Object?>(
        'getInstalledApps',
      );
      final apps = [
        for (final value in values ?? const <Object?>[])
          if (value is Map) Map<String, dynamic>.from(value),
      ];
      if (mounted) setState(() => _apps = apps);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '读取本机应用失败');
    } on MissingPluginException {
      if (mounted) setState(() => _error = '当前平台不支持读取本机应用');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleApps {
    final apps = _apps
        .where((app) => _showSystemApps || app['isSystem'] != true)
        .toList();
    switch (_sort) {
      case 'name':
        apps.sort(
          (a, b) => '${a['label']}'.toLowerCase().compareTo(
            '${b['label']}'.toLowerCase(),
          ),
        );
        break;
      case 'size':
        apps.sort(
          (a, b) => _number(b['sizeBytes']).compareTo(_number(a['sizeBytes'])),
        );
        break;
      default:
        apps.sort(
          (a, b) => _number(b['updatedAt']).compareTo(_number(a['updatedAt'])),
        );
        break;
    }
    return apps;
  }

  Future<void> _openApp(Map<String, dynamic> app) async {
    try {
      final launched = await _channel.invokeMethod<bool>('launchApp', {
        'packageName': app['packageName'],
      });
      if (launched != true && mounted) {
        AppToast.show(context, '这个应用没有可用的启动入口');
      }
    } on PlatformException catch (error) {
      if (mounted) AppToast.show(context, error.message ?? '打开应用失败');
    }
  }

  Future<void> _showAppInfo(Map<String, dynamic> app) async {
    try {
      await _channel.invokeMethod<bool>('showAppInfo', {
        'packageName': app['packageName'],
      });
    } on PlatformException catch (error) {
      if (mounted) AppToast.show(context, error.message ?? '打开应用详情失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = _visibleApps;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('应用管理'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '排序方式',
            icon: const Icon(Icons.filter_list_rounded),
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              _sortItem('recent', '最近更新'),
              _sortItem('name', '按名称'),
              _sortItem('size', '按大小'),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabsController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: const Color(0xFF00A993),
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicatorColor: const Color(0xFF00A993),
            indicatorWeight: 3,
            tabs: [
              Tab(text: '应用(${apps.length})'),
              for (final title in _tabs) Tab(text: title),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabsController,
              children: [
                _buildAppsTab(apps),
                _emptyTab(
                  Icons.system_update_alt_rounded,
                  '暂未接入更新检查',
                  '酷安更新接口所需的应用清单格式尚未验证，当前不会自动提交本机应用信息。',
                ),
                _emptyTab(
                  Icons.download_outlined,
                  '暂无应用内下载任务',
                  '目前应用下载会交由系统或外部应用处理。',
                ),
                _emptyTab(
                  Icons.install_mobile_outlined,
                  '暂未接入安装包扫描',
                  '本页仅列出已安装应用。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String title) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Expanded(child: Text(title)),
        if (_sort == value)
          const Icon(Icons.check_rounded, size: 18, color: Color(0xFF00A993)),
      ],
    ),
  );

  Widget _buildAppsTab(List<Map<String, dynamic>> apps) => Column(
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: const Text('显示系统预装应用'),
        trailing: Switch.adaptive(
          value: _showSystemApps,
          activeTrackColor: const Color(0xFF00A993),
          onChanged: (value) => setState(() => _showSystemApps = value),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _loadApps,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : apps.isEmpty
            ? const Center(child: Text('没有找到本机应用'))
            : RefreshIndicator.adaptive(
                onRefresh: _loadApps,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  itemCount: apps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) => _appRow(apps[index]),
                ),
              ),
      ),
    ],
  );

  Widget _appRow(Map<String, dynamic> app) {
    final icon = app['icon'];
    final bytes = icon is Uint8List ? icon : null;
    final launchable = app['canLaunch'] == true;
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: bytes == null || bytes.isEmpty
                  ? _iconFallback()
                  : Image.memory(
                      bytes,
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _iconFallback(),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${app['label'] ?? app['packageName'] ?? '未知应用'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${app['version'] ?? ''}  ${_formatSize(_number(app['sizeBytes']))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '应用选项',
              icon: Icon(
                Icons.more_vert_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onSelected: (_) => _showAppInfo(app),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'info', child: Text('应用详情')),
              ],
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 78,
              height: 38,
              child: FilledButton(
                onPressed: launchable ? () => _openApp(app) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF009F91),
                  disabledBackgroundColor: const Color(0xFF454545),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: const StadiumBorder(),
                ),
                child: const Text('打开'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconFallback() => Container(
    width: 52,
    height: 52,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: const Icon(Icons.android_rounded),
  );

  Widget _emptyTab(IconData icon, String title, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  static int _number(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '大小未知';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}G';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}M';
    }
    return '${(bytes / 1024).toStringAsFixed(0)}K';
  }
}
