import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hive box used for small persisted settings. Opened in `main()`.
const String settingsBoxName = 'settings';

/// Maximum entries kept in memory for high-volume panels.
const int maxConsoleLogs = 1000;
const int maxNetworkRequests = 500;

/// Truncate captured bodies so a single huge response can't exhaust memory.
const int maxBodyChars = 100 * 1024;

Box? _settingsBoxOrNull() =>
    Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

// --- Models ---
class ConsoleLog {
  final String level;
  final String message;
  final DateTime timestamp;
  ConsoleLog({required this.level, required this.message, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'level': level,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}

class NetworkRequest {
  final String type;
  final String url;
  final String method;
  final int status;
  final int duration;
  final String? requestBody;
  final String? responseBody;
  final String? error;
  final DateTime timestamp;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;

  NetworkRequest({
    required this.type,
    required this.url,
    required this.method,
    required this.status,
    required this.duration,
    this.requestBody,
    this.responseBody,
    this.error,
    required this.timestamp,
    this.requestHeaders = const {},
    this.responseHeaders = const {},
  });

  bool get failed => status == 0 || error != null;

  Map<String, dynamic> toJson() => {
        'type': type,
        'url': url,
        'method': method,
        'status': status,
        'duration': duration,
        'requestBody': requestBody,
        'responseBody': responseBody,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
        'requestHeaders': requestHeaders,
        'responseHeaders': responseHeaders,
      };
}

/// Appends [item] keeping at most [max] newest entries.
List<T> appendCapped<T>(List<T> list, T item, int max) {
  final next = [...list, item];
  return next.length > max ? next.sublist(next.length - max) : next;
}

/// Appends many [items] keeping at most [max] newest entries (one copy).
List<T> appendAllCapped<T>(List<T> list, List<T> items, int max) {
  if (items.length >= max) return items.sublist(items.length - max);
  final drop = (list.length + items.length - max).clamp(0, list.length);
  return [...list.skip(drop), ...items];
}

/// Collects entries and publishes them together at most every 100 ms, so a
/// page that logs hundreds of lines a second costs a few list copies and
/// redraws instead of one per line.
mixin _BatchedAppend<T> on Notifier<List<T>> {
  final List<T> _buffer = [];
  Timer? _flushTimer;
  int get _max;

  void _queue(T item, {bool now = false}) {
    _buffer.add(item);
    if (now) return _flush();
    _flushTimer ??= Timer(const Duration(milliseconds: 100), _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty || !ref.mounted) return;
    state = appendAllCapped(state, [..._buffer], _max);
    _buffer.clear();
  }

  void _drop() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _buffer.clear();
  }
}

// --- Notifiers ---
class ConsoleLogsNotifier extends Notifier<List<ConsoleLog>> with _BatchedAppend<ConsoleLog> {
  @override
  int get _max => maxConsoleLogs;

  @override
  List<ConsoleLog> build() {
    ref.onDispose(_drop);
    return [];
  }

  /// REPL input and results show at once; page logs are batched.
  void addLog(ConsoleLog log) => _queue(log, now: log.level == 'input' || log.level == 'result');

  /// Publishes anything still waiting (tests, exports).
  void flush() => _flush();

  void clear() {
    _drop();
    state = [];
  }
}

class NetworkRequestsNotifier extends Notifier<List<NetworkRequest>> with _BatchedAppend<NetworkRequest> {
  @override
  int get _max => maxNetworkRequests;

  @override
  List<NetworkRequest> build() {
    ref.onDispose(_drop);
    return [];
  }

  void addRequest(NetworkRequest req) => _queue(req);

  void flush() => _flush();

  void clear() {
    _drop();
    state = [];
  }
}

class StorageStateNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};

  void updateStorage(Map<String, dynamic> data) => state = data;
}

class DevicePerformanceNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};

  void updateInfo(Map<String, dynamic> data) => state = {...state, ...data};
}

// --- Providers ---
final consoleLogsProvider =
    NotifierProvider<ConsoleLogsNotifier, List<ConsoleLog>>(ConsoleLogsNotifier.new);

final networkRequestsProvider =
    NotifierProvider<NetworkRequestsNotifier, List<NetworkRequest>>(NetworkRequestsNotifier.new);

final storageProvider =
    NotifierProvider<StorageStateNotifier, Map<String, dynamic>>(StorageStateNotifier.new);

final devicePerformanceProvider =
    NotifierProvider<DevicePerformanceNotifier, Map<String, dynamic>>(DevicePerformanceNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    final saved = _settingsBoxOrNull()?.get(_key) as String?;
    return switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system, // follow the phone by default
    };
  }

  void set(ThemeMode mode) {
    state = mode;
    _settingsBoxOrNull()?.put(_key, mode.name);
  }

  /// Flips between light and dark (from whatever is showing now).
  void toggle({Brightness? current}) {
    final dark = state == ThemeMode.dark || (state == ThemeMode.system && current == Brightness.dark);
    set(dark ? ThemeMode.light : ThemeMode.dark);
  }
}

