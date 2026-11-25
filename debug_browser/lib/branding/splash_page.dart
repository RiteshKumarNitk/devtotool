import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/home_stats.dart';
import '../core/tabs_provider.dart';
import 'logo_painter.dart';

/// Animated launch screen. Its first frame matches the native splash
/// (solid [BrandColors.splash] + centred logo), so the hand-off is seamless.
class SplashPage extends ConsumerStatefulWidget {
  final Widget next;

  /// Start the browser engine (and the home page load) behind the splash.
  final bool prewarm;
  const SplashPage({super.key, required this.next, this.prewarm = true});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1650);

  /// After the first run the same animation plays about twice as fast, so
  /// opening the browser (or a link from another app) isn't slowed down.
  static const _quickDuration = Duration(milliseconds: 850);
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration);
  bool _leaving = false;

  Animation<double> _interval(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _c, curve: Interval(begin, end, curve: curve));

  late final _outline = _interval(0.0, 0.38, Curves.easeInOutCubic);
  late final _logoScale = Tween(begin: 0.85, end: 1.0).animate(_interval(0.0, 0.45));
  late final _spin = _interval(0.15, 0.55, Curves.easeOutBack);
  late final _badge = _interval(0.36, 0.68, Curves.elasticOut);
  late final _glow = _interval(0.40, 0.95, Curves.easeOut);
  late final _title = _interval(0.45, 0.78);
  late final _tagline = _interval(0.58, 0.92);
  late final _background = _interval(0.0, 0.6);

  @override
  void initState() {
    super.initState();
    if (widget.prewarm) ref.read(tabsProvider);
    final quick = ref.read(onboardedProvider);
    if (quick) _c.duration = _quickDuration;
    final hold = Duration(milliseconds: quick ? 80 : 250);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
        Future.delayed(const Duration(milliseconds: 250), _finish);
      } else {
        _c.forward().whenComplete(() => Future.delayed(hold, _finish));
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _finish() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => widget.next,
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(curved), child: child),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logo = math.min(size.width, size.height) * 0.42;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish, // tap to skip
      child: Semantics(
        label: 'Debug Browser is starting',
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return DecoratedBox(
              // Solid splash colour fades into the brand gradient.
              decoration: BoxDecoration(
                color: BrandColors.splash,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(BrandColors.splash, BrandColors.blue, _background.value)!,
                    Color.lerp(BrandColors.splash, BrandColors.violet, _background.value)!,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Expanding glow ring behind the logo.
                  Opacity(
                    // Invisible until its pulse starts, so frame 0 matches the
                    // plain native splash.
                    opacity: _glow.value == 0 ? 0 : (1 - _glow.value) * 0.5,
                    child: Container(
                      width: logo * (0.7 + _glow.value * 0.9),
                      height: logo * (0.7 + _glow.value * 0.9),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2 + 6 * (1 - _glow.value)),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: _logoScale.value,
                    child: SizedBox(
                      width: logo,
                      height: logo,
                      child: CustomPaint(
                        painter: LogoPainter(
                          outline: _outline.value,
                          spin: _spin.value,
                          badge: _badge.value,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    top: size.height / 2 + logo * 0.55,
                    child: Column(
                      children: [
                        Opacity(
                          opacity: _title.value,
                          child: Transform.translate(
                            offset: Offset(0, 24 * (1 - _title.value)),
                            child: const Text(
                              'Debug Browser',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: _tagline.value * 0.85,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - _tagline.value)),
                            child: const Text(
                              'Browse. Inspect. Debug.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 32 + MediaQuery.paddingOf(context).bottom,
                    child: Opacity(
                      opacity: _tagline.value * 0.7,
                      child: const Text(
                        'by InnovateX Technology',
                        style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
