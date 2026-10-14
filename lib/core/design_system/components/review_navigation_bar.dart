import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../settings/app_settings.dart';

import 'dart:math' as math;

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
