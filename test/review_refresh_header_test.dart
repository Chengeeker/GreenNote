import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/widgets/review_refresh_header.dart';

void main() {
  test('overlay header keeps the normal pull threshold', () {
    expect(reviewFrostedAppBarRefreshHeader.triggerOffset, 70);
    expect(reviewFrostedAppBarRefreshHeader.safeArea, isFalse);
    expect(reviewFrostedAppBarRefreshHeader.position, IndicatorPosition.above);
  });

  testWidgets('horizontal gestures do not trigger vertical refresh', (
    tester,
  ) async {
    var refreshCount = 0;
    final refreshCompleter = Completer<void>();
    final horizontalController = ScrollController();
    const staticTargetKey = ValueKey('horizontal-static-target');
    const horizontalListKey = ValueKey('horizontal-scroll-list');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EasyRefresh(
            triggerAxis: Axis.vertical,
            onRefresh: () {
              refreshCount++;
              return refreshCompleter.future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 120,
                  child: protectHorizontalDragFromVerticalRefresh(
                    ColoredBox(
                      key: staticTargetKey,
                      color: Colors.transparent,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                SizedBox(
                  height: 144,
                  child: protectHorizontalDragFromVerticalRefresh(
                    ListView.builder(
                      key: horizontalListKey,
                      controller: horizontalController,
                      scrollDirection: Axis.horizontal,
                      itemCount: 8,
                      itemBuilder: (_, index) => SizedBox(
                        width: 120,
                        child: Center(child: Text('item $index')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(staticTargetKey), const Offset(150, 100));
    await tester.pump();
    expect(refreshCount, 0);

    await tester.drag(find.byKey(horizontalListKey), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(horizontalController.offset, greaterThan(0));

    await tester.drag(find.byKey(staticTargetKey), const Offset(0, 120));
    await tester.pump();
    for (var attempt = 0; attempt < 20 && refreshCount == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(refreshCount, 1);

    refreshCompleter.complete();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    horizontalController.dispose();
  });

  testWidgets('refreshes without counting the overlay app-bar inset twice', (
    tester,
  ) async {
    var refreshCount = 0;
    final refreshCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 80),
              viewPadding: const EdgeInsets.only(top: 24),
            );
            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: const PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: SizedBox.expand(),
              ),
              body: MediaQuery(
                data: media,
                child: EasyRefresh(
                  header: reviewFrostedAppBarRefreshHeader,
                  onRefresh: () {
                    refreshCount++;
                    return refreshCompleter.future;
                  },
                  child: ListView.builder(
                    itemCount: 30,
                    itemBuilder: (_, _) => const SizedBox(height: 80),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    final indicatorPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('review-frosted-refresh-indicator-inset')),
    );
    expect(indicatorPadding.padding, const EdgeInsets.only(top: 80));
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    for (var attempt = 0; attempt < 20 && refreshCount == 0; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(refreshCount, 1);

    refreshCompleter.complete();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
