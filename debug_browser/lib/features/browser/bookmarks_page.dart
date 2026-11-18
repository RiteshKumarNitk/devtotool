import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bookmarks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No bookmarks yet. Tap ☆ in the menu to bookmark a page.', textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              itemCount: bookmarks.length,
              itemBuilder: (context, i) {
                final b = bookmarks[i];
                final url = b['url'] ?? '';
                return ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(b['title'] ?? url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    if (openInBrowser(ref, url)) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'new_tab') {
                        ref.read(tabsProvider.notifier).newTab(url: url);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      } else if (v == 'delete') {
                        ref.read(bookmarksProvider.notifier).removeBookmark(url);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'new_tab', child: Text('Open in new tab')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
