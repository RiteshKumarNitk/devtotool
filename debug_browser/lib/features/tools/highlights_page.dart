import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/favicons.dart';
import '../../core/highlights.dart';
import '../../core/tool_providers.dart';

const highlightSwatches = {
  'yellow': Color(0xFFFFF176),
  'green': Color(0xFFA5D6A7),
  'pink': Color(0xFFF8BBD0),
  'blue': Color(0xFF90CAF9),
};

/// Note editor shared by the page sheet and this list.
Future<String?> editHighlightNote(BuildContext context, Highlight h) async {
  final c = TextEditingController(text: h.note);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Note'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('"${h.text.length > 140 ? '${h.text.substring(0, 140)}…' : h.text}"',
            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(controller: c, autofocus: true, maxLines: 5, minLines: 2, decoration: const InputDecoration(hintText: 'Write a note', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
      ],
    ),
  );
  c.dispose();
  return r;
}

class HighlightsPage extends ConsumerStatefulWidget {
  const HighlightsPage({super.key});

  @override
  ConsumerState<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends ConsumerState<HighlightsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = ref.watch(highlightsProvider);
    final list = q.isEmpty
        ? all
        : all.where((h) => '${h.text} ${h.note} ${h.title} ${h.url}'.toLowerCase().contains(q)).toList();
    final byPage = <String, List<Highlight>>{};
    for (final h in list) {
      byPage.putIfAbsent(highlightPageKey(h.url), () => []).add(h);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Highlights & notes')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(isDense: true, hintText: 'Search highlights and notes', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: all.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Select text on any page and tap "Highlight". Highlights come back when you revisit the page. '
                      'They are stored only on this phone (never for private tabs).',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(children: [
                  for (final entry in byPage.entries) ...[
                    ListTile(
                      dense: true,
                      leading: SiteIcon(url: entry.key, size: 22),
                      title: Text(entry.value.first.title.isEmpty ? entry.key : entry.value.first.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(Uri.tryParse(entry.key)?.host ?? '', maxLines: 1),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () {
                        if (openInBrowser(ref, entry.key)) Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                    ),
                    for (final h in entry.value)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: highlightSwatches[h.color] ?? Colors.yellow, width: 4)),
                          ),
                          padding: const EdgeInsets.only(left: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(h.text, maxLines: 6, overflow: TextOverflow.ellipsis),
                                if (h.note.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('📝 ${h.note}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                  ),
                                Text(DateFormat('d MMM yyyy').format(h.created), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ]),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                final n = ref.read(highlightsProvider.notifier);
                                if (v == 'note') {
                                  final note = await editHighlightNote(context, h);
                                  if (note != null) n.update(h.id, (x) => x.copyWith(note: note.trim()));
                                } else if (v == 'copy') {
                                  Clipboard.setData(ClipboardData(text: h.note.isEmpty ? h.text : '${h.text}\n\nNote: ${h.note}'));
                                } else if (v == 'delete') {
                                  n.remove(h.id);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'note', child: Text(h.note.isEmpty ? 'Add note' : 'Edit note')),
                                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ]),
                        ),
                      ),
                    const Divider(),
                  ],
                ]),
        ),
      ]),
    );
  }
}
