import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/network/coolapk_api.dart';
import '../../core/storage/storage_path_resolver.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/haptic_feedback_util.dart';

enum _VideoDragMode { none, brightness, volume }

enum _VideoHudType { none, brightness, volume, doubleTapSeek, fastForward }

/// 全功能沉浸式视频播放器页面（复用自 Review 微博视频播放器逻辑，适配微博与酷安多媒体流）
class CoolapkVideoPlayerPage extends StatefulWidget {
  final CoolapkApi api;
  final String videoUrl;
  final String requestParams;
  final String? coverUrl;
  final String? title;
  final String? authorName;
  final String? feedId;

  const CoolapkVideoPlayerPage({
    super.key,
    required this.api,
    required this.videoUrl,
    this.requestParams = '',
    this.coverUrl,
    this.title,
    this.authorName,
    this.feedId,
  });

  @override
  State<CoolapkVideoPlayerPage> createState() => _CoolapkVideoPlayerPageState();
}

class _CoolapkVideoPlayerPageState extends State<CoolapkVideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isLandscape = false;

  double _playbackSpeed = 1.0;
  static const List<double> _availableSpeeds = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    3.0,
  ];

  _VideoDragMode _dragMode = _VideoDragMode.none;
  _VideoHudType _hudType = _VideoHudType.none;
  double _brightnessLevel = 0.5;
  double _volumeLevel = 0.7;
  int _hudSeekDiff = 0;
  Duration _targetSeekPosition = Duration.zero;
  Offset _panStartPos = Offset.zero;
  Timer? _hudDismissTimer;
  String _playableUrl = '';
  bool _isSavingVideo = false;

  @override
  void initState() {
    super.initState();
    _initAndPlay();
    _resetControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _hudDismissTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _initAndPlay() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _isInitialized = false;
    });

    try {
      final realUrl = await _resolvePlayableUrl(
        widget.videoUrl,
        widget.requestParams,
        widget.api,
      );
      if (realUrl.isEmpty) {
        throw Exception('无法解析视频播放地址');
      }
      _playableUrl = realUrl;

      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      };
      if (realUrl.contains('weibo') || realUrl.contains('sina')) {
        headers['Referer'] = 'https://h5.video.weibo.com/';
        headers['Origin'] = 'https://h5.video.weibo.com';
      } else if (realUrl.contains('coolapk')) {
        headers['Referer'] = 'https://www.coolapk.com/';
      }

      await _controller?.dispose();
      VideoPlayerController controller = VideoPlayerController.networkUrl(
        Uri.parse(realUrl),
        httpHeaders: headers,
      );
      _controller = controller;

      try {
        await controller.initialize();
      } catch (firstError) {
        // Fallback retry without Referer in case CDN rejected the header
        if (headers.containsKey('Referer')) {
          controller = VideoPlayerController.networkUrl(
            Uri.parse(realUrl),
            httpHeaders: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36',
            },
          );
          _controller = controller;
          await controller.initialize();
        } else {
          rethrow;
        }
      }

      if (!mounted || _controller != controller) return;

      controller.setLooping(true);
      controller.setPlaybackSpeed(_playbackSpeed);
      controller.setVolume(_volumeLevel);
      await controller.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 支持解析微博组件视频、短链接重定向与酷安视频直链
  static Future<String> _resolvePlayableUrl(
    String input,
    String requestParams,
    CoolapkApi api,
  ) async {
    var trimmed = input.trim();
    if (trimmed.isEmpty && requestParams.trim().isEmpty) return '';

    if (requestParams.trim().isNotEmpty) {
      try {
        final response = await api.resolveVideoUrl(requestParams);
        final stream = _extractStreamUrl(response);
        if (stream.isNotEmpty) return stream;
      } catch (_) {}
    }

    final directUri = Uri.tryParse(trimmed);
    if (directUri != null &&
        (directUri.path.toLowerCase().endsWith('.mp4') ||
            directUri.path.toLowerCase().endsWith('.m3u8'))) {
      return trimmed;
    }

    if (trimmed.isEmpty) return '';

    // 1. 跟随短链 301/302 重定向 (如 t.cn / b23.tv)
    if (trimmed.contains('t.cn/') ||
        trimmed.contains('b23.tv/') ||
        trimmed.contains('url.cn/')) {
      try {
        final redirectDio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        final res = await redirectDio.get<dynamic>(trimmed);
        final location = res.headers.value('location');
        if (location != null && location.isNotEmpty) {
          trimmed = location;
        }
      } catch (_) {}
    }

    if (trimmed.contains('.mp4') || trimmed.contains('.m3u8')) {
      return trimmed;
    }

    // 2. 提取并解析微博视频 (兼容 Review weibo_video_link_page 算法)
    final weiboObjectId = await _extractOrResolveWeiboObjectId(trimmed);
    if (weiboObjectId != null && weiboObjectId.isNotEmpty) {
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
            headers: {
              'Accept': 'application/json, text/plain, */*',
              'Referer': 'https://h5.video.weibo.com/show/$weiboObjectId',
              'Origin': 'https://h5.video.weibo.com',
              'PAGE-REFERER': '/show/$weiboObjectId',
              'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
            },
          ),
        );
        final response = await dio.post<dynamic>(
          'https://h5.video.weibo.com/api/component',
          queryParameters: {'page': '/show/$weiboObjectId'},
          data:
              'data=${jsonEncode({
                'Component_Play_Playinfo': {'oid': weiboObjectId},
              })}',
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );

        dynamic payload = response.data;
        if (payload is String) {
          try {
            payload = jsonDecode(payload);
          } catch (_) {}
        }

        if (payload is Map) {
          final data = payload['data'] is Map
              ? payload['data'] as Map
              : payload;
          final playInfo = data['Component_Play_Playinfo'] is Map
              ? data['Component_Play_Playinfo'] as Map
              : payload['Component_Play_Playinfo'] is Map
              ? payload['Component_Play_Playinfo'] as Map
              : null;

          if (playInfo != null) {
            final rawUrls = playInfo['urls'];
            if (rawUrls is Map) {
              for (final prefix in ['1080', '720', 'hd', 'ld']) {
                for (final entry in rawUrls.entries) {
                  final k = entry.key.toString().toLowerCase();
                  if (k.contains(prefix)) {
                    final stream = _normalizeStreamUrl(entry.value);
                    if (stream.isNotEmpty) return stream;
                  }
                }
              }
              for (final entry in rawUrls.entries) {
                final stream = _normalizeStreamUrl(entry.value);
                if (stream.isNotEmpty) return stream;
              }
            } else if (rawUrls is List) {
              for (final item in rawUrls) {
                if (item is Map) {
                  final stream = _normalizeStreamUrl(
                    item['url'] ?? item['play_url'] ?? item['play_info'],
                  );
                  if (stream.isNotEmpty) return stream;
                }
              }
            }

            final streamUrl = _normalizeStreamUrl(
              playInfo['stream_url'] ?? playInfo['stream_url_hd'],
            );
            if (streamUrl.isNotEmpty) return streamUrl;
          }
        }
      } catch (_) {}
    }

    return trimmed;
  }

  static String _normalizeStreamUrl(dynamic val) {
    if (val == null) return '';
    final s = val is Map
        ? (val['url'] ?? val['src'] ?? '').toString()
        : val.toString();
    if (s.isEmpty) return '';
    final normalized = s.startsWith('//') ? 'https:$s' : s;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return '';
    }
    return normalized;
  }

  static String _extractStreamUrl(dynamic payload) {
    const urlKeys = [
      'url',
      'videoUrl',
      'video_url',
      'videoSrc',
      'video_src',
      'finalUrl',
      'final_url',
    ];
    const nestedKeys = [
      'data',
      'result',
      'payload',
      'urlList',
      'url_list',
      'urls',
    ];
    final pending = <dynamic>[payload];
    final visited = <Object>{};
    var cursor = 0;

    while (cursor < pending.length) {
      final value = pending[cursor++];
      final direct = _normalizeStreamUrl(value);
      if (direct.isNotEmpty) return direct;
      if (value is List) {
        pending.addAll(value);
      } else if (value is Map) {
        if (!visited.add(value)) continue;
        for (final key in urlKeys) {
          if (value.containsKey(key)) pending.add(value[key]);
        }
        for (final key in nestedKeys) {
          if (value.containsKey(key)) {
            final nested = value[key];
            pending.add(nested);
            if (key == 'urls' && nested is Map) {
              pending.addAll(nested.values);
            }
          }
        }
      }
    }
    return '';
  }

  static Future<String?> _extractOrResolveWeiboObjectId(String url) async {
    // 1. Direct object id (1034:xxx)
    final reg1034 = RegExp(r'1034(?::|%3A)\d+');
    final m1 = reg1034.firstMatch(url);
    if (m1 != null) {
      return m1.group(0)!.replaceAll('%3A', ':');
    }

    // 2. fid or object_id query parameter
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final fid =
          uri.queryParameters['fid'] ??
          uri.queryParameters['object_id'] ??
          uri.queryParameters['oid'];
      if (fid != null && fid.isNotEmpty) {
        return fid.startsWith('1034:') ? fid : '1034:$fid';
      }
    }

    // 3. /show/{id} or /tv/show/{id}
    final tvMatch = RegExp(r'/show/(1034:\d+|\d+)').firstMatch(url);
    if (tvMatch != null) {
      final id = tvMatch.group(1)!;
      return id.startsWith('1034:') ? id : '1034:$id';
    }

    // 4. Weibo status link (e.g. weibo.com/12345/Abcd or m.weibo.cn/status/Abcd)
    final statusMatch = RegExp(
      r'weibo\.(?:com|cn)/(?:\d+|status|detail)/([A-Za-z0-9]+)',
    ).firstMatch(url);
    if (statusMatch != null) {
      final statusId = statusMatch.group(1)!;
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
            },
          ),
        );
        final res = await dio.get<dynamic>(
          'https://m.weibo.cn/statuses/show?id=$statusId',
        );
        if (res.data is Map) {
          final pageInfo = res.data['data']?['page_info'];
          if (pageInfo is Map) {
            final oid = (pageInfo['object_id'] ?? '').toString();
            if (oid.isNotEmpty) {
              return oid.startsWith('1034:') ? oid : '1034:$oid';
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  void _resetControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted && (_controller?.value.isPlaying ?? false)) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedbackUtil.light();
    if (c.value.isPlaying) {
      c.pause();
      setState(() => _showControls = true);
    } else {
      c.play();
      _resetControlsTimer();
    }
    setState(() {});
  }

  void _toggleOrientation() {
    HapticFeedbackUtil.light();
    final toLandscape = !_isLandscape;
    setState(() => _isLandscape = toLandscape);
    if (toLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  void _seekBy(int seconds) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedbackUtil.light();
    final current = c.value.position;
    final total = c.value.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > total ? total : target);
    c.seekTo(clamped);

    _showHud(
      _VideoHudType.doubleTapSeek,
      seekDiff: seconds,
      targetPosition: clamped,
    );
  }

  void _showHud(
    _VideoHudType type, {
    int seekDiff = 0,
    Duration targetPosition = Duration.zero,
  }) {
    _hudDismissTimer?.cancel();
    setState(() {
      _hudType = type;
      _hudSeekDiff = seekDiff;
      _targetSeekPosition = targetPosition;
    });
    _hudDismissTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hudType = _VideoHudType.none);
    });
  }

  void _startFastForward() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedbackUtil.medium();
    c.setPlaybackSpeed(2.0);
    _showHud(_VideoHudType.fastForward);
  }

  void _stopFastForward() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    c.setPlaybackSpeed(_playbackSpeed);
    if (mounted) setState(() => _hudType = _VideoHudType.none);
  }

  void _showSpeedPicker() {
    HapticFeedbackUtil.light();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '播放倍速',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: _availableSpeeds.map((speed) {
                  final isSelected = _playbackSpeed == speed;
                  return ChoiceChip(
                    label: Text('${speed}x'),
                    selected: isSelected,
                    selectedColor: const Color(0xFF2E7D32),
                    backgroundColor: Colors.white12,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      HapticFeedbackUtil.selection();
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      _controller?.setPlaybackSpeed(speed);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final isPlaying = c?.value.isPlaying ?? false;
    final position = c?.value.position ?? Duration.zero;
    final duration = c?.value.duration ?? Duration.zero;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 视频渲染核心与手势捕获
          if (_isInitialized && c != null)
            GestureDetector(
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                final width = MediaQuery.of(context).size.width;
                final dx = details.localPosition.dx;
                if (dx < width * 0.35) {
                  _seekBy(-10);
                } else if (dx > width * 0.65) {
                  _seekBy(10);
                } else {
                  _togglePlayPause();
                }
              },
              onLongPressStart: (_) => _startFastForward(),
              onLongPressEnd: (_) => _stopFastForward(),
              onVerticalDragStart: (details) {
                _panStartPos = details.localPosition;
                final width = MediaQuery.of(context).size.width;
                if (_panStartPos.dx < width * 0.5) {
                  _dragMode = _VideoDragMode.brightness;
                } else {
                  _dragMode = _VideoDragMode.volume;
                }
              },
              onVerticalDragUpdate: (details) {
                final dy = details.localPosition.dy - _panStartPos.dy;
                final delta = -dy / 200.0;
                if (_dragMode == _VideoDragMode.brightness) {
                  final b = (_brightnessLevel + delta).clamp(0.1, 1.0);
                  setState(() => _brightnessLevel = b);
                  _showHud(_VideoHudType.brightness);
                } else if (_dragMode == _VideoDragMode.volume) {
                  final v = (_volumeLevel + delta).clamp(0.0, 1.0);
                  setState(() => _volumeLevel = v);
                  _controller?.setVolume(v);
                  _showHud(_VideoHudType.volume);
                }
              },
              onVerticalDragEnd: (_) {
                _dragMode = _VideoDragMode.none;
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio > 0
                      ? c.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(c),
                ),
              ),
            )
          else if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage.isNotEmpty ? _errorMessage : '视频加载失败',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _initAndPlay,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试加载'),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),

          // 2. 模拟亮度遮罩
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(
                alpha: (1.0 - _brightnessLevel) * 0.75,
              ),
            ),
          ),

          // 3. 手势与状态 HUD
          Center(child: _buildHud()),

          // 4. 浮动控制层 (Controls Overlay)
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Column(
                children: [
                  // 顶部 AppBar
                  _buildTopBar(),
                  const Spacer(),
                  // 底部播放控制条
                  _buildBottomBar(position, duration, isPlaying),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title?.trim().isNotEmpty == true
                        ? widget.title!
                        : '视频播放',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.authorName?.trim().isNotEmpty == true)
                    Text(
                      widget.authorName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: _isSavingVideo
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: '保存视频',
              onPressed: _isSavingVideo ? null : _saveVideo,
            ),
            IconButton(
              icon: const Icon(Icons.speed_rounded, color: Colors.white),
              tooltip: '播放倍速',
              onPressed: _showSpeedPicker,
            ),
            IconButton(
              icon: Icon(
                _isLandscape
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
              tooltip: '全屏旋转',
              onPressed: _toggleOrientation,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVideo() async {
    if (_isSavingVideo) return;
    final resolvedUrl = _playableUrl.isNotEmpty ? _playableUrl : widget.videoUrl;
    if (resolvedUrl.isEmpty) {
      AppToast.show(context, '无法获取视频地址');
      return;
    }
    setState(() => _isSavingVideo = true);
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    try {
      final response = await dio.get<List<int>>(
        resolvedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: widget.api.imageHeadersFor(),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) throw Exception('下载数据为空');

      final prefs = await SharedPreferences.getInstance();
      final pathType = prefs.getInt('greennote.video_save_path_type') ?? 0;
      final subDir = StoragePathResolver.resolveSubDir(
        pathType: pathType,
        myNickname: widget.api.currentUserNickname,
        authorName: widget.authorName,
        isVideo: true,
      );

      final savedPath = await const MethodChannel('com.green.note/media').invokeMethod<String>(
        'saveMediaToGallery',
        {
          'bytes': Uint8List.fromList(bytes),
          'fileName': 'gn_${DateTime.now().microsecondsSinceEpoch}.mp4',
          'relativeSubDir': subDir,
          'isVideo': true,
          'mimeType': 'video/mp4',
        },
      );
      HapticFeedbackUtil.medium();
      if (mounted) {
        AppToast.show(context, '视频已保存至相册：${savedPath ?? "Movies/$subDir"}');
      }
    } catch (_) {
      if (mounted) AppToast.show(context, '保存视频失败，请重试');
    } finally {
      dio.close();
      if (mounted) setState(() => _isSavingVideo = false);
    }
  }

  Widget _buildBottomBar(Duration position, Duration duration, bool isPlaying) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度滑块
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.5,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: const Color(0xFF2E7D32),
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: duration.inMilliseconds > 0
                    ? position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble()
                    : 0.0,
                max: duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0,
                onChanged: (val) {
                  _resetControlsTimer();
                  _controller?.seekTo(Duration(milliseconds: val.toInt()));
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _togglePlayPause,
                ),
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showSpeedPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isLandscape
                        ? Icons.screen_lock_rotation_rounded
                        : Icons.screen_rotation_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _toggleOrientation,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    switch (_hudType) {
      case _VideoHudType.fastForward:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                '2.0X 快进中',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      case _VideoHudType.doubleTapSeek:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hudSeekDiff > 0
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '${_hudSeekDiff > 0 ? '+' : ''}${_hudSeekDiff}s (${_formatDuration(_targetSeekPosition)})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      case _VideoHudType.brightness:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.brightness_6_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  value: _brightnessLevel,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        );
      case _VideoHudType.volume:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _volumeLevel > 0
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  value: _volumeLevel,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        );
      case _VideoHudType.none:
        return const SizedBox.shrink();
    }
  }
}
