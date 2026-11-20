import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search_shortcuts.dart';

class SearchShortcutsPage extends ConsumerWidget {
  const SearchShortcutsPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [SearchShortcut? s]) async {
    final kw = TextEditingController(text: s?.keyword ?? '');
    final name = TextEditingController(text: s?.name ?? '');
    final tpl = TextEditingController(text: s?.template ?? 'https://');
    String? error;
    final saved = await showDialog<SearchShortcut>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(s == null ? 'New shortcut' : 'Edit shortcut'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: kw, decoration: const InputDecoration(labelText: 'Keyword', hintText: 'e.g. w')),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Wikipedia')),
              TextField(
                controller: tpl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Search URL', helperText: 'Use %s where the search words go'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(d).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = SearchShortcut.fromJson({'keyword': kw.text, 'name': name.text, 'template': tpl.text});
                if (parsed == null) {
                  set(() => error = 'Keyword must be one word, and the URL must start with http and contain %s');
                  return;
                }
                Navigator.pop(d, parsed);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in [kw, name, tpl]) {
      c.dispose();
    }
    if (saved != null) ref.read(searchShortcutsProvider.notifier).save(saved, replacing: s?.keyword);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(searchShortcutsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search shortcuts'),
        actions: [
          TextButton(onPressed: () => ref.read(searchShortcutsProvider.notifier).reset(), child: const Text('Reset')),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, ref), child: const Icon(Icons.add)),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Type a keyword, a space and your search in the address bar, e.g. "w taj mahal".',
              style: TextStyle(color: Colors.grey)),
        ),
        for (final s in list)
          ListTile(
            leading: CircleAvatar(radius: 18, child: Text(s.keyword, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
            title: Text(s.name),
            subtitle: Text(s.template, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _edit(context, ref, s),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(searchShortcutsProvider.notifier).remove(s.keyword),
            ),
          ),
      ]),
    );
  }
}
