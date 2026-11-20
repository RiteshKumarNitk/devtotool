import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'browser_native.dart';
import 'browser_settings.dart';
import 'downloads.dart';
import 'extensions.dart';
import 'favicons.dart';
import 'highlights.dart';
import 'search_shortcuts.dart';
import 'home_stats.dart';
import 'js_bridge.dart';
import 'providers.dart';
import 'scripts/debug_sdk_extras.dart';
import 'scripts/debug_sdk_string.dart';
import 'tool_providers.dart';

const int maxTabs = 30;

@immutable
class BrowserTab {
  final String id;
  final String url;
  final String title;
  final double progress;
  final bool isLoading;
  final bool canGoBack;
  final bool canGoForward;

  /// Main-frame load error, shown as an error page.
  final String? error;

  /// False for restored tabs that haven't been opened yet (lazy load).
  final bool loaded;

  /// Private tab: separate cookie/storage profile, no history, not restored.
  final bool isPrivate;

  /// Requests blocked by the ad/tracker blocker on the current page.
  final int blockedCount;
  final Map<String, int> blockedDomains;

  /// Last real page in this tab's WebView (kept while the New Tab page shows).
  final String? lastWebUrl;
  final String? lastWebTitle;

  /// The tab came from the New Tab page: back at the start returns to it.
  final bool ntpBehind;

  /// HTTPS-only: the http:// address whose secure version failed to load.
  final String? insecureFallback;

  /// Tab that opened this one (link in new tab): back at the start returns
  /// there, like Chrome.
  final String? openerId;

  /// Tab group name (null = ungrouped).
  final String? group;

  const BrowserTab({
    required this.id,
    required this.url,
    this.title = '',
    this.progress = 0,
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.error,
    this.loaded = true,
    this.isPrivate = false,
    this.blockedCount = 0,
    this.blockedDomains = const {},
    this.lastWebUrl,
    this.lastWebTitle,
    this.ntpBehind = false,
    this.insecureFallback,
    this.openerId,
    this.group,
  });

  bool get isNewTab => url == newTabUrl;
  bool get isSecure => url.startsWith('https://');
  String get displayTitle => isNewTab
      ? (isPrivate ? 'Private tab' : 'New tab')
      : title.isNotEmpty
          ? title
          : (Uri.tryParse(url)?.host ?? url);

  /// Whether Back does something (page history, or the New Tab page).
  /// Whether the toolbar Back button does something here. Every page has a
  /// way back (history, opener tab or the New Tab page); the New Tab page
  /// is the end, where Back offers to exit.
  bool get canNavigateBack => !isNewTab;

  BrowserTab copyWith({
    String? url,
    String? title,
    double? progress,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    String? Function()? error,
    bool? loaded,
    int? blockedCount,
    Map<String, int>? blockedDomains,
    String? Function()? lastWebUrl,
    String? Function()? lastWebTitle,
    bool? ntpBehind,
    String? Function()? insecureFallback,
    String? Function()? group,
  }) =>
      BrowserTab(
        id: id,
        url: url ?? this.url,
        title: title ?? this.title,
        progress: progress ?? this.progress,
        isLoading: isLoading ?? this.isLoading,
        canGoBack: canGoBack ?? this.canGoBack,
        canGoForward: canGoForward ?? this.canGoForward,
        error: error != null ? error() : this.error,
        loaded: loaded ?? this.loaded,
        isPrivate: isPrivate,
        blockedCount: blockedCount ?? this.blockedCount,
        blockedDomains: blockedDomains ?? this.blockedDomains,
        lastWebUrl: lastWebUrl != null ? lastWebUrl() : this.lastWebUrl,
        lastWebTitle: lastWebTitle != null ? lastWebTitle() : this.lastWebTitle,
        ntpBehind: ntpBehind ?? this.ntpBehind,
        insecureFallback: insecureFallback != null ? insecureFallback() : this.insecureFallback,
        openerId: openerId,
        group: group != null ? group() : this.group,
      );
}

/// Private tabs are locked (after leaving the app, if enabled).
class PrivateLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void lock() => state = true;
  void unlock() => state = false;
}

final privateLockProvider = NotifierProvider<PrivateLockNotifier, bool>(PrivateLockNotifier.new);

/// What Back does next in the active tab.
enum BackStep { history, opener, newTab, exit }

/// Browser-like Back order: page history, then the tab that opened this one,
/// then the New Tab page; on the New Tab page itself, exit (with a prompt).
BackStep decideBack({
  required bool onNewTabPage,
  required bool hasHistory,
  required bool hasOpener,
  required bool newTabPageEnabled,
}) {
  if (onNewTabPage) return BackStep.exit;
  if (hasHistory) return BackStep.history;
  if (hasOpener) return BackStep.opener;
  if (newTabPageEnabled) return BackStep.newTab;
  return BackStep.exit;
}

@immutable
class TabsState {
  final List<BrowserTab> tabs;
  final String activeId;
  const TabsState(this.tabs, this.activeId);

  BrowserTab get active => tabs.firstWhere((t) => t.id == activeId, orElse: () => tabs.first);
  int get activeIndex => tabs.indexWhere((t) => t.id == activeId);
}

/// A tab the user closed, kept so it can be reopened (session only; never
/// private tabs or the New Tab page).
@immutable
class ClosedTab {
  final String url;
  final String title;
  final String? group;
  final int index;
  final DateTime closedAt;
  const ClosedTab({required this.url, required this.title, required this.index, required this.closedAt, this.group});
}

class RecentlyClosedNotifier extends Notifier<List<ClosedTab>> {
  static const max = 25;
  @override
  List<ClosedTab> build() => const [];

  void push(ClosedTab t) {
    state = [t, ...state.where((x) => x.url != t.url)].take(max).toList();
  }

