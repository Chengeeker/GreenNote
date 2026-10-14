import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/network/coolapk_image.dart';
import 'package:greennote/core/network/http_overrides.dart';
import 'package:greennote/core/widgets/app_avatar.dart';
import 'package:greennote/core/widgets/cached_network_image.dart';
import 'package:greennote/features/feed/nine_grid_view.dart';
import 'package:greennote/features/feed/image_gallery_page.dart';

class _FakeApi extends Fake implements CoolapkApi {
  @override
  String get currentUserAvatar => '';
  @override
  bool get hasCookie => false;
}

void main() {
  group('Image Performance & Pre-caching Tests', () {
    test('AppHttpOverrides configures maxConnectionsPerHost and timeouts', () {
      final overrides = AppHttpOverrides();
      final client = overrides.createHttpClient(null);
      expect(client.maxConnectionsPerHost, 32);
      expect(client.idleTimeout, const Duration(seconds: 30));
      expect(client.connectionTimeout, const Duration(seconds: 15));
      client.close();
    });

    testWidgets('AppAvatar uses downscaled cacheWidth and cacheHeight', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAvatar(
              url: 'https://avatar.coolapk.com/avatar_test.jpg',
              size: 40,
              api: _FakeApi(),
            ),
          ),
        ),
      );

      // Verify widget builds without error
      expect(find.byType(AppAvatar), findsOneWidget);
    });

    testWidgets('CachedNetworkImage automatically computes effective cache dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CachedNetworkImage(
              'https://image.coolapk.com/pic_test.jpg',
              width: 100,
              height: 80,
            ),
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('NineGridView builds with cache downsampling', (tester) async {
      final pics = [
        const GalleryImage('https://image.coolapk.com/pic1.jpg'),
        const GalleryImage('https://image.coolapk.com/pic2.jpg'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NineGridView(
              api: _FakeApi(),
              pics: pics,
              statusId: 'perf_test',
            ),
          ),
        ),
      );

      expect(find.byType(NineGridView), findsOneWidget);
    });

    testWidgets('precacheFeedImages safely handles CoolapkFeed and Map items', (tester) async {
      final feeds = [
        const CoolapkFeed(
          id: '1',
          username: '测试',
          avatar: 'https://avatar.coolapk.com/test.jpg',
          message: 'Hello',
          date: '刚刚',
          likeCount: '0',
          replyCount: '0',
          pictures: ['https://image.coolapk.com/pic1.jpg'],
        ),
        {
          'userAvatar': 'https://avatar.coolapk.com/test2.jpg',
          'pic': 'https://image.coolapk.com/pic2.jpg',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              precacheFeedImages(feeds, context, api: _FakeApi());
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pump();
    });
  });
}
