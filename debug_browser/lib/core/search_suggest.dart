import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_settings.dart';
import 'tabs_provider.dart';

/// Autocomplete endpoint for each engine (all return OpenSearch-style JSON,
/// except DuckDuckGo's list of {phrase}).
Uri suggestUri(SearchEngine engine, String q) => switch (engine) {
      SearchEngine.google =>
        Uri.https('suggestqueries.google.com', '/complete/search', {'client': 'firefox', 'q': q}),
      SearchEngine.duckDuckGo => Uri.https('duckduckgo.com', '/ac/', {'q': q, 'type': 'list'}),
      SearchEngine.bing => Uri.https('api.bing.com', '/osjson.aspx', {'query': q}),
      SearchEngine.brave => Uri.https('search.brave.com', '/api/suggest', {'q': q}),
    };

/// Parses a suggestion response; never throws. At most [limit] results.
List<String> parseSuggestions(String body, {int limit = 5}) {
  try {
    final j = jsonDecode(body);
    List<String> out = const [];
    if (j is List && j.length > 1 && j[1] is List) {
      out = (j[1] as List).map((e) => '$e').toList();
    } else if (j is List && j.isNotEmpty && j.first is Map) {
      out = j.whereType<Map>().map((e) => '${e['phrase'] ?? ''}').toList();
    }
    return out.where((s) => s.trim().isNotEmpty).take(limit).toList();
  } catch (_) {
    return const [];
  }
}

/// Live suggestions for the address bar. Empty when disabled, in private
/// tabs, while a proxy is on (requests wouldn't go through it), or for URLs.
final searchSuggestionsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, query) async {
  final q = query.trim();
  final settings = ref.read(browserSettingsProvider);
  if (!settings.searchSuggestions || q.length < 2 || q.length > 120) return const [];
  if (q.contains('://') || (!q.contains(' ') && q.contains('.') && !q.endsWith('.'))) return const [];
  if (ref.read(tabsProvider).active.isPrivate) return const [];
  if (ref.read(proxyStatusProvider) == ProxyStatus.active) return const [];

  // Debounce: autoDispose drops this provider when the text changes.
  await Future<void>.delayed(const Duration(milliseconds: 180));
  if (!ref.mounted) return const [];

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  ref.onDispose(() => client.close(force: true));
  try {
    final req = await client.getUrl(suggestUri(settings.engine, q));
    final res = await req.close().timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) return const [];
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
    return parseSuggestions(body).where((s) => s.toLowerCase() != q.toLowerCase()).toList();
  } catch (_) {
    return const [];
  }
});