  ClosedTab? pop([ClosedTab? which]) {
    if (state.isEmpty) return null;
    final t = which ?? state.first;
    state = [...state]..remove(t);
    return t;
  }

  void clear() => state = const [];
}

final recentlyClosedProvider = NotifierProvider<RecentlyClosedNotifier, List<ClosedTab>>(RecentlyClosedNotifier.new);

/// A page asked for a link menu (long-press). Shown by the browser shell.
@immutable
class LinkMenuRequest {
  final String href;
  final String text;
  final String image;
  final int nonce;
  const LinkMenuRequest(this.href, this.text, this.image, this.nonce);
}

class LinkMenuNotifier extends Notifier<LinkMenuRequest?> {
  int _n = 0;
  @override
  LinkMenuRequest? build() => null;
  void show(Map<String, dynamic> d) =>
      state = LinkMenuRequest('${d['href'] ?? ''}', '${d['text'] ?? ''}', '${d['image'] ?? ''}', _n++);
}

final linkMenuProvider = NotifierProvider<LinkMenuNotifier, LinkMenuRequest?>(LinkMenuNotifier.new);

/// A site (not our proxy) asked for HTTP authentication. Shown as a dialog.
@immutable
class AuthPrompt {
  final String host;
  final String? realm;
  final void Function(String user, String password) proceed;
  final void Function() cancel;
  const AuthPrompt(this.host, this.realm, this.proceed, this.cancel);
}

class AuthPromptNotifier extends Notifier<AuthPrompt?> {
  @override
  AuthPrompt? build() => null;
  void show(AuthPrompt p) => state = p;
  void clear() => state = null;
}

final authPromptProvider = NotifierProvider<AuthPromptNotifier, AuthPrompt?>(AuthPromptNotifier.new);

/// Schemes the WebView handles itself; anything else goes to another app.
const _webSchemes = {'http', 'https', 'about', 'data', 'blob', 'javascript', 'file'};

/// For `intent://…#Intent;…;S.browser_fallback_url=…;end` returns the fallback.
@visibleForTesting
String? intentFallbackUrl(String url) {
  final m = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
  if (m == null) return null;
  final decoded = Uri.decodeComponent(m.group(1)!);
  return decoded.startsWith('http') ? decoded : null;
}

class TabsNotifier extends Notifier<TabsState> {
  static const _storeKey = 'openTabs';
  final Map<String, WebViewController> _controllers = {};
  final Set<String> _sdkActive = {};

  /// Per tab: main-frame URLs sent to the WebView with no page started yet.
  /// The Android plugin reports a download as a second navigation request
  /// for such a URL, which is how downloads are detected.
  final Map<String, Set<String>> _pendingNav = {};

  /// URLs the download probe found to be ordinary pages: navigate next time.
  final Set<String> _forceNavigate = {};

  /// Notifies the UI that a download started (file name), for a snackbar.
  final downloadStarted = ValueNotifier<String?>(null);

  /// User-facing message, e.g. private browsing unsupported on this device.
  final notice = ValueNotifier<String?>(null);

  /// URL of the last pop-up the blocker stopped (UI offers "Open anyway").
  final popupBlocked = ValueNotifier<String?>(null);

  /// Auto-hiding toolbars: false while the user scrolls down a page.
  final toolbarsVisible = ValueNotifier<bool>(true);

  bool _toolbarsFrozen = false;

  /// Keeps the toolbars shown and still (screenshots resize-sensitive work).
  void freezeToolbars(bool frozen) {
    _toolbarsFrozen = frozen;
    if (frozen) toolbarsVisible.value = true;
  }

  /// Pull to refresh: current pull distance in px, or null when not pulling.
  final pullDistance = ValueNotifier<double?>(null);
  static const double pullTrigger = 110;

  /// HTTPS-only: per tab, the original http:// URL of an upgrade in flight.
  final Map<String, String> _upgradedFrom = {};

  /// Hosts allowed over http this session (no https, or the user chose so).
  final Set<String> _httpAllowed = {};

  /// Host -> when we last upgraded it (detects https->http redirect loops).
  final Map<String, DateTime> _recentUpgrades = {};

  /// Private tabs whose WebView isn't in the private profile yet: never load.
  final Set<String> _awaitingProfile = {};

  /// Times the proxy rejected the saved credentials (avoids an auth loop).
  int _proxyAuthFailures = 0;
  int _seq = 0;

  Box? get _box => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;
  BrowserSettings get _settings => ref.read(browserSettingsProvider);

  WebViewController controllerFor(String id) => _controllers[id]!;
  WebViewController get activeController => _controllers[state.activeId]!;

