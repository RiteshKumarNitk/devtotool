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
import '../extensions/extensions_page.dart';
import '../more/history_page.dart';
import '../settings/proxy_page.dart';
import '../settings/settings_page.dart';
import 'bookmarks_page.dart';
import 'downloads_page.dart';
import '../../core/page_tools.dart';
import '../../core/read_aloud.dart';
import '../tools/offline_pages_page.dart';
import '../tools/source_viewer_page.dart';
import '../tools/highlights_page.dart';
import 'qr_sheet.dart';
import 'tab_actions.dart';
import '../../core/favicons.dart';

/// Chrome-style overflow menu. Developer tools live here, not in the footer.
void showBrowserMenu(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onFind,
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => Consumer(
      builder: (sheet, ref, _) {
        final tab = ref.watch(tabsProvider).active;
        final tabs = ref.read(tabsProvider.notifier);
        final settings = ref.watch(browserSettingsProvider);
        final bookmarked = ref
            .watch(bookmarksProvider)
            .any((b) => b['url'] == tab.url);
        final errors = ref.watch(
          consoleLogsProvider.select(
            (l) => l.where((x) => x.level == 'error').length,
          ),
        );
        final nav = Navigator.of(context);
        // App-wide reader: stays valid after this sheet closes.
        final read = ProviderScope.containerOf(context, listen: false).read;
        final running = ref.watch(
          downloadsProvider.select(
            (l) => l.where((d) => d.status == DownloadStatus.running).length,
          ),
        );

        void close() => Navigator.pop(sheet);
        void push(Widget page) {
          close();
          nav.push(MaterialPageRoute(builder: (_) => page));
        }

        void snack(String t) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t)));

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!tab.isNewTab)
                  _SiteHeader(
                    tab: tab,
                    onTap: () {
                      close();
                      Clipboard.setData(ClipboardData(text: tab.url));
                      snack('Link copied');
                    },
                  ),
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
                          HapticFeedback.lightImpact();
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
                          SharePlus.instance.share(
                            ShareParams(
                              uri: Uri.parse(tab.url),
                              subject: tab.displayTitle,
                            ),
                          );
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
                  leading: const Icon(Icons.extension_outlined),
                  title: const Text('Extensions'),
                  subtitle: const Text('Ad blocker, dark mode, user scripts'),
                  onTap: () => push(const ExtensionsPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.chrome_reader_mode_outlined),
                  title: const Text('Reader mode'),
                  onTap: () {
                    close();
                    tabs.toggleReaderMode();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('History'),
                  onTap: () => push(const HistoryPage()),
                ),
                if (ref.watch(recentlyClosedProvider).isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.restore_page_outlined),
                    title: const Text('Recently closed'),
                    trailing: Text(
                      '${ref.watch(recentlyClosedProvider).length}',
                    ),
                    onTap: () {
                      close();
                      showRecentlyClosed(context, read);
                    },
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
                  onChanged: (v) => ref
                      .read(browserSettingsProvider.notifier)
                      .update((s) => s.copyWith(desktopMode: v)),
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
                  subtitle: const Text('Visible area or the whole page'),
                  onTap: () async {
                    close();
                    final full = await showModalBottomSheet<bool>(
                      context: context,
                      showDragHandle: true,
                      builder: (c) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.crop_portrait),
                              title: const Text('Visible area'),
                              onTap: () => Navigator.pop(c, false),
                            ),
                            ListTile(
                              leading: const Icon(Icons.vertical_split),
                              title: const Text('Full page'),
                              subtitle: const Text(
                                'Scrolls and stitches the whole page',
                              ),
                              onTap: () => Navigator.pop(c, true),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (full == null) return;
                    if (full) snack('Capturing the full page…');
                    final png = full
                        ? await captureFullPage(read)
                        : await read(screenshotControllerProvider).capture();
                    if (png == null) {
                      snack('Screenshot failed');
                      return;
                    }
                    final dir = await getTemporaryDirectory();
                    final f = File(
                      '${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
                    );
                    await f.writeAsBytes(png);
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(f.path)],
                        text: tab.displayTitle,
                      ),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Page tools',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    children: [
                      _Quick(
                        icon: Icons.translate,
                        label: 'Translate',
                        onTap: () {
                          close();
                          if (tab.isNewTab)
                            return snack('Open a web page first');
                          final lang = effectiveTranslateLang(settings);
                          tabs.loadUri(translateUri(tab.url, lang));
                        },
                      ),
                      _Quick(
                        icon: Icons.record_voice_over_outlined,
                        label: 'Read aloud',
                        onTap: () async {
                          close();
                          final err = await ref
                              .read(readAloudProvider.notifier)
                              .start();
                          if (err != null) snack(err);
                        },
                      ),
                      _Quick(
                        icon: Icons.download_for_offline_outlined,
                        label: 'Save offline',
                        onTap: () async {
                          close();
                          final err = await ref
                              .read(offlinePagesProvider.notifier)
                              .saveActive();
                          snack(err ?? 'Saved. Find it in Offline pages.');
                        },
                      ),
                      _Quick(
                        icon: Icons.add_to_home_screen,
                        label: 'Home screen',
                        onTap: () async {
                          close();
                          if (tab.isNewTab)
                            return snack('Open a web page first');
                          final ok = await addActiveToHomeScreen(read);
                          if (!ok)
                            snack(
                              'Your launcher does not support adding shortcuts',
                            );
                        },
                      ),
                      _Quick(
                        icon: Icons.highlight_alt,
                        label: 'Block element',
                        onTap: () {
                          close();
                          if (tab.isNewTab)
                            return snack('Open a web page first');
                          tabs.activeController.runJavaScript(
                            'window.__dbg && window.__dbg.pickElement()',
                          );
                          snack('Tap the thing you want to hide');
                        },
                      ),
                      _Quick(
                        icon: Icons.slow_motion_video,
                        label: 'Video speed',
                        onTap: () async {
                          close();
                          final rate = await showModalBottomSheet<double>(
                            context: context,
                            showDragHandle: true,
                            builder: (c) => SafeArea(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final r in const [
                                    0.5,
                                    0.75,
                                    1.0,
                                    1.25,
                                    1.5,
                                    1.75,
                                    2.0,
                                    2.5,
                                    3.0,
                                  ])
                                    ChoiceChip(
                                      label: Text('$r×'),
                                      selected: false,
                                      onSelected: (_) => Navigator.pop(c, r),
                                    ),
                                  const SizedBox(
                                    width: double.infinity,
                                    height: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (rate == null) return;
                          tabs.setVideoRate(rate);
                          snack('Videos on this page play at $rate×');
                        },
                      ),
                      _Quick(
                        icon: Icons.picture_in_picture_alt_outlined,
                        label: 'Picture-in-picture',
                        onTap: () async {
                          close();
                          final err = await startPictureInPicture(read);
                          if (err != null) snack(err);
                        },
                      ),
                      _Quick(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Print / PDF',
                        onTap: () async {
                          close();
                          if (!await printActivePage(read))
                            snack('Open a web page first');
                        },
                      ),
                      _Quick(
                        icon: Icons.qr_code_2,
                        label: 'QR code',
                        onTap: () {
                          close();
                          showQrSheet(context, read);
                        },
                      ),
                      _Quick(
                        icon: Icons.code,
                        label: 'Source',
                        onTap: () async {
                          close();
                          if (tab.isNewTab)
                            return snack('Open a web page first');
                          final html = jsResultString(
                            await tabs.activeController
                                .runJavaScriptReturningResult(
                                  'document.documentElement.outerHTML',
                                ),
                          );
                          nav.push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SourceViewerPage(url: tab.url, source: html),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.offline_pin_outlined),
                  title: const Text('Offline pages'),
                  onTap: () => push(const OfflinePagesPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.border_color_outlined),
                  title: const Text('Highlights & notes'),
                  subtitle: const Text(
                    'Select text on a page and tap Highlight',
                  ),
                  onTap: () => push(const HighlightsPage()),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.nightlight_outlined),
                  title: const Text('Night light'),
                  value: settings.nightLight,
                  onChanged: (v) => ref
                      .read(browserSettingsProvider.notifier)
                      .update((s) => s.copyWith(nightLight: v)),
                ),
                if (settings.nightLight)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Slider(
                      value: settings.nightLightStrength,
                      min: 0.1,
                      max: 0.6,
                      label: 'Strength',
                      onChanged: (v) => ref
                          .read(browserSettingsProvider.notifier)
                          .update((s) => s.copyWith(nightLightStrength: v)),
                    ),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.developer_mode,
                    color: Colors.blueAccent,
                  ),
                  title: const Text('Developer tools'),
                  subtitle: const Text(
                    'Console, network, storage, DOM, performance',
                  ),
                  trailing: errors > 0
                      ? Badge(
                          label: Text('$errors'),
                          backgroundColor: Colors.redAccent,
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    close();
                    ref
                        .read(homeTabProvider.notifier)
                        .select(errors > 0 ? AppTab.console : AppTab.network);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Hard reload'),
                  subtitle: const Text(
                    'Clear cache, storage and cookies, then reload',
                  ),
                  onTap: () {
                    close();
                    tabs.hardReload();
                    snack('Cache cleared & reloaded');
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.vpn_lock_outlined,
                    color: ref.watch(proxyStatusProvider) == ProxyStatus.active
                        ? Colors.green
                        : null,
                  ),
                  title: const Text('Proxy / VPN'),
                  subtitle: Text(switch (ref.watch(proxyStatusProvider)) {
                    ProxyStatus.active =>
                      'On: ${ref.watch(proxySettingsProvider).host}',
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
      },
    ),
  );
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _Quick({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

/// Top of the menu: which site this is and whether the connection is secure.
class _SiteHeader extends StatelessWidget {
  final BrowserTab tab;
  final VoidCallback onTap;
  const _SiteHeader({required this.tab, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = (Uri.tryParse(tab.url)?.host ?? '').replaceFirst(
      RegExp(r'^www\.'),
      '',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                tab.isPrivate
                    ? const Icon(Icons.privacy_tip_outlined, size: 28)
                    : SiteIcon(url: tab.url, size: 28, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            tab.isSecure ? Icons.lock_outline : Icons.lock_open,
                            size: 13,
                            color: tab.isSecure
                                ? scheme.onSurfaceVariant
                                : scheme.error,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              host.isEmpty ? tab.url : host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
