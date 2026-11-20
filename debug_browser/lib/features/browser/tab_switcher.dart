import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tabs_provider.dart';
import '../../core/favicons.dart';

/// Grid of open tabs with Chrome-style "Tabs" / "Private" sections.
class TabSwitcherPage extends ConsumerStatefulWidget {
  const TabSwitcherPage({super.key});

  @override
  ConsumerState<TabSwitcherPage> createState() => _TabSwitcherPageState();
}

class _TabSwitcherPageState extends ConsumerState<TabSwitcherPage> {
  late bool _private = ref.read(tabsProvider).active.isPrivate;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tabsProvider);
    final shown = all.tabs.where((t) => t.isPrivate == _private).toList();
    final state = TabsState(shown, all.activeId);
    final privateCount = all.tabs.where((t) => t.isPrivate).length;
    final normalCount = all.tabs.length - privateCount;
    final thumbs = ref.watch(tabThumbnailsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.tab),
              label: Text('$normalCount'),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text('$privateCount'),
            ),
          ],
          selected: {_private},
          onSelectionChanged: (s) => setState(() => _private = s.first),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'close_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(
                      _private ? 'Close all private tabs?' : 'Close all tabs?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Close all'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  if (_private) {
                    tabs.closePrivateTabs();
                  } else {
                    tabs.closeAll();
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'close_all', child: Text('Close all')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          tabs.newTab(private: _private);
          Navigator.pop(context);
        },
        icon: const Icon(Icons.add),
        label: Text(_private ? 'New private tab' : 'New tab'),
      ),
      body: shown.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _private
                      ? "Private tabs don't save history, and their cookies and site data "
                            'are deleted when you close the last private tab. Downloads and '
                            'bookmarks are kept.'
                      : 'No open tabs',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : GridView.builder(
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
                          border: Border.all(
                            color: active ? scheme.primary : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                              child: Row(
                                children: [
                                  if (t.isNewTab)
                                    Icon(
                                      t.isPrivate ? Icons.privacy_tip_outlined : Icons.home_outlined,
                                      size: 16,
                                    )
                                  else
                                    SiteIcon(url: t.url, size: 16, radius: 3),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      t.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close tab',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => tabs.closeTab(t.id),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: thumbs[t.id] != null
                                  ? Image.memory(
                                      thumbs[t.id]!,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.medium,
                                    )
                                  : Container(
                                      color: scheme.surface,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor:
                                                scheme.primaryContainer,
                                            child: Text(
                                              host
                                                      .replaceFirst('www.', '')
                                                      .isEmpty
                                                  ? '?'
                                                  : host
                                                        .replaceFirst(
                                                          'www.',
                                                          '',
                                                        )[0]
                                                        .toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 20,
                                                color:
                                                    scheme.onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            host,
                                            maxLines: 2,
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          if (!t.loaded)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 6),
                                              child: Text(
                                                'Not loaded',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
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
