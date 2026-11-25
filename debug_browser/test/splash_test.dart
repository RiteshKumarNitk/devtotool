import 'package:debug_browser/branding/logo_painter.dart';
import 'package:debug_browser/branding/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app({bool reduceMotion = false}) => ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: const SplashPage(prewarm: false, next: Scaffold(body: Text('HOME'))),
          ),
        ),
      ),
    );

LogoPainter painter(WidgetTester t) =>
    t.widget<CustomPaint>(find.descendant(of: find.byType(SplashPage), matching: find.byType(CustomPaint)).first).painter!
        as LogoPainter;

void main() {
  testWidgets('animates the logo, then opens the app', (t) async {
    await t.pumpWidget(app());
    await t.pump();
    // First frame: nothing drawn yet (matches the plain native splash).
    expect(painter(t).outline, 0);
    expect(painter(t).badge, 0);

    await t.pump(const Duration(milliseconds: 500));
    expect(painter(t).outline, greaterThan(0.9), reason: 'outline drawn by ~0.6 s');
    expect(painter(t).badge, 0, reason: 'badge appears after the globe');

    await t.pump(const Duration(milliseconds: 1200));
    expect(painter(t).badge, closeTo(1, 0.05));
    expect(find.text('Debug Browser'), findsOneWidget);

    // Short hold on the finished logo, then the cross-fade into the app.
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing, reason: 'splash is replaced, not stacked');
  });

  testWidgets('tap skips the animation', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byType(SplashPage));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final frame and leaves quickly', (t) async {
    await t.pumpWidget(app(reduceMotion: true));
    await t.pump();
    await t.pump();
    expect(painter(t).outline, 1);
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
