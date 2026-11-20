import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'browser_settings.dart';
import 'extensions.dart';
import 'highlights.dart';
import 'search_shortcuts.dart';
import 'providers.dart';
import 'tool_providers.dart';

/// `ref.read` of a WidgetRef or ProviderContainer (lets tests drive this).
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

const backupFormat = 'debug-browser-backup';
const backupVersion = 1;

List<Map<String, String>> _stringMaps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.map((k, val) => MapEntry('$k', '${val ?? ''}'))).toList()
    : const [];

/// What a backup contains, for the confirmation dialog.
@immutable
class BackupSummary {
  final DateTime? createdAt;
  final int bookmarks, history, userScripts, mockRules, environments, snippets, highlights, shortcuts;
  final bool settings, extensions, proxy;
  const BackupSummary({
    this.createdAt,
    this.bookmarks = 0,
    this.history = 0,
    this.userScripts = 0,
    this.mockRules = 0,
    this.environments = 0,
    this.snippets = 0,
    this.highlights = 0,
    this.shortcuts = 0,
    this.settings = false,
    this.extensions = false,
    this.proxy = false,
  });

  List<String> describe() => [
        if (bookmarks > 0) '$bookmarks bookmark${bookmarks == 1 ? '' : 's'}',
        if (history > 0) '$history history entr${history == 1 ? 'y' : 'ies'}',
        if (settings) 'Browser settings',
        if (extensions) 'Extension settings',
        if (userScripts > 0) '$userScripts user script${userScripts == 1 ? '' : 's'}',
        if (mockRules > 0) '$mockRules API mock rule${mockRules == 1 ? '' : 's'}',
        if (environments > 0) '$environments environment${environments == 1 ? '' : 's'}',
        if (snippets > 0) '$snippets JS snippet${snippets == 1 ? '' : 's'}',
        if (highlights > 0) '$highlights highlight${highlights == 1 ? '' : 's'}',
        if (shortcuts > 0) '$shortcuts search shortcut${shortcuts == 1 ? '' : 's'}',
        if (proxy) 'Proxy / VPN settings (password not included)',
      ];
}

/// Validates a parsed backup. Returns (summary, null) or (null, error).
(BackupSummary?, String?) inspectBackup(Object? json) {
  if (json is! Map) return (null, 'This file is not a Debug Browser backup.');
  if (json['format'] != backupFormat) return (null, 'This file is not a Debug Browser backup.');
  final v = json['version'];
  if (v is! num || v > backupVersion) {
    return (null, 'This backup was made by a newer version of the app. Update the app first.');
  }
  final d = json['data'];
  if (d is! Map) return (null, 'The backup is empty or damaged.');
  int len(String k) => d[k] is List ? (d[k] as List).length : 0;
  return (
    BackupSummary(
      createdAt: DateTime.tryParse('${json['createdAt']}'),
      bookmarks: len('bookmarks'),
      history: len('history'),
      userScripts: len('userScripts'),
      mockRules: len('mockRules'),
      environments: len('environments'),
      snippets: len('snippets'),
      highlights: len('highlights'),
      shortcuts: len('searchShortcuts'),
      settings: d['browserSettings'] is Map,
      extensions: d['extensions'] is Map,
      proxy: d['proxy'] is Map,
    ),
    null,
  );
}

/// Everything worth keeping, as one JSON document. The proxy password is
/// never written; history only if asked.
Map<String, dynamic> buildBackup(ProviderReader read, {bool includeHistory = false, DateTime? now}) {
  final proxy = read(proxySettingsProvider).toJson()..remove('password');
  return {
    'format': backupFormat,
    'version': backupVersion,
    'createdAt': (now ?? DateTime.now()).toIso8601String(),
    'data': {
      'bookmarks': read(bookmarksProvider),
      if (includeHistory) 'history': read(historyProvider),
      'browserSettings': read(browserSettingsProvider).toJson(),
      'extensions': read(extensionsProvider).toJson(),
      'userScripts': read(userScriptsProvider).map((s) => s.toJson()).toList(),
      'mockRules': read(networkMocksProvider).map((r) => r.toJson()).toList(),
      'environments': read(environmentsProvider),
      'snippets': read(snippetsProvider),
      'highlights': read(highlightsProvider).map((h) => h.toJson()).toList(),
      'searchShortcuts': read(searchShortcutsProvider).map((s) => s.toJson()).toList(),
      'proxy': proxy,
    },
  };
}

