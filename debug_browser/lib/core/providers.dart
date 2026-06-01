import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

// --- Models ---
class ConsoleLog {
  final String level;
  final String message;
  final DateTime timestamp;
  ConsoleLog({required this.level, required this.message, required this.timestamp});
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
}

// --- Notifiers ---
class ConsoleLogsNotifier extends Notifier<List<ConsoleLog>> {
  @override
  List<ConsoleLog> build() => [];

  void addLog(ConsoleLog log) {
    state = [...state, log];
  }
  
  void clear() {
    state = [];
  }
}

class NetworkRequestsNotifier extends Notifier<List<NetworkRequest>> {
  @override
  List<NetworkRequest> build() => [];

  void addRequest(NetworkRequest req) {
    state = [...state, req];
  }
  
  void clear() {
    state = [];
  }
}

class StorageStateNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};
  
  void updateStorage(Map<String, dynamic> data) {
    state = data;
  }
}

class DevicePerformanceNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};
  
  void updateInfo(Map<String, dynamic> data) {
    state = {...state, ...data};
  }
}

// --- Providers ---
final consoleLogsProvider = NotifierProvider<ConsoleLogsNotifier, List<ConsoleLog>>(() {
  return ConsoleLogsNotifier();
});

final networkRequestsProvider = NotifierProvider<NetworkRequestsNotifier, List<NetworkRequest>>(() {
  return NetworkRequestsNotifier();
});

final storageProvider = NotifierProvider<StorageStateNotifier, Map<String, dynamic>>(() {
  return StorageStateNotifier();
});

final devicePerformanceProvider = NotifierProvider<DevicePerformanceNotifier, Map<String, dynamic>>(() {
  return DevicePerformanceNotifier();
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

final themeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

class WebViewControllerNotifier extends Notifier<WebViewController?> {
  @override
  WebViewController? build() => null;
  void setController(WebViewController controller) => state = controller;
}

final webViewControllerProvider = NotifierProvider<WebViewControllerNotifier, WebViewController?>(() {
  return WebViewControllerNotifier();
});

class UserAgentNotifier extends Notifier<String> {
  @override
  String build() => 'default';

  void setAgent(String agent) {
    state = agent;
  }
}

final userAgentProvider = NotifierProvider<UserAgentNotifier, String>(() {
  return UserAgentNotifier();
});

class DomTreeNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setTree(Map<String, dynamic> tree) {
    state = tree;
  }
}

final domTreeProvider = NotifierProvider<DomTreeNotifier, Map<String, dynamic>?>(() {
  return DomTreeNotifier();
});

class NetworkMocksNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void addMock(String pattern, String response) {
    state = {...state, pattern: response};
  }

  void removeMock(String pattern) {
    final newState = Map<String, String>.from(state);
    newState.remove(pattern);
    state = newState;
  }
}

final networkMocksProvider = NotifierProvider<NetworkMocksNotifier, Map<String, String>>(() {
  return NetworkMocksNotifier();
});

class BookmarksNotifier extends Notifier<List<Map<String, String>>> {
  @override
  List<Map<String, String>> build() => [];

  void addBookmark(String title, String url) {
    state = [...state, {'title': title, 'url': url}];
  }

  void removeBookmark(String url) {
    state = state.where((b) => b['url'] != url).toList();
  }
}

final bookmarksProvider = NotifierProvider<BookmarksNotifier, List<Map<String, String>>>(() {
  return BookmarksNotifier();
});