  @override
  TabsState build() {
    ref.listen(networkMocksProvider, (_, next) => _pushAll(_mocksJs(next)));
    ref.listen(networkConditionProvider, (_, next) => _pushAll(_conditionJs(next)));
    ref.listen(geoOverrideProvider, (_, next) => _pushAll(_geoJs(next)));
    ref.listen(userAgentProvider, (_, __) => _applyUserAgents());
    ref.listen(browserSettingsProvider.select((s) => s.desktopMode), (_, __) => _applyUserAgents());
    ref.listen(proxySettingsProvider, (_, next) => _applyProxy(next));
    ref.listen(extensionsProvider, (prev, next) => _onExtensionsChanged(prev, next));
    ref.listen(userScriptsProvider, (_, __) => _reapplyExtensions());
    Future.microtask(() => _applyProxy(ref.read(proxySettingsProvider)));
    // Wipe anything a crashed private session left behind.
    BrowserNative.clearPrivateData();
    // "Clear data on exit" also runs at start, in case Android killed the
    // app without a clean exit.
    if (_settings.clearOnExit) Future.microtask(_clearBrowsingData);

    final restored = <BrowserTab>[];
    var activeIndex = 0;
    final saved = _settings.restoreTabs ? _box?.get(_storeKey) : null;
    if (saved is Map && saved['tabs'] is List) {
      for (final t in (saved['tabs'] as List).whereType<Map>().take(maxTabs)) {
        final url = '${t['url'] ?? ''}';
        if (!url.startsWith('http') && url != newTabUrl && !url.startsWith('file://')) continue;
        restored.add(BrowserTab(
          id: _newId(),
          url: url,
          title: '${t['title'] ?? ''}',
          loaded: false,
          group: t['group'] is String && (t['group'] as String).isNotEmpty ? t['group'] as String : null,
        ));
      }
      activeIndex = (saved['active'] as num?)?.toInt() ?? 0;
    }
    if (restored.isEmpty) {
      final tab = BrowserTab(id: _newId(), url: _settings.homepage, loaded: false);
      restored.add(tab);
    }
    activeIndex = activeIndex.clamp(0, restored.length - 1);
    for (final t in restored) {
      _controllers[t.id] = _createController(t.id);
    }
    final initial = TabsState(restored, restored[activeIndex].id);
    // Load the active tab after build() returns.
    Future.microtask(() => _ensureLoaded(initial.activeId));
    return initial;
  }

  String _newId() => 't${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  // ------------------------------------------------------------------ tabs

  String newTab({String? url, bool activate = true, bool private = false, String? openerId}) {
    if (state.tabs.length >= maxTabs) {
      // Reuse the oldest inactive tab rather than growing unbounded.
      final victim = state.tabs.firstWhere((t) => t.id != state.activeId);
      closeTab(victim.id);
    }
    final id = _newId();
    final tab = BrowserTab(
      id: id,
      url: url ?? _settings.homepage,
      loaded: false,
      isPrivate: private,
      openerId: openerId,
    );
    if (private) _privatePending.add(id);
    _controllers[id] = _createController(id);
    _privatePending.remove(id);
    if (private) {
      _awaitingProfile.add(id);
      _attachPrivateProfile(id);
    }
    final tabs = [...state.tabs];
    // Like Chrome: open next to the current tab.
    tabs.insert(state.activeIndex + 1, tab);
    state = TabsState(tabs, activate ? id : state.activeId);
    if (activate) {
      lastSwitchDirection = 1; // new tabs open to the right
      _onActivated(id);
    }
    _persist();
    return id;
  }

  void closeTab(String id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final closing = state.tabs[i];
    if (!closing.isPrivate && !closing.isNewTab && closing.url.startsWith('http')) {
      ref.read(recentlyClosedProvider.notifier).push(ClosedTab(
            url: closing.url,
            title: closing.displayTitle,
            group: closing.group,
            index: i,
            closedAt: DateTime.now(),
          ));
    }
    final tabs = [...state.tabs]..removeAt(i);
    _controllers.remove(id)?.loadRequest(Uri.parse('about:blank'));
    _sdkActive.remove(id);
    _pendingNav.remove(id);
    _awaitingProfile.remove(id);
    ref.read(tabThumbnailsProvider.notifier).remove(id);
    _extReady.remove(id);
    final wasPrivate = state.tabs[i].isPrivate;
    if (tabs.isEmpty) {
      final fresh = BrowserTab(id: _newId(), url: _settings.homepage, loaded: false);
      _controllers[fresh.id] = _createController(fresh.id);
      lastSwitchDirection = 0;
      state = TabsState([fresh], fresh.id);
      _onActivated(fresh.id);
    } else if (id == state.activeId) {
      final next = tabs[i.clamp(0, tabs.length - 1)];
      lastSwitchDirection = 0; // closing a tab: fade to the neighbour
      state = TabsState(tabs, next.id);
      _onActivated(next.id);
    } else {
      state = TabsState(tabs, state.activeId);
    }
    if (wasPrivate && !state.tabs.any((t) => t.isPrivate)) {
      // Last private tab closed: forget its cookies and site data.
      BrowserNative.clearPrivateData();
    }
    _persist();
  }

  /// Reopens the last closed tab (or [which]) at its old position.
  /// Returns false when there is nothing to reopen.
  bool reopenClosed([ClosedTab? which]) {
    final t = ref.read(recentlyClosedProvider.notifier).pop(which);
    if (t == null) return false;
    final id = newTab(url: t.url);
    final tabs = [...state.tabs];
    final cur = tabs.indexWhere((x) => x.id == id);
    final tab = tabs.removeAt(cur).copyWith(title: t.title, group: () => t.group);
    tabs.insert(t.index.clamp(0, tabs.length), tab);
    state = TabsState(tabs, state.activeId);
    _persist();
    return true;
  }

  /// Called before the app exits from the Back prompt.
  Future<void> prepareForExit() async {
    closePrivateTabs();
    await BrowserNative.clearPrivateData();
    if (_settings.clearOnExit) await _clearBrowsingData();
  }

  Future<void> _clearBrowsingData() async {
    ref.read(historyProvider.notifier).clear();
    ref.read(recentlyClosedProvider.notifier).clear();
    await WebViewCookieManager().clearCookies();
    for (final c in _controllers.values) {
      await c.clearCache().catchError((Object _) {});
      await c.clearLocalStorage().catchError((Object _) {});
    }
  }

  /// Activates the next/previous tab of the same kind (normal or private).
  void switchRelative(int delta) {
    final private = state.active.isPrivate;
    final same = state.tabs.where((t) => t.isPrivate == private).toList();
    if (same.length < 2) return;
    final i = same.indexWhere((t) => t.id == state.activeId);
    activate(same[(i + delta + same.length) % same.length].id, direction: delta.sign);
  }

