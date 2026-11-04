import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/core/utils/haptic_feedback_util.dart';

void main() {
  for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
    for (final haptics in [true, false]) {
      testWidgets(
        'no tap or hold ripple in ${theme.brightness}, haptics $haptics',
        (tester) async {
          final vibrations = <Object?>[];
          HapticFeedbackUtil.resetForTesting();
          HapticFeedbackUtil.isEnabled = haptics;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'HapticFeedback.vibrate') {
                  vibrations.add(call.arguments);
                }
                return null;
              });
          addTearDown(() {
            HapticFeedbackUtil.isEnabled = true;
            HapticFeedbackUtil.resetForTesting();
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null);
          });
          var taps = 0;
          var holds = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: InkWell(
                    enableFeedback: false,
                    onTap: () {
                      taps++;
                      HapticFeedbackUtil.light();
                    },
                    onLongPress: () {
                      holds++;
                    },
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ),
              ),
            ),
          );
          final ink = find.byType(InkWell).first;
          final context = tester.element(ink);
          await tester.tap(ink);
          await tester.pump();
          expect(taps, 1);
          expect(vibrations, hasLength(haptics ? 1 : 0));
          expect(theme.splashColor, Colors.transparent);
          expect(theme.highlightColor, Colors.transparent);
          await tester.longPress(ink);
          await tester.pumpAndSettle();
          expect(holds, 1);
          expect(taps, 1);
          if (!haptics) expect(vibrations, isEmpty);
          final splash = Theme.of(context).splashFactory.create(
            controller: Material.of(context),
            referenceBox: tester.renderObject<RenderBox>(ink),
            position: Offset.zero,
            color: Colors.blue,
            textDirection: TextDirection.ltr,
          );
          expect(splash, isA<NoSplash>());
          Material.of(context).addInkFeature(splash);
          splash.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
    test(
      'toggle touch halos are transparent and focus can keep defaults in ${theme.brightness}',
      () {
        for (final overlay in [
          theme.checkboxTheme.overlayColor!,
          theme.radioTheme.overlayColor!,
          theme.switchTheme.overlayColor!,
          AppTheme.noTouchOverlay,
        ]) {
          expect(overlay.resolve({WidgetState.pressed}), Colors.transparent);
          expect(
            overlay.resolve({WidgetState.selected, WidgetState.pressed}),
            Colors.transparent,
          );
          expect(overlay.resolve({WidgetState.dragged}), Colors.transparent);
          expect(overlay.resolve({WidgetState.focused}), isNull);
          expect(overlay.resolve({WidgetState.hovered}), isNull);
        }
      },
    );
  }
}
