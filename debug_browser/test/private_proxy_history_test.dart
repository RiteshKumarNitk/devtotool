import 'dart:convert';

import 'package:debug_browser/core/browser_settings.dart';
import 'package:debug_browser/core/downloads.dart';
import 'package:debug_browser/core/js_bridge.dart';
import 'package:debug_browser/core/tabs_provider.dart';
import 'package:debug_browser/core/tool_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proxy settings', () {
    test('parses provider strings', () {
      final a = parseProxyString('socks5://alice:p%40ss@nl1.vpn.example:1080')!;
      expect(a.type, ProxyType.socks5);
      expect(a.host, 'nl1.vpn.example');
      expect(a.port, 1080);
      expect(a.username, 'alice');
      expect(a.password, 'p@ss');
      expect(a.rule, 'socks://nl1.vpn.example:1080');

      final b = parseProxyString('10.0.0.5:3128')!;
      expect(b.type, ProxyType.http);
      expect(b.hasCredentials, isFalse);
      expect(b.rule, 'http://10.0.0.5:3128');

      expect(parseProxyString('https://u:p@proxy.example:443/')!.type, ProxyType.https);
      expect(parseProxyString('no-port'), isNull);
      expect(parseProxyString('host:99999'), isNull);
    });

    test('validate', () {
      expect(const ProxySettings(host: 'p.example', port: 8080).validate(), isNull);
      expect(const ProxySettings(host: '', port: 8080).validate(), isNotNull);
      expect(const ProxySettings(host: 'http://p.example', port: 8080).validate(), contains('Host only'));
      expect(const ProxySettings(host: 'p.example', port: 0).validate(), contains('Port'));
    });

    test('JSON round-trip', () {
      const p = ProxySettings(
          enabled: true, type: ProxyType.socks5, host: 'h', port: 1080, username: 'u', password: 'p', bypass: ['*.local']);
      final back = ProxySettings.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.toJson(), p.toJson());
      expect(ProxySettings.fromJson(null).enabled, isFalse);
    });
  });

  group('download messages from the page', () {
    BridgeMessage? m(String type, Map<String, Object> data) => parseBridgeMessage(jsonEncode({'type': type, 'data': data}));

    test('blob_download only accepts data: URLs', () {
      final ok = m('blob_download', {'href': 'data:text/csv;base64,YSxi', 'name': 'export.csv'});
      expect(ok, isA<BrowserActionMessage>());
      expect(m('blob_download', {'href': 'https://x/y'}), isNull);
      expect(m('blob_download', {'href': 'javascript:alert(1)'}), isNull);
    });

    test('download_link only accepts web URLs', () {
      expect(m('download_link', {'href': 'https://x/report.pdf', 'name': 'r.pdf'}), isA<BrowserActionMessage>());
      expect(m('download_link', {'href': 'file:///sdcard/x'}), isNull);
    });

    test('page-suggested name is used when the server gives none', () {
      expect(suggestFileName('https://x/dl?id=9', null, 'text/csv', suggested: 'export.csv'), 'export.csv');
      // Content-Disposition still wins.
      expect(suggestFileName('https://x/dl', 'attachment; filename="server.csv"', null, suggested: 'page.csv'), 'server.csv');
      // And the suggestion is sanitised.
      expect(suggestFileName('https://x/', null, null, suggested: '../../evil.sh').contains('/'), isFalse);
    });
  });

  test('private flag survives copyWith', () {
    const t = BrowserTab(id: '1', url: 'https://a.b', isPrivate: true);
    expect(t.copyWith(title: 'x', loaded: true).isPrivate, isTrue);
  });

  test('history groups by Today / Yesterday / date, newest first', () {
    final now = DateTime(2026, 11, 18, 15);
    Map<String, String> v(String url, DateTime t) => {'url': url, 'title': '', 'time': t.toIso8601String()};
    final entries = [
      v('https://old', DateTime(2026, 11, 10, 9)),
      v('https://y1', DateTime(2026, 11, 17, 8)),
      v('https://t1', DateTime(2026, 11, 18, 9)),
      v('https://t2', DateTime(2026, 11, 18, 14)),
    ];
    final g = groupHistoryByDay(entries, now: now);
    expect(g.map((x) => x.$1).toList(), ['Today', 'Yesterday', '2026-11-10']);
    expect(g.first.$2.map((e) => e['url']).toList(), ['https://t2', 'https://t1']);
  });
}