/// Accent colours offered in Settings (seed for the Material 3 scheme).
const accentColors = <String, int>{
  'Blue': 0xFF1A73E8,
  'Teal': 0xFF00897B,
  'Purple': 0xFF7E57C2,
  'Orange': 0xFFF4511E,
  'Pink': 0xFFD81B60,
  'Green': 0xFF43A047,
};

class AccentColorNotifier extends Notifier<int> {
  static const _key = 'accentColor';

  @override
  int build() {
    final v = _settingsBoxOrNull()?.get(_key);
    return v is int && accentColors.containsValue(v) ? v : accentColors['Blue']!;
  }

  void set(int color) {
    if (!accentColors.containsValue(color)) return;
    state = color;
    _settingsBoxOrNull()?.put(_key, color);
  }
}

final accentColorProvider = NotifierProvider<AccentColorNotifier, int>(AccentColorNotifier.new);

final themeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class WebViewControllerNotifier extends Notifier<WebViewController?> {
  @override
  WebViewController? build() => null;
  void setController(WebViewController controller) => state = controller;
}

final webViewControllerProvider =
    NotifierProvider<WebViewControllerNotifier, WebViewController?>(WebViewControllerNotifier.new);

class UserAgentNotifier extends Notifier<String> {
  @override
  String build() => 'default';

  void setAgent(String agent) => state = agent;
}

final userAgentProvider = NotifierProvider<UserAgentNotifier, String>(UserAgentNotifier.new);

class DomTreeNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setTree(Map<String, dynamic> tree) => state = tree;
}

final domTreeProvider =
    NotifierProvider<DomTreeNotifier, Map<String, dynamic>?>(DomTreeNotifier.new);

/// A response-mocking rule applied by the debug SDK to fetch and XHR.
@immutable
class MockRule {
  final String id;
  final String pattern;
  final bool isRegex;
  final String method; // 'ANY' or an HTTP method
  final int status;
  final int delayMs;
  final String body;
  final String contentType;
  final bool enabled;

  const MockRule({
    required this.id,
    required this.pattern,
    this.isRegex = false,
    this.method = 'ANY',
    this.status = 200,
    this.delayMs = 0,
    this.body = '',
    this.contentType = 'application/json',
    this.enabled = true,
  });

  static const methods = ['ANY', 'GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  /// Returns an error message if the rule is invalid, else null.
  String? validate() {
    if (pattern.trim().isEmpty) return 'Pattern is required';
    if (status < 200 || status > 599) return 'Status must be 200–599';
    if (delayMs < 0 || delayMs > 60000) return 'Delay must be 0–60000 ms';
    if (isRegex) {
      try {
        RegExp(pattern);
      } on FormatException catch (e) {
        return 'Invalid regex: ${e.message}';
      }
    }
    return null;
  }

  MockRule copyWith({
    String? pattern,
    bool? isRegex,
    String? method,
    int? status,
    int? delayMs,
    String? body,
    String? contentType,
    bool? enabled,
  }) =>
      MockRule(
        id: id,
        pattern: pattern ?? this.pattern,
        isRegex: isRegex ?? this.isRegex,
        method: method ?? this.method,
        status: status ?? this.status,
        delayMs: delayMs ?? this.delayMs,
        body: body ?? this.body,
        contentType: contentType ?? this.contentType,
        enabled: enabled ?? this.enabled,
      );

  /// Shape consumed by the SDK's `updateApiMocks`.
  Map<String, dynamic> toJson() => {
        'id': id,
        'pattern': pattern,
        'isRegex': isRegex,
        'method': method,
        'status': status,
        'delay': delayMs,
        'body': body,
        'contentType': contentType,
        'enabled': enabled,
      };

  static MockRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final pattern = json['pattern']?.toString() ?? '';
    if (pattern.isEmpty) return null;
    int asInt(Object? v, int d) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
    return MockRule(
      id: json['id']?.toString() ?? newId(),
      pattern: pattern,
      isRegex: json['isRegex'] == true,
      method: methods.contains(json['method']) ? json['method'] as String : 'ANY',
      status: asInt(json['status'], 200),
      delayMs: asInt(json['delay'], 0),
      body: json['body']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'application/json',
      enabled: json['enabled'] != false,
    );
  }

  static int _seq = 0;
  static String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

/// Parses an imported mock file: a list of rules, or a legacy
/// `{pattern: body}` map. Invalid entries are skipped.
List<MockRule> parseMockRules(Object? json) {
  if (json is List) {
    return json.map(MockRule.fromJson).whereType<MockRule>().toList();
  }
  if (json is Map) {
    return [
      for (final e in json.entries)
        if (e.key.toString().isNotEmpty)
          MockRule(id: MockRule.newId(), pattern: e.key.toString(), body: '${e.value ?? ''}'),
    ];
  }
  return const [];
}

class NetworkMocksNotifier extends Notifier<List<MockRule>> {
  static const _key = 'networkMockRules';
  static const _legacyKey = 'networkMocks';

