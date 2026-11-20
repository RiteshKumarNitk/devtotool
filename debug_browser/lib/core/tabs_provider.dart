import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'browser_native.dart';
import 'browser_settings.dart';
import 'downloads.dart';
import 'extensions.dart';
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
  });

  bool get isNewTab => url == newTabUrl;
  bool get isSecure => url.startsWith('https://');
  String get displayTitle => isNewTab
      ? (isPrivate ? 'Private tab' : 'New tab')
      : title.isNotEmpty
          ? title
          : (Uri.tryParse(url)?.host ?? url);

  /// Whether Back does something (page history, or the New Tab page).
  bool get canNavigateBack => isNewTab ? lastWebUrl != null : (canGoBack || ntpBehind);

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
      );
}

@immutable
class TabsState {
  final List<BrowserTab> tabs;
  final String activeId;
  const TabsState(this.tabs, this.activeId);

  BrowserTab get active => tabs.firstWhere((t) => t.id == activeId, orElse: () => tabs.first);
  int get activeIndex => tabs.indexWhere((t) => t.id == activeId);
}

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

    final restored = <BrowserTab>[];
    var activeIndex = 0;
    final saved = _settings.restoreTabs ? _box?.get(_storeKey) : null;
    if (saved is Map && saved['tabs'] is List) {
      for (final t in (saved['tabs'] as List).whereType<Map>().take(maxTabs)) {
        final url = '${t['url'] ?? ''}';
        if (!url.startsWith('http') && url != newTabUrl) continue;
        restored.add(BrowserTab(id: _newId(), url: url, title: '${t['title'] ?? ''}', loaded: false));
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

  String newTab({String? url, bool activate = true, bool private = false}) {
    if (state.tabs.length >= maxTabs) {
      // Reuse the oldest inactive tab rather than growing unbounded.
      final victim = state.tabs.firstWhere((t) => t.id != state.activeId);
      closeTab(victim.id);
    }
    final id = _newId();
    final tab = BrowserTab(id: id, url: url ?? _settings.homepage, loaded: false, isPrivate: private);
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
    if (activate) _onActivated(id);
    _persist();
    return id;
  }

  void closeTab(String id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
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
      state = TabsState([fresh], fresh.id);
      _onActivated(fresh.id);
    } else if (id == state.activeId) {
      final next = tabs[i.clamp(0, tabs.length - 1)];
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

  void activate(String id) {
    if (id == state.activeId || !_controllers.containsKey(id)) return;
    state = TabsState(state.tabs, id);
    _onActivated(id);
    _persist();
  }

  void _onActivated(String id) {
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
      ready.whenComplete(() => _controllers[id]?.loadRequest(normaliseUrlInput(tab.url)));
    }
  }

  // ------------------------------------------------------------ navigation

  void loadInput(String text) {
    final engine = _settings.engine;
    loadUri(normaliseUrlInput(text, search: engine.searchUri));
  }

  void loadUri(Uri uri, {String? tabId}) {
    final id = tabId ?? state.activeId;
    if (uri.toString() == newTabUrl) {
      showNewTabPage(tabId: id);
      return;
    }
    final fromNtp = _tab(id)?.isNewTab ?? false;
    _patch(id, (t) => t.copyWith(
          url: uri.toString(),
          loaded: true,
          error: () => null,
          // Back from the first page returns to the New Tab page, unless
          // the WebView already has history of its own.
          ntpBehind: fromNtp ? t.lastWebUrl == null : t.ntpBehind,
        ));
    _sdkActive.remove(id);
    _pendingNav.putIfAbsent(id, () => {}).add(uri.toString());
    _controllers[id]?.loadRequest(uri);
  }

  void goHome() => loadUri(normaliseUrlInput(_settings.homepage));

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
  Future<bool> canGoBackNow() async {
    final tab = state.active;
    if (tab.isNewTab) return tab.lastWebUrl != null;
    return await activeController.canGoBack() || tab.ntpBehind;
  }

  Future<void> goBack() async {
    final tab = state.active;
    if (tab.isNewTab) {
      // Return to the page the New Tab page was opened over.
      if (tab.lastWebUrl != null) {
        _patch(tab.id, (t) => t.copyWith(url: t.lastWebUrl, title: t.lastWebTitle ?? ''));
        ref.read(currentPageProvider.notifier).set(tab.lastWebUrl!, tab.lastWebTitle ?? '');
      }
      return;
    }
    final c = activeController;
    if (await c.canGoBack()) {
      await c.goBack();
    } else if (tab.ntpBehind) {
      _patch(tab.id, (t) => t.copyWith(ntpBehind: false));
      showNewTabPage(tabId: tab.id);
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
          if (!t.isPrivate) {'url': t.url, 'title': t.title},
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
          _patch(id, (t) => t.copyWith(isLoading: false, error: () => e.description));
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
    if (c == null || !await _startScriptsSupported) return;
    await BrowserNative.setStartScripts(
      c,
      buildStartScripts(ref.read(extensionsProvider), ref.read(userScriptsProvider)),
    );
  }

  Future<void> _reapplyExtensions() async {
    for (final id in _controllers.keys.toList()) {
      if (_awaitingProfile.contains(id)) continue;
      await _applyExtensions(id);
    }
    reload();
  }

  void _onExtensionsChanged(ExtensionSettings? prev, ExtensionSettings next) {
    final zoomOnly = prev != null &&
        prev.blocker == next.blocker &&
        prev.cosmetic == next.cosmetic &&
        prev.dark == next.dark &&
        prev.cookies == next.cookies &&
        prev.popups == next.popups &&
        _sameExceptZoom(prev, next);
    if (zoomOnly) {
      _applyTextZoom(state.activeId, state.active.url);
    } else {
      _reapplyExtensions();
    }
  }

  static bool _sameExceptZoom(ExtensionSettings a, ExtensionSettings b) {
    final keys = {...a.sites.keys, ...b.sites.keys};
    for (final k in keys) {
      final x = a.sites[k], y = b.sites[k];
      if (x?.blocker != y?.blocker || x?.dark != y?.dark || x?.cookies != y?.cookies || x?.popups != y?.popups) {
        return false;
      }
    }
    return true;
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
    final c = _controllers[id];
    if (c == null) return;
    try {
      await c.runJavaScript(debugSdkJs);
      await c.runJavaScript(debugSdkExtrasJs);
      _sdkActive.add(id);
      await c.runJavaScript(_mocksJs(ref.read(networkMocksProvider)));
      await c.runJavaScript(_conditionJs(ref.read(networkConditionProvider)));
      await c.runJavaScript(_geoJs(ref.read(geoOverrideProvider)));
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
        newTab(url: msg.href, private: _tab(id)?.isPrivate ?? false);
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
