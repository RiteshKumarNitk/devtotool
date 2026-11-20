import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/backup.dart' show ProviderReader;
import '../../core/favicons.dart';
import '../../core/tabs_provider.dart';

/// Closes a tab and offers "Undo" (never for private tabs: nothing of them is
/// kept once closed).
void closeTabWithUndo(BuildContext context, ProviderReader read, String id) {
  final tabs = read(tabsProvider);
  final i = tabs.tabs.indexWhere((t) => t.id == id);
  if (i < 0) return;
  final tab = tabs.tabs[i];
  HapticFeedback.lightImpact();
  read(tabsProvider.notifier).closeTab(id);
  final closed = read(recentlyClosedProvider);
  final undoable = closed.isNotEmpty && closed.first.url == tab.url && !tab.isPrivate;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text(
        tab.isPrivate ? 'Private tab closed' : 'Closed "${tab.displayTitle}"',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      action: undoable
          ? SnackBarAction(
              label: 'Undo',
              onPressed: () {
                final again = read(recentlyClosedProvider);
                if (again.isNotEmpty && again.first.url == tab.url) {
                  read(tabsProvider.notifier).reopenClosed(again.first);
                }
              },
            )
          : null,
    ));
}

/// Sheet listing tabs closed in this session; tap one to reopen it.
Future<void> showRecentlyClosed(BuildContext context, ProviderReader read, {VoidCallback? onReopened}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => Consumer(builder: (c, ref, _) {
      final list = ref.watch(recentlyClosedProvider);
      final time = DateFormat.jm();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text('Recently closed', style: Theme.of(c).textTheme.titleMedium),
              trailing: list.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => ref.read(recentlyClosedProvider.notifier).clear(),
                      child: const Text('Clear'),
                    ),
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text('Tabs you close appear here until you leave the app. Private tabs never do.',
                    textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final t in list)
                    ListTile(
                      leading: SiteIcon(url: t.url, size: 24),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${Uri.tryParse(t.url)?.host ?? t.url} · ${time.format(t.closedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(c);
                        read(tabsProvider.notifier).reopenClosed(t);
                        onReopened?.call();
                      },
                    ),
                ]),
              ),
          ]),
        ),
      );
    }),
  );
}

/// Long-press on the tabs button: the common tab actions without opening
/// the switcher, like Chrome.
Future<void> showTabsQuickMenu(BuildContext context, ProviderReader read) {
  HapticFeedback.mediumImpact();
  final tabs = read(tabsProvider.notifier);
  final active = read(tabsProvider).active;
  final hasClosed = read(recentlyClosedProvider).isNotEmpty;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.add_box_outlined),
          title: const Text('New tab'),
          onTap: () {
            Navigator.pop(c);
            tabs.newTab();
          },
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('New private tab'),
          onTap: () {
            Navigator.pop(c);
            tabs.newTab(private: true);
          },
        ),
        if (hasClosed)
          ListTile(
            leading: const Icon(Icons.restore_page_outlined),
            title: const Text('Reopen closed tab'),
            subtitle: Text(read(recentlyClosedProvider).first.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(c);
              tabs.reopenClosed();
            },
          ),
        ListTile(
          leading: const Icon(Icons.close),
          title: const Text('Close this tab'),
          subtitle: Text(active.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.pop(c);
            closeTabWithUndo(context, read, active.id);
          },
        ),
      ]),
    ),
  );
}
