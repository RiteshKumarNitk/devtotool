import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../branding/logo_painter.dart';
import '../../core/browser_settings.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';
import 'proxy_page.dart';
import 'dart:convert';
import '../../core/backup.dart';
import '../../services/export_service.dart';
import '../../core/home_stats.dart';
import '../newtab/new_tab_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _editHomepage(BuildContext context, WidgetRef ref, BrowserSettings s) async {
    final ctrl = TextEditingController(text: s.customHomepage);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Homepage'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.engine.home,
            helperText: 'Leave empty to use ${s.engine.label}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Use default')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    final value = result.trim().isEmpty ? '' : normaliseUrlInput(result).toString();
    ref.read(browserSettingsProvider.notifier).update((x) => x.copyWith(customHomepage: value));
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    var history = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Back up'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Saves bookmarks, settings, extensions, user scripts, mock rules, environments and '
                'snippets to a file you can keep or move to another phone. Your proxy password is not included.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: history,
              title: const Text('Include browsing history'),
              onChanged: (v) => set(() => history = v ?? false),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save backup')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final done = await ExportService.shareJson(
      buildBackup(ref.read, includeHistory: history),
      fileName: 'debug_browser_backup',
      text: 'Debug Browser backup',
    );
    if (!done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup failed')));
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    void snack(String t) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }

    String? text;
    try {
      text = await pickBackupFile();
    } on FormatException catch (e) {
      snack(e.message);
      return;
    }
    if (text == null) return;
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      snack('This file is not a Debug Browser backup.');
      return;
    }
    final (summary, error) = inspectBackup(json);
    if (summary == null) {
      snack(error!);
      return;
    }
    if (!context.mounted) return;
    final items = summary.describe();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (summary.createdAt != null)
            Text('Made ${MaterialLocalizations.of(c).formatMediumDate(summary.createdAt!)}',
                style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          for (final i in items) Text('• $i'),
          const SizedBox(height: 12),
          const Text('Missing items are added; nothing is deleted. Settings are replaced.',
              style: TextStyle(fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    restoreBackup(ref.read, json as Map);
    snack(summary.proxy ? 'Restored. Reconnect your proxy in Proxy / VPN.' : 'Backup restored');
  }

  Future<void> _clearData(BuildContext context, WidgetRef ref) async {
    var history = true, cookies = true, cache = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Clear browsing data'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CheckboxListTile(value: history, title: const Text('Browsing history'), onChanged: (v) => set(() => history = v!)),
            CheckboxListTile(value: cookies, title: const Text('Cookies and site data'), onChanged: (v) => set(() => cookies = v!)),
            CheckboxListTile(value: cache, title: const Text('Cached images and files'), onChanged: (v) => set(() => cache = v!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear data')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final controller = ref.read(tabsProvider.notifier).activeController;
    if (history) ref.read(historyProvider.notifier).clear();
    if (cookies) {
      await WebViewCookieManager().clearCookies();
      await controller.clearLocalStorage();
    }
    if (cache) await controller.clearCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Browsing data cleared')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(browserSettingsProvider);
    final notifier = ref.read(browserSettingsProvider.notifier);
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  )),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          header('General'),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search engine'),
            subtitle: Text(s.engine.label),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final e in SearchEngine.values)
                    ListTile(
                      leading: Icon(e == s.engine ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      title: Text(e.label),
                      subtitle: Text(e.home),
                      onTap: () {
                        notifier.update((x) => x.copyWith(engine: e));
                        Navigator.pop(c);
                      },
                    ),
                ]),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('Default browser'),
            subtitle: Text(switch (ref.watch(isDefaultBrowserProvider)) {
              AsyncData(value: true) => 'Debug Browser opens links from other apps',
              _ => 'Tap to open links from other apps here',
            }),
            onTap: () async {
              await SystemBrowser.requestDefault();
              ref.invalidate(isDefaultBrowserProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('New Tab page'),
            subtitle: Text(s.newTabPage ? 'On: ${s.newTabTheme.label} theme' : 'Off'),
            onTap: () => showCustomizeSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Homepage'),
            subtitle: Text(s.homepage),
            onTap: () => _editHomepage(context, ref, s),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.tab),
            title: const Text('Reopen tabs on start'),
            value: s.restoreTabs,
            onChanged: (v) => notifier.update((x) => x.copyWith(restoreTabs: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.https_outlined),
            title: const Text('HTTPS-only mode'),
            subtitle: const Text('Open sites securely; ask before using an insecure connection'),
            value: s.httpsOnly,
            onChanged: (v) => notifier.update((x) => x.copyWith(httpsOnly: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.unfold_less),
            title: const Text('Hide toolbars while scrolling'),
            subtitle: const Text('More room for the page; scroll up to bring them back'),
            value: s.autoHideToolbars,
            onChanged: (v) => notifier.update((x) => x.copyWith(autoHideToolbars: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.refresh),
            title: const Text('Pull to refresh'),
            value: s.pullToRefresh,
            onChanged: (v) => notifier.update((x) => x.copyWith(pullToRefresh: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.exit_to_app),
            title: const Text('Ask before exiting'),
            subtitle: const Text('Confirm when the back button would close the app'),
            value: s.confirmExit,
            onChanged: (v) => notifier.update((x) => x.copyWith(confirmExit: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark theme'),
            value: isDark,
            onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
          ),
          header('Privacy'),
          ListTile(
            leading: const Icon(Icons.vpn_lock_outlined),
            title: const Text('Proxy / VPN'),
            subtitle: Text(ref.watch(proxyStatusProvider) == ProxyStatus.active
                ? 'On: ${ref.watch(proxySettingsProvider).host}'
                : "Route browsing through your VPN provider's proxy"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProxyPage())),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear browsing data'),
            subtitle: const Text('History, cookies, cache'),
            onTap: () => _clearData(context, ref),
          ),
          header('Developer'),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Floating debug bubble'),
            subtitle: const Text('Live error and request counts over the page'),
            value: s.showDebugBubble,
            onChanged: (v) => notifier.update((x) => x.copyWith(showDebugBubble: v)),
          ),
          ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Open developer tools'),
            onTap: () {
              Navigator.pop(context);
              ref.read(homeTabProvider.notifier).select(AppTab.console);
            },
          ),
          header('Backup'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Back up'),
            subtitle: const Text('Bookmarks, settings, extensions, scripts and more, in one file'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            subtitle: const Text('Adds what is missing; nothing is deleted'),
            onTap: () => _importBackup(context, ref),
          ),
          header('About'),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationIcon: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(width: 48, height: 48, child: CustomPaint(painter: LogoPainter(background: true, scale: 0.86))),
            ),
            applicationName: 'Debug Browser',
            applicationVersion: '2.0.0',
            applicationLegalese: '© InnovateX Technology',
            aboutBoxChildren: [
              SizedBox(height: 12),
              Text('All browsing and debugging data stays on this device. Nothing is uploaded; '
                  'data leaves the device only when you choose to share or export it.'),
            ],
          ),
        ],
      ),
    );
  }
}
