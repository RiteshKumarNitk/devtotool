import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class PerformancePage extends ConsumerWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(devicePerformanceProvider);
    final perf = info['performance'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Inspector'),
      ),
      body: perf == null || perf.isEmpty
          ? const Center(child: Text('Waiting for performance data...'))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text('Timing Metrics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                const SizedBox(height: 8),
                _buildMetricCard(context, 'Page Load Time', "\${perf['pageLoadTime']} ms"),
                _buildMetricCard(context, 'DOM Load Time', "\${perf['domLoadTime']} ms"),
                _buildMetricCard(context, 'First Paint', "\${perf['firstPaint']} ms"),
                _buildMetricCard(context, 'First Contentful Paint', "\${perf['firstContentfulPaint']} ms"),
                
                const SizedBox(height: 24),
                const Text('Memory Usage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                const SizedBox(height: 8),
                if (perf['memory'] != null && (perf['memory'] as Map).isNotEmpty)
                  ...[
                    _buildMetricCard(context, 'JS Heap Size Limit', _formatBytes(perf['memory']['jsHeapSizeLimit'])),
                    _buildMetricCard(context, 'Total JS Heap Size', _formatBytes(perf['memory']['totalJSHeapSize'])),
                    _buildMetricCard(context, 'Used JS Heap Size', _formatBytes(perf['memory']['usedJSHeapSize'])),
                  ]
                else
                  const Card(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Memory metrics not supported by this browser.'))),
              ],
            ),
    );
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return 'Unknown';
    final b = (bytes is int) ? bytes : (bytes as double).toInt();
    if (b < 1024) return '\$b B';
    if (b < 1024 * 1024) return '\${(b / 1024).toStringAsFixed(2)} KB';
    return '\${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Widget _buildMetricCard(BuildContext context, String title, String value) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}