/// Restores by merging: adds what's missing, never deletes. Settings are
/// replaced. A restored proxy starts switched off (password not included).
void restoreBackup(ProviderReader read, Map json) {
  final d = json['data'] as Map;

  final bookmarks = read(bookmarksProvider.notifier);
  for (final b in _stringMaps(d['bookmarks'])) {
    final url = b['url'] ?? '';
    if (url.isNotEmpty) bookmarks.addBookmark(b['title']?.isNotEmpty == true ? b['title']! : url, url);
  }
  if (d['history'] is List) read(historyProvider.notifier).importEntries(_stringMaps(d['history']));
  if (d['browserSettings'] is Map) {
    read(browserSettingsProvider.notifier).update((_) => BrowserSettings.fromJson(d['browserSettings']));
  }
  if (d['extensions'] is Map) {
    read(extensionsProvider.notifier).update((_) => ExtensionSettings.fromJson(d['extensions']));
  }
  if (d['userScripts'] is List) {
    read(userScriptsProvider.notifier).importAll(
        (d['userScripts'] as List).map(UserScript.fromJson).whereType<UserScript>().toList());
  }
  if (d['mockRules'] is List) {
    final rules = parseMockRules(d['mockRules']);
    if (rules.isNotEmpty) read(networkMocksProvider.notifier).importRules(rules);
  }
  final envs = read(environmentsProvider.notifier);
  final haveEnvs = read(environmentsProvider).map((e) => e['url']).toSet();
  for (final e in _stringMaps(d['environments'])) {
    if ((e['url'] ?? '').isNotEmpty && haveEnvs.add(e['url'])) envs.save(e['name'] ?? e['url']!, e['url']!);
  }
  final snippets = read(snippetsProvider.notifier);
  final haveSnippets = read(snippetsProvider).map((s) => '${s['name']}|${s['code']}').toSet();
  for (final s in _stringMaps(d['snippets'])) {
    if ((s['code'] ?? '').isNotEmpty && haveSnippets.add('${s['name']}|${s['code']}')) {
      snippets.save(s['name'] ?? 'Snippet', s['code']!);
    }
  }
  if (d['highlights'] is List) {
    read(highlightsProvider.notifier)
        .importAll((d['highlights'] as List).map(Highlight.fromJson).whereType<Highlight>().toList());
  }
  if (d['searchShortcuts'] is List) {
    final n = read(searchShortcutsProvider.notifier);
    for (final s in (d['searchShortcuts'] as List).map(SearchShortcut.fromJson).whereType<SearchShortcut>()) {
      n.save(s);
    }
  }
  if (d['proxy'] is Map) {
    final restored = ProxySettings.fromJson(d['proxy']);
    final current = read(proxySettingsProvider);
    read(proxySettingsProvider.notifier).save(restored.copyWith(
          enabled: false,
          password: restored.host == current.host ? current.password : '',
        ));
  }
}

/// Lets the user pick a backup file (Android document picker). Null if
/// cancelled or unavailable.
Future<String?> pickBackupFile() async {
  try {
    return await const MethodChannel('com.innovatextechnology.debugbrowser/links').invokeMethod<String>('pickTextFile');
  } on PlatformException catch (e) {
    throw FormatException(e.message ?? 'Could not read the file');
  } catch (_) {
    return null;
  }
}

String prettyJson(Object json) => const JsonEncoder.withIndent('  ').convert(json);
