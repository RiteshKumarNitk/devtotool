import 'package:debug_browser/core/providers.dart';
import 'package:debug_browser/core/tool_providers.dart';
import 'package:debug_browser/features/console/console_page.dart';
import 'package:debug_browser/features/console/json_tree.dart';
import 'package:debug_browser/features/more/environments_page.dart';
import 'package:debug_browser/features/performance/performance_page.dart';
import 'package:debug_browser/features/storage/storage_page.dart';
import 'package:debug_browser/services/bug_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleLog log(String level, String msg) =>
    ConsoleLog(level: level, message: msg, timestamp: DateTime.utc(2026, 1, 1));

void main() {
  group('MockRule', () {
    test('validate', () {
      const ok = MockRule(id: '1', pattern: '/api');
      expect(ok.validate(), isNull);
      expect(const MockRule(id: '1', pattern: ' ').validate(), isNotNull);
      expect(const MockRule(id: '1', pattern: '/a', status: 99).validate(), contains('Status'));
      expect(const MockRule(id: '1', pattern: '/a', delayMs: -1).validate(), contains('Delay'));
      expect(const MockRule(id: '1', pattern: '[bad', isRegex: true).validate(), contains('regex'));
    });

    test('JSON round-trip', () {
      const r = MockRule(
          id: 'x', pattern: r'/u/\d+', isRegex: true, method: 'POST', status: 503, delayMs: 250, body: '{}', enabled: false);
      final back = MockRule.fromJson(r.toJson())!;
      expect(back.toJson(), r.toJson());
    });

    test('parseMockRules accepts legacy map and skips junk', () {
      final legacy = parseMockRules({'/login': '{"ok":1}', '': 'skip'});
      expect(legacy.single.pattern, '/login');
      expect(legacy.single.status, 200);
      final list = parseMockRules([
        {'pattern': '/a', 'method': 'WEIRD'},
        {'nopattern': true},
        'junk',
      ]);
      expect(list.single.method, 'ANY');
      expect(parseMockRules('nope'), isEmpty);
    });
  });

  group('console', () {
    final logs = [log('error', 'boom'), log('warn', 'careful'), log('log', 'hello'), log('input', '1+1'), log('result', '2')];

    test('filterLogs by level group and query', () {
      expect(filterLogs(logs, LogLevelFilter.values.toSet(), '').length, 5);
      expect(filterLogs(logs, {LogLevelFilter.error}, '').single.message, 'boom');
      expect(filterLogs(logs, {LogLevelFilter.info}, '').single.message, 'hello');
      expect(filterLogs(logs, {LogLevelFilter.repl}, '').length, 2);
      expect(filterLogs(logs, LogLevelFilter.values.toSet(), 'CARE').single.level, 'warn');
    });

    test('extractJson finds trailing JSON and ignores primitives', () {
      final r = extractJson('user {"id":1,"tags":["a"]}')!;
      expect(r.prefix, 'user');
      expect((r.json as Map)['id'], 1);
      expect(extractJson('[1,2]')!.json, [1, 2]);
      expect(extractJson('42'), isNull);
      expect(extractJson('not {json'), isNull);
    });
  });

  test('rateVital uses web.dev thresholds', () {
    expect(rateVital('lcp', 2400), VitalRating.good);
    expect(rateVital('lcp', 3000), VitalRating.needsImprovement);
    expect(rateVital('lcp', 4001), VitalRating.poor);
    expect(rateVital('cls', 0.05), VitalRating.good);
    expect(rateVital('cls', 0.3), VitalRating.poor);
    expect(rateVital('inp', null), VitalRating.unknown);
  });

  test('parseCookieString keeps = inside values', () {
    final c = parseCookieString('a=1; token=x=y==; empty; ');
    expect(c.map((e) => e.key), ['a', 'token', 'empty']);
    expect(c[1].value, 'x=y==');
    expect(c[2].value, '');
  });

  test('switchEnvironment keeps path, query and fragment', () {
    expect(
      switchEnvironment('https://prod.example.com/checkout?step=2#pay', 'staging.example.com'),
      'https://staging.example.com/checkout?step=2#pay',
    );
    expect(switchEnvironment('', 'http://localhost:3000'), 'http://localhost:3000');
  });

  test('session request JSON restores headers and types', () {
    final r = requestFromJsonForTest({
      'type': 'xhr',
      'url': 'https://a.b',
      'method': 'POST',
      'status': '500',
      'duration': 12,
      'timestamp': '2026-01-01T00:00:00.000Z',
      'requestHeaders': {'x': 1},
    })!;
    expect(r.status, 500);
    expect(r.requestHeaders, {'x': '1'});
    expect(requestFromJsonForTest('junk'), isNull);
  });

  test('bug report markdown includes errors, failed requests as cURL, vitals', () {
    final md = buildBugReportMarkdown(
      description: 'Checkout button does nothing',
      page: const CurrentPage(url: 'https://shop.test/cart', title: 'Cart'),
      logs: [log('error', 'TypeError: x is undefined'), log('log', 'noise')],
      requests: [
        NetworkRequest(
            type: 'fetch', url: 'https://shop.test/api/pay', method: 'POST', status: 500, duration: 80,
            responseBody: '{"error":"db"}', timestamp: DateTime.utc(2026)),
        NetworkRequest(type: 'fetch', url: 'https://shop.test/ok', method: 'GET', status: 200, duration: 5, timestamp: DateTime.utc(2026)),
      ],
      deviceInfo: {
        'device': {'userAgent': 'UA', 'screenWidth': 390, 'screenHeight': 844, 'pixelRatio': 3, 'language': 'en', 'timezone': 'Asia/Kolkata'}
      },
      vitals: {
        'vitals': {'lcp': 2100, 'cls': 0.02, 'inp': null, 'fcp': 900, 'ttfb': 120}
      },
      now: DateTime.utc(2026, 1, 2),
    );
    expect(md, contains('https://shop.test/cart'));
    expect(md, contains('Checkout button does nothing'));
    expect(md, contains('TypeError: x is undefined'));
    expect(md, isNot(contains('noise')));
    expect(md, contains('## Failed requests (1)'));
    expect(md, contains("curl 'https://shop.test/api/pay'"));
    expect(md, contains('{"error":"db"}'));
    expect(md, contains('| 2100 ms | 0.02 | – | 900 ms | 120 ms |'));
  });
}
