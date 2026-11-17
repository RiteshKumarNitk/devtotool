import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/tool_providers.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _query = '';

  void _open(String url) {
    if (openInBrowser(ref, url)) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final entries = ref
        .watch(historyProvider)
        .reversed
        .where((e) => q.isEmpty || '${e['url']} ${e['title']}'.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear all history?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) ref.read(historyProvider.notifier).clear();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search history',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('No history'))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final time = DateTime.tryParse(e['time'] ?? '');
                      final title = (e['title'] ?? '').isEmpty ? e['url']! : e['title']!;
                      return ListTile(
                        leading: const Icon(Icons.public),
                        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(e['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: time == null
                            ? null
                            : Text(DateFormat('d MMM HH:mm').format(time), style: const TextStyle(fontSize: 11)),
                        onTap: () => _open(e['url'] ?? ''),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
