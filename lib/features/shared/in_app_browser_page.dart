import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/app_toast.dart';

class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage({super.key, required this.url});
  final String url;
  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  WebViewController? _controller;
  late String _url = widget.url;
  String _title = '';
  String? _error;
  int _progress = 0;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final uri = Uri.tryParse(widget.url);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('网页地址无效');
      }
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _url = url;
                _error = null;
              });
            }
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            try {
              final title = await controller.getTitle();
              final back = await controller.canGoBack();
              if (mounted) {
                setState(() {
                  _title = title ?? '';
                  _canGoBack = back;
                });
              }
            } catch (_) {
              // The platform view may already be closing.
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    ['http', 'https'].contains(uri.scheme) &&
                    uri.userInfo.isEmpty
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '网页加载失败，请重试');
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(uri);
    } catch (_) {
      if (mounted) setState(() => _error = '当前无法打开内置浏览器');
    }
  }

  Future<void> _external() async {
    try {
      final opened = await launchUrl(
        Uri.parse(_url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) AppToast.show(context, '无法打开外部浏览器');
    } catch (_) {
      if (mounted) AppToast.show(context, '无法打开外部浏览器');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) await _controller?.goBack();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '关闭网页',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_title.isNotEmpty)
              Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            Text(
              Uri.tryParse(_url)?.host ?? _url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新网页',
            onPressed: _controller == null
                ? _prepare
                : () => _controller!.reload(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '网页选项',
            onSelected: (value) async {
              if (value == 'external') {
                await _external();
              } else {
                await Clipboard.setData(ClipboardData(text: _url));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'external', child: Text('用外部浏览器打开')),
              PopupMenuItem(value: 'copy', child: Text('复制链接')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100 && _error == null)
            LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _controller == null
                      ? _prepare
                      : () => _controller!.reload(),
                  child: const Text('重试'),
                ),
              ],
            ),
          if (_controller != null)
            Expanded(child: WebViewWidget(controller: _controller!)),
        ],
      ),
    ),
  );
}
