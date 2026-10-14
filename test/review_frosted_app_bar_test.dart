import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greennote/core/design_system/components/review_frosted_app_bar.dart';

void main() {
  testWidgets('bottom hairline can be disabled while solid material remains', (
    tester,
  ) async {
    const appBarColor = Color(0xff342f48);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          appBarTheme: const AppBarTheme(backgroundColor: appBarColor),
        ),
        home: const Scaffold(
          appBar: ReviewFrostedAppBar(
            title: Text('超话中心'),
            showBottomBorder: false,
          ),
          body: SizedBox.expand(),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final decoration = appBar.flexibleSpace! as DecoratedBox;
    final boxDecoration = decoration.decoration as BoxDecoration;
    expect(boxDecoration.color, appBarColor);
    expect(boxDecoration.border, isNull);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(appBar.backgroundColor, appBarColor);
    expect(appBar.forceMaterialTransparency, isFalse);
  });

  testWidgets('review app bar paints an opaque surface on its Material', (
    tester,
  ) async {
    const appBarColor = Color(0xff342f48);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          appBarTheme: const AppBarTheme(backgroundColor: appBarColor),
        ),
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: const ReviewFrostedAppBar(title: Text('普通顶栏')),
          body: ListView(
            children: const [SizedBox(height: 900, child: Text('滚动内容'))],
          ),
        ),
      ),
    );

    expect(find.byType(ReviewFrostedAppBar), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, appBarColor);
    expect(appBar.forceMaterialTransparency, isFalse);
    expect(find.text('普通顶栏'), findsOneWidget);
  });
}
