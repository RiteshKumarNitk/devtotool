import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers.dart';

enum SearchEngine {
  google('Google', 'https://www.google.com', 'https://www.google.com/search?q='),
  duckDuckGo('DuckDuckGo', 'https://duckduckgo.com', 'https://duckduckgo.com/?q='),
  bing('Bing', 'https://www.bing.com', 'https://www.bing.com/search?q='),
  brave('Brave Search', 'https://search.brave.com', 'https://search.brave.com/search?q=');

  const SearchEngine(this.label, this.home, this.queryPrefix);
  final String label;
  final String home;
  final String queryPrefix;

  Uri searchUri(String query) => Uri.parse('$queryPrefix${Uri.encodeQueryComponent(query)}');

  static SearchEngine byName(Object? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => SearchEngine.google);
}

@immutable
class BrowserSettings {
  final SearchEngine engine;

  /// Empty means "the search engine's home page".
  final String customHomepage;
  final bool showDebugBubble;
  final bool desktopMode;
  final bool restoreTabs;

  /// Ask before the back button closes the app.
  final bool confirmExit;

  const BrowserSettings({
    this.engine = SearchEngine.google,
    this.customHomepage = '',
    this.showDebugBubble = true,
    this.desktopMode = false,
    this.restoreTabs = true,
    this.confirmExit = true,
  });

  String get homepage => customHomepage.trim().isEmpty ? engine.home : customHomepage.trim();

  BrowserSettings copyWith({
    SearchEngine? engine,
    String? customHomepage,
    bool? showDebugBubble,
    bool? desktopMode,
    bool? restoreTabs,
    bool? confirmExit,
  }) =>
      BrowserSettings(
        engine: engine ?? this.engine,
        customHomepage: customHomepage ?? this.customHomepage,
        showDebugBubble: showDebugBubble ?? this.showDebugBubble,
        desktopMode: desktopMode ?? this.desktopMode,
        restoreTabs: restoreTabs ?? this.restoreTabs,
        confirmExit: confirmExit ?? this.confirmExit,
      );

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'customHomepage': customHomepage,
        'showDebugBubble': showDebugBubble,
        'restoreTabs': restoreTabs,
        'confirmExit': confirmExit,
        // desktopMode is per-session on purpose (like Chrome's "Desktop site").
      };

  static BrowserSettings fromJson(Object? j) {
    if (j is! Map) return const BrowserSettings();
    return BrowserSettings(
      engine: SearchEngine.byName(j['engine']),
      customHomepage: '${j['customHomepage'] ?? ''}',
      showDebugBubble: j['showDebugBubble'] != false,
      restoreTabs: j['restoreTabs'] != false,
      confirmExit: j['confirmExit'] != false,
    );
  }
}

const desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

class BrowserSettingsNotifier extends Notifier<BrowserSettings> {
  static const _key = 'browserSettings';

  Box? get _box => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

  @override
  BrowserSettings build() => BrowserSettings.fromJson(_box?.get(_key));

  void update(BrowserSettings Function(BrowserSettings) change) {
    state = change(state);
    _box?.put(_key, state.toJson());
  }
}

final browserSettingsProvider =
    NotifierProvider<BrowserSettingsNotifier, BrowserSettings>(BrowserSettingsNotifier.new);

// ---------------------------------------------------------------------------
// Proxy ("VPN") — routes all browser traffic through a user-supplied proxy,
// e.g. the HTTP/SOCKS5 proxy offered by a VPN provider.
// ---------------------------------------------------------------------------
enum ProxyType {
  http('HTTP', 'http'),
  https('HTTPS', 'https'),
  socks5('SOCKS5', 'socks');

  const ProxyType(this.label, this.scheme);
  final String label;
  final String scheme;

  static ProxyType byName(Object? n) => values.firstWhere((e) => e.name == n, orElse: () => ProxyType.http);
}

@immutable
class ProxySettings {
  final bool enabled;
  final ProxyType type;
  final String host;
  final int port;

