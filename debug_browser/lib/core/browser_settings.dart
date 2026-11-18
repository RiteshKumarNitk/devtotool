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

  const BrowserSettings({
    this.engine = SearchEngine.google,
    this.customHomepage = '',
    this.showDebugBubble = true,
    this.desktopMode = false,
    this.restoreTabs = true,
  });

  String get homepage => customHomepage.trim().isEmpty ? engine.home : customHomepage.trim();

  BrowserSettings copyWith({
    SearchEngine? engine,
    String? customHomepage,
    bool? showDebugBubble,
    bool? desktopMode,
    bool? restoreTabs,
  }) =>
      BrowserSettings(
        engine: engine ?? this.engine,
        customHomepage: customHomepage ?? this.customHomepage,
        showDebugBubble: showDebugBubble ?? this.showDebugBubble,
        desktopMode: desktopMode ?? this.desktopMode,
        restoreTabs: restoreTabs ?? this.restoreTabs,
      );

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'customHomepage': customHomepage,
        'showDebugBubble': showDebugBubble,
        'restoreTabs': restoreTabs,
        // desktopMode is per-session on purpose (like Chrome's "Desktop site").
      };

  static BrowserSettings fromJson(Object? j) {
    if (j is! Map) return const BrowserSettings();
    return BrowserSettings(
      engine: SearchEngine.byName(j['engine']),
      customHomepage: '${j['customHomepage'] ?? ''}',
      showDebugBubble: j['showDebugBubble'] != false,
      restoreTabs: j['restoreTabs'] != false,
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
