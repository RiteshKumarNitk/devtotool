import 'dart:convert';

import 'providers.dart';

/// Encodes [value] as a JavaScript string literal (including quotes).
/// JSON string encoding is a valid JS literal and escapes quotes,
/// backslashes, newlines and control characters safely.
String jsString(String value) => jsonEncode(value);

String? _truncate(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.length > maxBodyChars ? '${s.substring(0, maxBodyChars)}… [truncated]' : s;
}

Map<String, String> _asHeaders(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      if (e.key != null) e.key.toString().toLowerCase(): '${e.value ?? ''}',
  };
}

int _asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// A decoded message from the injected debug SDK.
sealed class BridgeMessage {
  const BridgeMessage();
}

class ConsoleMessage extends BridgeMessage {
  final ConsoleLog log;
  const ConsoleMessage(this.log);
}

class NetworkMessage extends BridgeMessage {
  final NetworkRequest request;
  const NetworkMessage(this.request);
}

class StorageMessage extends BridgeMessage {
  final Map<String, dynamic> data;
  const StorageMessage(this.data);
}

class DeviceInfoMessage extends BridgeMessage {
  final String kind; // 'device' | 'performance'
  final Map<String, dynamic> data;
  const DeviceInfoMessage(this.kind, this.data);
}

/// Per-page data from the SDK extras: 'vitals', 'dom_tree', 'a11y'.
class PageDataMessage extends BridgeMessage {
  final String kind;
  final Map<String, dynamic> data;
  const PageDataMessage(this.kind, this.data);
}

class DomNodeMessage extends BridgeMessage {
  final Map<String, dynamic> data;
  const DomNodeMessage(this.data);
}

/// Parses a raw `DebugBridge.postMessage` payload. Returns null for
/// malformed or unknown messages — page content is untrusted.
BridgeMessage? parseBridgeMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final type = decoded['type'];
  final data = decoded['data'];
  if (data is! Map) return null;
  final map = Map<String, dynamic>.from(data);
  final ts = decoded['timestamp'];
  final timestamp = ts is num
      ? DateTime.fromMillisecondsSinceEpoch(ts.toInt())
      : DateTime.now();

  switch (type) {
    case 'console':
      return ConsoleMessage(ConsoleLog(
        level: (map['level'] ?? 'log').toString(),
        message: _truncate(map['message']) ?? '',
        timestamp: timestamp,
      ));
    case 'error':
      final stack = map['stack'];
      return ConsoleMessage(ConsoleLog(
        level: 'error',
        message: '${map['message'] ?? 'Unknown error'}${stack != null ? '\n$stack' : ''}',
        timestamp: timestamp,
      ));
    case 'network':
      return NetworkMessage(NetworkRequest(
        type: (map['type'] ?? 'fetch').toString(),
        url: (map['url'] ?? '').toString(),
        method: (map['method'] ?? 'GET').toString().toUpperCase(),
        status: _asInt(map['status']),
        duration: _asInt(map['duration']),
        requestBody: _truncate(map['requestBody']),
        responseBody: _truncate(map['responseBody']),
        error: map['error']?.toString(),
        timestamp: timestamp,
        requestHeaders: _asHeaders(map['requestHeaders']),
        responseHeaders: _asHeaders(map['responseHeaders']),
      ));
    case 'storage':
      return StorageMessage(map);
    case 'device':
    case 'performance':
      return DeviceInfoMessage(type as String, map);
    case 'dom_node':
      return DomNodeMessage(map);
    case 'vitals':
    case 'dom_tree':
    case 'a11y':
    case 'find_result':
      return PageDataMessage(type as String, map);
    case 'ui':
      final kind = map['kind'];
      if (kind != 'scroll' && kind != 'pull') return null;
      return UiEventMessage(kind as String, map);
    case 'blocked':
      final n = map['n'];
      final domains = map['domains'];
      if (n is! num) return null;
      return BlockedMessage(n.toInt(), {
        if (domains is Map)
          for (final e in domains.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      });
    case 'blob_download':
      final data = map['href'];
      if (data is! String || !data.startsWith('data:')) return null;
      return BrowserActionMessage(type as String, map);
    case 'open_tab':
    case 'link_menu':
    case 'download_link':
    case 'popup_blocked':
    case 'favicon':
      final href = map['href'];
      // Only web links may open tabs from page content.
      if (href is! String || !(href.startsWith('http://') || href.startsWith('https://'))) return null;
      return BrowserActionMessage(type as String, map);
  }
  return null;
}

/// Browser-UI signals from the page: 'scroll' {dir: down|up|top} and
/// 'pull' {state: move|release|cancel, d: pixels}.
class UiEventMessage extends BridgeMessage {
  final String kind;
  final Map<String, dynamic> data;
  const UiEventMessage(this.kind, this.data);
}

/// The extension blocker stopped [count] requests (delta since last report).
class BlockedMessage extends BridgeMessage {
  final int count;
  final Map<String, int> domains;
  const BlockedMessage(this.count, this.domains);
}

/// Page-initiated browser actions: 'open_tab' (target=_blank / window.open)
/// and 'link_menu' (long-press on a link or image).
class BrowserActionMessage extends BridgeMessage {
  final String kind;
  final Map<String, dynamic> data;
  const BrowserActionMessage(this.kind, this.data);
  String get href => data['href'] as String;
}

/// Normalises user input from the address bar into a loadable URI.
/// Bare words become a query for [search] (Google by default).
Uri normaliseUrlInput(String input, {Uri Function(String query)? search}) {
  final text = input.trim();
  if (text.isEmpty) return Uri.parse('about:blank');
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text) ||
      text.startsWith('about:') ||
      text.startsWith('data:');
  if (hasScheme) return Uri.parse(text);
  final looksLikeHost = !text.contains(' ') &&
      (text.contains('.') || text.startsWith('localhost'));
  if (looksLikeHost) {
    final isLocal = text.startsWith('localhost') ||
        RegExp(r'^(\d{1,3}\.){3}\d{1,3}').hasMatch(text);
    return Uri.parse('${isLocal ? 'http' : 'https'}://$text');
  }
  return search?.call(text) ?? Uri.https('www.google.com', '/search', {'q': text});
}