  /// Closes every private tab (and wipes private data).
  void closePrivateTabs() {
    for (final t in [...state.tabs]) {
      if (t.isPrivate) closeTab(t.id);
    }
  }

  void closeAll() {
    for (final t in [...state.tabs]) {
      if (t.id != state.activeId) closeTab(t.id);
    }
    closeTab(state.activeId);
  }

  /// How the last tab change happened, for the page transition:
  /// +1 next (slide from right), -1 previous (from left), 0 jump (fade).
  int lastSwitchDirection = 0;

  void activate(String id, {int direction = 0}) {
    if (id == state.activeId || !_controllers.containsKey(id)) return;
    lastSwitchDirection = direction;
    state = TabsState(state.tabs, id);
    _onActivated(id);
    _persist();
  }

  void _onActivated(String id) {
    toolbarsVisible.value = true;
    pullDistance.value = null;
    // Dev tools follow the active tab.
    ref.read(webViewControllerProvider.notifier).setController(_controllers[id]!);
    ref.read(pageDataProvider.notifier).clear();
    ref.read(domTreeProvider.notifier).setTree({});
    final tab = _tab(id);
    if (tab != null) ref.read(currentPageProvider.notifier).set(tab.url, tab.title);
    _ensureLoaded(id);
  }

  void _ensureLoaded(String id) {
    final tab = _tab(id);
    if (tab == null || _awaitingProfile.contains(id)) return;
    if (id == state.activeId) {
      ref.read(webViewControllerProvider.notifier).setController(_controllers[id]!);
    }
    if (!tab.loaded && tab.isNewTab) {
      _patch(id, (t) => t.copyWith(loaded: true));
      return;
    }
    if (!tab.loaded) {
      _patch(id, (t) => t.copyWith(loaded: true));
      final ready = _extReady[id] ?? Future<void>.value();
      ready.whenComplete(() {
        _applyJsMode(id, tab.url);
        _loadInto(id, normaliseUrlInput(tab.url));
      });
    }
  }

  // ------------------------------------------------------------ navigation

  void loadInput(String text) {
    final shortcut = matchShortcut(text, ref.read(searchShortcutsProvider));
    if (shortcut != null) {
      loadUri(shortcut.$1.uriFor(shortcut.$2));
      return;
    }
    final engine = _settings.engine;
    loadUri(normaliseUrlInput(text, search: engine.searchUri));
  }

  // ------------------------------------------------------------ tab groups

  /// Group names in use (in tab order).
  List<String> get groups => <String>{
        for (final t in state.tabs)
          if (t.group != null) t.group!,
      }.toList();

  void setGroup(String tabId, String? group) {
    final g = group?.trim();
    _patch(tabId, (t) => t.copyWith(group: () => (g == null || g.isEmpty) ? null : g));
    _persist();
  }

  void renameGroup(String from, String to) {
    final name = to.trim();
    if (name.isEmpty) return;
    state = TabsState([for (final t in state.tabs) t.group == from ? t.copyWith(group: () => name) : t], state.activeId);
    _persist();
  }

  void ungroup(String group) {
    state = TabsState([for (final t in state.tabs) t.group == group ? t.copyWith(group: () => null) : t], state.activeId);
    _persist();
  }

  /// Plays every video/audio on the page (all frames) at [rate].
  void setVideoRate(double rate) => activeController
      .runJavaScript('window.__dbg_setVideoRate && window.__dbg_setVideoRate($rate)')
      .catchError((Object _) {});

