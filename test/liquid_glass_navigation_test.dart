import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:greennote/core/design_system/components/review_navigation_bar.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/theme/app_theme.dart';

void main() {
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
      expect(applied.blur, lessThanOrEqualTo(2));
      expect(applied.refractiveIndex, greaterThanOrEqualTo(1.16));
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

      final gesture = await tester.startGesture(const Offset(118, 751));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final lenses = tester.widgetList<AnimatedGlassIndicator>(
        find.byType(AnimatedGlassIndicator),
      );
      expect(lenses.any((lens) => lens.thickness > 0.5), isTrue);
      // The expanded lens is 64dp tall: its radius must reach half that height.
      expect(lenses.every((lens) => lens.borderRadius >= 32), isTrue);
      expect(lenses.any((lens) => lens.innerBlur > applied.blur), isTrue);
      await gesture.moveBy(const Offset(125, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(selections, isNot(contains(2)));
      expect(tester.takeException(), isNull);
    },
  );
}
