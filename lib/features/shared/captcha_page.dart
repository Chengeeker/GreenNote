import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/network/coolapk_captcha.dart';
import '../../core/design_system/components/review_frosted_app_bar.dart';

class CoolapkCaptchaPage extends StatefulWidget {
  const CoolapkCaptchaPage({super.key, required this.challenge});
  final CoolapkCaptchaChallenge challenge;
  @override
  State<CoolapkCaptchaPage> createState() => _CoolapkCaptchaPageState();
}

class _CoolapkCaptchaPageState extends State<CoolapkCaptchaPage> {
  WebViewController? _controller;
  String? _error;
  bool _finished = false;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (_preparing || _finished) return;
    if (!widget.challenge.isValid) {
      setState(() => _error = '验证参数无效，请重新加载榜单');
      return;
    }
    _preparing = true;
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'CoolapkCaptcha',
        onMessageReceived: (message) {
          if (!mounted ||
              _finished ||
              widget.challenge.proof(message.message) == null) {
            return;
          }
          _finished = true;
          Navigator.of(context).pop(message.message);
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              !request.isMainFrame ||
                  request.url == 'about:blank' ||
                  request.url == 'https://captcha.greennote.invalid/'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      if (!mounted) return;
      _controller = controller;
      await _load();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '验证页面加载失败，请重试');
    } finally {
      _preparing = false;
    }
  }

  Future<void> _load() async {
    if (!mounted || _finished) return;
    setState(() => _error = null);
    try {
      await _controller?.loadHtmlString(
        '''<!doctype html><html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>:root{color-scheme:light dark}body{font:16px sans-serif;margin:24px;line-height:1.6;color:CanvasText;background:Canvas}</style>
</head><body><p id="status">正在加载验证组件…</p><div id="captcha"></div>
<script>
function statusText(s){document.getElementById('status').textContent=s;}
var timeout=setTimeout(function(){statusText('加载超时，请点击右上角重新加载');},15000);
var script=document.createElement('script');script.src='https://cstaticdun.126.net/load.min.js';
script.onerror=function(){clearTimeout(timeout);statusText('加载失败，请检查网络后重新加载');};
script.onload=function(){try{initNECaptcha({captchaId:'${widget.challenge.id}',element:'#captcha',
protocol:'https',mode:'embed',apiVersion:2,width:Math.min(320,window.innerWidth-48)+'px',lang:'zh-CN',
onVerify:function(err,data){if(!err&&data&&data.validate){CoolapkCaptcha.postMessage(data.validate);}
else{statusText('验证未通过，请按提示重试');}}},
function(){clearTimeout(timeout);statusText('请按下方提示完成人机验证');},
function(){clearTimeout(timeout);statusText('验证组件不可用，请重新加载');});}
catch(e){clearTimeout(timeout);statusText('验证组件初始化失败，请重新加载');}};
document.head.appendChild(script);
</script></body></html>''',
        baseUrl: 'https://captcha.greennote.invalid/',
      );
    } catch (_) {
      if (mounted) setState(() => _error = '验证页面加载失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: const Text('人机验证'),
      actions: [
        IconButton(
          tooltip: '重新加载验证',
          icon: const Icon(Icons.refresh),
          onPressed: _preparing
              ? null
              : _controller == null
              ? _prepare
              : _load,
        ),
      ],
    ),
    body: _error != null
        ? Center(child: Text(_error!))
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(controller: _controller!),
  );
}