  /// JavaScript per site (NoScript-style): set before each navigation.
  void _applyJsMode(String id, String url) {
    final on = ref.read(extensionsProvider).jsOn(url);
    final wasOff = _jsOff.contains(id);
    if (on == !wasOff) return;
    on ? _jsOff.remove(id) : _jsOff.add(id);
    _controllers[id]?.setJavaScriptMode(on ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
  }

  final Set<String> _jsOff = {};

  void loadUri(Uri uri, {String? tabId}) {
    final id = tabId ?? state.activeId;
    if (uri.toString() == newTabUrl) {
      showNewTabPage(tabId: id);
      return;
    }
    if (_settings.httpsOnly && shouldUpgradeToHttps(uri, allowedHttpHosts: _httpAllowed)) {
      _upgradedFrom[id] = uri.toString();
      _recentUpgrades[uri.host.toLowerCase()] = DateTime.now();
      uri = uri.replace(scheme: 'https', port: uri.hasPort && uri.port != 80 ? uri.port : null);
    } else {
      _upgradedFrom.remove(id);
    }
    final fromNtp = _tab(id)?.isNewTab ?? false;
    _patch(id, (t) => t.copyWith(
          url: uri.toString(),
          loaded: true,
          error: () => null,
          insecureFallback: () => null,
          // Back from the first page returns to the New Tab page, unless
          // the WebView already has history of its own.
          ntpBehind: fromNtp ? t.lastWebUrl == null : t.ntpBehind,
        ));
    _sdkActive.remove(id);
    _pendingNav.putIfAbsent(id, () => {}).add(uri.toString());
    _loadInto(id, uri);
  }

  /// Loads [uri] in a tab's WebView; local files (saved offline pages) go
  /// through WebView's file loader.
  void _loadInto(String id, Uri uri) {
    final c = _controllers[id];
    if (c == null) return;
    _applyJsMode(id, uri.toString());
    if (uri.scheme == 'file') {
      c.loadFile(uri.toFilePath());
    } else {
      c.loadRequest(uri);
    }
  }

  void goHome() => loadUri(normaliseUrlInput(_settings.homepage));

  /// HTTPS-only fallback: the user chose to open the site without https.
  void continueInsecure() {
    final tab = state.active;
    final url = tab.insecureFallback;
    if (url == null) return;
    final uri = Uri.parse(url);
    _httpAllowed.add(uri.host.toLowerCase());
    loadUri(uri, tabId: tab.id);
  }

  /// Shows the built-in New Tab page in a tab, keeping its WebView page.
  void showNewTabPage({String? tabId}) {
    final id = tabId ?? state.activeId;
    _patch(id, (t) => t.copyWith(
          url: newTabUrl,
          title: '',
          loaded: true,
          isLoading: false,
          error: () => null,
          blockedCount: 0,
          blockedDomains: const {},
        ));
    if (id == state.activeId) {
      ref.read(currentPageProvider.notifier).set('', 'New tab');
      ref.read(pageDataProvider.notifier).clear();
    }
    _persist();
  }

  /// Whether Back can do something in the active tab.
  /// Browser-like Back, in order: page history -> the tab that opened this
  /// one -> the New Tab page. The New Tab page is the end (the app then asks
  /// whether to exit).
  Future<BackStep> backStep() async {
    final tab = state.active;
    return decideBack(
      onNewTabPage: tab.isNewTab,
      hasHistory: !tab.isNewTab && tab.error == null && await activeController.canGoBack(),
      hasOpener: tab.openerId != null && _tab(tab.openerId!) != null,
      newTabPageEnabled: _settings.newTabPage,
    );
  }

  Future<bool> canGoBackNow() async => await backStep() != BackStep.exit;

  Future<void> goBack() async {
    final tab = state.active;
    switch (await backStep()) {
      case BackStep.history:
        await activeController.goBack();
      case BackStep.opener:
        final opener = tab.openerId!;
        closeTab(tab.id);
        activate(opener);
      case BackStep.newTab:
        showNewTabPage(tabId: tab.id);
      case BackStep.exit:
        break;
    }
  }

  Future<void> goForward() async {
    final c = activeController;
    if (await c.canGoForward()) await c.goForward();
  }

  void reload() {
    final tab = state.active;
    if (tab.isNewTab) return;
    _sdkActive.remove(tab.id);
    if (tab.error != null) {
      loadUri(normaliseUrlInput(tab.url));
    } else {
      activeController.reload();
    }
  }

  void stop() => activeController.runJavaScript('window.stop()');

  Future<void> hardReload() async {
    final c = activeController;
    await c.clearCache();
    await c.clearLocalStorage();
    await WebViewCookieManager().clearCookies();
    ref.read(consoleLogsProvider.notifier).clear();
    ref.read(networkRequestsProvider.notifier).clear();
    reload();
  }

  // ------------------------------------------------------------- internals

  BrowserTab? _tab(String id) {
    for (final t in state.tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _patch(String id, BrowserTab Function(BrowserTab) change) {
    if (_tab(id) == null) return;
    state = TabsState([for (final t in state.tabs) t.id == id ? change(t) : t], state.activeId);
  }

  void _persist() {
    _box?.put(_storeKey, {
      'tabs': [
        for (final t in state.tabs)
          if (!t.isPrivate) {'url': t.url, 'title': t.title, if (t.group != null) 'group': t.group},
      ],
      'active': state.tabs.where((t) => !t.isPrivate).toList().indexWhere((t) => t.id == state.activeId).clamp(0, 999),
    });
  }

  String? _userAgent() {
    final custom = ref.read(userAgentProvider);
    if (custom != 'default') return custom;
    return _settings.desktopMode ? desktopUserAgent : null;
  }

  void _applyUserAgents() {
    final ua = _userAgent();
    for (final c in _controllers.values) {
      c.setUserAgent(ua);
    }
    reload();
  }

  WebViewController _createController(String id) {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) => _onNavigationRequest(id, req),
        onProgress: (p) => _patch(id, (t) => t.copyWith(progress: p / 100.0)),
        onUrlChange: (change) {
          final url = change.url;
          if (url == null) return;
          if (_tab(id)?.isNewTab == true) {
            _patch(id, (t) => t.copyWith(lastWebUrl: () => url));
          } else {
            _patch(id, (t) => t.copyWith(url: url));
          }
        },
        onPageStarted: (url) {
          _sdkActive.remove(id);
          _pendingNav[id]?.clear();
          _patch(id, (t) => t.copyWith(blockedCount: 0, blockedDomains: const {}));
          _applyTextZoom(id, url);
          if (_tab(id)?.isNewTab == true) return;
          _patch(id, (t) => t.copyWith(url: url, isLoading: true, progress: 0.05, error: () => null));
          if (id == state.activeId) toolbarsVisible.value = true;
          if (id == state.activeId) {
            ref.read(pageDataProvider.notifier).clear();
            ref.read(domTreeProvider.notifier).setTree({});
          }
        },
        onPageFinished: (url) => _onPageFinished(id, url),
        onHttpAuthRequest: (req) => _onHttpAuth(id, req),
        onWebResourceError: (e) {
          if (e.isForMainFrame != true) return;
          // -999/cancelled navigations aren't real errors.
          if (e.errorType == WebResourceErrorType.unknown && e.description.toLowerCase().contains('cancel')) return;
          final httpUrl = _upgradedFrom.remove(id);
          _patch(id, (t) => t.copyWith(
                isLoading: false,
                error: () => e.description,
                insecureFallback: () => httpUrl,
              ));
          if (id == state.activeId) {
            ref.read(consoleLogsProvider.notifier).addLog(ConsoleLog(
                  level: 'error',
                  message: '[Navigation] ${e.errorCode}: ${e.description}',
                  timestamp: DateTime.now(),
                ));
          }
        },
      ))
      ..addJavaScriptChannel('DebugBridge', onMessageReceived: (m) => _onBridgeMessage(id, m.message))
      ..setOnConsoleMessage((msg) {
        // Native console is only a fallback before the SDK hooks console.*.
        if (_sdkActive.contains(id) || id != state.activeId) return;
        final level = switch (msg.level) {
          JavaScriptLogLevel.error => 'error',
          JavaScriptLogLevel.warning => 'warn',
          JavaScriptLogLevel.debug => 'debug',
          _ => 'info',
        };
        ref.read(consoleLogsProvider.notifier).addLog(
            ConsoleLog(level: level, message: '[System] ${msg.message}', timestamp: DateTime.now()));
      });
    final ua = _userAgent();
    if (ua != null) c.setUserAgent(ua);
    // Extensions must be registered before the first load. Private tabs do
    // it after their profile is attached (see _attachPrivateProfile).
    _controllers[id] = c;
    if (!_awaitingProfile.contains(id) && !_privatePending.contains(id)) {
      _extReady[id] = _applyExtensions(id);
    }
    return c;
  }