  @override
  List<MockRule> build() {
    final box = _settingsBoxOrNull();
    final saved = box?.get(_key);
    if (saved is List) return parseMockRules(saved);
    // One-time migration from the old {pattern: body} format.
    final legacy = box?.get(_legacyKey);
    if (legacy is Map) {
      final migrated = parseMockRules(legacy);
      box?.put(_key, migrated.map((r) => r.toJson()).toList());
      box?.delete(_legacyKey);
      return migrated;
    }
    return [];
  }

  void upsert(MockRule rule) {
    final i = state.indexWhere((r) => r.id == rule.id);
    if (i < 0) {
      state = [...state, rule];
    } else {
      final next = [...state];
      next[i] = rule;
      state = next;
    }
    _persist();
  }

  void toggle(String id) {
    state = [for (final r in state) r.id == id ? r.copyWith(enabled: !r.enabled) : r];
    _persist();
  }

  void remove(String id) {
    state = state.where((r) => r.id != id).toList();
    _persist();
  }

  /// Adds imported rules; replaces existing ones with the same id.
  int importRules(List<MockRule> rules) {
    final byId = {for (final r in state) r.id: r};
    for (final r in rules) {
      byId[r.id] = r;
    }
    state = byId.values.toList();
    _persist();
    return rules.length;
  }

  void _persist() =>
      _settingsBoxOrNull()?.put(_key, state.map((r) => r.toJson()).toList());
}

final networkMocksProvider =
    NotifierProvider<NetworkMocksNotifier, List<MockRule>>(NetworkMocksNotifier.new);

class BookmarksNotifier extends Notifier<List<Map<String, String>>> {
  static const _key = 'bookmarks';

  @override
  List<Map<String, String>> build() {
    final saved = _settingsBoxOrNull()?.get(_key);
    if (saved is List) {
      return saved
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    }
    return [];
  }

  /// Adds a bookmark; returns false if the URL is already bookmarked.
  bool addBookmark(String title, String url, {String? folder}) {
    if (state.any((b) => b['url'] == url)) return false;
    state = [
      ...state,
      {'title': title, 'url': url, if (folder != null && folder.trim().isNotEmpty) 'folder': folder.trim()},
    ];
    _persist();
    return true;
  }

  /// Folder names in use (bookmarks without a folder are at the top level).
  List<String> get folders => <String>{
        for (final b in state)
          if ((b['folder'] ?? '').isNotEmpty) b['folder']!,
      }.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  void moveToFolder(String url, String? folder) {
    final f = folder?.trim() ?? '';
    state = [
      for (final b in state)
        if (b['url'] == url) ({...b}..remove('folder')..addAll(f.isEmpty ? {} : {'folder': f})) else b,
    ];
    _persist();
  }

  void renameBookmark(String url, String title) {
    state = [for (final b in state) b['url'] == url ? {...b, 'title': title.trim()} : b];
    _persist();
  }

  void renameFolder(String from, String to) {
    final name = to.trim();
    if (name.isEmpty) return;
    state = [for (final b in state) b['folder'] == from ? {...b, 'folder': name} : b];
    _persist();
  }

  /// Removes the folder; its bookmarks move to the top level.
  void deleteFolder(String folder) {
    state = [for (final b in state) b['folder'] == folder ? ({...b}..remove('folder')) : b];
    _persist();
  }

  void removeBookmark(String url) {
    state = state.where((b) => b['url'] != url).toList();
    _persist();
  }

  void _persist() => _settingsBoxOrNull()?.put(_key, state);
}

final bookmarksProvider =
    NotifierProvider<BookmarksNotifier, List<Map<String, String>>>(BookmarksNotifier.new);

/// Simulated network conditions applied inside the page by the debug SDK.
/// Session-only on purpose: a forgotten "Offline" must not survive restarts.
enum NetworkCondition {
  none('No throttling', 0, false),
  fast3g('Fast 3G (~560 ms)', 560, false),
  slow3g('Slow 3G (~2 s)', 2000, false),
  offline('Offline', 0, true);

  const NetworkCondition(this.label, this.latencyMs, this.isOffline);
  final String label;
  final int latencyMs;
  final bool isOffline;

  Map<String, dynamic> toJson() => {'offline': isOffline, 'latency': latencyMs};
}

class NetworkConditionNotifier extends Notifier<NetworkCondition> {
  @override
  NetworkCondition build() => NetworkCondition.none;

  void set(NetworkCondition condition) => state = condition;
}

final networkConditionProvider =
    NotifierProvider<NetworkConditionNotifier, NetworkCondition>(NetworkConditionNotifier.new);
