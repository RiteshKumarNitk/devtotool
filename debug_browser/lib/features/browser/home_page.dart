import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/browser_settings.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/thumbnails.dart';
import '../../core/tool_providers.dart';
import '../devtools/devtools_page.dart';
import 'browser_menu.dart';
import 'downloads_page.dart';
import 'debug_bubble.dart';
import 'tab_switcher.dart';

/// The main screen: a Chrome/Firefox-style browser. Developer tools open
/// from the menu or the floating bubble.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  final _findText = TextEditingController();
  bool _editing = false;
  bool _finding = false;
  late final ValueNotifier<String?> _downloads;

  void _onDownloadStarted() {
    final name = _downloads.value;
    if (name == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Downloading $name'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsPage())),
        ),
      ));
    _downloads.value = null;
  }

  @override
  void initState() {
    super.initState();
    HomeTabNotifier.openDevToolsRoute = _openDevTools;
    _downloads = ref.read(tabsProvider.notifier).downloadStarted..addListener(_onDownloadStarted);
    _addressFocus.addListener(() {
      final focused = _addressFocus.hasFocus;
      if (focused) {
        _address.text = ref.read(tabsProvider).active.url;
        _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length);
      }
      setState(() => _editing = focused);
    });
  }

  @override
  void dispose() {
    HomeTabNotifier.openDevToolsRoute = null;
    _downloads.removeListener(_onDownloadStarted);
    _address.dispose();
    _addressFocus.dispose();
    _findText.dispose();
    super.dispose();
  }

  void _openDevTools() {
    HomeTabNotifier.devToolsOpen = true;
    appNavigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => const DevToolsPage()))
        .whenComplete(() => HomeTabNotifier.devToolsOpen = false);
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    ref.read(tabsProvider.notifier).loadInput(text);
    _addressFocus.unfocus();
  }

  void _openUrl(String url) {
    ref.read(tabsProvider.notifier).loadUri(normaliseUrlInput(url));
    _addressFocus.unfocus();
  }

  // ------------------------------------------------------------------ find
  void startFind() {
    setState(() => _finding = true);
  }

  void _find(String term) => _js('window.__dbg && window.__dbg.find(${jsString(term)})');

  void _closeFind() {
    _js('window.__dbg && window.__dbg.findClear()');
    _findText.clear();
    ref.read(pageDataProvider.notifier).put('find_result', const {'count': 0, 'index': -1});
    setState(() => _finding = false);
  }

  void _js(String code) => ref.read(tabsProvider.notifier).activeController.runJavaScript(code);

  // ------------------------------------------------------------- link menu
  void _showLinkMenu(LinkMenuRequest r) {
    final tabs = ref.read(tabsProvider.notifier);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(r.text.isNotEmpty ? r.text : r.href, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(r.href, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open in new tab'),
              onTap: () {
                Navigator.pop(c);
                tabs.newTab(url: r.href);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tab_unselected),
              title: const Text('Open in background tab'),
              onTap: () {
                Navigator.pop(c);
                tabs.newTab(url: r.href, activate: false);
                _snack('Opened in background');
              },
            ),
            if (r.image.isNotEmpty && r.image != r.href)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Open image in new tab'),
                onTap: () {
                  Navigator.pop(c);
                  tabs.newTab(url: r.image);
                },
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () {
                Navigator.pop(c);
                Clipboard.setData(ClipboardData(text: r.href));
                _snack('Link copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share link'),
              onTap: () {
                Navigator.pop(c);
                SharePlus.instance.share(ShareParams(uri: Uri.parse(r.href)));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
    }
  }

  // ----------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);
    final tab = tabsState.active;
    final settings = ref.watch(browserSettingsProvider);
    ref.listen(linkMenuProvider, (_, next) {
      if (next != null) _showLinkMenu(next);
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_finding) return _closeFind();
        if (_editing) return _addressFocus.unfocus();
        final c = ref.read(tabsProvider.notifier).activeController;
        if (await c.canGoBack()) {
          await c.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _AddressBar(
                controller: _address,
                focus: _addressFocus,
                editing: _editing,
                tab: tab,
                onSubmit: _submit,
                onReload: () => ref.read(tabsProvider.notifier).reload(),
                onStop: () => ref.read(tabsProvider.notifier).stop(),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _WebArea(tab: tab, controller: ref.read(tabsProvider.notifier).controllerFor(tab.id))),
                    if (tab.error != null)
                      Positioned.fill(
                        child: _ErrorPage(
                          url: tab.url,
                          message: tab.error!,
                          onRetry: () => ref.read(tabsProvider.notifier).reload(),
                        ),
                      ),
                    if (_editing)
                      Positioned.fill(
                        child: _Suggestions(
                          query: _address.text,
                          engine: settings.engine,
                          onSearch: _submit,
                          onOpen: _openUrl,
                          listenable: _address,
                        ),
                      ),
                    if (settings.showDebugBubble && !_editing) const DebugBubble(),
                  ],
                ),
              ),
              if (_finding)
                _FindBar(controller: _findText, onChanged: _find, onClose: _closeFind, onStep: (d) {
                  _js('window.__dbg && window.__dbg.findStep($d)');
                })
              else if (!_editing)
                _BottomBar(
                  tab: tab,
                  tabCount: tabsState.tabs.length,
                  onFind: startFind,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebArea extends ConsumerWidget {
  final BrowserTab tab;
  final WebViewController controller;
  const _WebArea({required this.tab, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(viewportProvider);
    // Keyed by tab id: switching tabs swaps the native WebView.
    final web = WebViewWidget(key: ValueKey(tab.id), controller: controller);
    Widget child = web;
    if (viewport.width != null) {
      final w = viewport.width!, h = viewport.height!;
      child = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${viewport.label} • ${w.toInt()}×${h.toInt()}', style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey, width: 2)),
                    child: web,
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    return Screenshot(controller: ref.watch(screenshotControllerProvider), child: child);
  }
}

class _AddressBar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool editing;
  final BrowserTab tab;
  final void Function(String) onSubmit;
  final VoidCallback onReload;
  final VoidCallback onStop;

  const _AddressBar({
    required this.controller,
    required this.focus,
    required this.editing,
    required this.tab,
    required this.onSubmit,
    required this.onReload,
    required this.onStop,
  });

  /// "https://www.example.com/path" -> "example.com/path"
  static String displayUrl(String url) {
    var s = url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '');
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (!editing && controller.text != displayUrl(tab.url)) {
      // Not editing: show the short form of the current URL.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!focus.hasFocus) controller.text = displayUrl(tab.url);
      });
    }
    return Material(
      color: scheme.surface,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  if (editing)
                    Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant)
                  else
                    GestureDetector(
                      onTap: () => _showSiteInfo(context),
                      child: Icon(
                        tab.isSecure ? Icons.lock_outline : Icons.info_outline,
                        size: 18,
                        color: tab.isSecure ? scheme.onSurfaceVariant : scheme.error,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search or type web address',
                        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      onSubmitted: onSubmit,
                    ),
                  ),
                  if (editing)
                    IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: controller.clear,
                    )
                  else
                    IconButton(
                      tooltip: tab.isLoading ? 'Stop' : 'Reload',
                      icon: Icon(tab.isLoading ? Icons.close : Icons.refresh, size: 20),
                      onPressed: tab.isLoading ? onStop : onReload,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: tab.isLoading ? LinearProgressIndicator(value: tab.progress, minHeight: 2) : null,
          ),
        ],
      ),
    );
  }

  void _showSiteInfo(BuildContext context) {
    final host = Uri.tryParse(tab.url)?.host ?? tab.url;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(host, style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(children: [
                Icon(tab.isSecure ? Icons.lock : Icons.warning_amber,
                    color: tab.isSecure ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tab.isSecure
                      ? 'Connection is secure. Information you send to this site is encrypted.'
                      : 'Connection is not secure. Don\'t enter passwords or payment details on this site.'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  final BrowserTab tab;
  final int tabCount;
  final VoidCallback onFind;
  const _BottomBar({required this.tab, required this.tabCount, required this.onFind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.read(tabsProvider.notifier);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: tab.canGoBack ? tabs.goBack : null,
              ),
              IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward),
                onPressed: tab.canGoForward ? tabs.goForward : null,
              ),
              IconButton(tooltip: 'Home', icon: const Icon(Icons.home_outlined), onPressed: tabs.goHome),
              IconButton(
                tooltip: 'Tabs',
                onPressed: () async {
                  // Preview of the current page for the switcher.
                  await captureActiveTabThumbnail(ref);
                  if (context.mounted) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TabSwitcherPage()));
                  }
                },
                icon: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tabCount > 99 ? ':D' : '$tabCount',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.more_vert),
                onPressed: () => showBrowserMenu(context, ref, onFind: onFind),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  final String query;
  final SearchEngine engine;
  final void Function(String) onSearch;
  final void Function(String) onOpen;
  final Listenable listenable;
  const _Suggestions({
    required this.query,
    required this.engine,
    required this.onSearch,
    required this.onOpen,
    required this.listenable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final q = (listenable as TextEditingController).text.trim();
        final ql = q.toLowerCase();
        final history = ref.watch(historyProvider).reversed;
        final bookmarks = ref.watch(bookmarksProvider);
        final seen = <String>{};
        final matches = <(IconData, String, String)>[];
        void add(IconData icon, Map<String, String> e) {
          final url = e['url'] ?? '';
          if (url.isEmpty || seen.contains(url) || matches.length >= 8) return;
          final title = e['title'] ?? '';
          if (ql.isNotEmpty && !url.toLowerCase().contains(ql) && !title.toLowerCase().contains(ql)) return;
          seen.add(url);
          matches.add((icon, title.isEmpty ? url : title, url));
        }

        for (final b in bookmarks) {
          add(Icons.star_outline, b);
        }
        for (final h in history) {
          add(Icons.history, h);
        }

        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (q.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${engine.label} search'),
                  onTap: () => onSearch(q),
                ),
              if (q.isEmpty && matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Your bookmarks and recent sites appear here.', textAlign: TextAlign.center),
                ),
              for (final (icon, title, url) in matches)
                ListTile(
                  leading: Icon(icon),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_AddressBar.displayUrl(url), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.north_west, size: 18),
                    onPressed: () {
                      final c = listenable as TextEditingController;
                      c.text = url;
                      c.selection = TextSelection.collapsed(offset: url.length);
                    },
                  ),
                  onTap: () => onOpen(url),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FindBar extends ConsumerWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final VoidCallback onClose;
  final void Function(int delta) onStep;
  const _FindBar({required this.controller, required this.onChanged, required this.onClose, required this.onStep});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(pageDataProvider)['find_result'];
    final count = (result?['count'] as num?)?.toInt() ?? 0;
    final index = (result?['index'] as num?)?.toInt() ?? -1;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Find in page', border: InputBorder.none),
                onChanged: onChanged,
                onSubmitted: (_) => onStep(1),
              ),
            ),
            Text(controller.text.isEmpty ? '' : '${count == 0 ? 0 : index + 1}/$count',
                style: const TextStyle(color: Colors.grey)),
            IconButton(tooltip: 'Previous', icon: const Icon(Icons.keyboard_arrow_up), onPressed: count > 0 ? () => onStep(-1) : null),
            IconButton(tooltip: 'Next', icon: const Icon(Icons.keyboard_arrow_down), onPressed: count > 0 ? () => onStep(1) : null),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
          ]),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final String url;
  final String message;
  final VoidCallback onRetry;
  const _ErrorPage({required this.url, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(url)?.host ?? url;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text("This site can't be reached", style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(host, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}
