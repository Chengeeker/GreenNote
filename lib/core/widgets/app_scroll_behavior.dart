import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppScrollBehavior extends MaterialScrollBehavior
    with _ScrollFrameRateBehavior {
  const AppScrollBehavior();
}

// EasyRefresh replaces the inherited behavior, so it needs the same scroll hook.
class AppRefreshScrollBehavior extends ERScrollBehavior
    with _ScrollFrameRateBehavior {
  const AppRefreshScrollBehavior(super.physics);
}

mixin _ScrollFrameRateBehavior on ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final viewport = super.buildOverscrollIndicator(context, child, details);
    if (getPlatform(context) != TargetPlatform.android ||
        axisDirectionToAxis(details.direction) != Axis.vertical) {
      return viewport;
    }
    return _ScrollFrameRate(child: viewport);
  }
}

class _ScrollFrameRate extends StatefulWidget {
  const _ScrollFrameRate({required this.child});
  final Widget child;

  @override
  State<_ScrollFrameRate> createState() => _ScrollFrameRateState();
}

class _ScrollFrameRateState extends State<_ScrollFrameRate>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.green.note/ui');
  static final _scrolling = <_ScrollFrameRateState>{};
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _setScrolling(bool active) {
    final wasActive = _scrolling.isNotEmpty;
    if (active) {
      _scrolling.add(this);
    } else {
      _scrolling.remove(this);
    }
    if (wasActive != _scrolling.isNotEmpty) {
      unawaited(_notifyPlatform(_scrolling.isNotEmpty));
    }
  }

  static Future<void> _notifyPlatform(bool active) async {
    try {
      await _channel.invokeMethod<void>('setScrolling', active);
    } on MissingPluginException {
      // Hosts without the native hint still use normal scroll scheduling.
    } on PlatformException {
      // A rejected frame-rate hint must not interrupt the scroll.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
    if (!_enabled) _setScrolling(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _setScrolling(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setScrolling(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 || !_enabled) return false;
          final lifecycle = WidgetsBinding.instance.lifecycleState;
          if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
            return false;
          }
          // ScrollEnd covers the ballistic tail; finger-up/UserScroll.idle does not.
          if (notification is ScrollEndNotification) {
            _setScrolling(false);
          } else if (notification is ScrollStartNotification ||
              notification is ScrollUpdateNotification) {
            _setScrolling(true);
          }
          return false;
        },
        child: widget.child,
      );
}
