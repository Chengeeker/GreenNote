import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        VelocityTracker,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../settings/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptic_feedback_util.dart';

/// Material 3 navigation shared by the app shell.
class ReviewNavigationBar extends ConsumerStatefulWidget {
  const ReviewNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.hasBottomInset,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;

  static LiquidGlassSettings liquidGlassSettingsFor(
    BuildContext context, [
    LiquidGlassSettings? settings,
  ]) {
    final base = settings ?? liquidGlassSettings;
    return Theme.of(context).brightness == Brightness.light
        ? base.copyWith(glassColor: const Color(0xF0FFFFFF), rimLight: 1)
        : base;
  }

  static const liquidGlassSettings = LiquidGlassSettings(
    glassColor: Color(0x66000000),
    bodyMode: GlassBodyMode.clear,
    thickness: 10,
    blur: 1.5,
    lightIntensity: 0.25,
    ambientStrength: 0,
    refractiveIndex: 1.16,
    chromaticAberration: 0.008,
    saturation: 1,
    shadowElevation: 0,
  );
  static const liquidGlassQuality = GlassQuality.premium;

  static const _destinations = <_NavigationDestination>[
    _NavigationDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: '首页',
    ),
    _NavigationDestination(
      icon: Icons.smartphone_outlined,
      selectedIcon: Icons.smartphone_rounded,
      label: '数码',
    ),
    _NavigationDestination(
      icon: Icons.add_rounded,
      selectedIcon: Icons.add_rounded,
      label: '发布',
    ),
    _NavigationDestination(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: '发现',
    ),
    _NavigationDestination(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: '我的',
    ),
  ];

  @override
  ConsumerState<ReviewNavigationBar> createState() =>
      _ReviewNavigationBarState();
}

class _ReviewNavigationBarState extends ConsumerState<ReviewNavigationBar> {
  static const _longPressThreshold = Duration(milliseconds: 220);
  static const _flickVelocityThreshold = 800.0;

  final GlobalKey _barKey = GlobalKey();
  Timer? _longPressTimer;
  Timer? _glassResetTimer;
  int? _activePointer;
  VelocityTracker? _velocityTracker;
  Duration? _pointerDownAt;
  Offset? _pointerDownPosition;
  int _selectedIndexAtPointerDown = 0;
  int? _pendingIndex;
  bool _movedBeyondSlop = false;
  bool _draggedHorizontally = false;
  bool _cancelled = false;
  bool _isJellyDragging = false;
  int _gestureId = 0;

