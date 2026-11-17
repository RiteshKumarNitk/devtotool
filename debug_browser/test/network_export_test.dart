import 'dart:convert';

import 'package:debug_browser/core/network_export.dart';
import 'package:debug_browser/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkRequest req({
  String url = 'https://api.example.com/users?id=7&tag=a&tag=b',
  String method = 'GET',
  int status = 200,
  String type = 'fetch',
  String? body,
  String? error,
  Map<String, String> reqHeaders = const {},
  Map<String, String> resHeaders = const {},
}) =>
    NetworkRequest(
      type: type,
      url: url,
      method: method,
      status: status,
      duration: 120,
      requestBody: body,
      responseBody: '{"ok":true}',
      error: error,
      timestamp: DateTime.utc(2026, 1, 1, 12),
      requestHeaders: reqHeaders,
      responseHeaders: resHeaders,
    );

void main() {
  group('shellQuote', () {
    test('escapes single quotes POSIX-style', () {
      expect(shellQuote("it's"), r"'it'\''s'");
    });
  });

  group('toCurl', () {
    test('GET has no -X and quotes URL', () {
      final c = toCurl(req());
      expect(c, startsWith("curl 'https://api.example.com/users?id=7&tag=a&tag=b'"));
      expect(c.contains('-X'), isFalse);
    });

    test('POST includes method, headers and body; skips content-length', () {
      final c = toCurl(req(
        method: 'POST',
        body: '{"name":"O\'Brien"}',
        reqHeaders: {'content-type': 'application/json', 'content-length': '18'},
      ));
      expect(c, contains('-X POST'));
      expect(c, contains("-H 'content-type: application/json'"));
      expect(c.contains('content-length'), isFalse);
      expect(c, contains(r"""--data-raw '{"name":"O'\''Brien"}'"""));
    });
  });

  test('toFetch produces valid options JSON', () {
    final f = toFetch(req(method: 'PUT', body: 'x', reqHeaders: {'a': 'b'}));
    expect(f, startsWith('fetch("https://api.example.com/users?id=7&tag=a&tag=b", '));
    final opts = jsonDecode(f.substring(f.indexOf(', ') + 2, f.length - 2));
    expect(opts, {'method': 'PUT', 'headers': {'a': 'b'}, 'body': 'x'});
  });

  group('buildHar', () {
    test('produces HAR 1.2 structure', () {
      final har = buildHar([
        req(resHeaders: {'content-type': 'application/json'}),
      ]);
      final log = har['log'] as Map;
      expect(log['version'], '1.2');
      final entry = (log['entries'] as List).single as Map;
      expect(entry['time'], 120);
      expect(entry['startedDateTime'], '2026-01-01T11:59:59.880Z');
      final request = entry['request'] as Map;
      expect(request['queryString'], [
        {'name': 'id', 'value': '7'},
        {'name': 'tag', 'value': 'a'},
        {'name': 'tag', 'value': 'b'},
      ]);
      expect(request.containsKey('postData'), isFalse);
      final content = (entry['response'] as Map)['content'] as Map;
      expect(content['mimeType'], 'application/json');
      // Must be JSON-serialisable end to end.
      expect(() => jsonEncode(har), returnsNormally);
    });

    test('includes postData when there is a body', () {
      final har = buildHar([req(method: 'POST', body: 'a=1')]);
      final request = ((har['log'] as Map)['entries'] as List).single['request'] as Map;
      expect((request['postData'] as Map)['text'], 'a=1');
    });
  });

  group('filterRequests', () {
    final all = [
      req(url: 'https://a.com/ok', status: 200),
      req(url: 'https://a.com/missing', status: 404, type: 'xhr'),
      req(url: 'https://b.com/boom', status: 503),
      req(url: 'https://b.com/down', status: 0, error: 'Simulated offline'),
      req(url: 'https://b.com/redirect', status: 302, type: 'xhr', method: 'POST'),
    ];

    test('status buckets', () {
      expect(filterRequests(all, status: StatusFilter.success).length, 1);
      expect(filterRequests(all, status: StatusFilter.clientError).single.status, 404);
      expect(filterRequests(all, status: StatusFilter.serverError).single.status, 503);
      expect(filterRequests(all, status: StatusFilter.failed).single.status, 0);
      expect(filterRequests(all, status: StatusFilter.redirect).single.status, 302);
    });

    test('type filter', () {
      expect(filterRequests(all, type: 'xhr').length, 2);
    });

    test('query matches URL, exact method and exact status', () {
      expect(filterRequests(all, query: 'b.com').length, 3);
      expect(filterRequests(all, query: 'post').single.status, 302);
      expect(filterRequests(all, query: '404').single.status, 404);
    });

    test('filters combine', () {
      expect(filterRequests(all, query: 'a.com', type: 'xhr').single.status, 404);
    });
  });

  test('NetworkCondition JSON matches what the SDK expects', () {
    expect(NetworkCondition.offline.toJson(), {'offline': true, 'latency': 0});
    expect(NetworkCondition.slow3g.toJson(), {'offline': false, 'latency': 2000});
  });
}
