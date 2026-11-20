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
import 'package:local_auth/local_auth.dart';
import '../devtools/devtools_page.dart';
import '../newtab/new_tab_page.dart';
import '../tools/highlights_page.dart';
import '../../core/highlights.dart';
import '../../core/home_stats.dart';
import '../../core/extensions.dart';
import '../../core/favicons.dart';
import '../../core/search_suggest.dart';
import '../../core/search_shortcuts.dart';
import '../../core/read_aloud.dart';
import '../extensions/site_sheet.dart';
import 'browser_menu.dart';
import 'downloads_page.dart';
import 'debug_bubble.dart';
import 'tab_switcher.dart';
import 'tab_actions.dart';

/// The main screen: a Chrome/Firefox-style browser. Developer tools open
/// from the menu or the floating bubble.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  // ------------------------------------------------------- private tab lock
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final lockOn = ref.read(browserSettingsProvider).lockPrivateTabs;
      if (lockOn && ref.read(tabsProvider).tabs.any((t) => t.isPrivate)) {
        ref.read(privateLockProvider.notifier).lock();
      }
    }
  }

  Future<void> _unlockPrivate() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) {
        // No screen lock set up: nothing to verify against.
        ref.read(privateLockProvider.notifier).unlock();
        _snack('Set a screen lock on your phone to protect private tabs.');
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Unlock your private tabs',
        persistAcrossBackgrounding: true,
      );
      if (ok) ref.read(privateLockProvider.notifier).unlock();
    } catch (e) {
      _snack('Could not unlock: $e');
    }
  }

  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  final _findText = TextEditingController();
  bool _editing = false;
  bool _finding = false;
  late final ValueNotifier<String?> _downloads;
  late final ValueNotifier<String?> _notice;
  late final ValueNotifier<String?> _popups;

  /// Toolbars hide while scrolling down a page (if enabled), never while
  /// typing, finding, loading or on the New Tab / error pages.
  bool _barsVisible(BrowserSettings settings, BrowserTab tab) =>
      !settings.autoHideToolbars ||
      _toolbars.value ||
      _editing ||
      _finding ||
      tab.isNewTab ||
      tab.error != null ||
      tab.isLoading;

  late final ValueNotifier<bool> _toolbars;

  // ---------------------------------------------- widget / tile / PiP
  bool _inPip = false;

  void _onLaunchAction(String action) {
    final tabs = ref.read(tabsProvider.notifier);
    ref.read(homeTabProvider.notifier).select(AppTab.browser);
    if (action == 'private') {
      tabs.newTab(private: true);
    } else if (action == 'search') {
      tabs.newTab();
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _addressFocus.requestFocus();
      });
    }
  }

  void _onPip(bool inPip) {
    setState(() => _inPip = inPip);
    if (!inPip) {
      ref
          .read(tabsProvider.notifier)
          .activeController
          .runJavaScript('window.__dbg && window.__dbg.focusVideo(false)')
          .catchError((Object _) {});
    }
  }

  // -------------------------------------------------- block an element
  Future<void> _showElementSheet(Map<String, dynamic> picked) async {
    final js = ref.read(tabsProvider.notifier).activeController;
    final selector = '${picked['selector']}';
    final host = siteKey(ref.read(tabsProvider).active.url);
    var preview = false;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isDismissible: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hide this on $host?',
                  style: Theme.of(c).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if ('${picked['text']}'.isNotEmpty)
                  Text(
                    '"${picked['text']}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  '${picked['tag']} • matches ${picked['count']} element${picked['count'] == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (picked['canGrow'] == true)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(c, 'parent'),
                        icon: const Icon(Icons.open_in_full, size: 18),
                        label: const Text('Bigger'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        preview = !preview;
                        js.runJavaScript(
                          'window.__dbg && window.__dbg.pickPreview($preview)',
                        );
                        set(() {});
                      },
                      icon: Icon(
                        preview ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      label: Text(preview ? 'Show again' : 'Preview'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(c, 'hide'),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Hide on this site'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ref.read(pageDataProvider.notifier).put('element_picked', const {});
    if (choice == 'parent') {
      await js.runJavaScript(
        'window.__dbg && window.__dbg.pickPreview(false); window.__dbg && window.__dbg.pickParent()',
      );
    } else if (choice == 'hide') {
      ref
          .read(extensionsProvider.notifier)
          .update(
            (x) => x.withSite(
              host,
              (o) => o.copyWith(hidden: [...o.hidden, selector]),
            ),
          );
      await js.runJavaScript(
        'window.__dbg && window.__dbg.hideSelector(${jsString(selector)})',
      );
      _snack('Hidden on $host. Undo from the shield in the address bar.');
    } else {
      await js.runJavaScript('window.__dbg && window.__dbg.pickCancel()');
    }
  }

  // ------------------------------------------------------- highlights
  void _onHighlightAdded(Map<String, dynamic> d) {
    ref.read(pageDataProvider.notifier).put('highlight_added', const {});
    final tab = ref.read(tabsProvider).active;
    if (tab.isPrivate) {
      _snack('Highlights are not saved in private tabs');
      return;
    }
    final h = Highlight(
      id: '${d['id']}',
      url: tab.url,
      title: tab.displayTitle,
      text: '${d['text']}',
      prefix: '${d['prefix'] ?? ''}',
      suffix: '${d['suffix'] ?? ''}',
      color: '${d['color'] ?? 'yellow'}',
      created: DateTime.now(),
    );
    ref.read(highlightsProvider.notifier).add(h);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Highlighted'),
          action: SnackBarAction(
            label: 'Add note',
            onPressed: () async {
              final note = await editHighlightNote(context, h);
              if (note != null)
                ref
                    .read(highlightsProvider.notifier)
                    .update(h.id, (x) => x.copyWith(note: note.trim()));
            },
          ),
        ),
      );
  }

  Future<void> _onHighlightTap(String id) async {
    ref.read(pageDataProvider.notifier).put('highlight_tap', const {});
    final list = ref.read(highlightsProvider).where((h) => h.id == id);
    if (list.isEmpty) return;
    final h = list.first;
    final js = ref.read(tabsProvider.notifier).activeController;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
              subtitle: h.note.isEmpty ? null : Text('📝 ${h.note}'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final e in highlightSwatches.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(c);
                          ref
                              .read(highlightsProvider.notifier)
                              .update(h.id, (x) => x.copyWith(color: e.key));
                          js.runJavaScript(
                            'window.__dbg && (window.__dbg.removeHighlight(${jsString(h.id)}), window.__dbg.applyHighlights(${jsString(ref.read(highlightsProvider.notifier).pageJson(h.url))}))',
                          );
                        },
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: e.value,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(h.note.isEmpty ? 'Add note' : 'Edit note'),
              onTap: () async {
                Navigator.pop(c);
                final note = await editHighlightNote(context, h);
                if (note != null)
                  ref
                      .read(highlightsProvider.notifier)
                      .update(h.id, (x) => x.copyWith(note: note.trim()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove highlight'),
              onTap: () {
                Navigator.pop(c);
                ref.read(highlightsProvider.notifier).remove(h.id);
                js.runJavaScript(
                  'window.__dbg && window.__dbg.removeHighlight(${jsString(h.id)})',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onToolbars() => setState(() {});

  void _onPopupBlocked() {
    final url = _popups.value;
    if (url == null || !mounted) return;
    final host = Uri.tryParse(url)?.host ?? url;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Pop-up blocked: $host'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Open anyway',
            onPressed: () => ref.read(tabsProvider.notifier).newTab(url: url),
          ),
        ),
      );
    _popups.value = null;
  }

  void _onNotice() {
    final msg = _notice.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
    _notice.value = null;
  }

  Future<void> _showAuthPrompt(AuthPrompt p) async {
    final user = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Sign in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.host} requires a username and password${p.realm == null || p.realm!.isEmpty ? '' : ' ("${p.realm}")'}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: user,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (ok == true) {
      p.proceed(user.text, pass.text);
    } else {
      p.cancel();
    }
    user.dispose();
    pass.dispose();
    ref.read(authPromptProvider.notifier).clear();
  }

  void _onDownloadStarted() {
    final name = _downloads.value;
    if (name == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Downloading $name'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DownloadsPage())),
          ),
        ),
      );
    _downloads.value = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeTabNotifier.openDevToolsRoute = _openDevTools;
    // Links opened from other apps (when this is the default browser).
    SystemBrowser.listen(
      (url) => ref.read(tabsProvider.notifier).newTab(url: url),
      onAction: _onLaunchAction,
      onPip: _onPip,
    );
    SystemBrowser.takeInitialAction().then((a) {
      if (a != null && mounted) _onLaunchAction(a);
    });
    SystemBrowser.takeInitialUrl().then((url) {
      if (url != null && mounted) {
        ref.read(tabsProvider.notifier).newTab(url: url);
      }
    });
    _downloads = ref.read(tabsProvider.notifier).downloadStarted
      ..addListener(_onDownloadStarted);
    _notice = ref.read(tabsProvider.notifier).notice..addListener(_onNotice);
    _popups = ref.read(tabsProvider.notifier).popupBlocked
      ..addListener(_onPopupBlocked);
    _toolbars = ref.read(tabsProvider.notifier).toolbarsVisible
      ..addListener(_onToolbars);
    _addressFocus.addListener(() {
      final focused = _addressFocus.hasFocus;
      if (focused) {
        final active = ref.read(tabsProvider).active;
        _address.text = active.isNewTab ? '' : active.url;
        _address.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _address.text.length,
        );
      }
      setState(() => _editing = focused);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeTabNotifier.openDevToolsRoute = null;
    _downloads.removeListener(_onDownloadStarted);
    _notice.removeListener(_onNotice);
    _popups.removeListener(_onPopupBlocked);
    _toolbars.removeListener(_onToolbars);
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

  void _find(String term) =>
      _js('window.__dbg && window.__dbg.find(${jsString(term)})');

  void _closeFind() {
    _js('window.__dbg && window.__dbg.findClear()');
    _findText.clear();
    ref.read(pageDataProvider.notifier).put('find_result', const {
      'count': 0,
      'index': -1,
    });
    setState(() => _finding = false);
  }

  void _js(String code) =>
      ref.read(tabsProvider.notifier).activeController.runJavaScript(code);

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
              title: Text(
                r.text.isNotEmpty ? r.text : r.href,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                r.href,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open in new tab'),
              onTap: () {
                Navigator.pop(c);
                tabs.newTab(
                  url: r.href,
                  openerId: ref.read(tabsProvider).activeId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Open in private tab'),
              onTap: () {
                Navigator.pop(c);
                tabs.newTab(url: r.href, private: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(
                r.image.isNotEmpty && r.image == r.href
                    ? 'Download image'
                    : 'Download link',
              ),
              onTap: () {
                Navigator.pop(c);
                tabs.downloadUrl(r.href);
              },
            ),
            if (r.image.isNotEmpty && r.image != r.href)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Download image'),
                onTap: () {
                  Navigator.pop(c);
                  tabs.downloadUrl(r.image);
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

  /// Back on the New Tab page (the end of the back chain): ask before exiting.
  Future<void> _onBackAtStart() async {
    final tabsState = ref.read(tabsProvider);
    final settings = ref.read(browserSettingsProvider);
    if (!settings.confirmExit) {
      await _exitApp();
      return;
    }
    final multiple = tabsState.tabs.length > 1;
    final private = tabsState.active.isPrivate;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.exit_to_app),
        title: const Text('Exit Debug Browser?'),
        content: Text(
          [
            multiple
                ? 'You have ${tabsState.tabs.length} open tabs. They will be here when you come back.'
                : 'Your tab will be here when you come back.',
            if (private) 'Private tabs are closed and their data deleted.',
            if (settings.clearOnExit)
              'Browsing data will be cleared, as set in Settings.',
          ].join('\n\n'),
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          if (multiple)
            TextButton(
              onPressed: () => Navigator.pop(c, 'close_tab'),
              child: const Text('Close this tab'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'exit'),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'close_tab') {
      if (mounted)
        closeTabWithUndo(
          context,
          ProviderScope.containerOf(context, listen: false).read,
          tabsState.activeId,
        );
    } else if (choice == 'exit') {
      await _exitApp();
    }
  }

  /// Closes private tabs, applies "clear data on exit", then leaves the app.
  Future<void> _exitApp() async {
    await ref.read(tabsProvider.notifier).prepareForExit();
    await SystemNavigator.pop();
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(t), duration: const Duration(seconds: 2)),
        );
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
    ref.listen(tabsProvider.select((t) => t.active.isPrivate), (_, private) {
      SystemBrowser.setSecure(private);
    });
    ref.listen(pageDataProvider.select((d) => d['element_picked']), (_, next) {
      if (next != null && next.isNotEmpty) _showElementSheet(next);
    });
    ref.listen(pageDataProvider.select((d) => d['highlight_added']), (_, next) {
      if (next != null && next.isNotEmpty) _onHighlightAdded(next);
    });
    ref.listen(pageDataProvider.select((d) => d['highlight_tap']), (_, next) {
      if (next != null && next.isNotEmpty) _onHighlightTap('${next['id']}');
    });
    ref.listen(authPromptProvider, (_, next) {
      if (next != null) _showAuthPrompt(next);
    });
    final private = tab.isPrivate;

    // Picture-in-picture: only the (focused) video page, no browser chrome.
    if (_inPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _WebArea(
          tab: tab,
          controller: ref.read(tabsProvider.notifier).controllerFor(tab.id),
          onSearchTap: () {},
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_finding) return _closeFind();
        if (_editing) return _addressFocus.unfocus();
        final tabs = ref.read(tabsProvider.notifier);
        if (await tabs.canGoBackNow()) {
          await tabs.goBack();
        } else {
          await _onBackAtStart();
        }
      },
      // Private tabs get a dark "incognito" look, like Chrome.
      child: Theme(
        data: private ? privateTheme : Theme.of(context),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Tablets / unfolded foldables: Chrome-style tab strip.
                if (MediaQuery.sizeOf(context).width >= 840)
                  _Collapsible(
                    visible: _barsVisible(settings, tab),
                    alignment: Alignment.bottomCenter,
                    child: const TabStrip(),
                  ),
                _Collapsible(
                  visible: _barsVisible(settings, tab),
                  alignment: Alignment.bottomCenter,
                  child: _AddressBar(
                    controller: _address,
                    focus: _addressFocus,
                    editing: _editing,
                    tab: tab,
                    onSubmit: _submit,
                    onReload: () => ref.read(tabsProvider.notifier).reload(),
                    onStop: () => ref.read(tabsProvider.notifier).stop(),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TabTransition(
                          tabId: tab.id,
                          direction: ref
                              .read(tabsProvider.notifier)
                              .lastSwitchDirection,
                          child: _WebArea(
                            tab: tab,
                            controller: ref
                                .read(tabsProvider.notifier)
                                .controllerFor(tab.id),
                            onSearchTap: () => _addressFocus.requestFocus(),
                          ),
                        ),
                      ),
                      if (tab.isPrivate && ref.watch(privateLockProvider))
                        Positioned.fill(
                          child: _PrivateLocked(onUnlock: _unlockPrivate),
                        ),
                      if (tab.error != null)
                        Positioned.fill(
                          child: _ErrorPage(
                            url: tab.url,
                            message: tab.error!,
                            insecureFallback: tab.insecureFallback,
                            onRetry: () =>
                                ref.read(tabsProvider.notifier).reload(),
                            onContinueInsecure: () => ref
                                .read(tabsProvider.notifier)
                                .continueInsecure(),
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
                      if (settings.nightLight)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ColoredBox(
                              color: const Color(0xFFFF8F00).withValues(
                                alpha: settings.nightLightStrength * 0.55,
                              ),
                            ),
                          ),
                        ),
                      if (settings.pullToRefresh && !tab.isNewTab)
                        const Positioned.fill(
                          child: IgnorePointer(child: _PullIndicator()),
                        ),
                      if (settings.showDebugBubble && !_editing)
                        const DebugBubble(),
                    ],
                  ),
                ),
                if (ref.watch(readAloudProvider).active) const _ReadAloudBar(),
                if (_finding)
                  _FindBar(
                    controller: _findText,
                    onChanged: _find,
                    onClose: _closeFind,
                    onStep: (d) {
                      _js('window.__dbg && window.__dbg.findStep($d)');
                    },
                  )
                else if (!_editing)
                  _Collapsible(
                    visible: _barsVisible(settings, tab),
                    alignment: Alignment.topCenter,
                    child: _BottomBar(
                      tab: tab,
                      tabCount: tabsState.tabs.length,
                      onFind: startFind,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme used while a private tab is in front.
final ThemeData privateTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF5E35B1),
    brightness: Brightness.dark,
    surface: const Color(0xFF202124),
  ),
  scaffoldBackgroundColor: const Color(0xFF202124),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);

/// Shield with the number of blocked requests; opens per-site controls.
class _ShieldButton extends ConsumerWidget {
  final BrowserTab tab;
  const _ShieldButton({required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = ref.watch(extensionsProvider);
    final on = ext.blockerOn(tab.url);
    final n = tab.blockedCount;
    return IconButton(
      tooltip: on ? '$n blocked. Site settings' : 'Site settings',
      onPressed: () => showSiteControls(context),
      icon: Badge(
        isLabelVisible: on && n > 0,
        backgroundColor: Colors.green.shade700,
        label: Text(
          n > 99 ? '99+' : '$n',
          style: const TextStyle(fontSize: 10),
        ),
        child: Icon(
          on ? Icons.shield : Icons.shield_outlined,
          size: 20,
          color: on ? Colors.green : null,
        ),
      ),
    );
  }
}

class _WebArea extends ConsumerWidget {
  final BrowserTab tab;
  final WebViewController controller;
  final VoidCallback onSearchTap;
  const _WebArea({
    required this.tab,
    required this.controller,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab.isNewTab) {
      return Screenshot(
        controller: ref.watch(screenshotControllerProvider),
        child: NewTabPage(
          key: ValueKey('ntp-${tab.id}'),
          onSearchTap: onSearchTap,
          isPrivate: tab.isPrivate,
        ),
      );
    }
    final viewport = ref.watch(viewportProvider);
    // Keyed by tab id: switching tabs swaps the native WebView.
    final web = WebViewWidget(key: ValueKey(tab.id), controller: controller);
    Widget child = web;
    if (viewport.width != null) {
      final w = viewport.width!, h = viewport.height!;
      child = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${viewport.label} • ${w.toInt()}×${h.toInt()}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blueGrey, width: 2),
                      ),
                      child: web,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Screenshot(
      controller: ref.watch(screenshotControllerProvider),
      child: child,
    );
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
    if (url == newTabUrl) return '';
    var s = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
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
            // Swipe the address bar to switch tabs, like Chrome.
            child: GestureDetector(
              onHorizontalDragEnd: editing
                  ? null
                  : (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() < 300) return;
                      HapticFeedback.selectionClick();
                      ref
                          .read(tabsProvider.notifier)
                          .switchRelative(v < 0 ? 1 : -1);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 44,
                decoration: BoxDecoration(
                  color: editing
                      ? scheme.surfaceContainerLowest
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(editing ? 14 : 22),
                  border: Border.all(
                    color: editing ? scheme.primary : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: editing
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : const [],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    if (tab.isPrivate) ...[
                      const Tooltip(
                        message: 'Private tab',
                        child: Icon(Icons.privacy_tip, size: 18),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (ref.watch(proxyStatusProvider) ==
                        ProxyStatus.active) ...[
                      const Tooltip(
                        message: 'Traffic goes through your proxy/VPN',
                        child: Icon(
                          Icons.vpn_lock,
                          size: 18,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (editing || tab.isNewTab)
                      Icon(
                        Icons.search,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      )
                    else
                      GestureDetector(
                        onTap: () => _showSiteInfo(context),
                        child: Icon(
                          tab.isSecure
                              ? Icons.lock_outline
                              : Icons.info_outline,
                          size: 18,
                          color: tab.isSecure
                              ? scheme.onSurfaceVariant
                              : scheme.error,
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
                    if (!editing && !tab.isNewTab) _ShieldButton(tab: tab),
                    if (editing)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: controller.clear,
                      )
                    else
                      IconButton(
                        tooltip: tab.isLoading ? 'Stop' : 'Reload',
                        icon: Icon(
                          tab.isLoading ? Icons.close : Icons.refresh,
                          size: 20,
                        ),
                        onPressed: tab.isLoading ? onStop : onReload,
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: tab.isLoading
                ? LinearProgressIndicator(value: tab.progress, minHeight: 2)
                : null,
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
              Row(
                children: [
                  Icon(
                    tab.isSecure ? Icons.lock : Icons.warning_amber,
                    color: tab.isSecure ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tab.isSecure
                          ? 'Connection is secure. Information you send to this site is encrypted.'
                          : 'Connection is not secure. Don\'t enter passwords or payment details on this site.',
                    ),
                  ),
                ],
              ),
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
  const _BottomBar({
    required this.tab,
    required this.tabCount,
    required this.onFind,
  });

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
                onPressed: tab.canNavigateBack ? tabs.goBack : null,
              ),
              IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward),
                onPressed: tab.canGoForward ? tabs.goForward : null,
              ),
              IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: tabs.goHome,
              ),
              GestureDetector(
                // Long-press: new tab, private tab, reopen, close.
                onLongPress: () => showTabsQuickMenu(
                  context,
                  ProviderScope.containerOf(context, listen: false).read,
                ),
                child: IconButton(
                  tooltip: 'Tabs (long-press for more)',
                  onPressed: () async {
                    // Preview of the current page for the switcher.
                    await captureActiveTabThumbnail(ref);
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TabSwitcherPage(),
                        ),
                      );
                    }
                  },
                  icon: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    // The count pops when tabs are opened or closed.
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween(begin: 0.4, end: 1.0).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.elasticOut,
                          ),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        tabCount > 99 ? ':D' : '$tabCount',
                        key: ValueKey(tabCount),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
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
          if (ql.isNotEmpty &&
              !url.toLowerCase().contains(ql) &&
              !title.toLowerCase().contains(ql)) {
            return;
          }
          seen.add(url);
          matches.add((icon, title.isEmpty ? url : title, url));
        }

        for (final b in bookmarks) {
          add(Icons.star_outline, b);
        }
        for (final h in history) {
          add(Icons.history, h);
        }

        final shortcut = matchShortcut(q, ref.watch(searchShortcutsProvider));
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (q.isEmpty) _PasteChip(onPaste: onSearch),
              if (shortcut != null)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      shortcut.$1.keyword,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(
                    shortcut.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Search ${shortcut.$1.name}'),
                  onTap: () => onSearch(q),
                )
              else if (q.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${engine.label} search'),
                  onTap: () => onSearch(q),
                ),
              if (q.isNotEmpty)
                for (final sug
                    in ref.watch(searchSuggestionsProvider(q)).value ??
                        const <String>[])
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.search, size: 20),
                    title: Text(
                      sug,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSearch(sug),
                    trailing: IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.north_west, size: 18),
                      onPressed: () {
                        final c = listenable as TextEditingController;
                        c.text = '$sug ';
                        c.selection = TextSelection.collapsed(
                          offset: c.text.length,
                        );
                      },
                    ),
                  ),
              if (q.isEmpty && matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your bookmarks and recent sites appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final (icon, title, url) in matches)
                ListTile(
                  leading: Badge(
                    // Small kind marker (bookmark / history) on the site icon.
                    backgroundColor: Colors.transparent,
                    alignment: AlignmentDirectional.bottomEnd,
                    offset: const Offset(4, 4),
                    label: Icon(icon, size: 12),
                    child: SiteIcon(url: url, size: 24),
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _AddressBar.displayUrl(url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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

/// "Paste and go" when the clipboard has text. Only checks *whether* there
/// is text (no "pasted from" toast); the text is read when tapped.
class _PasteChip extends StatelessWidget {
  final void Function(String) onPaste;
  const _PasteChip({required this.onPaste});

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: Clipboard.hasStrings(),
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(Icons.content_paste_go, size: 18),
            label: const Text('Paste and go'),
            onPressed: () async {
              final text =
                  (await Clipboard.getData(
                    Clipboard.kTextPlain,
                  ))?.text?.trim() ??
                  '';
              if (text.isEmpty) return;
              HapticFeedback.selectionClick();
              onPaste(text.length > 2000 ? text.substring(0, 2000) : text);
            },
          ),
        ),
      );
    },
  );
}

class _FindBar extends ConsumerWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final VoidCallback onClose;
  final void Function(int delta) onStep;
  const _FindBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    required this.onStep,
  });

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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Find in page',
                    border: InputBorder.none,
                  ),
                  onChanged: onChanged,
                  onSubmitted: (_) => onStep(1),
                ),
              ),
              Text(
                controller.text.isEmpty
                    ? ''
                    : '${count == 0 ? 0 : index + 1}/$count',
                style: const TextStyle(color: Colors.grey),
              ),
              IconButton(
                tooltip: 'Previous',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: count > 0 ? () => onStep(-1) : null,
              ),
              IconButton(
                tooltip: 'Next',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: count > 0 ? () => onStep(1) : null,
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final String url;
  final String message;
  final VoidCallback onRetry;

  /// Set when HTTPS-only upgraded an http:// address and https failed.
  final String? insecureFallback;
  final VoidCallback onContinueInsecure;
  const _ErrorPage({
    required this.url,
    required this.message,
    required this.onRetry,
    required this.insecureFallback,
    required this.onContinueInsecure,
  });

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
              Icon(
                insecureFallback != null ? Icons.lock_open : Icons.cloud_off,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                insecureFallback != null
                    ? "This site doesn't support a secure connection"
                    : "This site can't be reached",
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(host, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              if (insecureFallback != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'HTTPS-only mode tried the secure version. Anyone on your network could see or '
                  'change what you send to the insecure version.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onContinueInsecure,
                  child: const Text('Continue to site (not secure)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides a toolbar out of view and gives its space to the page.
class _Collapsible extends StatelessWidget {
  final bool visible;
  final Alignment alignment;
  final Widget child;
  const _Collapsible({
    required this.visible,
    required this.alignment,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final fast = MediaQuery.of(context).disableAnimations;
    return ClipRect(
      child: AnimatedAlign(
        alignment: alignment,
        heightFactor: visible ? 1 : 0,
        duration: fast ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// Pull-to-refresh spinner driven by the page's pull gesture.
class _PullIndicator extends ConsumerWidget {
  const _PullIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.read(tabsProvider.notifier);
    return ValueListenableBuilder<double?>(
      valueListenable: tabs.pullDistance,
      builder: (context, d, _) {
        if (d == null) return const SizedBox.shrink();
        final p = (d / TabsNotifier.pullTrigger).clamp(0.0, 1.0);
        final ready = p >= 1;
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 8 + 48 * p),
            child: Opacity(
              opacity: (p * 1.5).clamp(0.0, 1.0),
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: scheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Transform.rotate(
                    angle: p * 3.14159 * 1.5,
                    child: Icon(
                      Icons.refresh,
                      color: ready ? scheme.primary : scheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown over private tabs while they're locked.
class _PrivateLocked extends StatelessWidget {
  final VoidCallback onUnlock;
  const _PrivateLocked({required this.onUnlock});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1B1036),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock, size: 56, color: Color(0xFFB39DDB)),
        const SizedBox(height: 16),
        const Text(
          'Private tabs are locked',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use your fingerprint, face or screen lock to continue.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onUnlock,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Unlock'),
        ),
      ],
    ),
  );
}

/// Player controls while an article is being read aloud.
class _ReadAloudBar extends ConsumerWidget {
  const _ReadAloudBar();

  static const _rates = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(readAloudProvider);
    final n = ref.read(readAloudProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: st.status == ReadAloudStatus.loading ? null : st.progress,
            minHeight: 2,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            child: Row(
              children: [
                const Icon(Icons.record_voice_over, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    st.title.isEmpty ? 'Reading aloud' : st.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous paragraph',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => n.skip(-1),
                ),
                IconButton(
                  tooltip: st.status == ReadAloudStatus.playing
                      ? 'Pause'
                      : 'Play',
                  icon: Icon(
                    st.status == ReadAloudStatus.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: st.status == ReadAloudStatus.playing
                      ? n.pause
                      : n.resume,
                ),
                IconButton(
                  tooltip: 'Next paragraph',
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => n.skip(1),
                ),
                TextButton(
                  onPressed: () {
                    final i = _rates.indexOf(st.rate);
                    n.setRate(_rates[(i + 1) % _rates.length]);
                  },
                  child: Text('${st.rate}×'),
                ),
                IconButton(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.close),
                  onPressed: n.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animates changing tabs: slide from the right/left when moving to the
/// next/previous tab (swipe on the address bar, new tab), and fade + slight
/// zoom when jumping (tab switcher, closing a tab). Navigating within a tab
/// doesn't animate (same key).
class TabTransition extends StatelessWidget {
  final String tabId;

  /// +1 next, -1 previous, 0 jump.
  final int direction;
  final Widget child;
  const TabTransition({
    super.key,
    required this.tabId,
    required this.direction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduce
            ? Duration.zero
            : Duration(milliseconds: direction == 0 ? 260 : 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey(tabId);
          if (direction == 0) {
            return FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(
                  begin: incoming ? 0.94 : 1.03,
                  end: 1.0,
                ).animate(anim),
                child: child,
              ),
            );
          }
          // Incoming enters from the swipe side; outgoing leaves the other way.
          final from = Offset(
            (incoming ? direction : -direction).toDouble(),
            0,
          );
          return SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(anim),
            child: FadeTransition(
              opacity: Tween(begin: 0.6, end: 1.0).animate(anim),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(tabId), child: child),
      ),
    );
  }
}

/// Horizontal tab strip for wide screens.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final private = state.active.isPrivate;
    final shown = state.tabs.where((t) => t.isPrivate == private).toList();
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 6, top: 4),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final t = shown[i];
                  final active = t.id == state.activeId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Material(
                      color: active ? scheme.surface : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                      child: InkWell(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                        onTap: () => tabs.activate(t.id),
                        child: SizedBox(
                          width: 200,
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              if (t.isNewTab)
                                Icon(
                                  t.isPrivate
                                      ? Icons.privacy_tip_outlined
                                      : Icons.home_outlined,
                                  size: 16,
                                )
                              else
                                SiteIcon(url: t.url, size: 16, radius: 3),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                tooltip: 'Close tab',
                                icon: const Icon(Icons.close),
                                onPressed: () => closeTabWithUndo(
                                  context,
                                  ProviderScope.containerOf(
                                    context,
                                    listen: false,
                                  ).read,
                                  t.id,
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
            ),
            IconButton(
              tooltip: 'New tab',
              icon: const Icon(Icons.add),
              onPressed: () => tabs.newTab(private: private),
            ),
          ],
        ),
      ),
    );
  }
}
