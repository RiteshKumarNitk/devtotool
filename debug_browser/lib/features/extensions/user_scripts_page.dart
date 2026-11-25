import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
import '../../services/export_service.dart';

/// Starter examples users can add with one tap.
final _examples = <UserScript>[
  UserScript(
    id: 'example-hide-sticky',
    name: 'Hide sticky headers',
    matches: const ['*'],
    css: '',
    js: "document.querySelectorAll('*').forEach(function (el) {\n"
        "  var p = getComputedStyle(el).position;\n"
        "  if ((p === 'fixed' || p === 'sticky') && el.getBoundingClientRect().top < 80) el.style.display = 'none';\n"
        "});",
    enabled: false,
  ),
  UserScript(
    id: 'example-wide-reading',
    name: 'Readable width for long text',
    matches: const ['*'],
    css: 'p, li { max-width: 42rem; line-height: 1.6 !important; }',
    enabled: false,
  ),
  UserScript(
    id: 'example-show-passwords',
    name: 'Show password fields (local testing)',
    matches: const ['http://localhost*', 'http://127.0.0.1*', 'http://10.*', 'http://192.168.*'],
    js: "document.querySelectorAll('input[type=password]').forEach(function (i) { i.type = 'text'; });",
    enabled: false,
  ),
];

class UserScriptsPage extends ConsumerWidget {
  const UserScriptsPage({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: clip?.text ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import user scripts'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(hintText: 'Paste exported JSON', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Import')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    try {
      final decoded = jsonDecode(text);
      final list = (decoded is List ? decoded : [decoded]).map(UserScript.fromJson).whereType<UserScript>().toList();
      final n = ref.read(userScriptsProvider.notifier).importAll(list);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $n script${n == 1 ? '' : 's'}')));
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not valid JSON')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scripts = ref.watch(userScriptsProvider);
    final notifier = ref.read(userScriptsProvider.notifier);
    final missingExamples = _examples.where((e) => !scripts.any((s) => s.id == e.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User scripts'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'import') await _import(context, ref);
              if (v == 'export' && scripts.isNotEmpty) {
                await ExportService.shareJson(scripts.map((s) => s.toJson()).toList(),
                    fileName: 'user_scripts', text: 'Debug Browser user scripts');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('Import')),
              if (scripts.isNotEmpty) const PopupMenuItem(value: 'export', child: Text('Export')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserScriptEditor())),
        icon: const Icon(Icons.add),
        label: const Text('New script'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Scripts run in pages whose address matches one of their patterns, e.g. '
              'https://*.example.com/* . Only add code you understand: scripts can read everything on the pages they run on.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          for (final s in scripts)
            ListTile(
              leading: Switch(value: s.enabled, onChanged: (_) => notifier.toggle(s.id)),
              title: Text(s.name),
              subtitle: Text(
                '${s.matches.join(', ')} • ${s.runAt == 'start' ? 'before page scripts' : 'after load'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserScriptEditor(initial: s))),
              trailing: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => notifier.remove(s.id),
              ),
            ),
          if (missingExamples.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text('Examples', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final e in missingExamples)
              ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(e.name),
                subtitle: Text(e.matches.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: () => notifier.upsert(e), child: const Text('Add')),
              ),
          ],
        ],
      ),
    );
  }
}

class UserScriptEditor extends ConsumerStatefulWidget {
  final UserScript? initial;
  const UserScriptEditor({super.key, this.initial});

  @override
  ConsumerState<UserScriptEditor> createState() => _UserScriptEditorState();
}

class _UserScriptEditorState extends ConsumerState<UserScriptEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _matches = TextEditingController(text: (widget.initial?.matches ?? const ['https://*.example.com/*']).join('\n'));
  late final _js = TextEditingController(text: widget.initial?.js ?? '');
  late final _css = TextEditingController(text: widget.initial?.css ?? '');
  late String _runAt = widget.initial?.runAt ?? 'end';
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _matches, _js, _css]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final matches = _matches.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the script a name');
    if (matches.isEmpty) return setState(() => _error = 'Add at least one address pattern (use * for all sites)');
    if (_js.text.trim().isEmpty && _css.text.trim().isEmpty) return setState(() => _error = 'Add some JavaScript or CSS');
    ref.read(userScriptsProvider.notifier).upsert(UserScript(
          id: widget.initial?.id ?? UserScript.newId(),
          name: _name.text.trim(),
          matches: matches,
          js: _js.text,
          css: _css.text,
          enabled: widget.initial?.enabled ?? true,
          runAt: _runAt,
        ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New user script' : 'Edit user script'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            controller: _matches,
            minLines: 2,
            maxLines: 5,
            style: mono,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Run on (one pattern per line)',
              helperText: '* matches anything, e.g. https://*.example.com/*',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'end', label: Text('After page loads')),
              ButtonSegment(value: 'start', label: Text('Before page scripts')),
            ],
            selected: {_runAt},
            onSelectionChanged: (v) => setState(() => _runAt = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _js,
            minLines: 8,
            maxLines: 24,
            style: mono,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'JavaScript', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _css,
            minLines: 3,
            maxLines: 12,
            style: mono,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'CSS (optional)', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          const Text('Errors in your script are shown in Developer tools → Console.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
