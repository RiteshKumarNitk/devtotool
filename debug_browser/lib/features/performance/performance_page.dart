import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';

enum VitalRating { good, needsImprovement, poor, unknown }

/// Thresholds from web.dev/articles/vitals (p75 "good" / "poor" boundaries).
VitalRating rateVital(String metric, num? value) {
  if (value == null) return VitalRating.unknown;
  const thresholds = {
    'lcp': (2500, 4000),
    'inp': (200, 500),
    'cls': (0.1, 0.25),
    'fcp': (1800, 3000),
    'ttfb': (800, 1800),
  };
  final t = thresholds[metric];
  if (t == null) return VitalRating.unknown;
  if (value <= t.$1) return VitalRating.good;
  if (value <= t.$2) return VitalRating.needsImprovement;
  return VitalRating.poor;
}

String formatBytes(Object? bytes) {
  if (bytes is! num) return '–';
  final b = bytes.toInt();
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class PerformancePage extends ConsumerWidget {
  const PerformancePage({super.key});

  void _refresh(WidgetRef ref) {
    ref.read(webViewControllerProvider)?.runJavaScript(
        'if (window.__dbg && window.__dbg.collectVitals) window.__dbg.collectVitals();');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(devicePerformanceProvider)['performance'] as Map<String, dynamic>?;
    final data = ref.watch(pageDataProvider)['vitals'];
    final vitals = data?['vitals'] as Map?;
    final resources = data?['resources'] as Map?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => _refresh(ref)),
        ],
      ),
      body: (vitals == null && (perf == null || perf.isEmpty))
          ? const Center(child: Text('Load a page to collect performance data'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (vitals != null) ...[
                  const _Section('Core Web Vitals'),
                  _VitalsGrid(vitals: vitals),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      'INP is approximated from the slowest interaction so far. Interact with the page, then refresh.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
                if (perf != null && perf.isNotEmpty) ...[
                  const _Section('Load timing'),
                  _MetricRow('Page load', '${perf['pageLoadTime']} ms'),
                  _MetricRow('DOM processing', '${perf['domLoadTime']} ms'),
                  _MetricRow('First paint', '${(perf['firstPaint'] as num?)?.round() ?? '–'} ms'),
                  if (perf['memory'] is Map && (perf['memory'] as Map).isNotEmpty) ...[
                    const _Section('JS heap'),
                    _MetricRow('Used', formatBytes(perf['memory']['usedJSHeapSize'])),
                    _MetricRow('Total', formatBytes(perf['memory']['totalJSHeapSize'])),
                    _MetricRow('Limit', formatBytes(perf['memory']['jsHeapSizeLimit'])),
                  ],
                ],
                if (resources != null) ...[
                  _Section('Resources (${resources['count']} • ${formatBytes(resources['totalBytes'])})'),
                  if (resources['byType'] is Map)
                    for (final e in (resources['byType'] as Map).entries)
                      _MetricRow('${e.key}', '${e.value['count']} • ${formatBytes(e.value['bytes'])}'),
                  const _Section('Slowest resources'),
                  for (final r in (resources['slowest'] as List? ?? const []))
                    _ResourceBar(
                      name: '${r['name']}',
                      type: '${r['type']}',
                      start: (r['start'] as num?) ?? 0,
                      duration: (r['duration'] as num?) ?? 0,
                      maxEnd: (resources['slowest'] as List)
                          .map((x) => ((x['start'] as num?) ?? 0) + ((x['duration'] as num?) ?? 0))
                          .fold<num>(1, (a, b) => a > b ? a : b),
                      bytes: r['bytes'],
                    ),
                ],
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetricRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      );
}

class _VitalsGrid extends StatelessWidget {
  final Map vitals;
  const _VitalsGrid({required this.vitals});

  static const _metrics = [
    ('lcp', 'LCP', 'Largest Contentful Paint'),
    ('inp', 'INP', 'Interaction to Next Paint'),
    ('cls', 'CLS', 'Cumulative Layout Shift'),
    ('fcp', 'FCP', 'First Contentful Paint'),
    ('ttfb', 'TTFB', 'Time to First Byte'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, short, long) in _metrics) _VitalCard(
          short: short,
          long: long,
          value: vitals[key] as num?,
          unit: key == 'cls' ? '' : ' ms',
          rating: rateVital(key, vitals[key] as num?),
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  final String short;
  final String long;
  final num? value;
  final String unit;
  final VitalRating rating;
  const _VitalCard({required this.short, required this.long, required this.value, required this.unit, required this.rating});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (rating) {
      VitalRating.good => (Colors.green, 'Good'),
      VitalRating.needsImprovement => (Colors.orange, 'Needs work'),
      VitalRating.poor => (Colors.red, 'Poor'),
      VitalRating.unknown => (Colors.grey, 'No data'),
    };
    return Tooltip(
      message: long,
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(short, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value == null ? '–' : '$value$unit',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// One row of a mini waterfall: bar offset = start, width = duration.
class _ResourceBar extends StatelessWidget {
  final String name;
  final String type;
  final num start;
  final num duration;
  final num maxEnd;
  final Object? bytes;
  const _ResourceBar({
    required this.name,
    required this.type,
    required this.start,
    required this.duration,
    required this.maxEnd,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(name);
    final short = (uri != null && uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty)
        ? uri.pathSegments.last
        : name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Tooltip(
                message: name,
                child: Text(short, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
            ),
            Text('$type • ${duration.round()} ms • ${formatBytes(bytes)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 3),
          LayoutBuilder(builder: (context, box) {
            final maxLeft = box.maxWidth > 2 ? box.maxWidth - 2 : 0.0;
            final double left = (box.maxWidth * (start / maxEnd)).clamp(0.0, maxLeft).toDouble();
            final room = box.maxWidth - left;
            final double width =
                (box.maxWidth * (duration / maxEnd)).clamp(2.0, room < 2 ? 2.0 : room).toDouble();
            return SizedBox(
              height: 6,
              child: Stack(children: [
                Positioned(
                  left: left,
                  width: width.toDouble(),
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}
