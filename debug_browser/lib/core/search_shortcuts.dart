import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

/// "w taj mahal" -> Wikipedia search. `%s` in the template is the query.
@immutable
class SearchShortcut {
  final String keyword;
  final String name;
  final String template;
  const SearchShortcut(this.keyword, this.name, this.template);

  Uri uriFor(String query) => Uri.parse(template.replaceAll('%s', Uri.encodeQueryComponent(query)));

  Map<String, String> toJson() => {'keyword': keyword, 'name': name, 'template': template};

  static SearchShortcut? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = '${j['keyword'] ?? ''}'.trim().toLowerCase();
    final t = '${j['template'] ?? ''}'.trim();
    if (k.isEmpty || k.contains(' ') || !t.contains('%s') || !t.startsWith('http')) return null;
    return SearchShortcut(k, '${j['name'] ?? k}', t);
  }
}

const defaultSearchShortcuts = [
  SearchShortcut('w', 'Wikipedia', 'https://en.wikipedia.org/wiki/Special:Search?search=%s'),
  SearchShortcut('yt', 'YouTube', 'https://www.youtube.com/results?search_query=%s'),
  SearchShortcut('m', 'Maps', 'https://www.google.com/maps/search/%s'),
  SearchShortcut('gh', 'GitHub', 'https://github.com/search?q=%s'),
  SearchShortcut('so', 'Stack Overflow', 'https://stackoverflow.com/search?q=%s'),
  SearchShortcut('a', 'Amazon', 'https://www.amazon.in/s?k=%s'),
  SearchShortcut('g', 'Google', 'https://www.google.com/search?q=%s'),
  SearchShortcut('d', 'DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
];

/// If [input] starts with a shortcut keyword and a query, returns
/// (shortcut, query). "w" alone or "w " is not a shortcut search.
(SearchShortcut, String)? matchShortcut(String input, List<SearchShortcut> shortcuts) {
  final t = input.trimLeft();
  final space = t.indexOf(' ');
  if (space <= 0) return null;
  final kw = t.substring(0, space).toLowerCase();
  final q = t.substring(space + 1).trim();
  if (q.isEmpty) return null;
  for (final s in shortcuts) {
    if (s.keyword == kw) return (s, q);
  }
  return null;
}

class SearchShortcutsNotifier extends Notifier<List<SearchShortcut>> {
  static const _key = 'searchShortcuts';

  @override
  List<SearchShortcut> build() {
    final saved = _box()?.get(_key);
    if (saved is! List) return defaultSearchShortcuts;
    return saved.map(SearchShortcut.fromJson).whereType<SearchShortcut>().toList();
  }

  /// Adds or replaces (by keyword).
  void save(SearchShortcut s, {String? replacing}) {
    state = [
      for (final x in state)
        if (x.keyword != s.keyword && x.keyword != replacing) x,
      s,
    ];
    _persist();
  }

  void remove(String keyword) {
    state = state.where((s) => s.keyword != keyword).toList();
    _persist();
  }

  void reset() {
    state = defaultSearchShortcuts;
    _persist();
  }

  void _persist() => _box()?.put(_key, state.map((s) => s.toJson()).toList());
}

final searchShortcutsProvider =
    NotifierProvider<SearchShortcutsNotifier, List<SearchShortcut>>(SearchShortcutsNotifier.new);
