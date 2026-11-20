import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

import 'providers.dart';
import 'tabs_provider.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

List<Map<String, String>> _readStringMaps(String key) {
  final saved = _box()?.get(key);
  if (saved is! List) return [];
  return saved
      .whereType<Map>()
      .map((m) => m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
      .toList();
}

// ---------------------------------------------------------------------------
// Page data pushed by the SDK extras (vitals, dom_tree, a11y).
// ---------------------------------------------------------------------------
class PageDataNotifier extends Notifier<Map<String, Map<String, dynamic>>> {
  @override
  Map<String, Map<String, dynamic>> build() => {};

  void put(String type, Map<String, dynamic> data) => state = {...state, type: data};

  /// Called on navigation: per-page data is no longer valid.
  void clear() => state = {};
}

final pageDataProvider =
    NotifierProvider<PageDataNotifier, Map<String, Map<String, dynamic>>>(PageDataNotifier.new);

// ---------------------------------------------------------------------------
// Current page + navigation between tabs.
// ---------------------------------------------------------------------------
@immutable
class CurrentPage {
  final String url;
  final String title;
  const CurrentPage({this.url = '', this.title = ''});
}

class CurrentPageNotifier extends Notifier<CurrentPage> {
  @override
  CurrentPage build() => const CurrentPage();
  void set(String url, String title) => state = CurrentPage(url: url, title: title);
}

final currentPageProvider =
    NotifierProvider<CurrentPageNotifier, CurrentPage>(CurrentPageNotifier.new);

/// Root navigator, so non-widget code can switch between browser and dev tools.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Screens: [browser] is the browser itself; the rest are Developer-tools tabs.
abstract final class AppTab {
  static const browser = 0;
  static const console = 1;
  static const network = 2;
  static const storage = 3;
  static const dom = 4;
  static const performance = 5;
  static const more = 6;
}

/// Selecting [AppTab.browser] closes Developer tools; any other tab opens
/// Developer tools on that panel.
class HomeTabNotifier extends Notifier<int> {
  /// Set by the browser shell: pushes the Developer-tools route.
  static void Function()? openDevToolsRoute;
  static bool devToolsOpen = false;

  @override
  int build() => AppTab.browser;

  void select(int index) {
    if (index == AppTab.browser) {
      state = AppTab.browser;
      appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    state = index;
    if (!devToolsOpen) openDevToolsRoute?.call();
  }
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, int>(HomeTabNotifier.new);

/// Opens [url] in the current browser tab and shows the browser.
bool openInBrowser(WidgetRef ref, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || url.isEmpty) return false;
  ref.read(tabsProvider.notifier).loadUri(uri);
  ref.read(homeTabProvider.notifier).select(AppTab.browser);
  return true;
}

/// Shared so the bug-report generator can capture the browser view.
final screenshotControllerProvider = Provider<ScreenshotController>((ref) => ScreenshotController());

// ---------------------------------------------------------------------------
// Device emulation
// ---------------------------------------------------------------------------
enum ViewportPreset {
  fill('Fill screen', null, null),
  iphoneSe('iPhone SE', 375, 667),
  iphone15('iPhone 15', 393, 852),
  pixel8('Pixel 8', 412, 915),
  galaxyFold('Galaxy Fold (folded)', 280, 653),
  ipadMini('iPad mini', 768, 1024),
  laptop('Laptop', 1280, 800);

  const ViewportPreset(this.label, this.width, this.height);
  final String label;
  final double? width;
  final double? height;
}

class ViewportNotifier extends Notifier<ViewportPreset> {
  @override
  ViewportPreset build() => ViewportPreset.fill;
  void set(ViewportPreset p) => state = p;
}

final viewportProvider = NotifierProvider<ViewportNotifier, ViewportPreset>(ViewportNotifier.new);

@immutable
class GeoOverride {
  final double lat;
  final double lng;
  final String label;
  const GeoOverride(this.lat, this.lng, this.label);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracy': 10};

  static const presets = [
    GeoOverride(28.6139, 77.2090, 'New Delhi'),
    GeoOverride(19.0760, 72.8777, 'Mumbai'),
    GeoOverride(51.5074, -0.1278, 'London'),
    GeoOverride(40.7128, -74.0060, 'New York'),
    GeoOverride(35.6762, 139.6503, 'Tokyo'),
    GeoOverride(-33.8688, 151.2093, 'Sydney'),
  ];
}

/// Session-only, like network throttling.
class GeoOverrideNotifier extends Notifier<GeoOverride?> {
  @override
  GeoOverride? build() => null;
  void set(GeoOverride? g) => state = g;
}

final geoOverrideProvider =
    NotifierProvider<GeoOverrideNotifier, GeoOverride?>(GeoOverrideNotifier.new);

// ---------------------------------------------------------------------------
// History (persisted, capped)
// ---------------------------------------------------------------------------
const int maxHistoryEntries = 500;

class HistoryNotifier extends Notifier<List<Map<String, String>>> {
  static const _key = 'history';

  @override
  List<Map<String, String>> build() => _readStringMaps(_key);

  void record(String url, String title) {
    if (url.isEmpty || url == 'about:blank') return;
    // Collapse reloads of the same URL.
    if (state.isNotEmpty && state.last['url'] == url) {
      final next = [...state];
      next[next.length - 1] = {...next.last, 'title': title.isEmpty ? next.last['title']! : title};
      state = next;
    } else {
      state = appendCapped(
        state,
        {'url': url, 'title': title, 'time': DateTime.now().toIso8601String()},
        maxHistoryEntries,
      );
    }
    _box()?.put(_key, state);
  }

  void clear() {
    state = [];
    _box()?.delete(_key);
  }

  /// Merges visits from a backup (deduplicated, oldest first, capped).
  int importEntries(List<Map<String, String>> entries) {
    final key = {for (final e in state) '${e['url']}|${e['time']}'};
    final added = entries.where((e) => (e['url'] ?? '').isNotEmpty && key.add('${e['url']}|${e['time']}')).toList();
    final merged = [...state, ...added]..sort((a, b) => (a['time'] ?? '').compareTo(b['time'] ?? ''));
    state = merged.length > maxHistoryEntries ? merged.sublist(merged.length - maxHistoryEntries) : merged;
    _box()?.put(_key, state);
    return added.length;
  }

  /// Deletes one visit (matched by URL and time).
  void remove(Map<String, String> entry) {
    state = state.where((e) => !(e['url'] == entry['url'] && e['time'] == entry['time'])).toList();
    _box()?.put(_key, state);
  }

  /// Deletes visits on or after [since] ("last hour", "today").
  void clearSince(DateTime since) {
    state = state.where((e) {
      final t = DateTime.tryParse(e['time'] ?? '');
      return t != null && t.isBefore(since);
    }).toList();
    _box()?.put(_key, state);
  }
}

/// Groups history (newest first) under "Today", "Yesterday" or a date label.
List<(String, List<Map<String, String>>)> groupHistoryByDay(
  List<Map<String, String>> entries, {
  DateTime? now,
  String Function(DateTime day)? formatDay,
}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final groups = <(String, List<Map<String, String>>)>[];
  String? currentLabel;
  for (final e in entries.reversed) {
    final t = DateTime.tryParse(e['time'] ?? '')?.toLocal();
    final day = t == null ? null : DateUtils.dateOnly(t);
    final diff = day == null ? null : today.difference(day).inDays;
    final label = switch (diff) {
      null => 'Earlier',
      0 => 'Today',
      1 => 'Yesterday',
      _ => formatDay?.call(day!) ?? '${day!.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    };
    if (label != currentLabel) {
      groups.add((label, []));
      currentLabel = label;
    }
    groups.last.$2.add(e);
  }
  return groups;
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<Map<String, String>>>(HistoryNotifier.new);

// ---------------------------------------------------------------------------
// Environments (dev / staging / prod shortcuts)
// ---------------------------------------------------------------------------
class EnvironmentsNotifier extends Notifier<List<Map<String, String>>> {
  static const _key = 'environments';

  @override
  List<Map<String, String>> build() => _readStringMaps(_key);

  void save(String name, String url, {int? index}) {
    final entry = {'name': name.trim(), 'url': url.trim()};
    final next = [...state];
    if (index != null && index >= 0 && index < next.length) {
      next[index] = entry;
    } else {
      next.add(entry);
    }
    state = next;
    _box()?.put(_key, state);
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _box()?.put(_key, state);
  }
}

final environmentsProvider =
    NotifierProvider<EnvironmentsNotifier, List<Map<String, String>>>(EnvironmentsNotifier.new);

// ---------------------------------------------------------------------------
// JS snippets
// ---------------------------------------------------------------------------
const _defaultSnippets = [
  {'name': 'Clear localStorage', 'code': 'localStorage.clear(); "cleared"'},
  {'name': 'List cookies', 'code': 'document.cookie'},
  {'name': 'Count DOM nodes', 'code': 'document.querySelectorAll("*").length'},
  {'name': 'Outline all elements', 'code': 'document.querySelectorAll("*").forEach(e => e.style.outline = "1px solid rgba(255,0,0,.4)"); "done"'},
  {'name': 'Show page timing', 'code': 'JSON.stringify(performance.getEntriesByType("navigation")[0])'},
];

class SnippetsNotifier extends Notifier<List<Map<String, String>>> {
  static const _key = 'snippets';

  @override
  List<Map<String, String>> build() {
    final saved = _box()?.get(_key);
    if (saved == null) return _defaultSnippets.map(Map<String, String>.from).toList();
    return _readStringMaps(_key);
  }

  void save(String name, String code, {int? index}) {
    final entry = {'name': name.trim(), 'code': code};
    final next = [...state];
    if (index != null && index >= 0 && index < next.length) {
      next[index] = entry;
    } else {
      next.add(entry);
    }
    state = next;
    _box()?.put(_key, state);
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _box()?.put(_key, state);
  }
}

final snippetsProvider =
    NotifierProvider<SnippetsNotifier, List<Map<String, String>>>(SnippetsNotifier.new);

/// Runs [code] in the page and logs input + result to the console panel.
Future<void> runJsInPage(WidgetRef ref, String code) async {
  final controller = ref.read(webViewControllerProvider);
  final logs = ref.read(consoleLogsProvider.notifier);
  if (controller == null) {
    logs.addLog(ConsoleLog(level: 'error', message: 'WebView not ready', timestamp: DateTime.now()));
    return;
  }
  logs.addLog(ConsoleLog(level: 'input', message: code, timestamp: DateTime.now()));
  try {
    final result = await controller.runJavaScriptReturningResult(code);
    logs.addLog(ConsoleLog(level: 'result', message: '$result', timestamp: DateTime.now()));
  } catch (e) {
    logs.addLog(ConsoleLog(level: 'error', message: 'Error: $e', timestamp: DateTime.now()));
  }
}

// ---------------------------------------------------------------------------
// Saved sessions (JSON files in app documents)
// ---------------------------------------------------------------------------
@immutable
class SavedSession {
  final File file;
  final String name;
  final DateTime savedAt;
  final int logCount;
  final int requestCount;
  const SavedSession(this.file, this.name, this.savedAt, this.logCount, this.requestCount);
}

ConsoleLog? _logFromJson(Object? j) {
  if (j is! Map) return null;
  return ConsoleLog(
    level: '${j['level'] ?? 'log'}',
    message: '${j['message'] ?? ''}',
    timestamp: DateTime.tryParse('${j['timestamp']}') ?? DateTime.now(),
  );
}

NetworkRequest? _requestFromJson(Object? j) {
  if (j is! Map) return null;
  Map<String, String> headers(Object? h) =>
      h is Map ? h.map((k, v) => MapEntry('$k', '${v ?? ''}')) : const {};
  int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  return NetworkRequest(
    type: '${j['type'] ?? 'fetch'}',
    url: '${j['url'] ?? ''}',
    method: '${j['method'] ?? 'GET'}',
    status: asInt(j['status']),
    duration: asInt(j['duration']),
    requestBody: j['requestBody']?.toString(),
    responseBody: j['responseBody']?.toString(),
    error: j['error']?.toString(),
    timestamp: DateTime.tryParse('${j['timestamp']}') ?? DateTime.now(),
    requestHeaders: headers(j['requestHeaders']),
    responseHeaders: headers(j['responseHeaders']),
  );
}

class SessionStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sessions');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> save(WidgetRef ref, String name) async {
    final dir = await _dir();
    final now = DateTime.now();
    final data = {
      'format': 'debug-browser-session',
      'version': 1,
      'name': name,
      'savedAt': now.toIso8601String(),
      'page': {'url': ref.read(currentPageProvider).url, 'title': ref.read(currentPageProvider).title},
      'deviceInfo': ref.read(devicePerformanceProvider),
      'storage': ref.read(storageProvider),
      'logs': ref.read(consoleLogsProvider).map((l) => l.toJson()).toList(),
      'network': ref.read(networkRequestsProvider).map((n) => n.toJson()).toList(),
    };
    final file = File('${dir.path}/session_${now.millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(data));
    return file;
  }

  static Future<List<SavedSession>> list() async {
    final dir = await _dir();
    final out = <SavedSession>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is! Map || j['format'] != 'debug-browser-session') continue;
        out.add(SavedSession(
          f,
          '${j['name'] ?? 'Session'}',
          DateTime.tryParse('${j['savedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
          (j['logs'] as List?)?.length ?? 0,
          (j['network'] as List?)?.length ?? 0,
        ));
      } catch (e) {
        debugPrint('Skipping unreadable session ${f.path}: $e');
      }
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// Replaces the current console + network data with the saved session.
  static Future<void> load(WidgetRef ref, File file) async {
    final j = jsonDecode(await file.readAsString()) as Map;
    final logsN = ref.read(consoleLogsProvider.notifier)..clear();
    for (final l in (j['logs'] as List? ?? const []).map(_logFromJson).whereType<ConsoleLog>()) {
      logsN.addLog(l);
    }
    final netN = ref.read(networkRequestsProvider.notifier)..clear();
    for (final r in (j['network'] as List? ?? const []).map(_requestFromJson).whereType<NetworkRequest>()) {
      netN.addRequest(r);
    }
    if (j['deviceInfo'] is Map) {
      ref.read(devicePerformanceProvider.notifier).updateInfo(Map<String, dynamic>.from(j['deviceInfo'] as Map));
    }
  }
}

/// Visible for tests.
@visibleForTesting
NetworkRequest? requestFromJsonForTest(Object? j) => _requestFromJson(j);
