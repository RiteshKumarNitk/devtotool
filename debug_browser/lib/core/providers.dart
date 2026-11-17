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
  });

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
      };
}

/// Appends [item] keeping at most [max] newest entries.
List<T> appendCapped<T>(List<T> list, T item, int max) {
  final next = [...list, item];
  return next.length > max ? next.sublist(next.length - max) : next;
}

// --- Notifiers ---
class ConsoleLogsNotifier extends Notifier<List<ConsoleLog>> {
  @override
  List<ConsoleLog> build() => [];

  void addLog(ConsoleLog log) => state = appendCapped(state, log, maxConsoleLogs);

  void clear() => state = [];
}

class NetworkRequestsNotifier extends Notifier<List<NetworkRequest>> {
  @override
  List<NetworkRequest> build() => [];

  void addRequest(NetworkRequest req) =>
      state = appendCapped(state, req, maxNetworkRequests);

  void clear() => state = [];
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
    return saved == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _settingsBoxOrNull()?.put(_key, state == ThemeMode.light ? 'light' : 'dark');
  }
}

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

class NetworkMocksNotifier extends Notifier<Map<String, String>> {
  static const _key = 'networkMocks';

  @override
  Map<String, String> build() {
    final saved = _settingsBoxOrNull()?.get(_key);
    if (saved is Map) {
      return saved.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return {};
  }

  void addMock(String pattern, String response) {
    if (pattern.trim().isEmpty) return;
    state = {...state, pattern.trim(): response};
    _persist();
  }

  void removeMock(String pattern) {
    state = Map<String, String>.from(state)..remove(pattern);
    _persist();
  }

  void _persist() => _settingsBoxOrNull()?.put(_key, state);
}

final networkMocksProvider =
    NotifierProvider<NetworkMocksNotifier, Map<String, String>>(NetworkMocksNotifier.new);

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
  bool addBookmark(String title, String url) {
    if (state.any((b) => b['url'] == url)) return false;
    state = [...state, {'title': title, 'url': url}];
    _persist();
    return true;
  }

  void removeBookmark(String url) {
    state = state.where((b) => b['url'] != url).toList();
    _persist();
  }

  void _persist() => _settingsBoxOrNull()?.put(_key, state);
}

final bookmarksProvider =
    NotifierProvider<BookmarksNotifier, List<Map<String, String>>>(BookmarksNotifier.new);
