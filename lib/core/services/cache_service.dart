import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CacheBreakdown {
  const CacheBreakdown({
    required this.totalBytes,
    required this.imageBytes,
    required this.networkBytes,
    required this.systemBytes,
  });

  final int totalBytes;
  final int imageBytes;
  final int networkBytes;
  final int systemBytes;

  static const empty = CacheBreakdown(
    totalBytes: 0,
    imageBytes: 0,
    networkBytes: 0,
    systemBytes: 0,
  );

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }
}

class CacheService {
  static final revision = ValueNotifier<int>(0);
  static const MethodChannel _channel = MethodChannel('com.green.note/cache');

  /// Fetches cache statistics from native platform or falls back to Dart file calculation.
  static Future<CacheBreakdown> getCacheStats() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getCacheStats',
      );
      if (res != null) {
        return CacheBreakdown(
          totalBytes: (res['total'] as num?)?.toInt() ?? 0,
          imageBytes: (res['images'] as num?)?.toInt() ?? 0,
          networkBytes: (res['network'] as num?)?.toInt() ?? 0,
          systemBytes: (res['system'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint(
        'Native cache stats unavailable, falling back to Dart directory scan: $e',
      );
    }

    return _getCacheStatsFallback();
  }

  /// Clears in-memory image caches, disk caches, and native Android cache directories.
  static Future<int> clearCache() async {
    // 1. Clear Flutter & extended_image memory cache
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      clearMemoryImageCache();
    } catch (e) {
      debugPrint('Failed to clear memory image cache: $e');
    }

    // 2. Clear extended_image disk cache
    try {
      await clearDiskCachedImages();
    } catch (e) {
      debugPrint('Failed to clear extended_image disk cache: $e');
    }

    // 3. Clear native Android cache directories via MethodChannel
    var clearedBytes = 0;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('clearCache');
      if (res != null && res['cleared'] != null) {
        clearedBytes = (res['cleared'] as num).toInt();
      }
    } catch (e) {
      debugPrint(
        'Native clearCache unavailable, using fallback directory deletion: $e',
      );
      clearedBytes = await _clearCacheFallback();
    }

    try {
      await (await SharedPreferences.getInstance()).remove(
        'cached_home_headline_v1',
      );
    } catch (error) {
      debugPrint('Unable to clear cached headline snapshot: $error');
    }
    revision.value++;
    return clearedBytes;
  }

  /// Automatically clears cache if the total cache size exceeds the given threshold in MB.
  static Future<bool> checkAndAutoClearCache(int thresholdMb) async {
    if (thresholdMb <= 0) return false;
    try {
      final stats = await getCacheStats();
      final thresholdBytes = thresholdMb * 1024 * 1024;
      if (stats.totalBytes >= thresholdBytes) {
        debugPrint(
          'Cache size (${stats.totalBytes} bytes) exceeded threshold ($thresholdMb MB). Auto clearing cache...',
        );
        await clearCache();
        return true;
      }
    } catch (e) {
      debugPrint('Failed to run checkAndAutoClearCache: $e');
    }
    return false;
  }

  static Future<CacheBreakdown> _getCacheStatsFallback() async {
    var total = 0;
    var images = 0;
    var network = 0;
    var system = 0;

    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final list = tempDir.listSync(recursive: true, followLinks: false);
        for (final entity in list) {
          if (entity is File) {
            final len = entity.lengthSync();
            total += len;
            final p = entity.path.toLowerCase();
            if (p.contains('image') ||
                p.endsWith('.png') ||
                p.endsWith('.jpg') ||
                p.endsWith('.jpeg') ||
                p.endsWith('.webp') ||
                p.endsWith('.gif')) {
              images += len;
            } else if (p.contains('http') ||
                p.contains('webview') ||
                p.contains('dio') ||
                p.endsWith('.tmp')) {
              network += len;
            } else {
              system += len;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning temporary directory: $e');
    }

    return CacheBreakdown(
      totalBytes: total,
      imageBytes: images,
      networkBytes: network,
      systemBytes: system,
    );
  }

  static Future<int> _clearCacheFallback() async {
    var deletedBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final entries = tempDir.listSync(recursive: false, followLinks: false);
        for (final entry in entries) {
          try {
            if (entry is File) {
              deletedBytes += entry.lengthSync();
              entry.deleteSync();
            } else if (entry is Directory) {
              deletedBytes += _getDirectorySize(entry);
              entry.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error clearing temporary directory: $e');
    }
    return deletedBytes;
  }

  static int _getDirectorySize(Directory dir) {
    var size = 0;
    try {
      if (dir.existsSync()) {
        for (final entity in dir.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            size += entity.lengthSync();
          }
        }
      }
    } catch (_) {}
    return size;
  }
}
