import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/js_bridge.dart';
import '../../core/tool_providers.dart';

/// Swaps the scheme+host+port of [current] for [base]'s, keeping path/query.
/// Lets you jump from prod `/checkout?x=1` to the same page on staging.
String switchEnvironment(String current, String base) {
  final cur = Uri.tryParse(current);
  final target = normaliseUrlInput(base);
  if (cur == null || !cur.hasScheme || cur.host.isEmpty) return target.toString();
  return target
      .replace(path: cur.path, query: cur.hasQuery ? cur.query : null, fragment: cur.hasFragment ? cur.fragment : null)
      .toString();
}

class EnvironmentsPage extends ConsumerWidget {
  const EnvironmentsPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {int? index, Map<String, String>? initial}) async {
    final name = TextEditingController(text: initial?['name'] ?? '');
    final url = TextEditingController(text: initial?['url'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(index == null ? 'Add environment' : 'Edit environment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. Staging)')),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Base URL (e.g. https://staging.example.com)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || url.text.trim().isEmpty) return;
              Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(environmentsProvider.notifier).save(name.text, url.text, index: index);
    name.dispose();
    url.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envs = ref.watch(environmentsProvider);
    final current = ref.watch(currentPageProvider).url;

    void go(String url) {
      if (openInBrowser(ref, url)) Navigator.of(context).popUntil((r) => r.isFirst);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Environments')),
      body: envs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Save your dev, staging and production URLs, then jump between them, '
                  'optionally keeping the current path.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: envs.length,
              itemBuilder: (context, i) {
                final e = envs[i];
                return ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(e['name'] ?? ''),
                  subtitle: Text(e['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => go(normaliseUrlInput(e['url'] ?? '').toString()),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'same':
                          go(switchEnvironment(current, e['url'] ?? ''));
                        case 'edit':
                          _edit(context, ref, index: i, initial: e);
                        case 'delete':
                          ref.read(environmentsProvider.notifier).removeAt(i);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'same',
                        enabled: current.isNotEmpty,
                        child: const Text('Open current path here'),
                      ),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add environment',
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
