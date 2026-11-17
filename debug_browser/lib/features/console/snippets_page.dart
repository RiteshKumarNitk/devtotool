import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/tool_providers.dart';

class SnippetsPage extends ConsumerWidget {
  const SnippetsPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {int? index, Map<String, String>? initial}) async {
    final name = TextEditingController(text: initial?['name'] ?? '');
    final code = TextEditingController(text: initial?['code'] ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'New snippet' : 'Edit snippet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                controller: code,
                maxLines: 10,
                minLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'JavaScript',
                  hintText: 'The last expression is shown as the result',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || code.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      ref.read(snippetsProvider.notifier).save(name.text, code.text, index: index);
    }
    name.dispose();
    code.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snippets = ref.watch(snippetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('JS Snippets')),
      body: snippets.isEmpty
          ? const Center(child: Text('No snippets. Tap + to add one.'))
          : ListView.separated(
              itemCount: snippets.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = snippets[i];
                return ListTile(
                  title: Text(s['name'] ?? ''),
                  subtitle: Text(
                    s['code'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  leading: IconButton(
                    tooltip: 'Run in page',
                    icon: const Icon(Icons.play_circle, color: Colors.green),
                    onPressed: () async {
                      await runJsInPage(ref, s['code'] ?? '');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ran "${s['name']}". See Console for the result.')),
                        );
                      }
                    },
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _edit(context, ref, index: i, initial: s);
                      if (v == 'delete') ref.read(snippetsProvider.notifier).removeAt(i);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add snippet',
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
