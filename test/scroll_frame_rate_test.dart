import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/widgets/app_scroll_behavior.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.green.note/ui');
  final hints = <bool>[];
  final originalRefreshBehavior = EasyRefresh.defaultScrollBehaviorBuilder;

  setUp(() {
    EasyRefresh.defaultScrollBehaviorBuilder = AppRefreshScrollBehavior.new;
    hints.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setScrolling') hints.add(call.arguments as bool);
          return {
            'active': call.arguments,
            'window': 'applied',
            'surface': 'applied',
          };
        });
  });

  tearDown(() {
    EasyRefresh.defaultScrollBehaviorBuilder = originalRefreshBehavior;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget page(
    ScrollController controller, {
    bool enabled = true,
    TargetPlatform platform = TargetPlatform.android,
    Axis axis = Axis.vertical,
  }) => MaterialApp(
    theme: ThemeData(platform: platform),
    scrollBehavior: const AppScrollBehavior(),
    home: Scaffold(
      body: TickerMode(
        enabled: enabled,
        child: ListView.builder(
          controller: controller,
          scrollDirection: axis,
          itemExtent: 80,
          itemCount: 500,
          itemBuilder: (_, index) => Text('item $index'),
        ),
      ),
    ),
  );

  for (final frameMs in [8, 11, 16]) {
    testWidgets(
      'fling hint survives finger-up through the tail at ${frameMs}ms',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(page(controller));
        expect(hints, isEmpty);
        await tester.fling(find.byType(ListView), const Offset(0, -220), 1600);
        await tester.pump(Duration(milliseconds: frameMs));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(hints, [true]);
        var frames = 0;
        while (controller.position.isScrollingNotifier.value &&
            frames++ < 500) {
          await tester.pump(Duration(milliseconds: frameMs));
        }
        expect(controller.position.isScrollingNotifier.value, isFalse);
        expect(hints, [true, false]);
        await tester.pump(const Duration(seconds: 2));
        expect(hints, [true, false]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'EasyRefresh keeps the request beyond two seconds of deceleration',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 4000);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: EasyRefresh(
              onRefresh: () async {},
              child: ListView.builder(
                controller: controller,
                physics: const AlwaysScrollableScrollPhysics(),
                itemExtent: 80,
                itemCount: 500,
                itemBuilder: (_, index) => Text('item $index'),
              ),
            ),
          ),
        ),
      );
      await tester.fling(find.byType(ListView), const Offset(0, -240), 2400);
      await tester.pump();
      for (var i = 0; i < 260; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(controller.position.isScrollingNotifier.value, isTrue);
      expect(hints, [true]);
      final tailOffset = controller.offset;
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.offset, greaterThan(tailOffset));
      for (
        var i = 0;
        i < 750 && controller.position.isScrollingNotifier.value;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(controller.position.isScrollingNotifier.value, isFalse);
      expect(hints, [true, false]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('EasyRefresh still refreshes and releases its scroll request', (
    tester,
  ) async {
    final complete = Completer<void>();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: EasyRefresh(
            onRefresh: () {
              refreshes++;
              return complete.future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(refreshes, 1);
    complete.complete();
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(hints.first, isTrue);
    expect(hints.last, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('overlapping scrolls keep the hint until both stop', (
    tester,
  ) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget list(ScrollController controller) => Expanded(
      child: ListView.builder(
        controller: controller,
        itemExtent: 80,
        itemCount: 100,
        itemBuilder: (_, index) => Text('item $index'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(body: Row(children: [list(first), list(second)])),
      ),
    );
    final a = first.animateTo(
      700,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );
    final b = second.animateTo(
      900,
      duration: const Duration(milliseconds: 500),
      curve: Curves.linear,
    );
    await tester.pump();
    expect(hints, [true]);
    await tester.pump(const Duration(milliseconds: 210));
    await a;
    expect(hints, [true]);
    await tester.pump(const Duration(milliseconds: 310));
    await b;
    expect(hints, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden and disposed scrolling viewports release their hints', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(page(controller));
    await tester.fling(find.byType(ListView), const Offset(0, -200), 1600);
    await tester.pump();
    expect(hints, [true]);
    await tester.pumpWidget(page(controller, enabled: false));
    expect(hints, [true, false]);
    await tester.pumpWidget(page(controller));
    await tester.fling(find.byType(ListView), const Offset(0, -200), 1600);
    await tester.pump();
    expect(hints.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(hints.last, isFalse);
  });

  testWidgets(
    'background releases the hint and a new scroll can request again',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(page(controller));
      await tester.fling(find.byType(ListView), const Offset(0, -200), 1600);
      await tester.pump();
      expect(hints, [true]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(hints, [true, false]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.fling(find.byType(ListView), const Offset(0, -200), 1600);
      await tester.pump();
      expect(hints.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(hints.last, isFalse);
    },
  );

  testWidgets(
    'horizontal paging and non-Android hosts use existing scheduling',
    (tester) async {
      for (final options in [
        (TargetPlatform.android, Axis.horizontal),
        (TargetPlatform.iOS, Axis.vertical),
      ]) {
        final controller = ScrollController();
        await tester.pumpWidget(
          page(controller, platform: options.$1, axis: options.$2),
        );
        await tester.fling(
          find.byType(ListView),
          options.$2 == Axis.vertical
              ? const Offset(0, -200)
              : const Offset(-200, 0),
          1600,
        );
        await tester.pump();
        expect(hints, isEmpty);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets('unavailable native hint does not interrupt scrolling', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'surface_unavailable'),
        );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(page(controller));
    await tester.fling(find.byType(ListView), const Offset(0, -200), 1600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset, greaterThan(200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
