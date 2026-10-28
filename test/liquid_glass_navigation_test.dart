import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/utils/draggable_indicator_physics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:greennote/core/design_system/components/review_navigation_bar.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/theme/app_theme.dart';

void main() {
  test(
    'zero pinch keeps a fast moving indicator free of jelly deformation',
    () {
      final flat = DraggableIndicatorPhysics.buildJellyTransform(
        velocity: const Offset(800, 0),
        maxDistortion: 0,
        velocityScale: 10,
      );
      expect(flat.storage[0], 1);
      expect(flat.storage[5], 1);
      final jelly = DraggableIndicatorPhysics.buildJellyTransform(
        velocity: const Offset(800, 0),
        maxDistortion: 0.7,
        velocityScale: 10,
      );
      expect(jelly.storage[0], lessThan(1));
      expect(jelly.storage[5], greaterThan(1));
    },
  );

  testWidgets(
    'glass rail renders the reference proportions and dark material',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container
            .read(appSettingsProvider.notifier)
            .setFloatingNavBar(true);
        await container
            .read(appSettingsProvider.notifier)
            .setLiquidGlassNavBar(true);
      });
      var selected = 0;
      final selections = <int>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(colorIndex: 3),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                extendBody: true,
                body: const ColoredBox(color: Color(0xFF1C1C1C)),
                bottomNavigationBar: ReviewNavigationBar(
                  selectedIndex: selected,
                  hasBottomInset: false,
                  onSelected: (index) {
                    selections.add(index);
                    if (index != 2) setState(() => selected = index);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final track = find.byType(AdaptiveGlass);
      expect(
        tester.getRect(track),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(20, 723, 320, 56),
          epsilon: 0.02,
        ),
      );
      final glassBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(glassBar.indicatorSettings?.rimLight, 0);
      expect(glassBar.indicatorSettings?.rimShade, 0);
      expect(
        find.byKey(const ValueKey('liquid-glass-light-rim')),
        findsNothing,
      );
      expect(glassBar.enableBlend, isTrue);
      expect(glassBar.maskingQuality, MaskingQuality.high);
      expect(glassBar.showIndicator, isTrue);
      expect(glassBar.indicatorPinchStrength, 0);
      expect(glassBar.indicatorExpansion, EdgeInsets.zero);
      final material = tester.widget<LightweightLiquidGlass>(
        find.descendant(
          of: track,
          matching: find.byType(LightweightLiquidGlass),
        ),
      );
      final trackGlass = tester.widget<AdaptiveGlass>(track);
      // Check the renderer's effective settings, not just the outer theme.
      expect(material.settings, isNotNull);
      final applied = material.settings!;
      expect(trackGlass.quality, GlassQuality.premium);
      expect(applied.glassColor, const Color(0x66000000));
      expect(applied.ambientStrength, 0);
      expect(applied.bodyMode, GlassBodyMode.clear);
      expect(applied.blur, 1.5);
      expect(applied.refractiveIndex, 1.16);
      expect(applied.chromaticAberration, greaterThan(0));
      final publish = find
          .ancestor(
            of: find.byIcon(Icons.add_rounded),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getSize(publish), const Size(50, 36));
      expect(
        tester.getCenter(publish),
        offsetMoreOrLessEquals(const Offset(180, 751), epsilon: 0.02),
      );
      expect(find.text('发布'), findsNothing);

      final barState = tester.state(find.byType(GlassTabBar));
      expect(
        tester
            .widgetList<AnimatedGlassIndicator>(
              find.byType(AnimatedGlassIndicator),
            )
            .every((indicator) => indicator.thickness == 0),
        isTrue,
      );
      await tester.tapAt(const Offset(244, 751));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widgetList<AnimatedGlassIndicator>(
              find.byType(AnimatedGlassIndicator),
            )
            .every((indicator) => indicator.thickness == 0),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(tester.state(find.byType(GlassTabBar)), same(barState));
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        3,
      );
      expect(selections, isNot(contains(2)));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(selections, [3, 2]);
      expect(selected, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('light glass rail uses a white shell and theme colors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container
          .read(appSettingsProvider.notifier)
          .setFloatingNavBar(true);
      await container
          .read(appSettingsProvider.notifier)
          .setLiquidGlassNavBar(true);
    });
    const colorIndex = 3;
    final colorScheme = AppTheme.lightTheme(colorIndex: colorIndex).colorScheme;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme(colorIndex: colorIndex),
          home: Scaffold(
            extendBody: true,
            body: const ColoredBox(color: Colors.white),
            bottomNavigationBar: ReviewNavigationBar(
              selectedIndex: 0,
              hasBottomInset: false,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final glassBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(glassBar.settings?.glassColor, const Color(0xF0FFFFFF));
    expect(glassBar.settings?.rimLight, 1);
    expect(glassBar.indicatorSettings?.glassColor, const Color(0x18000000));
    expect(glassBar.indicatorSettings?.bodyMode, GlassBodyMode.clear);
    expect(glassBar.indicatorSettings?.rimShade, 0.12);
    expect(glassBar.indicatorSettings?.rimLight, 0.35);
    expect(glassBar.indicatorSettings?.refractiveIndex, 1.18);
    expect(glassBar.indicatorSettings?.chromaticAberration, 0.025);
    expect(glassBar.indicatorColor, const Color(0x26000000));
    expect(glassBar.selectedIconColor, colorScheme.primary);
    expect(glassBar.selectedLabelColor, colorScheme.primary);
    expect(glassBar.unselectedIconColor, colorScheme.onSurfaceVariant);
    expect(glassBar.unselectedLabelColor, colorScheme.onSurfaceVariant);
    expect(
      find.byKey(const ValueKey('liquid-glass-light-rim')),
      findsOneWidget,
    );
    final customSettings = ReviewNavigationBar.liquidGlassSettingsFor(
      tester.element(find.byType(ReviewNavigationBar)),
      const LiquidGlassSettings(
        visibility: 0.5,
        glassColor: Color(0x66000000),
        thickness: 32,
      ),
    );
    expect(customSettings.glassColor, const Color(0xF0FFFFFF));
    expect(customSettings.rimLight, 1);
    expect(customSettings.visibility, 0.5);
    expect(customSettings.thickness, 32);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuous deliberate drag from home to profile selects profile without being truncated to digital',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container
            .read(appSettingsProvider.notifier)
            .setFloatingNavBar(true);
        await container
            .read(appSettingsProvider.notifier)
            .setLiquidGlassNavBar(true);
      });
      var selected = 0;
      final selections = <int>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(colorIndex: 3),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                extendBody: true,
                body: const ColoredBox(color: Color(0xFF1C1C1C)),
                bottomNavigationBar: ReviewNavigationBar(
                  selectedIndex: selected,
                  hasBottomInset: false,
                  onSelected: (index) {
                    selections.add(index);
                    if (index != 2) setState(() => selected = index);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start drag at Tab 0 (首页, center x ≈ 52)
      final gesture = await tester.startGesture(const Offset(52, 751));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<GlassTabBar>(find.byType(GlassTabBar))
            .indicatorPinchStrength,
        0,
      );
      await tester.pump(const Duration(milliseconds: 100));
      var glassBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(glassBar.showIndicator, isTrue);
      expect(glassBar.indicatorPinchStrength, 0.7);
      expect(
        glassBar.indicatorExpansion,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );
      expect(find.byType(AnimatedGlassIndicator), findsWidgets);
      expect(selections, isEmpty);

      await gesture.moveTo(const Offset(100, 751));
      await tester.pump(const Duration(milliseconds: 100));
      final firstPosition = tester
          .widgetList<AnimatedGlassIndicator>(
            find.byType(AnimatedGlassIndicator),
          )
          .first
          .alignment
          .resolve(TextDirection.ltr)
          .x;
      await gesture.moveTo(const Offset(108, 751));
      await tester.pump(const Duration(milliseconds: 100));
      final nextPosition = tester
          .widgetList<AnimatedGlassIndicator>(
            find.byType(AnimatedGlassIndicator),
          )
          .first
          .alignment
          .resolve(TextDirection.ltr)
          .x;
      // Moving inside one slot must move the lens before a page is selected.
      expect(nextPosition, greaterThan(firstPosition));
      expect(selected, 0);

      // Drag deliberately across the entire bar to Tab 4 (我的, center x ≈ 308)
      await gesture.moveTo(const Offset(308, 751));
      await tester.pump(const Duration(milliseconds: 150));
      glassBar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(glassBar.selectedIndex, 0);
      await gesture.up();
      await tester.pumpAndSettle();

      // Must land on Tab 4 (我的), NOT truncated to Tab 1 (数码)
      expect(selected, 4);
      expect(selections.last, 4);
      expect(
        tester
            .widget<GlassTabBar>(find.byType(GlassTabBar))
            .indicatorPinchStrength,
        0,
      );
      expect(
        tester
            .widgetList<AnimatedGlassIndicator>(
              find.byType(AnimatedGlassIndicator),
            )
            .every((indicator) => indicator.thickness < 0.01),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
