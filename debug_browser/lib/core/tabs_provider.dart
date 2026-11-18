import 'dart:convert';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'browser_settings.dart';
import 'downloads.dart';
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
  });

  bool get isSecure => url.startsWith('https://');
  String get displayTitle => title.isNotEmpty ? title : (Uri.tryParse(url)?.host ?? url);

  BrowserTab copyWith({
    String? url,
    String? title,
    double? progress,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    String? Function()? error,
    bool? loaded,
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

    final restored = <BrowserTab>[];
    var activeIndex = 0;
    final saved = _settings.restoreTabs ? _box?.get(_storeKey) : null;
    if (saved is Map && saved['tabs'] is List) {
      for (final t in (saved['tabs'] as List).whereType<Map>().take(maxTabs)) {
        final url = '${t['url'] ?? ''}';
        if (!url.startsWith('http')) continue;
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

  String newTab({String? url, bool activate = true}) {
    if (state.tabs.length >= maxTabs) {
      // Reuse the oldest inactive tab rather than growing unbounded.
      final victim = state.tabs.firstWhere((t) => t.id != state.activeId);
      closeTab(victim.id);
    }
    final id = _newId();
    final tab = BrowserTab(id: id, url: url ?? _settings.homepage, loaded: false);
    _controllers[id] = _createController(id);
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
    ref.read(tabThumbnailsProvider.notifier).remove(id);
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
    _persist();
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
    if (tab == null) return;
    if (id == state.activeId) {
      ref.read(webViewControllerProvider.notifier).setController(_controllers[id]!);
    }
    if (!tab.loaded) {
      _patch(id, (t) => t.copyWith(loaded: true));
      _controllers[id]!.loadRequest(normaliseUrlInput(tab.url));
    }
  }

  // ------------------------------------------------------------ navigation

  void loadInput(String text) {
    final engine = _settings.engine;
    loadUri(normaliseUrlInput(text, search: engine.searchUri));
  }

  void loadUri(Uri uri, {String? tabId}) {
    final id = tabId ?? state.activeId;
    _patch(id, (t) => t.copyWith(url: uri.toString(), loaded: true, error: () => null));
    _sdkActive.remove(id);
    _pendingNav.putIfAbsent(id, () => {}).add(uri.toString());
    _controllers[id]?.loadRequest(uri);
  }

  void goHome() => loadUri(normaliseUrlInput(_settings.homepage));

  Future<void> goBack() async {
    final c = activeController;
    if (await c.canGoBack()) await c.goBack();
  }

  Future<void> goForward() async {
    final c = activeController;
    if (await c.canGoForward()) await c.goForward();
  }

  void reload() {
    final tab = state.active;
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
        for (final t in state.tabs) {'url': t.url, 'title': t.title},
      ],
      'active': state.activeIndex,
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
          if (url != null) _patch(id, (t) => t.copyWith(url: url));
        },
        onPageStarted: (url) {
          _sdkActive.remove(id);
          _pendingNav[id]?.clear();
          _patch(id, (t) => t.copyWith(url: url, isLoading: true, progress: 0.05, error: () => null));
          if (id == state.activeId) {
            ref.read(pageDataProvider.notifier).clear();
            ref.read(domTreeProvider.notifier).setTree({});
          }
        },
        onPageFinished: (url) => _onPageFinished(id, url),
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
    return c;
  }

  NavigationDecision _onNavigationRequest(String id, NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.navigate;
    if (_webSchemes.contains(uri.scheme)) {
      if (!req.isMainFrame) return NavigationDecision.navigate;
      if (_forceNavigate.remove(req.url)) return NavigationDecision.navigate;
      final pending = _pendingNav.putIfAbsent(id, () => {});
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
    } catch (e) {
      debugPrint('SDK injection failed: $e');
    }
    final title = await c.getTitle() ?? '';
    final back = await c.canGoBack();
    final fwd = await c.canGoForward();
    _patch(id, (t) => t.copyWith(url: url, title: title, isLoading: false, progress: 1, canGoBack: back, canGoForward: fwd));
    if (id == state.activeId) ref.read(currentPageProvider.notifier).set(url, title);
    ref.read(historyProvider.notifier).record(url, title);
    _persist();
  }

  void _onBridgeMessage(String id, String raw) {
    final msg = parseBridgeMessage(raw);
    if (msg is BrowserActionMessage) {
      if (id != state.activeId) return;
      if (msg.kind == 'open_tab') {
        newTab(url: msg.href);
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
