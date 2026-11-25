import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/tabs_provider.dart';
import '../../core/favicons.dart';
import '../../core/tool_providers.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _query = '';

  void _open(String url, {bool newTab = false, bool private = false}) {
    if (newTab || private) {
      ref.read(tabsProvider.notifier).newTab(url: url, private: private);
      ref.read(homeTabProvider.notifier).select(AppTab.browser);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (openInBrowser(ref, url)) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _clear() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Clear history', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.schedule), title: const Text('Last hour'), onTap: () => Navigator.pop(c, 'hour')),
          ListTile(leading: const Icon(Icons.today), title: const Text('Today'), onTap: () => Navigator.pop(c, 'today')),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Theme.of(c).colorScheme.error),
            title: const Text('All time'),
            onTap: () => Navigator.pop(c, 'all'),
          ),
        ]),
      ),
    );
    final h = ref.read(historyProvider.notifier);
    switch (choice) {
      case 'hour':
        h.clearSince(DateTime.now().subtract(const Duration(hours: 1)));
      case 'today':
        h.clearSince(DateUtils.dateOnly(DateTime.now()));
      case 'all':
        h.clear();
    }
  }

  void _entryMenu(Map<String, String> e) {
    final url = e['url'] ?? '';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(e['title']?.isNotEmpty == true ? e['title']! : url, maxLines: 2), subtitle: Text(url, maxLines: 1)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open in new tab'),
            onTap: () {
              Navigator.pop(c);
              _open(url, newTab: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Open in private tab'),
            onTap: () {
              Navigator.pop(c);
              _open(url, private: true);
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
            title: const Text('Delete from history'),
            onTap: () {
              Navigator.pop(c);
              ref.read(historyProvider.notifier).remove(e);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = ref.watch(historyProvider);
    final filtered = q.isEmpty
        ? all
        : all.where((e) => '${e['url']} ${e['title']}'.toLowerCase().contains(q)).toList();
    final groups = groupHistoryByDay(filtered, formatDay: (d) => DateFormat('EEEE, d MMMM y').format(d));

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(tooltip: 'Clear history', icon: const Icon(Icons.delete_sweep), onPressed: all.isEmpty ? null : _clear),
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
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        all.isEmpty
                            ? 'Pages you visit appear here. Private tabs are never saved.'
                            : 'No matches',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final (label, entries) in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(label,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  )),
                        ),
                        for (final e in entries)
                          Dismissible(
                            key: ValueKey('${e['url']}|${e['time']}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Theme.of(context).colorScheme.errorContainer,
                              child: const Icon(Icons.delete_outline),
                            ),
                            onDismissed: (_) => ref.read(historyProvider.notifier).remove(e),
                            child: ListTile(
                              leading: SiteIcon(url: e['url'] ?? '', size: 28),
                              title: Text((e['title'] ?? '').isEmpty ? e['url']! : e['title']!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(Uri.tryParse(e['url'] ?? '')?.host ?? '',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text(_time(e['time']), style: const TextStyle(fontSize: 12)),
                              onTap: () => _open(e['url'] ?? ''),
                              onLongPress: () => _entryMenu(e),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }


  static String _time(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    return t == null ? '' : DateFormat('HH:mm').format(t);
  }
}
