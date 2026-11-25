// Renders the brand PNGs from LogoPainter (single source of truth).
//
//   flutter test tool/render_brand_assets_test.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// Outputs into assets/branding/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debug_browser/branding/logo_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(WidgetTester tester, String path, double size, LogoPainter painter) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: size, height: size, child: CustomPaint(painter: painter)),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('render brand assets', (tester) async {
    // Logical size == pixel size.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.reset);

    // Full icon (legacy Android, iOS, Play Store): gradient + logo.
    await _render(tester, 'assets/branding/icon.png', 1024, const LogoPainter(background: true, scale: 0.86));
    // Adaptive icon foreground: transparent. flutter_launcher_icons adds a 16%
    // inset, which puts the artwork inside Android's 66% safe zone.
    await _render(tester, 'assets/branding/icon_foreground.png', 1024, const LogoPainter(scale: 0.98));
    // Android 12+ requires a splash icon: a transparent one keeps the native
    // splash a plain colour, and the Flutter splash then draws the logo.
    await _render(tester, 'assets/branding/splash_blank.png', 960, const LogoPainter(outline: 0, spin: 0, badge: 0));
  });
}
