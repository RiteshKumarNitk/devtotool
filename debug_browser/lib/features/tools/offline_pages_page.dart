import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/favicons.dart';
import '../../core/home_stats.dart';
import '../../core/page_tools.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';

class OfflinePagesPage extends ConsumerWidget {
  const OfflinePagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(offlinePagesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offline pages')),
      body: pages.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Save any page with ⋮ → Save for offline to read it later without internet.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final p = pages[i];
                return ListTile(
                  leading: SiteIcon(url: p.url, size: 28),
                  title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${Uri.tryParse(p.url)?.host ?? ''} • ${formatBytesShort(p.size)} • '
                    '${DateFormat('d MMM, HH:mm').format(p.savedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    ref.read(tabsProvider.notifier).newTab(url: Uri.file(p.path).toString());
                    ref.read(homeTabProvider.notifier).select(AppTab.browser);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'live') {
                        ref.read(tabsProvider.notifier).newTab(url: p.url);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      } else if (v == 'delete') {
                        ref.read(offlinePagesProvider.notifier).remove(p);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'live', child: Text('Open live version')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