  void _scheduleGlassReset(int gestureId) {
    _glassResetTimer?.cancel();
    _glassResetTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || gestureId != _gestureId) return;
      setState(() => _isJellyDragging = false);
    });
  }

  static int _nextTab(int current, bool forward) {
    // Valid business tab indices: 0 (首页), 1 (数码), 3 (发现), 4 (我的)
    const validTabs = [0, 1, 3, 4];
    final currentPos = validTabs.indexOf(current);
    if (currentPos == -1) {
      return forward ? 1 : 0;
    }
    if (forward) {
      final nextPos = (currentPos + 1).clamp(0, validTabs.length - 1);
      return validTabs[nextPos];
    } else {
      final prevPos = (currentPos - 1).clamp(0, validTabs.length - 1);
      return validTabs[prevPos];
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _longPressTimer?.cancel();
    _glassResetTimer?.cancel();
    if (_isJellyDragging) {
      setState(() {
        _isJellyDragging = false;
        _pendingIndex = null;
      });
    }
    _activePointer = event.pointer;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDownAt = event.timeStamp;
    _pointerDownPosition = event.position;
    _selectedIndexAtPointerDown = widget.selectedIndex;
    _pendingIndex = null;
    _movedBeyondSlop = false;
    _draggedHorizontally = false;
    _cancelled = false;
    _gestureId++;
    _longPressTimer = Timer(_longPressThreshold, () {
      if (!mounted ||
          _activePointer != event.pointer ||
          _movedBeyondSlop ||
          _cancelled) {
        return;
      }
      setState(() {
        _isJellyDragging = true;
      });
      HapticFeedbackUtil.light();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final origin = _pointerDownPosition;
    if (origin == null) return;
    final delta = event.position - origin;
    if (delta.distance > kTouchSlop) {
      _movedBeyondSlop = true;
      _longPressTimer?.cancel();
      if (delta.dx.abs() > delta.dy.abs()) {
        _draggedHorizontally = true;
        if (!_isJellyDragging) {
          setState(() {
            _isJellyDragging = true;
          });
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0.0;
    _finishPointer(
      event.pointer,
      event.timeStamp,
      event.position,
      horizontalVelocity: velocity,
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishPointer(
      event.pointer,
      event.timeStamp,
      event.position,
      cancelled: true,
    );
  }

  void _finishPointer(
    int pointer,
    Duration releasedAt,
    Offset releasePosition, {
    bool cancelled = false,
    double horizontalVelocity = 0.0,
  }) {
    if (pointer != _activePointer) return;
    _longPressTimer?.cancel();
    _cancelled |= cancelled;
    final gestureId = _gestureId;

    scheduleMicrotask(() {
      if (!mounted || gestureId != _gestureId) return;

      final target = _pendingIndex;
      final wasLongPress =
          _pointerDownAt != null &&
          releasedAt - _pointerDownAt! >= _longPressThreshold;
      final wasDrag = _draggedHorizontally;
      final movedVertically = _movedBeyondSlop && !wasDrag;
      final wasCancelled = _cancelled;
      final startingIndex = _selectedIndexAtPointerDown;
      final wasJellyDragging = _isJellyDragging;

      _activePointer = null;
      _velocityTracker = null;
      _pointerDownAt = null;
      _pointerDownPosition = null;
      _pendingIndex = null;
      _movedBeyondSlop = false;
      _draggedHorizontally = false;
      _cancelled = false;
      if (wasJellyDragging) _scheduleGlassReset(gestureId);

      if (wasCancelled || movedVertically || target == null) return;
      if (target == 2) return;

      int? releaseSlot;
      final renderBox =
          _barKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final localPos = renderBox.globalToLocal(releasePosition);
        final slotFraction = localPos.dx / renderBox.size.width;
        releaseSlot = (slotFraction * 5).floor().clamp(0, 4);
      }

      final isFastFlick =
          wasDrag && horizontalVelocity.abs() >= _flickVelocityThreshold;
      final reachedTargetSlot = releaseSlot != null && releaseSlot == target;

      int selectedTarget = target;
      if (isFastFlick && !reachedTargetSlot) {
        if (horizontalVelocity > 0 || target > startingIndex) {
          selectedTarget = _nextTab(startingIndex, true);
        } else if (horizontalVelocity < 0 || target < startingIndex) {
          selectedTarget = _nextTab(startingIndex, false);
        }
      }

      if ((wasDrag || wasLongPress) && selectedTarget == startingIndex) return;

      _select(selectedTarget);
    });
  }

  void _handleTabSelected(int index) {
    if (index == 2) return;
    if (_activePointer != null) {
      _pendingIndex = index;
    } else {
      _select(index);
    }
  }

  void _select(int index) {
    HapticFeedbackUtil.light();
    widget.onSelected(index);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _glassResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useFloating = ref.watch(
      appSettingsProvider.select((state) => state.useFloatingNavBar),
    );
    final useLiquidGlass = ref.watch(
      appSettingsProvider.select((state) => state.useLiquidGlassNavBar),
    );
    final colorScheme = Theme.of(context).colorScheme;

    if (!useFloating) {
      return NavigationBar(
        selectedIndex: widget.selectedIndex,
        elevation: 0,
        height: 68,
        onDestinationSelected: widget.onSelected,
        destinations: [
          for (final destination in ReviewNavigationBar._destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      );
    }

    if (useLiquidGlass) {
      return _buildLiquidGlassBar(context);
    }

    return SafeArea(
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.hasBottomInset ? 6 : 14),
          child: Container(
            // Five business slots retain Review's per-slot width where space permits.
            width: math.min(440, MediaQuery.sizeOf(context).width - 32),
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.12,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedAlign(
                  alignment: Alignment(-1 + widget.selectedIndex * 0.5, 0),
                  duration: Duration(
                    milliseconds: MediaQuery.disableAnimationsOf(context)
                        ? 0
                        : 220,
                  ),
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                    widthFactor: 1 / ReviewNavigationBar._destinations.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(
                    ReviewNavigationBar._destinations.length,
                    (index) => Expanded(
                      child: _buildFloatingItem(context, index, colorScheme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidGlassBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLightMode = theme.brightness == Brightness.light;
    final indicatorColor = isLightMode
        ? const Color(0x26000000)
        : const Color(0x66000000);
    const interactionGlowColor = Color(0x20FFFFFF);
    final glassSettings = ReviewNavigationBar.liquidGlassSettingsFor(
      context,
      ReviewNavigationBar.liquidGlassSettings.copyWith(
        shadowElevation: isLightMode ? 0.55 : 0,
      ),
    );
    final selectedContentColor = isLightMode
        ? colorScheme.primary
        : Colors.white;
    final unselectedContentColor = isLightMode
        ? colorScheme.onSurfaceVariant
        : Colors.white;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 21),
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          key: _barKey,
          width: math.min(440, MediaQuery.sizeOf(context).width - 40),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: ExcludeSemantics(
                  child: GlassTabBar.bottom(
                    selectedIndex: widget.selectedIndex,
                    onTabSelected: _handleTabSelected,
                    tabs: [
                      for (
                        var index = 0;
                        index < ReviewNavigationBar._destinations.length;
                        index++
                      )
                        GlassTab(
                          icon: index == 2
                              ? const SizedBox.shrink()
                              : _LiquidGlassTabIcon(index: index),
                          activeIcon: index == 2
                              ? const SizedBox.shrink()
                              : _LiquidGlassTabIcon(index: index),
                          label: index == 2
                              ? ''
                              : ReviewNavigationBar._destinations[index].label,
                          semanticLabel:
                              ReviewNavigationBar._destinations[index].label,
                        ),
                    ],
                    iconSize: 24,
                    labelFontSize: 10.5,
                    textStyle: const TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                    ),
                    iconLabelSpacing: 2,
                    horizontalPadding: 0,
                    barHeight: 56,
                    // Keep full end arcs when the pressed lens expands.
                    barBorderRadius: 9999,
                    indicatorBorderRadius: 9999,
                    verticalPadding: 0,
                    // GlassTabBar's own preset overrides GlassTheme settings.
                    settings: glassSettings,
                    quality: ReviewNavigationBar.liquidGlassQuality,
                    backgroundQuality: ReviewNavigationBar.liquidGlassQuality,
                    indicatorSettings: LiquidGlassSettings(
                      glassColor: isLightMode
                          ? const Color(0x18000000)
                          : const Color(0x00FFFFFF),
                      bodyMode: isLightMode
                          ? GlassBodyMode.clear
                          : GlassBodyMode.adaptive,
                      refractiveIndex: 1.18,
                      chromaticAberration: 0.025,
                      rimShade: isLightMode ? 0.12 : 0,
                      rimLight: isLightMode ? 0.35 : 0,
                    ),
                    innerBlur: 6,
                    indicatorColor: indicatorColor,
                    interactionGlowColor: interactionGlowColor,
                    indicatorPinchStrength: _isJellyDragging ? 0.7 : 0.0,
                    indicatorExpansion: _isJellyDragging
                        ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          )
                        : EdgeInsets.zero,
                    pressScale: 1.06,
                    selectedIconColor: selectedContentColor,
                    selectedLabelColor: selectedContentColor,
                    unselectedIconColor: unselectedContentColor,
                    unselectedLabelColor: unselectedContentColor,
                  ),
                ),
              ),
              if (isLightMode)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('liquid-glass-light-rim'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(
                          color: const Color(0xF5FFFFFF),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              // The library's extraButton only supports a left or right slot.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      for (
                        var index = 0;
                        index < ReviewNavigationBar._destinations.length;
                        index++
                      )
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected:
                                index != 2 && widget.selectedIndex == index,
                            inMutuallyExclusiveGroup: index != 2,
                            label:
                                ReviewNavigationBar._destinations[index].label,
                            onTap: () => widget.onSelected(index),
                            child: index == 2
                                ? GestureDetector(
                                    key: const ValueKey(
                                      'liquid-glass-publish-action',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    excludeFromSemantics: true,
                                    onTap: () {
                                      HapticFeedbackUtil.light();
                                      widget.onSelected(index);
                                    },
                                    child: Center(
                                      child: Container(
                                        width: 50,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF65C4B9),
                                              Color(0xFF13A99F),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingItem(
    BuildContext context,
    int index,
    ColorScheme colorScheme,
  ) {
    final selected = widget.selectedIndex == index;
    final destination = ReviewNavigationBar._destinations[index];
    final activeContent = colorScheme.onSecondaryContainer;
    final inactiveContent = colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () => widget.onSelected(index),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: selected ? activeContent : inactiveContent,
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: context.adjustWeight(
                      selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    color: selected ? activeContent : inactiveContent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassTabIcon extends StatelessWidget {
  const _LiquidGlassTabIcon({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        painter: _LiquidGlassTabIconPainter(index, theme.color ?? Colors.white),
      ),
    );
  }
}

class _LiquidGlassTabIconPainter extends CustomPainter {
  const _LiquidGlassTabIconPainter(this.index, this.color);

  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()..fillType = PathFillType.evenOdd;
    if (index == 0) {
      path
        ..moveTo(11, 3.5)
        ..quadraticBezierTo(12, 2.9, 13, 3.5)
        ..lineTo(20, 7.8)
        ..quadraticBezierTo(21, 8.4, 21, 9.5)
        ..lineTo(21, 19)
        ..quadraticBezierTo(21, 21, 19, 21)
        ..lineTo(5, 21)
        ..quadraticBezierTo(3, 21, 3, 19)
        ..lineTo(3, 9.5)
        ..quadraticBezierTo(3, 8.4, 4, 7.8)
        ..close()
        ..addRRect(RRect.fromLTRBR(11, 12, 13, 18, const Radius.circular(1)));
    } else if (index == 1) {
      path
        ..addRRect(RRect.fromLTRBR(3.5, 3, 20.5, 21, const Radius.circular(2)))
        ..addRRect(RRect.fromLTRBR(9, 16, 15, 18, const Radius.circular(1)));
    } else if (index == 3) {
      path
        ..addOval(const Rect.fromLTWH(2, 2, 20, 20))
        ..moveTo(9, 9)
        ..lineTo(17, 6)
        ..lineTo(15, 15)
        ..lineTo(6, 18)
        ..close()
        ..addOval(const Rect.fromLTWH(10.8, 10.8, 2.4, 2.4));
    } else {
      path
        ..addOval(const Rect.fromLTWH(7.5, 2, 9, 9))
        ..moveTo(3, 21)
        ..lineTo(3, 17)
        ..quadraticBezierTo(3, 13, 12, 13)
        ..quadraticBezierTo(21, 13, 21, 17)
        ..lineTo(21, 21)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidGlassTabIconPainter oldDelegate) =>
      index != oldDelegate.index || color != oldDelegate.color;
}

class _NavigationDestination {
  const _NavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
