import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/browser_settings.dart';

/// Colours for each New Tab theme: base, then three light "blobs".
const Map<NewTabTheme, List<Color>> newTabPalettes = {
  NewTabTheme.aurora: [Color(0xFF0B1033), Color(0xFF3D5AFE), Color(0xFF7C4DFF), Color(0xFF00BFA5)],
  NewTabTheme.sunset: [Color(0xFF2A0F2E), Color(0xFFFF6E40), Color(0xFFE91E63), Color(0xFFFFC107)],
  NewTabTheme.ocean: [Color(0xFF021B33), Color(0xFF0091EA), Color(0xFF00B8D4), Color(0xFF1DE9B6)],
  NewTabTheme.forest: [Color(0xFF07170F), Color(0xFF2E7D32), Color(0xFF00897B), Color(0xFFC0CA33)],
  NewTabTheme.midnight: [Color(0xFF050608), Color(0xFF283593), Color(0xFF4A148C), Color(0xFF1565C0)],
  NewTabTheme.plain: [Color(0xFF1A73E8), Color(0xFF1A73E8), Color(0xFF6A3DE8), Color(0xFF1A73E8)],
};

/// Slowly drifting soft colour blobs over a dark base (static if the user
/// turned animations off, or for the "plain" theme).
class AuroraBackground extends StatefulWidget {
  final NewTabTheme theme;
  final Widget child;
  const AuroraBackground({super.key, required this.theme, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations || widget.theme == NewTabTheme.plain;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didUpdateWidget(AuroraBackground old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = newTabPalettes[widget.theme]!;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(_c, colors, plain: widget.theme == NewTabTheme.plain),
        child: widget.child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final Animation<double> t;
  final List<Color> colors;
  final bool plain;
  _AuroraPainter(this.t, this.colors, {required this.plain}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (plain) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors[1], colors[2]],
          ).createShader(rect),
      );
      return;
    }
    canvas.drawRect(rect, Paint()..color = colors[0]);
    final a = t.value * 2 * math.pi;
    final r = size.longestSide * 0.75;
    // Three blobs on slow Lissajous paths.
    final blobs = [
      (Offset(size.width * (0.25 + 0.15 * math.sin(a)), size.height * (0.20 + 0.10 * math.cos(a * 2))), colors[1]),
      (Offset(size.width * (0.80 + 0.12 * math.cos(a)), size.height * (0.35 + 0.15 * math.sin(a))), colors[2]),
      (Offset(size.width * (0.45 + 0.20 * math.sin(a + 2)), size.height * (0.85 + 0.08 * math.cos(a + 1))), colors[3]),
    ];
    for (final (center, color) in blobs) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
    // Soft vignette for text contrast.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.35)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.colors != colors || old.plain != plain;
}