  /// Used to answer the proxy's HTTP authentication challenge (HTTP/HTTPS
  /// proxies only; WebView doesn't support SOCKS authentication).
  final String username;
  final String password;

  /// Hosts that skip the proxy, e.g. "*.example.com", "10.0.0.0/8".
  final List<String> bypass;

  const ProxySettings({
    this.enabled = false,
    this.type = ProxyType.http,
    this.host = '',
    this.port = 8080,
    this.username = '',
    this.password = '',
    this.bypass = const [],
  });

  /// WebView proxy rule, e.g. "socks://1.2.3.4:1080".
  String get rule => '${type.scheme}://${host.trim()}:$port';

  bool get hasCredentials => username.isNotEmpty;

  /// Error message, or null when the settings can be applied.
  String? validate() {
    final h = host.trim();
    if (h.isEmpty) return 'Enter the proxy host';
    if (h.contains('://') || h.contains('/') || h.contains(' ')) return 'Host only, without http:// or a path';
    if (port < 1 || port > 65535) return 'Port must be 1–65535';
    return null;
  }

  ProxySettings copyWith({
    bool? enabled,
    ProxyType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    List<String>? bypass,
  }) =>
      ProxySettings(
        enabled: enabled ?? this.enabled,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        bypass: bypass ?? this.bypass,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'bypass': bypass,
      };

  static ProxySettings fromJson(Object? j) {
    if (j is! Map) return const ProxySettings();
    return ProxySettings(
      enabled: j['enabled'] == true,
      type: ProxyType.byName(j['type']),
      host: '${j['host'] ?? ''}',
      port: (j['port'] as num?)?.toInt() ?? 8080,
      username: '${j['username'] ?? ''}',
      password: '${j['password'] ?? ''}',
      bypass: (j['bypass'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

/// Parses "user:pass@host:port" or "host:port" pasted from a VPN provider.
ProxySettings? parseProxyString(String input, {ProxyType? type}) {
  var s = input.trim();
  var t = type ?? ProxyType.http;
  final scheme = RegExp(r'^(https?|socks5?h?)://', caseSensitive: false).firstMatch(s);
  if (scheme != null) {
    final sc = scheme.group(1)!.toLowerCase();
    t = sc.startsWith('socks') ? ProxyType.socks5 : (sc == 'https' ? ProxyType.https : ProxyType.http);
    s = s.substring(scheme.end);
  }
  var user = '', pass = '';
  final at = s.lastIndexOf('@');
  if (at > 0) {
    final cred = s.substring(0, at);
    s = s.substring(at + 1);
    final c = cred.indexOf(':');
    user = Uri.decodeComponent(c < 0 ? cred : cred.substring(0, c));
    pass = c < 0 ? '' : Uri.decodeComponent(cred.substring(c + 1));
  }
  s = s.split('/').first;
  final colon = s.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(s.substring(colon + 1));
  if (port == null) return null;
  final p = ProxySettings(type: t, host: s.substring(0, colon), port: port, username: user, password: pass);
  return p.validate() == null ? p : null;
}

enum ProxyStatus { off, active, unsupported, failed }

class ProxyNotifier extends Notifier<ProxySettings> {
  static const _key = 'proxySettings';
  Box? get _box => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

  @override
  ProxySettings build() => ProxySettings.fromJson(_box?.get(_key));

  void save(ProxySettings p) {
    state = p;
    _box?.put(_key, p.toJson());
  }
}

final proxySettingsProvider = NotifierProvider<ProxyNotifier, ProxySettings>(ProxyNotifier.new);

/// Current state of the proxy on the WebView side.
class ProxyStatusNotifier extends Notifier<ProxyStatus> {
  @override
  ProxyStatus build() => ProxyStatus.off;
  void set(ProxyStatus s) => state = s;
}

final proxyStatusProvider = NotifierProvider<ProxyStatusNotifier, ProxyStatus>(ProxyStatusNotifier.new);
