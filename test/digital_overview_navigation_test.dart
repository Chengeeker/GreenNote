import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/features/digital/views/digital_device_overview.dart';
import 'package:greennote/features/shell/main_pages.dart';

class _Api extends Fake implements CoolapkApi {
  @override
  bool get hasAccount => false;
  @override
  bool get hasCookie => false;
  @override
  bool get isAnonymous => false;
  @override
  String get currentUserAvatar => '';
  @override
  String get notificationSessionKey => 'test';
  @override
  Map<String, String> imageHeadersFor([String? url]) => {};
  @override
  Future<Map<String, String>> loadDiscoveryTabRoutes() async => {};
  @override
  Future<ApiPage> getList(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    return ApiPage(
      items: path == '/v6/search' && query['type'] == 'product'
          ? [
              {'id': 'phone', 'title': 'vivo test device'},
              {'id': 'rom', 'title': 'OriginOS 10'},
            ]
          : [],
      page: 1,
      hasMore: false,
      firstItem: '',
      lastItem: '',
    );
  }
}

void main() {
  for (final missingOs in [false, true]) {
    testWidgets(
      'local OS name is independent of hardware and search titles ($missingOs)',
      (tester) async {
        const channel = MethodChannel('com.green.note/ui');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'marketName': 'vivo test device',
            'osName': missingOs ? '' : 'OriginOS 10.2',
            'display': 'vivo test device',
            'androidVersion': '16',
          },
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DigitalDeviceOverview(
                api: _Api(),
                onOpenPhones: () {},
                onOpenSystems: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('vivo test device'), findsOneWidget);
        expect(
          find.text(missingOs ? 'Android 16' : 'OriginOS 10.2'),
          findsOneWidget,
        );
        expect(find.text('OriginOS 10'), findsNothing);
      },
    );
  }

  for (final discovery in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'top channel uses theme color without indicator space ($discovery/$brightness)',
        (tester) async {
          PreferredSizeWidget? top;
          final api = _Api();
          final scheme = ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: brightness,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: scheme),
              home: StatefulBuilder(
                builder: (context, setState) {
                  void update(PreferredSizeWidget? bar) =>
                      setState(() => top = bar);
                  return Scaffold(
                appBar: top == null ? null : AppBar(toolbarHeight: 52, bottom: top),
                    body: discovery
                        ? DiscoveryPage(api: api, onTopBarChanged: update)
                        : DigitalPage(api: api, onTopBarChanged: update),
                  );
                },
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final tabs = tester.widget<TabBar>(find.byType(TabBar).first);
          expect(tabs.labelColor, scheme.primary);
          expect((tabs.indicator! as BoxDecoration).color, Colors.transparent);
          expect(top!.preferredSize.height, 35);
          expect(tabs.indicatorWeight, 0.001);
          expect(tabs.preferredSize.height, lessThan(46.01));
          final page = discovery ? find.byType(DiscoveryPage) : find.byType(DigitalPage);
          expect(tester.getTopLeft(page).dy, 87);
        },
      );
    }
  }
}
