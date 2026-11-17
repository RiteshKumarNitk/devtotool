import 'dart:convert';

import 'package:debug_browser/core/js_bridge.dart';
import 'package:debug_browser/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBridgeMessage', () {
    test('parses console message', () {
      final msg = parseBridgeMessage(jsonEncode({
        'type': 'console',
        'data': {'level': 'warn', 'message': 'hi'},
        'timestamp': 1000,
      }));
      expect(msg, isA<ConsoleMessage>());
      final log = (msg as ConsoleMessage).log;
      expect(log.level, 'warn');
      expect(log.message, 'hi');
      expect(log.timestamp.millisecondsSinceEpoch, 1000);
    });

    test('error message includes stack on a new line', () {
      final msg = parseBridgeMessage(jsonEncode({
        'type': 'error',
        'data': {'message': 'boom', 'stack': 'at x'},
      })) as ConsoleMessage;
      expect(msg.log.message, 'boom\nat x');
      expect(msg.log.level, 'error');
    });

    test('network message tolerates missing / wrongly typed fields', () {
      final msg = parseBridgeMessage(jsonEncode({
        'type': 'network',
        'data': {'url': 'https://a.b', 'method': 'post', 'status': '201'},
      })) as NetworkMessage;
      expect(msg.request.method, 'POST');
      expect(msg.request.status, 201);
      expect(msg.request.duration, 0);
    });

    test('truncates huge bodies', () {
      final msg = parseBridgeMessage(jsonEncode({
        'type': 'network',
        'data': {'url': 'u', 'responseBody': 'x' * (maxBodyChars + 10)},
      })) as NetworkMessage;
      expect(msg.request.responseBody!.length, lessThan(maxBodyChars + 50));
      expect(msg.request.responseBody, endsWith('[truncated]'));
    });

    test('returns null for malformed input', () {
      expect(parseBridgeMessage('not json'), isNull);
      expect(parseBridgeMessage('[]'), isNull);
      expect(parseBridgeMessage(jsonEncode({'type': 'console', 'data': 'x'})), isNull);
      expect(parseBridgeMessage(jsonEncode({'type': 'unknown', 'data': {}})), isNull);
    });
  });

  group('jsString', () {
    test('escapes quotes, backslashes and newlines', () {
      const input = 'it\'s "a" \\ \n end';
      final encoded = jsString(input);
      expect(encoded.startsWith('"') && encoded.endsWith('"'), isTrue);
      expect(encoded.contains('\n'), isFalse); // no raw newline
      expect(jsonDecode(encoded), input); // round-trips exactly
    });
  });

  group('normaliseUrlInput', () {
    test('keeps explicit schemes', () {
      expect(normaliseUrlInput('http://x.com').toString(), 'http://x.com');
    });
    test('adds https to bare domains', () {
      expect(normaliseUrlInput('example.com').toString(), 'https://example.com');
    });
    test('uses http for localhost and IPs', () {
      expect(normaliseUrlInput('localhost:3000').toString(), 'http://localhost:3000');
      expect(normaliseUrlInput('192.168.1.2:8080').scheme, 'http');
    });
    test('turns plain words into a search', () {
      final uri = normaliseUrlInput('flutter riverpod');
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['q'], 'flutter riverpod');
    });
  });

  test('appendCapped keeps newest entries', () {
    var list = <int>[];
    for (var i = 0; i < 10; i++) {
      list = appendCapped(list, i, 3);
    }
    expect(list, [7, 8, 9]);
  });
}
