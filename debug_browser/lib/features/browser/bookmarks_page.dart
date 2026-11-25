import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/favicons.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';

Future<String?> askText(BuildContext context, {required String title, String initial = '', String hint = ''}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
      ],
    ),
  );
  c.dispose();
  return (r == null || r.trim().isEmpty) ? null : r.trim();
}

/// Bookmarks with folders. [folder] null = top level.
class BookmarksPage extends ConsumerWidget {
  final String? folder;
  const BookmarksPage({super.key, this.folder});

  void _openHere(BuildContext context, WidgetRef ref, String url) {
    if (openInBrowser(ref, url)) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _moveTo(BuildContext context, WidgetRef ref, Map<String, String> b) async {
    final n = ref.read(bookmarksProvider.notifier);
    final folders = n.folders;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Move to folder', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.vertical_align_top), title: const Text('Top level'), onTap: () => Navigator.pop(c, '')),
          for (final f in folders)
            ListTile(leading: const Icon(Icons.folder_outlined), title: Text(f), onTap: () => Navigator.pop(c, f)),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder…'),
            onTap: () async {
              final name = await askText(c, title: 'New folder', hint: 'e.g. Work');
              if (c.mounted) Navigator.pop(c, name);
            },
          ),
        ]),
      ),
    );
    if (choice == null) return;
    n.moveToFolder(b['url'] ?? '', choice.isEmpty ? null : choice);
  }

  void _bookmarkMenu(BuildContext context, WidgetRef ref, Map<String, String> b) {
    final url = b['url'] ?? '';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(b['title'] ?? url, maxLines: 2), subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open in new tab'),
            onTap: () {
              Navigator.pop(c);
              ref.read(tabsProvider.notifier).newTab(url: url);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Open in private tab'),
            onTap: () {
              Navigator.pop(c);
              ref.read(tabsProvider.notifier).newTab(url: url, private: true);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to folder'),
            onTap: () {
              Navigator.pop(c);
              _moveTo(context, ref, b);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(c);
              final name = await askText(context, title: 'Rename bookmark', initial: b['title'] ?? '');
              if (name != null) ref.read(bookmarksProvider.notifier).renameBookmark(url, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Copy link'),
            onTap: () {
              Navigator.pop(c);
              Clipboard.setData(ClipboardData(text: url));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(c);
              ref.read(bookmarksProvider.notifier).removeBookmark(url);
            },
          ),
        ]),
      ),
    );
  }

  void _folderMenu(BuildContext context, WidgetRef ref, String f) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(f, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename folder'),
            onTap: () async {
              Navigator.pop(c);
              final name = await askText(context, title: 'Rename folder', initial: f);
              if (name != null) ref.read(bookmarksProvider.notifier).renameFolder(f, name);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_delete_outlined),
            title: const Text('Delete folder'),
            subtitle: const Text('Its bookmarks move to the top level'),
            onTap: () {
              Navigator.pop(c);
              ref.read(bookmarksProvider.notifier).deleteFolder(f);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(bookmarksProvider);
    final folders = folder == null ? ref.read(bookmarksProvider.notifier).folders : const <String>[];
    final items = all.where((b) => (b['folder'] ?? '') == (folder ?? '')).toList();

    return Scaffold(
      appBar: AppBar(title: Text(folder ?? 'Bookmarks')),
      body: (items.isEmpty && folders.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  folder == null
                      ? 'No bookmarks yet. Tap ☆ in the menu to bookmark a page.'
                      : 'This folder is empty. Long-press a bookmark and choose "Move to folder".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(children: [
              for (final f in folders)
                ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: Text(f),
                  subtitle: Text('${all.where((b) => b['folder'] == f).length} bookmarks'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookmarksPage(folder: f))),
                  onLongPress: () => _folderMenu(context, ref, f),
                  trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _folderMenu(context, ref, f)),
                ),
              for (final b in items)
                ListTile(
                  leading: SiteIcon(url: b['url'] ?? '', size: 28),
                  title: Text(b['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(b['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _openHere(context, ref, b['url'] ?? ''),
                  onLongPress: () => _bookmarkMenu(context, ref, b),
                  trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _bookmarkMenu(context, ref, b)),
                ),
            ]),
      floatingActionButton: folder == null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final name = await askText(context, title: 'New folder', hint: 'e.g. Work');
                if (name == null || !context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Folder "$name" appears once a bookmark is moved into it')),
                );
                // Folders exist through their bookmarks: open it so the user sees where things go.
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookmarksPage(folder: name)));
              },
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New folder'),
            )
          : null,
    );
  }
}