  // ------------------------------------------------------------ extensions

  late final Future<bool> _startScriptsSupported = BrowserNative.startScriptSupported();

  /// Completes when a tab's extension scripts are registered.
  final Map<String, Future<void>> _extReady = {};

  /// Private tabs being created: extensions wait for the profile.
  final Set<String> _privatePending = {};

  Future<void> _applyExtensions(String id) async {
    final c = _controllers[id];
    if (c == null) return;
    await BrowserNative.setBlockImages(c, ref.read(extensionsProvider).dataSaver);
    if (!await _startScriptsSupported) return;
    await BrowserNative.setStartScripts(
      c,
      buildStartScripts(ref.read(extensionsProvider), ref.read(userScriptsProvider)),
    );
  }

  Future<void> _reapplyExtensions() async {
    for (final id in _controllers.keys.toList()) {
      if (_awaitingProfile.contains(id)) continue;
      await _applyExtensions(id);
      final t = _tab(id);
      if (t != null && !t.isNewTab) _applyJsMode(id, t.url);
    }
    reload();
  }

  void _onExtensionsChanged(ExtensionSettings? prev, ExtensionSettings next) {
    final zoomOnly = prev != null && _withoutZoom(prev) == _withoutZoom(next);
    if (zoomOnly) {
      _applyTextZoom(state.activeId, state.active.url);
    } else {
      _reapplyExtensions();
    }
  }

  /// Settings as JSON without text sizes: a change elsewhere needs the page
  /// scripts re-applied; a text-size change doesn't.
  static String _withoutZoom(ExtensionSettings s) {
    final j = s.toJson();
    final sites = Map<String, dynamic>.from(j['sites'] as Map);
    for (final k in sites.keys.toList()) {
      final m = Map<String, dynamic>.from(sites[k] as Map)..remove('textZoom');
      if (m.isEmpty) {
        sites.remove(k);
      } else {
        sites[k] = m;
      }
    }
    j['sites'] = sites;
    return jsonEncode(j);
  }

  void _applyTextZoom(String id, String url) {
    final c = _controllers[id];
    if (c == null) return;
    BrowserNative.setTextZoom(c, ref.read(extensionsProvider).textZoom(url));
  }

  /// Toggles reader mode on the current page.
  void toggleReaderMode() =>
      activeController.runJavaScript('window.__dbg && window.__dbg.readerMode && window.__dbg.readerMode()');

