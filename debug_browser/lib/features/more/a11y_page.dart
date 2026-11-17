import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';

const _severityOrder = ['critical', 'serious', 'moderate', 'minor'];

Color severityColor(String s) => switch (s) {
      'critical' => Colors.red,
      'serious' => Colors.deepOrange,
      'moderate' => Colors.amber.shade700,
      _ => Colors.blueGrey,
    };

class A11yPage extends ConsumerStatefulWidget {
  const A11yPage({super.key});

  @override
  ConsumerState<A11yPage> createState() => _A11yPageState();
}

class _A11yPageState extends ConsumerState<A11yPage> {
  String? _severity; // null = all
  bool _running = false;

  Future<void> _run() async {
    final c = ref.read(webViewControllerProvider);
    if (c == null) return;
    setState(() => _running = true);
    await c.runJavaScript('window.__dbg && window.__dbg.a11yAudit()');
    // Result arrives asynchronously via the bridge.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _running = false);
  }

  void _highlight(String path) {
    if (path.isEmpty) return;
    ref.read(webViewControllerProvider)?.runJavaScript('window.__dbg && window.__dbg.select(${jsString(path)})');
    ref.read(homeTabProvider.notifier).select(AppTab.browser);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(pageDataProvider)['a11y'];
    final issues = ((report?['issues'] as List?) ?? const []).whereType<Map>().toList()
      ..sort((a, b) => _severityOrder.indexOf('${a['severity']}').compareTo(_severityOrder.indexOf('${b['severity']}')));
    final counts = (report?['counts'] as Map?) ?? const {};
    final visible = _severity == null ? issues : issues.where((i) => i['severity'] == _severity).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessibility audit'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'Copy report',
              icon: const Icon(Icons.copy_all),
              onPressed: () {
                final text = [
                  'Accessibility audit: ${report['url']}',
                  for (final i in issues) '- [${i['severity']}] ${i['rule']}: ${i['message']} (${i['element']})',
                ].join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied')));
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _running ? null : _run,
        icon: _running
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
        label: Text(report == null ? 'Run audit' : 'Re-run'),
      ),
      body: report == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Checks the current page for common WCAG problems: missing alt text and labels, '
                  'low colour contrast, small tap targets, heading order, zoom blocking and more.\n\n'
                  'Automated checks catch roughly a third of issues; manual testing is still needed.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('All ${issues.length}'),
                          selected: _severity == null,
                          onSelected: (_) => setState(() => _severity = null),
                        ),
                      ),
                      for (final s in _severityOrder)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: CircleAvatar(backgroundColor: severityColor(s), radius: 5),
                            label: Text('$s ${counts[s] ?? 0}'),
                            selected: _severity == s,
                            onSelected: (_) => setState(() => _severity = s),
                          ),
                        ),
                    ],
                  ),
                ),
                if (report['truncated'] == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Showing the first 300 issues.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 48),
                            const SizedBox(height: 8),
                            Text(issues.isEmpty ? 'No automated issues found' : 'No issues at this severity'),
                          ]),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final issue = visible[i];
                            final sev = '${issue['severity']}';
                            final path = '${issue['path'] ?? ''}';
                            final element = '${issue['element'] ?? ''}';
                            return ListTile(
                              leading: Icon(Icons.circle, size: 12, color: severityColor(sev)),
                              minLeadingWidth: 12,
                              title: Text('${issue['message']}'),
                              subtitle: Text(
                                [issue['rule'], if (element.isNotEmpty) element].join(' • '),
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              ),
                              trailing: path.isEmpty && element.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Show in page',
                                      icon: const Icon(Icons.my_location),
                                      onPressed: () => _highlight(path),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
