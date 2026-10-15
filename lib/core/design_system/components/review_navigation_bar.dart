import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_theme.dart';
import '../../settings/app_settings.dart';

/// Material 3 navigation shared by the app shell.
class ReviewNavigationBar extends ConsumerWidget {
  const ReviewNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.hasBottomInset,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final useFloating = ref.watch(
      appSettingsProvider.select((state) => state.useFloatingNavBar),
    );
    final useLiquidGlass = ref.watch(
      appSettingsProvider.select((state) => state.useLiquidGlassNavBar),
    );
    final colorScheme = Theme.of(context).colorScheme;

    if (!useFloating) {
      return NavigationBar(
        selectedIndex: selectedIndex,
        elevation: 0,
        height: 68,
        onDestinationSelected: onSelected,
        destinations: [
          for (final destination in _destinations)
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
          padding: EdgeInsets.only(bottom: hasBottomInset ? 6 : 14),
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
            child: Row(
              children: List.generate(
                _destinations.length,
                (index) => Expanded(
                  child: _buildFloatingItem(context, index, colorScheme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidGlassBar(BuildContext context) {
    const accent = Color(0xFF159F97);
    const indicatorColor = Color(0x20FFFFFF);

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 21),
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: math.min(440, MediaQuery.sizeOf(context).width - 40),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: GlassTabBar.bottom(
                  selectedIndex: selectedIndex,
                  onTabSelected: (index) {
                    if (index != 2) onSelected(index);
                  },
                  tabs: [
                    for (var index = 0; index < _destinations.length; index++)
                      GlassTab(
                        icon: index == 2
                            ? const SizedBox.shrink()
                            : _LiquidGlassTabIcon(index: index),
                        activeIcon: index == 2
                            ? const SizedBox.shrink()
                            : _LiquidGlassTabIcon(index: index),
                        label: index == 2 ? '' : _destinations[index].label,
                        semanticLabel: _destinations[index].label,
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
                  settings: liquidGlassSettings,
                  quality: liquidGlassQuality,
                  backgroundQuality: liquidGlassQuality,
                  indicatorSettings: const LiquidGlassSettings(
                    refractiveIndex: 1.18,
                    chromaticAberration: 0.025,
                  ),
                  innerBlur: 6,
                  indicatorColor: indicatorColor,
                  interactionGlowColor: indicatorColor,
                  indicatorPinchStrength: 0.7,
                  pressScale: 1.06,
                  selectedIconColor: accent,
                  selectedLabelColor: accent,
                  unselectedIconColor: Colors.white,
                  unselectedLabelColor: Colors.white,
                ),
              ),
              // The library's extraButton only supports a left or right slot.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      for (var index = 0; index < _destinations.length; index++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: index != 2 && selectedIndex == index,
                            inMutuallyExclusiveGroup: index != 2,
                            label: _destinations[index].label,
                            onTap: () => onSelected(index),
                            child: index == 2
                                ? GestureDetector(
                                    key: const ValueKey(
                                      'liquid-glass-publish-action',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    excludeFromSemantics: true,
                                    onTap: () => onSelected(index),
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
    final selected = selectedIndex == index;
    final destination = _destinations[index];
    final activeBackground = colorScheme.secondaryContainer;
    final activeContent = colorScheme.onSecondaryContainer;
    final inactiveContent = colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () => onSelected(index),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (selected)
              TweenAnimationBuilder<double>(
                key: ValueKey(index),
                tween: Tween<double>(begin: 0, end: 1),
                duration: Duration(
                  milliseconds: MediaQuery.disableAnimationsOf(context)
                      ? 0
                      : 160,
                ),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: activeBackground,
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
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
