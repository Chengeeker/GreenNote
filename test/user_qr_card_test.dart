import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/network/coolapk_api.dart';
import 'package:greennote/core/theme/app_theme.dart';
import 'package:greennote/features/shared/user_qr_card_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _QrApi implements CoolapkApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('card copies its public UID link without account credentials', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UserQrCardPage(
          api: _QrApi(),
          uid: '12345',
          name: '名片用户',
          avatar: '',
        ),
      ),
    );
    await tester.tap(find.text('复制主页链接'));
    await tester.pump();
    expect(copied, 'https://www.coolapk.com/u/12345');
    expect(find.text('已复制主页链接'), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.backgroundColor, Colors.white);
    expect(qr.padding, const EdgeInsets.all(32));
    expect(qr.errorCorrectionLevel, QrErrorCorrectLevel.M);
    expect(qr.eyeStyle.color, Colors.black);
    expect(qr.dataModuleStyle.color, Colors.black);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final invalid in ['', '0', '123/../../other', 'anonymous-user']) {
    testWidgets('invalid or local-only UID $invalid does not produce a card', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => openUserQrCard(
                  context,
                  _QrApi(),
                  uid: invalid,
                  name: '用户',
                  avatar: '',
                ),
                child: const Text('名片'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('名片'));
      await tester.pump();
      expect(find.byType(UserQrCardPage), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('请先登录并加载个人资料'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    for (final brightness in Brightness.values) {
      testWidgets('card adapts to $size and $brightness with large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        var theme = brightness == Brightness.dark
            ? AppTheme.darkTheme()
            : AppTheme.lightTheme();
        if (const bool.fromEnvironment('GENERATE_QR_PREVIEW')) {
          await tester.runAsync(() async {
            final font = FontLoader('QrPreviewSans')
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
                  ),
                ),
              );
            await font.load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
          });
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'QrPreviewSans'),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: 'QrPreviewSans',
            ),
            appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'QrPreviewSans',
              ),
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
            ),
            home: UserQrCardPage(
              api: _QrApi(),
              uid: '1234567890',
              name: '较长的二维码名片用户名称',
              avatar: '',
            ),
          ),
        );
        await tester.pump();
        final qrSize = tester.getSize(find.byType(QrImageView));
        expect(qrSize.width, qrSize.height);
        expect(qrSize.width, greaterThan(160));
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('GENERATE_QR_PREVIEW') &&
            size.height > size.width &&
            brightness == Brightness.dark) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('tmp/verification/1.9.30/qr-card-dark.png')
                .writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
