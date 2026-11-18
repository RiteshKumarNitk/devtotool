import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tabs_provider.dart';

/// Grid of open tabs, like Chrome's tab switcher.
class TabSwitcherPage extends ConsumerWidget {
  const TabSwitcherPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${state.tabs.length} tab${state.tabs.length == 1 ? '' : 's'}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'close_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Close all tabs?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close all')),
                    ],
                  ),
                );
                if (ok == true) {
                  tabs.closeAll();
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'close_all', child: Text('Close all tabs'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          tabs.newTab();
          Navigator.pop(context);
        },
        icon: const Icon(Icons.add),
        label: const Text('New tab'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: state.tabs.length,
        itemBuilder: (context, i) {
          final t = state.tabs[i];
          final active = t.id == state.activeId;
          final host = Uri.tryParse(t.url)?.host ?? '';
          return Dismissible(
            key: ValueKey(t.id),
            onDismissed: (_) => tabs.closeTab(t.id),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  tabs.activate(t.id);
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? scheme.primary : Colors.transparent, width: 2.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                        child: Row(children: [
                          Icon(t.isSecure ? Icons.lock_outline : Icons.public, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(t.displayTitle,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            tooltip: 'Close tab',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => tabs.closeTab(t.id),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: Container(
                          color: scheme.surface,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(12),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: scheme.primaryContainer,
                              child: Text(
                                host.replaceFirst('www.', '').isEmpty ? '?' : host.replaceFirst('www.', '')[0].toUpperCase(),
                                style: TextStyle(fontSize: 20, color: scheme.onPrimaryContainer),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(host, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            if (!t.loaded)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Not loaded', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