  NavigationDecision _onNavigationRequest(String id, NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.navigate;
    if (_webSchemes.contains(uri.scheme)) {
      if (!req.isMainFrame) return NavigationDecision.navigate;
      _applyJsMode(id, req.url);
      if (_settings.httpsOnly && shouldUpgradeToHttps(uri, allowedHttpHosts: _httpAllowed)) {
        final host = uri.host.toLowerCase();
        final last = _recentUpgrades[host];
        if (last != null && DateTime.now().difference(last) < const Duration(seconds: 8)) {
          // https redirected straight back to http: the site has no https.
          _httpAllowed.add(host);
          _upgradedFrom.remove(id);
          return NavigationDecision.navigate;
        }
        loadUri(uri, tabId: id); // re-enters as https
        return NavigationDecision.prevent;
      }
      if (_forceNavigate.remove(req.url)) return NavigationDecision.navigate;
      final pending = _pendingNav.putIfAbsent(id, () => {});
      // Page-initiated jumps to known ad / pop-under networks (not addresses
      // the user typed, which are in `pending`).
      if (!pending.contains(req.url) && _isAdRedirect(id, uri)) {
        _patch(id, (t) => t.copyWith(
              blockedCount: t.blockedCount + 1,
              blockedDomains: {...t.blockedDomains, 'redirects': (t.blockedDomains['redirects'] ?? 0) + 1},
            ));
        ref.read(blockedTotalProvider.notifier).add(1);
        ref.read(privacyStatsProvider.notifier).add(1);
        if (id == state.activeId) notice.value = 'Blocked a redirect to ${uri.host}';
        return NavigationDecision.prevent;
      }
      if (pending.remove(req.url) || uri.scheme == 'data' && req.url.startsWith('data:application/')) {
        _startDownload(id, req.url);
        return NavigationDecision.prevent;
      }
      pending.add(req.url);
      return NavigationDecision.navigate;
    }
    if (uri.scheme == 'intent') {
      final fallback = intentFallbackUrl(req.url);
      if (fallback != null) {
        loadUri(Uri.parse(fallback), tabId: id);
        return NavigationDecision.prevent;
      }
    }
    // tel:, mailto:, sms:, geo:, market:, whatsapp:, … → the right app.
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object e) {
      debugPrint('No app for ${uri.scheme}: $e');
      return false;
    });
    return NavigationDecision.prevent;
  }

  Future<void> _attachPrivateProfile(String id) async {
    final c = _controllers[id];
    final ok = c != null && await BrowserNative.makePrivate(c);
    if (!_controllers.containsKey(id)) return;
    if (ok) {
      _extReady[id] = _applyExtensions(id);
      _awaitingProfile.remove(id);
      _ensureLoaded(id);
    } else {
      // Never fall back to a non-private WebView for a private tab.
      notice.value = 'Private browsing needs Android System WebView 110 or newer. Update it from the Play Store.';
      closeTab(id);
    }
  }

  Future<void> _applyProxy(ProxySettings p) async {
    final status = ref.read(proxyStatusProvider.notifier);
    _proxyAuthFailures = 0;
    if (!p.enabled || p.validate() != null) {
      await BrowserNative.clearProxy();
      status.set(ProxyStatus.off);
      return;
    }
    if (!await BrowserNative.proxySupported()) {
      status.set(ProxyStatus.unsupported);
      return;
    }
    final ok = await BrowserNative.setProxy(p.rule, bypass: p.bypass);
    status.set(ok ? ProxyStatus.active : ProxyStatus.failed);
    if (ok) reload();
  }

  void _onHttpAuth(String id, HttpAuthRequest req) {
    final proxy = ref.read(proxySettingsProvider);
    final isProxy = proxy.enabled && req.host.toLowerCase() == proxy.host.trim().toLowerCase();
    if (isProxy && proxy.hasCredentials && _proxyAuthFailures < 2) {
      _proxyAuthFailures++;
      req.onProceed(WebViewCredential(user: proxy.username, password: proxy.password));
      return;
    }
    if (id != state.activeId) {
      req.onCancel();
      return;
    }
    ref.read(authPromptProvider.notifier).show(AuthPrompt(
          req.host,
          req.realm,
          (u, p) => req.onProceed(WebViewCredential(user: u, password: p)),
          req.onCancel,
        ));
  }

  /// Explicit download (long-press "Download link", <a download>, blob:).
  Future<void> downloadUrl(String url, {String? suggestedName, String? tabId}) async {
    final id = tabId ?? state.activeId;
    final ok = await ref.read(downloadsProvider.notifier).start(
          url,
          userAgent: await _controllers[id]?.getUserAgent(),
          referer: _tab(id)?.url,
          suggestedName: suggestedName,
          force: true,
        );
    if (ok) {
      final latest = ref.read(downloadsProvider);
      downloadStarted.value = latest.isEmpty ? url : latest.first.fileName;
    }
  }

  bool _isAdRedirect(String id, Uri target) {
    final page = _tab(id)?.url ?? '';
    final ext = ref.read(extensionsProvider);
    if (!(ext.blockerOn(page) || ext.popupsOn(page))) return false;
    if (isBlockerExempt(target.host)) return false;
    final blocked = matchBlockedHost(target.host);
    // Visiting the ad network's own site directly is the user's choice.
    return blocked != null && matchBlockedHost(Uri.tryParse(page)?.host ?? '') == null;
  }

  Future<void> _startDownload(String id, String url) async {
    final c = _controllers[id];
    final tab = _tab(id);
    String? ua, cookie;
    try {
      ua = await c?.getUserAgent();
      // Page cookies for same-site downloads (HttpOnly ones aren't readable).
      final sameHost = Uri.tryParse(url)?.host == Uri.tryParse(tab?.url ?? '')?.host;
      if (sameHost && c != null) {
        final r = await c.runJavaScriptReturningResult('document.cookie');
        cookie = r is String ? (r.startsWith('"') ? jsonDecode(r) as String : r) : null;
      }
    } catch (_) {}
    final downloads = ref.read(downloadsProvider.notifier);
    final isFile = await downloads.start(url, userAgent: ua, cookie: cookie, referer: tab?.url);
    if (!isFile) {
      // It was a normal page after all.
      _forceNavigate.add(url);
      _controllers[id]?.loadRequest(Uri.parse(url));
      return;
    }
    final latest = ref.read(downloadsProvider);
    downloadStarted.value = latest.isEmpty ? url : latest.first.fileName;
  }

  Future<void> _onPageFinished(String id, String url) async {
    if (url.startsWith('https://')) _upgradedFrom.remove(id);
    final c = _controllers[id];
    if (c == null) return;
    try {
      await c.runJavaScript(debugSdkJs);
      await c.runJavaScript(debugSdkExtrasJs);
      _sdkActive.add(id);
      await c.runJavaScript(_mocksJs(ref.read(networkMocksProvider)));
      await c.runJavaScript(_conditionJs(ref.read(networkConditionProvider)));
      await c.runJavaScript(_geoJs(ref.read(geoOverrideProvider)));
      if (_tab(id)?.isPrivate == false) {
        final json = ref.read(highlightsProvider.notifier).pageJson(url);
        if (json != '[]') await c.runJavaScript('window.__dbg && window.__dbg.applyHighlights(${jsString(json)})');
      }
      if (!await _startScriptsSupported) {
        // Old WebView: inject late (after load). Blocking is weaker this way.
        for (final js in buildStartScripts(ref.read(extensionsProvider), ref.read(userScriptsProvider))) {
          await c.runJavaScript(js).catchError((Object _) {});
        }
      }
    } catch (e) {
      debugPrint('SDK injection failed: $e');
    }
    final title = await c.getTitle() ?? '';
    final back = await c.canGoBack();
    final fwd = await c.canGoForward();
    if (_tab(id)?.isNewTab == true) {
      _patch(id, (t) => t.copyWith(lastWebUrl: () => url, lastWebTitle: () => title, canGoBack: back, canGoForward: fwd));
    } else {
      _patch(id, (t) => t.copyWith(
            url: url,
            title: title,
            isLoading: false,
            progress: 1,
            canGoBack: back,
            canGoForward: fwd,
            lastWebUrl: () => url,
            lastWebTitle: () => title,
          ));
    }
    if (id == state.activeId && _tab(id)?.isNewTab != true) ref.read(currentPageProvider.notifier).set(url, title);
    if (_tab(id)?.isPrivate != true) ref.read(historyProvider.notifier).record(url, title);
    _persist();
  }

  void _onBridgeMessage(String id, String raw) {
    final msg = parseBridgeMessage(raw);
    if (msg is UiEventMessage) {
      if (id != state.activeId) return;
      if (msg.kind == 'scroll') {
        if (_toolbarsFrozen) return;
        final dir = msg.data['dir'];
        if (dir == 'down') toolbarsVisible.value = false;
        if (dir == 'up' || dir == 'top') toolbarsVisible.value = true;
      } else {
        final st = msg.data['state'];
        final d = (msg.data['d'] as num?)?.toDouble() ?? 0;
        if (st == 'move') {
          final was = pullDistance.value ?? 0;
          // A tick when the pull passes the point where letting go reloads.
          if (was < pullTrigger && d >= pullTrigger) HapticFeedback.selectionClick();
          pullDistance.value = d;
        } else {
          pullDistance.value = null;
          if (st == 'release' && d >= pullTrigger && _settings.pullToRefresh) {
            HapticFeedback.lightImpact();
            reload();
          }
        }
      }
      return;
    }
    if (msg is BrowserActionMessage && msg.kind == 'favicon') {
      final tab = _tab(id);
      if (tab != null && !tab.isPrivate && !tab.isNewTab) {
        ref.read(faviconsProvider.notifier).learn(tab.url, msg.href);
      }
      return;
    }
    if (msg is BlockedMessage) {
      _patch(id, (t) {
        final domains = Map<String, int>.from(t.blockedDomains);
        msg.domains.forEach((d, n) => domains[d] = (domains[d] ?? 0) + n);
        return t.copyWith(blockedCount: t.blockedCount + msg.count, blockedDomains: domains);
      });
      ref.read(blockedTotalProvider.notifier).add(msg.count);
      ref.read(privacyStatsProvider.notifier).add(msg.count);
      return;
    }
    if (msg is BrowserActionMessage) {
      if (id != state.activeId) return;
      if (msg.kind == 'popup_blocked') {
        popupBlocked.value = msg.href;
      } else if (msg.kind == 'open_tab') {
        newTab(url: msg.href, private: _tab(id)?.isPrivate ?? false, openerId: id);
      } else if (msg.kind == 'blob_download' || msg.kind == 'download_link') {
        downloadUrl(msg.href, suggestedName: '${msg.data['name'] ?? ''}', tabId: id);
      } else {
        ref.read(linkMenuProvider.notifier).show(msg.data);
      }
      return;
    }
    // Dev tools show the active tab only.
    if (id != state.activeId) return;
    switch (msg) {
      case ConsoleMessage(:final log):
        ref.read(consoleLogsProvider.notifier).addLog(log);
      case NetworkMessage(:final request):
        ref.read(networkRequestsProvider.notifier).addRequest(request);
      case StorageMessage(:final data):
        ref.read(storageProvider.notifier).updateStorage(data);
      case DeviceInfoMessage(:final kind, :final data):
        ref.read(devicePerformanceProvider.notifier).updateInfo({kind: data});
      case DomNodeMessage(:final data):
        ref.read(domTreeProvider.notifier).setTree(data);
      case PageDataMessage(:final kind, :final data):
        ref.read(pageDataProvider.notifier).put(kind, data);
      default:
        break;
    }
  }

  void _pushAll(String js) {
    for (final c in _controllers.values) {
      c.runJavaScript(js).catchError((Object _) {});
    }
  }

  static String _mocksJs(List<MockRule> rules) =>
      'if (window.updateApiMocks) window.updateApiMocks(${jsString(jsonEncode(rules.map((r) => r.toJson()).toList()))});';

  static String _conditionJs(NetworkCondition c) =>
      'if (window.updateNetConfig) window.updateNetConfig(${jsString(jsonEncode(c.toJson()))});';

  static String _geoJs(GeoOverride? g) =>
      'if (window.__dbg && window.__dbg.setGeolocation) window.__dbg.setGeolocation(${g == null ? 'null' : jsString(jsonEncode(g.toJson()))});';
}

final tabsProvider = NotifierProvider<TabsNotifier, TabsState>(TabsNotifier.new);

/// Requests blocked since the app started (all tabs).
class BlockedTotalNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void add(int n) => state += n;
}

final blockedTotalProvider = NotifierProvider<BlockedTotalNotifier, int>(BlockedTotalNotifier.new);

/// In-memory page previews for the tab switcher, keyed by tab id.
class TabThumbnailsNotifier extends Notifier<Map<String, Uint8List>> {
  @override
  Map<String, Uint8List> build() => {};

  void put(String tabId, Uint8List png) => state = {...state, tabId: png};

  void remove(String tabId) {
    if (!state.containsKey(tabId)) return;
    state = Map.of(state)..remove(tabId);
  }

  /// Drops previews of tabs that no longer exist.
  void retain(Iterable<String> tabIds) {
    final keep = tabIds.toSet();
    if (state.keys.every(keep.contains)) return;
    state = {for (final e in state.entries) if (keep.contains(e.key)) e.key: e.value};
  }
}

final tabThumbnailsProvider =
    NotifierProvider<TabThumbnailsNotifier, Map<String, Uint8List>>(TabThumbnailsNotifier.new);
