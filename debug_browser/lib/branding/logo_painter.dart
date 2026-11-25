import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand colours (shared by the icon, native splash and animated splash).
abstract final class BrandColors {
  static const blue = Color(0xFF1A73E8);
  static const violet = Color(0xFF6A3DE8);
  static const deep = Color(0xFF0B3D91);
  static const amber = Color(0xFFFFB300);
  static const ink = Color(0xFF1F2937);

  /// Solid colour used by the native (pre-Flutter) splash so the hand-off to
  /// the animated splash is seamless.
  static const splash = Color(0xFF1557C0);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, violet],
  );
}

/// The Debug Browser logo: a globe (the web) with a "</>" badge (dev tools).
///
/// Every part can be animated, so the same drawing is used for the launcher
/// icon (all values 1) and the animated splash.
class LogoPainter extends CustomPainter {
  /// 0..1: how much of the globe outline is drawn.
  final double outline;

  /// 0..1: meridians "spin in" (ellipse widths grow from flat).
  final double spin;

  /// 0..~1.1: badge scale (overshoots with an elastic curve).
  final double badge;

  /// Paint the gradient square behind the logo (launcher icon, legacy).
  final bool background;

  /// Scales the artwork about the centre (adaptive icons need a safe zone).
  final double scale;

  const LogoPainter({
    this.outline = 1,
    this.spin = 1,
    this.badge = 1,
    this.background = false,
    this.scale = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..shader = BrandColors.gradient.createShader(Offset.zero & size));
    }
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-s / 2, -s / 2);

    final c = Offset(s * 0.46, s * 0.46);
    final r = s * 0.30;
    final stroke = s * 0.045;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Soft fill behind the globe for depth.
    if (outline > 0) {
      canvas.drawCircle(
        c,
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.10 * outline.clamp(0, 1)),
      );
    }

    // Globe outline, drawn progressively from the top.
    final circle = Path()..addArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2);
    // (A zero-length path with round caps would paint a dot, so skip it.)
    if (outline > 0.001) {
      for (final m in circle.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * outline.clamp(0, 1)), white);
      }
    }

    // Grid, clipped to the globe.
    if (spin > 0) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - stroke / 2)));
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: spin.clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.75;
      final w = spin.clamp(0.0, 1.0);
      // Meridians: ellipses that widen as the globe "spins in".
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.05 * w, height: r * 2), grid);
      canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), grid);
      // Equator and two latitudes.
      canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), grid);
      final latitude = Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * w)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.45;
      for (final k in [-0.5, 0.5]) {
        final y = c.dy + r * k;
        final half = r * math.sqrt(1 - k * k);
        canvas.drawLine(Offset(c.dx - half, y), Offset(c.dx + half, y), latitude);
      }
      canvas.restore();
    }

    // "</>" badge, bottom-right.
    if (badge > 0) {
      final bc = Offset(s * 0.70, s * 0.70);
      final br = s * 0.17;
      canvas.save();
      canvas.translate(bc.dx, bc.dy);
      canvas.scale(badge);
      canvas.drawCircle(Offset.zero, br + stroke * 0.9, Paint()..color = BrandColors.deep.withValues(alpha: 0.35));
      canvas.drawCircle(Offset.zero, br, Paint()..color = BrandColors.amber);
      final ink = Paint()
        ..color = BrandColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final u = br * 0.42;
      // <
      canvas.drawPath(
        Path()
          ..moveTo(-u * 0.55, -u * 0.6)
          ..lineTo(-u * 1.25, 0)
          ..lineTo(-u * 0.55, u * 0.6),
        ink,
      );
      // >
      canvas.drawPath(
        Path()
          ..moveTo(u * 0.55, -u * 0.6)
          ..lineTo(u * 1.25, 0)
          ..lineTo(u * 0.55, u * 0.6),
        ink,
      );
      // /
      canvas.drawLine(Offset(u * 0.2, -u * 0.8), Offset(-u * 0.2, u * 0.8), ink);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.outline != outline || old.spin != spin || old.badge != badge || old.background != background || old.scale != scale;
}
