import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/services/cache_service.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/features/settings/cache_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CacheBreakdown formatting tests', () {
    test('formatBytes handles zero and negative numbers', () {
      expect(CacheBreakdown.formatBytes(0), '0 B');
      expect(CacheBreakdown.formatBytes(-50), '0 B');
    });

    test('formatBytes handles bytes, KB, MB, GB properly', () {
      expect(CacheBreakdown.formatBytes(512), '512 B');
      expect(CacheBreakdown.formatBytes(1024), '1.00 KB');
      expect(CacheBreakdown.formatBytes(1536), '1.50 KB');
      expect(CacheBreakdown.formatBytes(1024 * 1024), '1.00 MB');
      expect(CacheBreakdown.formatBytes(100 * 1024 * 1024), '100.00 MB');
      expect(CacheBreakdown.formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(CacheBreakdown.formatBytes(2560 * 1024 * 1024), '2.50 GB');
    });
  });

  group('CacheService unit tests', () {
    const channel = MethodChannel('com.green.note/cache');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getCacheStats') {
              return {
                'total': 150 * 1024 * 1024,
                'images': 100 * 1024 * 1024,
                'network': 30 * 1024 * 1024,
                'system': 20 * 1024 * 1024,
              };
            }
            if (call.method == 'clearCache') {
              return {'cleared': 150 * 1024 * 1024, 'success': true};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getCacheStats retrieves breakdown from channel', () async {
      final stats = await CacheService.getCacheStats();
      expect(stats.totalBytes, 150 * 1024 * 1024);
      expect(stats.imageBytes, 100 * 1024 * 1024);
      expect(stats.networkBytes, 30 * 1024 * 1024);
      expect(stats.systemBytes, 20 * 1024 * 1024);
    });

    test('clearCache executes and returns cleared bytes', () async {
      final cleared = await CacheService.clearCache();
      expect(cleared, 150 * 1024 * 1024);
    });

    test('checkAndAutoClearCache respects threshold', () async {
      // 150MB total cache
      // If threshold is 200MB, it shouldn't trigger
      final didClearBelow = await CacheService.checkAndAutoClearCache(200);
      expect(didClearBelow, isFalse);

      // If threshold is 100MB, it should trigger
      final didClearAbove = await CacheService.checkAndAutoClearCache(100);
      expect(didClearAbove, isTrue);

      // If threshold is 0 (disabled), it shouldn't trigger
      final didClearZero = await CacheService.checkAndAutoClearCache(0);
      expect(didClearZero, isFalse);
    });
  });

  group('AppSettings autoClearCacheThresholdMb tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'greennote.auto_clear_cache_threshold_mb': 500,
      });
    });

    test('default autoClearCacheThresholdMb is 200 MB without prior preference', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(const AppSettingsState().autoClearCacheThresholdMb, 200);

      container.read(appSettingsProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(appSettingsProvider).autoClearCacheThresholdMb,
        200,
      );
    });

    test('loads autoClearCacheThresholdMb from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'greennote.auto_clear_cache_threshold_mb': 500,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(appSettingsProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(appSettingsProvider).autoClearCacheThresholdMb,
        500,
      );

      await notifier.setAutoClearCacheThresholdMb(200);
      expect(
        container.read(appSettingsProvider).autoClearCacheThresholdMb,
        200,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('greennote.auto_clear_cache_threshold_mb'), 200);
    });

    test(
      'exportBackup and restoreBackup preserve autoClearCacheThresholdMb',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(appSettingsProvider.notifier);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await notifier.setAutoClearCacheThresholdMb(1024);

        final backup = await notifier.exportBackup(
          webDavUrl: 'https://dav.test',
          webDavUsername: 'user',
          webDavDirectory: 'GreenNote',
        );

        final prefsMap = backup['preferences'] as Map<String, dynamic>;
        expect(prefsMap['autoClearCacheThresholdMb'], 1024);

        // Modify state then restore
        await notifier.setAutoClearCacheThresholdMb(50);
        expect(
          container.read(appSettingsProvider).autoClearCacheThresholdMb,
          50,
        );

        await notifier.restoreBackup(backup);
        expect(
          container.read(appSettingsProvider).autoClearCacheThresholdMb,
          1024,
        );
      },
    );
  });

  group('CacheManagementPage widget tests', () {
    const channel = MethodChannel('com.green.note/cache');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (MethodCall call) async {
            return '.';
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getCacheStats') {
              return {
                'total': 120 * 1024 * 1024,
                'images': 80 * 1024 * 1024,
                'network': 30 * 1024 * 1024,
                'system': 10 * 1024 * 1024,
              };
            }
            if (call.method == 'clearCache') {
              return {'cleared': 120 * 1024 * 1024, 'success': true};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
    });

    testWidgets('renders cache management page with overview and tiles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CacheManagementPage())),
      );

      await tester.pumpAndSettle();

      expect(find.text('缓存管理'), findsOneWidget);
      expect(find.text('当前应用缓存占用'), findsOneWidget);
      expect(find.text('120.00 MB'), findsOneWidget);
      expect(find.text('图片与媒体'), findsOneWidget);
      expect(find.text('网络与临时'), findsOneWidget);
      expect(find.text('系统运行时'), findsOneWidget);
      expect(find.text('一键清理所有缓存'), findsOneWidget);
      expect(find.text('自动清理缓存阈值'), findsOneWidget);
      expect(find.text('真实物理清理'), findsOneWidget);
    });

    testWidgets('clicking auto clear threshold tile opens selection dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CacheManagementPage())),
      );

      await tester.pumpAndSettle();

      final thresholdTile = find.text('自动清理缓存阈值');
      expect(thresholdTile, findsOneWidget);

      await tester.tap(thresholdTile);
      await tester.pumpAndSettle();

      expect(find.text('选择自动清理阈值'), findsOneWidget);
      expect(find.text('500 MB'), findsOneWidget);

      await tester.tap(find.text('500 MB'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('选择自动清理阈值'), findsNothing);
      expect(find.text('500 MB'), findsWidgets);
    });

    testWidgets(
      'clicking clear cache shows confirmation and triggers clearing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: CacheManagementPage())),
        );

        await tester.pumpAndSettle();

        final clearButton = find.text('一键清理所有缓存');
        expect(clearButton, findsOneWidget);

        await tester.tap(clearButton);
        await tester.pumpAndSettle();

        expect(find.text('清理所有缓存？'), findsOneWidget);
        expect(find.text('立即清理'), findsOneWidget);

        // Change mock return for subsequent fetch to 0 B
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              if (call.method == 'getCacheStats') {
                return {'total': 0, 'images': 0, 'network': 0, 'system': 0};
              }
              if (call.method == 'clearCache') {
                return {'cleared': 120 * 1024 * 1024, 'success': true};
              }
              return null;
            });

        await tester.tap(find.text('立即清理'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('0 B'), findsWidgets);
      },
    );
  });
}
