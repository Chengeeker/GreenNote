import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greennote/core/settings/app_settings.dart';
import 'package:greennote/core/storage/storage_path_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StoragePathResolver Tests', () {
    test('sanitizeDirectoryName removes illegal chars and handles edge cases', () {
      expect(StoragePathResolver.sanitizeDirectoryName('hello/world'), 'hello_world');
      expect(StoragePathResolver.sanitizeDirectoryName('a:b*c?d"e<f>g|h'), 'a_b_c_d_e_f_g_h');
      expect(StoragePathResolver.sanitizeDirectoryName('   '), 'User');
      expect(StoragePathResolver.sanitizeDirectoryName(null, fallback: 'Default'), 'Default');
      expect(StoragePathResolver.sanitizeDirectoryName('.'), 'User');
      expect(StoragePathResolver.sanitizeDirectoryName('..'), 'User');
      expect(
        StoragePathResolver.sanitizeDirectoryName('a' * 100).length,
        lessThanOrEqualTo(50),
      );
    });

    test('getPathSummary formats correctly for images and videos', () {
      // Default (0)
      expect(
        StoragePathResolver.getPathSummary(0, '张三', isVideo: false),
        'Picture/GreenNote/',
      );
      expect(
        StoragePathResolver.getPathSummary(0, '张三', isVideo: true),
        'Movies/GreenNote/',
      );

      // Self nickname (1)
      expect(
        StoragePathResolver.getPathSummary(1, '张三', isVideo: false),
        'Picture/GreenNote/张三/',
      );
      expect(
        StoragePathResolver.getPathSummary(1, '', isVideo: true),
        'Movies/GreenNote/我的昵称/',
      );

      // Author nickname (2)
      expect(
        StoragePathResolver.getPathSummary(2, '张三', isVideo: false),
        'Picture/GreenNote/该条动态发布用户昵称/',
      );
      expect(
        StoragePathResolver.getPathSummary(2, '张三', isVideo: true),
        'Movies/GreenNote/该条动态发布用户昵称/',
      );
    });

    test('resolveSubDir resolves relative path appropriately', () {
      expect(
        StoragePathResolver.resolveSubDir(pathType: 0, isVideo: false),
        'GreenNote',
      );
      expect(
        StoragePathResolver.resolveSubDir(
          pathType: 1,
          myNickname: '李四',
          isVideo: false,
        ),
        'GreenNote/李四',
      );
      expect(
        StoragePathResolver.resolveSubDir(
          pathType: 2,
          authorName: '数码闲聊站',
          isVideo: true,
        ),
        'GreenNote/数码闲聊站',
      );
      expect(
        StoragePathResolver.resolveSubDir(
          pathType: 2,
          authorName: '   ',
          isVideo: false,
        ),
        'GreenNote/Unknown',
      );
    });
  });

  group('AppSettings Storage Settings Tests', () {
    test('default storage path types are 0 and survive setters and backup restore', () async {
      final notifier = AppSettingsNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state.imageSavePathType, 0);
      expect(notifier.state.videoSavePathType, 0);

      await notifier.setImageSavePathType(1);
      await notifier.setVideoSavePathType(2);

      expect(notifier.state.imageSavePathType, 1);
      expect(notifier.state.videoSavePathType, 2);

      final backup = await notifier.exportBackup(
        webDavUrl: '',
        webDavUsername: '',
        webDavDirectory: 'GreenNote',
      );

      final prefs = backup['preferences'] as Map<String, dynamic>;
      expect(prefs['imageSavePathType'], 1);
      expect(prefs['videoSavePathType'], 2);

      // Reset
      await notifier.setImageSavePathType(0);
      await notifier.setVideoSavePathType(0);
      expect(notifier.state.imageSavePathType, 0);
      expect(notifier.state.videoSavePathType, 0);

      // Restore from backup
      await notifier.restoreBackup(backup);
      expect(notifier.state.imageSavePathType, 1);
      expect(notifier.state.videoSavePathType, 2);
    });
  });
}
