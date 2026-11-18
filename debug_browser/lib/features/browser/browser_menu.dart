import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/browser_settings.dart';
import '../../core/downloads.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';
import '../more/history_page.dart';
import '../settings/proxy_page.dart';
import '../settings/settings_page.dart';
import 'bookmarks_page.dart';
import 'downloads_page.dart';

/// Chrome-style overflow menu. Developer tools live here, not in the footer.
void showBrowserMenu(BuildContext context, WidgetRef ref, {required VoidCallback onFind}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => Consumer(builder: (sheet, ref, _) {
      final tab = ref.watch(tabsProvider).active;
      final tabs = ref.read(tabsProvider.notifier);
      final settings = ref.watch(browserSettingsProvider);
      final bookmarked = ref.watch(bookmarksProvider).any((b) => b['url'] == tab.url);
      final errors = ref.watch(consoleLogsProvider.select((l) => l.where((x) => x.level == 'error').length));
      final nav = Navigator.of(context);
      final running = ref.watch(downloadsProvider.select((l) => l.where((d) => d.status == DownloadStatus.running).length));

      void close() => Navigator.pop(sheet);
      void push(Widget page) {
        close();
        nav.push(MaterialPageRoute(builder: (_) => page));
      }

      void snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Quick actions row, like Chrome's icon strip.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Quick(
                      icon: Icons.add_box_outlined,
                      label: 'New tab',
                      onTap: () {
                        close();
                        tabs.newTab();
                      },
                    ),
                    _Quick(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Private tab',
                      onTap: () {
                        close();
                        tabs.newTab(private: true);
                      },
                    ),
                    _Quick(
                      icon: bookmarked ? Icons.star : Icons.star_border,
                      label: bookmarked ? 'Bookmarked' : 'Bookmark',
                      color: bookmarked ? Colors.amber : null,
                      onTap: () {
                        final b = ref.read(bookmarksProvider.notifier);
                        if (bookmarked) {
                          b.removeBookmark(tab.url);
                        } else {
                          b.addBookmark(tab.displayTitle, tab.url);
                        }
                      },
                    ),
                    _Quick(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () {
                        close();
                        SharePlus.instance.share(ShareParams(uri: Uri.parse(tab.url), subject: tab.displayTitle));
                      },
                    ),
                    _Quick(
                      icon: Icons.refresh,
                      label: 'Reload',
                      onTap: () {
                        close();
                        tabs.reload();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('History'),
                onTap: () => push(const HistoryPage()),
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('Bookmarks'),
                onTap: () => push(const BookmarksPage()),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Downloads'),
                trailing: running > 0 ? Badge(label: Text('$running')) : null,
                onTap: () => push(const DownloadsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.find_in_page_outlined),
                title: const Text('Find in page'),
                onTap: () {
                  close();
                  onFind();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.desktop_windows_outlined),
                title: const Text('Desktop site'),
                value: settings.desktopMode,
                onChanged: (v) => ref.read(browserSettingsProvider.notifier).update((s) => s.copyWith(desktopMode: v)),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copy link'),
                onTap: () {
                  close();
                  Clipboard.setData(ClipboardData(text: tab.url));
                  snack('Link copied');
                },
              ),
              ListTile(
                leading: const Icon(Icons.screenshot_outlined),
                title: const Text('Screenshot'),
                onTap: () async {
                  close();
                  final png = await ref.read(screenshotControllerProvider).capture();
                  if (png == null) {
                    snack('Screenshot failed');
                    return;
                  }
                  final dir = await getTemporaryDirectory();
                  final f = File('${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
                  await f.writeAsBytes(png);
                  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: tab.displayTitle));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.developer_mode, color: Colors.blueAccent),
                title: const Text('Developer tools'),
                subtitle: const Text('Console, network, storage, DOM, performance'),
                trailing: errors > 0
                    ? Badge(label: Text('$errors'), backgroundColor: Colors.redAccent)
                    : const Icon(Icons.chevron_right),
                onTap: () {
                  close();
                  ref.read(homeTabProvider.notifier).select(errors > 0 ? AppTab.console : AppTab.network);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Hard reload'),
                subtitle: const Text('Clear cache, storage and cookies, then reload'),
                onTap: () {
                  close();
                  tabs.hardReload();
                  snack('Cache cleared & reloaded');
                },
              ),
              ListTile(
                leading: Icon(Icons.vpn_lock_outlined,
                    color: ref.watch(proxyStatusProvider) == ProxyStatus.active ? Colors.green : null),
                title: const Text('Proxy / VPN'),
                subtitle: Text(switch (ref.watch(proxyStatusProvider)) {
                  ProxyStatus.active => 'On: ${ref.watch(proxySettingsProvider).host}',
                  ProxyStatus.unsupported => 'Not supported by this WebView',
                  ProxyStatus.failed => 'Could not apply. Check settings',
                  ProxyStatus.off => 'Off',
                }),
                onTap: () => push(const ProxyPage()),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () => push(const SettingsPage()),
              ),
            ],
          ),
        ),
      );
    }),
  );
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _Quick({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}
