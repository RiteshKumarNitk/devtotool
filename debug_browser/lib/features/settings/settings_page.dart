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
          header('About'),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationIcon: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(width: 48, height: 48, child: CustomPaint(painter: LogoPainter(background: true, scale: 0.86))),
            ),
            applicationName: 'Debug Browser',
            applicationVersion: '1.8.0',
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
