import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/page_audit.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';

Color scoreColor(int s) => s >= 90
    ? const Color(0xFF0CCE6B)
    : s >= 50
        ? const Color(0xFFFFA400)
        : const Color(0xFFFF4E42);

/// Lighthouse-style report: performance, accessibility, best practices, SEO.
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  bool _running = false;
  List<AuditCategory>? _result;
  String? _url;

  Future<void> _run() async {
    final tab = ref.read(tabsProvider).active;
    if (tab.isNewTab || !tab.url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open a web page first')));
      return;
    }
    setState(() => _running = true);
    final c = ref.read(tabsProvider.notifier).activeController;
    final pageData = ref.read(pageDataProvider.notifier);
    pageData.put('page_audit', const {});
    await c.runJavaScript('if (window.__dbg) { __dbg.collectVitals(); __dbg.a11yAudit(); __dbg.pageAudit(); }');
    // Results arrive over the bridge.
    Map<String, dynamic>? seo;
    for (var i = 0; i < 30 && (seo == null || seo.isEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      seo = ref.read(pageDataProvider)['page_audit'];
    }
    if (!mounted) return;
    if (seo == null || seo.isEmpty) {
      setState(() => _running = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The page did not respond. Reload it and try again.')));
      return;
    }
    final data = ref.read(pageDataProvider);
    ref.read(consoleLogsProvider.notifier).flush();
    ref.read(networkRequestsProvider.notifier).flush();
    final errors = ref.read(consoleLogsProvider).where((l) => l.level == 'error').length;
    setState(() {
      _running = false;
      _url = tab.url;
      _result = scorePage(seo: seo!, vitals: data['vitals'], a11y: data['a11y'], consoleErrors: errors);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Page audit')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? null : _run,
        icon: _running
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
        label: Text(r == null ? 'Run audit' : 'Run again'),
      ),
      body: r == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Scores the current page for performance, accessibility, best practices and SEO, '
                  'like Lighthouse, right on your phone.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                if (_url != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_url!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                  ),
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  runSpacing: 12,
                  children: [for (final c in r) _Gauge(score: c.score, label: c.name)],
                ),
                const SizedBox(height: 16),
                for (final c in r)
                  Card(
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: scoreColor(c.score),
                        child: Text('${c.score}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(c.name),
                      subtitle: Text('${c.checks.where((x) => !x.passed).length} to improve'),
                      children: [
                        for (final ch in c.checks)
                          ListTile(
                            dense: true,
                            leading: Icon(ch.passed ? Icons.check_circle : Icons.error,
                                color: ch.passed ? const Color(0xFF0CCE6B) : const Color(0xFFFF4E42), size: 20),
                            title: Text(ch.title),
                            subtitle: ch.detail == null ? null : Text(ch.detail!),
                          ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Scores are estimates from this device and session. Run again after the page has fully '
                    'loaded and you have interacted with it for the best performance data.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Gauge extends StatelessWidget {
  final int score;
  final String label;
  const _Gauge({required this.score, required this.label});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 80,
        child: Column(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: score / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(
              painter: _GaugePainter(v, scoreColor(score)),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: Text('${(v * 100).round()}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scoreColor(score))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  _GaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.09;
    final r = rect.deflate(stroke / 2);
    canvas.drawCircle(rect.center, size.width / 2 - stroke / 2, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * value, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}
