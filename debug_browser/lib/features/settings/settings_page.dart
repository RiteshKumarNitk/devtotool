import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../branding/logo_painter.dart';
import '../../core/browser_settings.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';
import 'proxy_page.dart';
import 'search_shortcuts_page.dart';
import '../../core/search_shortcuts.dart';
import 'dart:convert';
import '../../core/backup.dart';
import '../../core/page_tools.dart';
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
    if (history) {
      ref.read(historyProvider.notifier).clear();
      ref.read(recentlyClosedProvider.notifier).clear();
    }
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
    final themeMode = ref.watch(themeProvider);
    final accent = ref.watch(accentColorProvider);

    Widget section(String t, Color color, List<Widget> children) => _SectionColor(
          color: color,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 16, 6),
              child: Text(t,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      )),
            ),
            Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          section('General', Colors.blue, [
          ListTile(
            leading: const _Badge(Icons.short_text),
            title: const Text('Search shortcuts'),
            subtitle: Text('Type "w taj mahal" for Wikipedia. ${ref.watch(searchShortcutsProvider).length} shortcuts'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchShortcutsPage())),
          ),
          ListTile(
            leading: const _Badge(Icons.search),
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
            leading: const _Badge(Icons.open_in_browser),
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
            leading: const _Badge(Icons.dashboard_customize_outlined),
            title: const Text('New Tab page'),
            subtitle: Text(s.newTabPage ? 'On: ${s.newTabTheme.label} theme' : 'Off'),
            onTap: () => showCustomizeSheet(context),
          ),
          ListTile(
            leading: const _Badge(Icons.home_outlined),
            title: const Text('Homepage'),
            subtitle: Text(s.homepage),
            onTap: () => _editHomepage(context, ref, s),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.tab),
            title: const Text('Reopen tabs on start'),
            value: s.restoreTabs,
            onChanged: (v) => notifier.update((x) => x.copyWith(restoreTabs: v)),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.manage_search),
            title: const Text('Search suggestions'),
            subtitle: Text('Suggestions from ${s.engine.label} as you type. Off in private tabs and with a proxy.'),
            value: s.searchSuggestions,
            onChanged: (v) => notifier.update((x) => x.copyWith(searchSuggestions: v)),
          ),
          ListTile(
            leading: const _Badge(Icons.translate),
            title: const Text('Translate pages into'),
            subtitle: Text(translateLanguages[effectiveTranslateLang(s)] ?? effectiveTranslateLang(s)),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (c) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(c).height * 0.6,
                  child: ListView(children: [
                    for (final e in translateLanguages.entries)
                      ListTile(
                        leading: Icon(e.key == effectiveTranslateLang(s) ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: Text(e.value),
                        onTap: () {
                          notifier.update((x) => x.copyWith(translateTo: e.key));
                          Navigator.pop(c);
                        },
                      ),
                  ]),
                ),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.https_outlined),
            title: const Text('HTTPS-only mode'),
            subtitle: const Text('Open sites securely; ask before using an insecure connection'),
            value: s.httpsOnly,
            onChanged: (v) => notifier.update((x) => x.copyWith(httpsOnly: v)),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.unfold_less),
            title: const Text('Hide toolbars while scrolling'),
            subtitle: const Text('More room for the page; scroll up to bring them back'),
            value: s.autoHideToolbars,
            onChanged: (v) => notifier.update((x) => x.copyWith(autoHideToolbars: v)),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.refresh),
            title: const Text('Pull to refresh'),
            value: s.pullToRefresh,
            onChanged: (v) => notifier.update((x) => x.copyWith(pullToRefresh: v)),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.exit_to_app),
            title: const Text('Ask before exiting'),
            subtitle: const Text('Confirm when the back button would close the app'),
            value: s.confirmExit,
            onChanged: (v) => notifier.update((x) => x.copyWith(confirmExit: v)),
          ),
          ]),
          section('Appearance', Colors.purple, [
            ListTile(
              leading: const _Badge(Icons.palette_outlined),
              title: const Text('Theme'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (v) {
                    HapticFeedback.selectionClick();
                    ref.read(themeProvider.notifier).set(v.first);
                  },
                ),
              ),
            ),
            ListTile(
              leading: const _Badge(Icons.color_lens_outlined),
              title: const Text('Accent colour'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 10, runSpacing: 8, children: [
                  for (final e in accentColors.entries)
                    _AccentDot(
                      color: Color(e.value),
                      name: e.key,
                      selected: e.value == accent,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(accentColorProvider.notifier).set(e.value);
                      },
                    ),
                ]),
              ),
            ),
          ]),
          section('Privacy', Colors.green, [
          ListTile(
            leading: const _Badge(Icons.vpn_lock_outlined),
            title: const Text('Proxy / VPN'),
            subtitle: Text(ref.watch(proxyStatusProvider) == ProxyStatus.active
                ? 'On: ${ref.watch(proxySettingsProvider).host}'
                : "Route browsing through your VPN provider's proxy"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProxyPage())),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.auto_delete_outlined),
            title: const Text('Clear data when exiting'),
            subtitle: const Text('History, cookies and cache are deleted when you leave the app'),
            value: s.clearOnExit,
            onChanged: (v) => notifier.update((x) => x.copyWith(clearOnExit: v)),
          ),
          SwitchListTile(
            secondary: const _Badge(Icons.fingerprint),
            title: const Text('Lock private tabs'),
            subtitle: const Text('Fingerprint or screen lock to reopen private tabs after leaving the app'),
            value: s.lockPrivateTabs,
            onChanged: (v) => notifier.update((x) => x.copyWith(lockPrivateTabs: v)),
          ),
          ListTile(
            leading: const _Badge(Icons.delete_outline),
            title: const Text('Clear browsing data'),
            subtitle: const Text('History, cookies, cache'),
            onTap: () => _clearData(context, ref),
          ),
          ]),
          section('Developer', Colors.deepOrange, [
          SwitchListTile(
            secondary: const _Badge(Icons.bug_report_outlined),
            title: const Text('Floating debug bubble'),
            subtitle: const Text('Live error and request counts over the page'),
            value: s.showDebugBubble,
            onChanged: (v) => notifier.update((x) => x.copyWith(showDebugBubble: v)),
          ),
          ListTile(
            leading: const _Badge(Icons.developer_mode),
            title: const Text('Open developer tools'),
            onTap: () {
              Navigator.pop(context);
              ref.read(homeTabProvider.notifier).select(AppTab.console);
            },
          ),
          ]),
          section('Backup', Colors.indigo, [
          ListTile(
            leading: const _Badge(Icons.backup_outlined),
            title: const Text('Back up'),
            subtitle: const Text('Bookmarks, settings, extensions, scripts and more, in one file'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const _Badge(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            subtitle: const Text('Adds what is missing; nothing is deleted'),
            onTap: () => _importBackup(context, ref),
          ),
          ]),
          section('About', Colors.blueGrey, [
          ListTile(
            leading: const _Badge(Icons.policy_outlined),
            title: const Text('Privacy policy & terms'),
            subtitle: const Text('innovatex-technology.com'),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              ref.read(tabsProvider.notifier).newTab(url: privacyPolicyUrl);
            },
          ),
          const AboutListTile(
            icon: _Badge(Icons.info_outline),
            applicationIcon: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(width: 48, height: 48, child: CustomPaint(painter: LogoPainter(background: true, scale: 0.86))),
            ),
            applicationName: 'Debug Browser',
            applicationVersion: '2.3.1',
            applicationLegalese: '© InnovateX Technology',
            aboutBoxChildren: [
              SizedBox(height: 12),
              Text('All browsing and debugging data stays on this device. Nothing is uploaded; '
                  'data leaves the device only when you choose to share or export it.'),
            ],
          ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}


/// Colour of the icon badges in one settings section.
/// Hosted on the company website; also given to the Play Console.
const privacyPolicyUrl = 'https://innovatex-technology.com/apps/debug-browser/privacy';

class _SectionColor extends InheritedWidget {
  final Color color;
  const _SectionColor({required this.color, required super.child});
  @override
  bool updateShouldNotify(_SectionColor old) => old.color != color;
}

/// Small rounded tinted square behind a settings icon.
class _Badge extends StatelessWidget {
  final IconData icon;
  const _Badge(this.icon);

  @override
  Widget build(BuildContext context) {
    final c = context.dependOnInheritedWidgetOfExactType<_SectionColor>()?.color ?? Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.withValues(alpha: dark ? 0.22 : 0.14), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: dark ? Color.lerp(c, Colors.white, 0.35) : c),
    );
  }
}

class _AccentDot extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _AccentDot({required this.color, required this.name, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: name,
        child: Semantics(
          button: true,
          selected: selected,
          label: '$name accent',
          child: InkResponse(
            onTap: onTap,
            radius: 24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: selected ? 38 : 32,
              height: selected ? 38 : 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 2.5),
              ),
              child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
            ),
          ),
        ),
      );
}
