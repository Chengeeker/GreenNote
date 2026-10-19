import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/design_system/components/review_frosted_app_bar.dart';
import '../../core/network/coolapk_api.dart';
import '../../core/network/coolapk_login.dart';

class OfficialLoginPage extends StatefulWidget {
  const OfficialLoginPage({required this.api, this.login, super.key});
  final CoolapkApi api;
  @visibleForTesting
  final CoolapkLogin? login;

  @override
  State<OfficialLoginPage> createState() => _OfficialLoginPageState();
}

class _OfficialLoginPageState extends State<OfficialLoginPage> {
  late final CoolapkLogin _session;
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  bool _busy = true;
  bool _ready = false;
  bool _validating = false;
  bool _showPassword = false;
  Uint8List? _captchaImage;
  String? _error;
  bool get _supportsWeb =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _session = widget.login ?? CoolapkLogin();
    _prepare();
  }

  @override
  void dispose() {
    _session.close();
    _account.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  String _message(Object error) => switch (error) {
    CoolapkLoginException() => error.message,
    CoolapkApiException() => '账号校验未通过：${error.message}',
    _ => '连接失败，请检查网络后重试，或使用官方网页登录',
  };

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
      _ready = false;
    });
    try {
      await _session.prepare();
      if (mounted) {
        setState(() {
          _ready = true;
          _captchaImage = null;
          _captcha.clear();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCaptcha() async {
    final bytes = await _session.captcha();
    if (mounted) {
      setState(() {
        _captchaImage = bytes;
        _captcha.clear();
      });
    }
  }

  Future<void> _refreshCaptcha() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _loadCaptcha();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (_busy || !_ready) return;
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    var webRequired = false;
    var success = false;
    try {
      final cookie = await _session.login(
        _account.text.trim(),
        _password.text,
        _captcha.text.trim(),
      );
      if (!mounted) return;
      setState(() => _validating = true);
      await widget.api.validateAndSaveCookie(cookie);
      if (!mounted) return;
      _password.clear();
      success = true;
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
      if (error is CoolapkLoginException) {
        webRequired = error.webRequired;
        if (error.captchaRequired) {
          try {
            await _loadCaptcha();
          } catch (_) {
            if (mounted) setState(() => _error = '验证码加载失败，请重试或使用官方网页登录');
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _validating = false;
        });
      }
    }
    if (success) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (mounted && webRequired && _supportsWeb) await _webLogin();
  }

  Future<void> _webLogin() async {
    if (_busy) return;
    _password.clear();
    setState(() => _busy = true);
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OfficialWebLoginPage(api: widget.api)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (success == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_validating,
    child: Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('账号登录')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('使用酷安账号登录。密码仅用于本次登录，不会保存；登录凭据通过校验后保存在本机安全存储中。'),
                const SizedBox(height: 24),
                TextField(
                  controller: _account,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    hintText: '用户名 / 手机号 / 邮箱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: _captchaImage == null
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: (_) {
                    if (_captchaImage == null) _login();
                  },
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                setState(() => _showPassword = !_showPassword),
                      tooltip: _showPassword ? '隐藏密码' : '显示密码',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (_captchaImage != null) ...[
                  const SizedBox(height: 16),
                  Image.memory(
                    _captchaImage!,
                    height: 72,
                    semanticLabel: '酷安图形验证码',
                    errorBuilder: (_, _, _) => const Text('验证码图片无法显示，请刷新'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _refreshCaptcha,
                    child: const Text('刷新验证码'),
                  ),
                  TextField(
                    controller: _captcha,
                    enabled: !_busy,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                      labelText: '图形验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(semanticsLabel: '正在处理登录'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy || !_ready ? null : _login,
                  child: const Text('登录并校验'),
                ),
                TextButton(
                  onPressed: _busy ? null : _prepare,
                  child: const Text('重新加载登录参数'),
                ),
                if (_supportsWeb) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _webLogin,
                    icon: const Icon(Icons.public),
                    label: const Text('使用官方网页登录'),
                  ),
                  const SizedBox(height: 8),
                  const Text('需要人机验证或无法直接登录时，可在酷安官方网页中完成登录。'),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class OfficialWebLoginPage extends StatefulWidget {
  const OfficialWebLoginPage({required this.api, super.key});
  final CoolapkApi api;
  @override
  State<OfficialWebLoginPage> createState() => _OfficialWebLoginPageState();
}

class _OfficialWebLoginPageState extends State<OfficialWebLoginPage> {
  static const _cookies = MethodChannel('com.green.note/login_cookies');
  WebViewController? _controller;
  String? _error;
  int _progress = 0;
  bool _checking = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _saved = false;
  bool _initializing = false;
  String? _lastCandidate;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  static bool _official(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      const ['account.coolapk.com', 'www.coolapk.com'].contains(uri.host);

  Future<void> _initialize() async {
    if (_initializing || _closing) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      await _cookies
          .invokeMethod<void>('clear')
          .timeout(const Duration(seconds: 10));
      if (!mounted || _closing) return;
      final controller = WebViewController();
      final background = Theme.of(context).colorScheme.surface;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(background);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onNavigationRequest: (request) {
            if (_closing) {
              return request.url == 'about:blank'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            if (!request.isMainFrame || uri != null && _official(uri)) {
              return NavigationDecision.navigate;
            }
            if (mounted && !_closing) {
              setState(() => _error = '此登录页仅支持酷安官方站内登录，请返回使用账号密码登录');
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (url) {
            final uri = Uri.tryParse(url);
            if (uri != null &&
                _official(uri) &&
                uri.host == 'www.coolapk.com' &&
                (uri.path.isEmpty || uri.path == '/')) {
              _finish(automatic: true);
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true && !_closing) {
              setState(() => _error = '官方登录页面加载失败，请重新加载');
            }
          },
          onHttpError: (error) {
            if (mounted &&
                error.request?.uri ==
                    Uri.tryParse(
                      'https://account.coolapk.com/auth/login?type=mobile',
                    )) {
              setState(() => _error = '官方登录页面暂不可用，请重新加载');
            }
          },
        ),
      );
      if (!mounted || _closing) return;
      setState(() => _controller = controller);
      await controller.loadRequest(
        Uri.parse('https://account.coolapk.com/auth/login?type=mobile'),
      );
    } catch (_) {
      if (mounted && !_closing) setState(() => _error = '无法初始化网页登录，请返回重试');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _finish({bool automatic = false}) async {
    if (_checking || _closing) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final cookie =
          await _cookies
              .invokeMethod<String>('read')
              .timeout(const Duration(seconds: 10)) ??
          '';
      if (!mounted || _closing) return;
      if (!CoolapkLogin.hasAccountCookie(cookie)) {
        if (!automatic) setState(() => _error = '尚未取得完整登录凭据，请先在网页中完成登录');
        return;
      }
      if (automatic && _lastCandidate == cookie) return;
      _lastCandidate = cookie;
      await widget.api.validateAndSaveCookie(cookie);
      _saved = true;
      if (mounted) await _leave(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is CoolapkApiException
              ? '账号校验未通过：${error.message}。可完成网页验证后重试。'
              : '无法读取或保存登录状态，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _leave(bool success) async {
    if (_closing) return;
    _closing = true;
    // Replace the document before removing the browser's temporary cookies.
    try {
      await _controller?.loadHtmlString('<!doctype html><html></html>');
      await _cookies
          .invokeMethod<void>('clear')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted) setState(() => _error = '临时网页登录数据清理失败，请重试');
      _closing = false;
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, success || _saved);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_checking) _leave(false);
    },
    child: Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('酷安官方网页登录'),
        leading: IconButton(
          tooltip: '返回',
          onPressed: _checking ? null : () => _leave(false),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '重新加载',
            onPressed: _checking || _controller == null
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _lastCandidate = null;
                    });
                    _controller!.reload();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress < 100 || _checking)
              LinearProgressIndicator(
                value: _checking ? null : _progress / 100,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _controller == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: _initialize,
                              child: const Text('重新初始化网页登录'),
                            ),
                    )
                  : WebViewWidget(controller: _controller!),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: _checking || _controller == null
                    ? null
                    : () => _finish(),
                child: const Text('已完成网页登录，校验并保存'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
