import 'dart:convert';

import 'providers.dart';

/// Headers the browser sets itself; copying them into cURL only adds noise
/// or breaks the request (e.g. a stale content-length).
const _skipHeaders = {'content-length', 'host', 'connection'};

/// POSIX shell single-quoting: wrap in '…' and turn each ' into '\''.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Builds a copy-pasteable cURL command for [req].
String toCurl(NetworkRequest req) {
  // One "flag value" per line: curl 'url' \⏎  -X POST \⏎  -H '...'
  final lines = <String>['curl ${shellQuote(req.url)}'];
  if (req.method != 'GET') lines.add('-X ${req.method}');
  req.requestHeaders.forEach((name, value) {
    if (_skipHeaders.contains(name.toLowerCase())) return;
    lines.add('-H ${shellQuote('$name: $value')}');
  });
  final body = req.requestBody;
  if (body != null && body.isNotEmpty) {
    lines.add('--data-raw ${shellQuote(body)}');
  }
  return lines.join(' \\\n  ');
}

/// Builds an equivalent JavaScript `fetch(...)` call for [req].
String toFetch(NetworkRequest req) {
  final headers = Map.fromEntries(req.requestHeaders.entries
      .where((e) => !_skipHeaders.contains(e.key.toLowerCase())));
  final options = <String, dynamic>{
    'method': req.method,
    if (headers.isNotEmpty) 'headers': headers,
    if (req.requestBody != null && req.requestBody!.isNotEmpty) 'body': req.requestBody,
  };
  const encoder = JsonEncoder.withIndent('  ');
  return 'fetch(${jsonEncode(req.url)}, ${encoder.convert(options)});';
}

List<Map<String, String>> _harHeaders(Map<String, String> headers) =>
    [for (final e in headers.entries) {'name': e.key, 'value': e.value}];

List<Map<String, String>> _harQuery(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return const [];
  return [
    for (final e in uri.queryParametersAll.entries)
      for (final v in e.value) {'name': e.key, 'value': v},
  ];
}

/// Builds a HAR 1.2 document (http://www.softwareishard.com/blog/har-12-spec/)
/// that Chrome DevTools, Firefox, Charles and Fiddler can import.
Map<String, dynamic> buildHar(
  List<NetworkRequest> requests, {
  String creatorVersion = '1.0.0',
}) {
  return {
    'log': {
      'version': '1.2',
      'creator': {'name': 'Debug Browser', 'version': creatorVersion},
      'pages': <Object>[],
      'entries': [
        for (final r in requests)
          {
            // The SDK reports at completion; derive the start time.
            'startedDateTime': r.timestamp
                .subtract(Duration(milliseconds: r.duration))
                .toUtc()
                .toIso8601String(),
            'time': r.duration,
            'request': {
              'method': r.method,
              'url': r.url,
              'httpVersion': 'HTTP/1.1',
              'cookies': <Object>[],
              'headers': _harHeaders(r.requestHeaders),
              'queryString': _harQuery(r.url),
              if (r.requestBody != null)
                'postData': {
                  'mimeType': r.requestHeaders['content-type'] ?? 'text/plain',
                  'text': r.requestBody,
                },
              'headersSize': -1,
              'bodySize': r.requestBody?.length ?? 0,
            },
            'response': {
              'status': r.status,
              'statusText': r.error ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': <Object>[],
              'headers': _harHeaders(r.responseHeaders),
              'content': {
                'size': r.responseBody?.length ?? 0,
                'mimeType': r.responseHeaders['content-type'] ?? 'text/plain',
                if (r.responseBody != null) 'text': r.responseBody,
              },
              'redirectURL': r.responseHeaders['location'] ?? '',
              'headersSize': -1,
              'bodySize': r.responseBody?.length ?? -1,
            },
            'cache': <String, Object>{},
            'timings': {'send': 0, 'wait': r.duration, 'receive': 0},
            '_resourceType': r.type,
          },
      ],
    },
  };
}

/// Status filter buckets for the Network panel.
enum StatusFilter {
  all('All'),
  success('2xx'),
  redirect('3xx'),
  clientError('4xx'),
  serverError('5xx'),
  failed('Failed');

  const StatusFilter(this.label);
  final String label;

  bool matches(NetworkRequest r) => switch (this) {
        StatusFilter.all => true,
        StatusFilter.success => r.status >= 200 && r.status < 300,
        StatusFilter.redirect => r.status >= 300 && r.status < 400,
        StatusFilter.clientError => r.status >= 400 && r.status < 500,
        StatusFilter.serverError => r.status >= 500,
        StatusFilter.failed => r.failed,
      };
}

/// Applies the Network panel filters. [type] is null for all, or 'fetch'/'xhr'.
List<NetworkRequest> filterRequests(
  List<NetworkRequest> requests, {
  String query = '',
  String? type,
  StatusFilter status = StatusFilter.all,
}) {
  final q = query.trim().toLowerCase();
  return requests.where((r) {
    if (type != null && r.type != type) return false;
    if (!status.matches(r)) return false;
    if (q.isEmpty) return true;
    return r.url.toLowerCase().contains(q) ||
        r.method.toLowerCase() == q ||
        r.status.toString() == q;
  }).toList();
}
