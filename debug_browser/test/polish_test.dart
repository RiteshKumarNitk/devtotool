import 'dart:convert';

import 'package:debug_browser/core/backup.dart';
import 'package:debug_browser/core/browser_settings.dart';
import 'package:debug_browser/core/extensions.dart';
import 'package:debug_browser/core/favicons.dart';
import 'package:debug_browser/core/js_bridge.dart';
import 'package:debug_browser/core/providers.dart';
import 'package:debug_browser/core/tool_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HTTPS-only', () {
    bool up(String u, [Set<String> allowed = const {}]) => shouldUpgradeToHttps(Uri.parse(u), allowedHttpHosts: allowed);

    test('public http sites are upgraded', () {
      expect(up('http://example.com/a'), isTrue);
      expect(up('http://news.example.co.uk'), isTrue);
      expect(up('http://8.8.8.8/'), isTrue);
    });

    test('local, private-network and allowed hosts are not', () {
      for (final u in [
        'http://localhost:3000',
        'http://192.168.1.1/',
        'http://10.0.0.5:8080',
        'http://172.20.1.1',
        'http://127.0.0.1',
        'http://169.254.1.1',
        'http://printer.local',
        'http://router.lan',
        'http://intranet',
        'http://dev.home.arpa',
      ]) {
        expect(up(u), isFalse, reason: u);
      }
      expect(up('http://172.32.0.1'), isTrue, reason: 'outside 172.16/12');
      expect(up('http://legacy.test', {'legacy.test'}), isFalse);
      expect(up('https://example.com'), isFalse);
    });

    test('settings defaults and persistence', () {
      const d = BrowserSettings();
      expect(d.httpsOnly && d.autoHideToolbars && d.pullToRefresh, isTrue);
      final off = d.copyWith(httpsOnly: false, autoHideToolbars: false, pullToRefresh: false);
      final back = BrowserSettings.fromJson(jsonDecode(jsonEncode(off.toJson())));
      expect([back.httpsOnly, back.autoHideToolbars, back.pullToRefresh], [false, false, false]);
    });
  });

  group('site icons', () {
    test('learned icon, else /favicon.ico; none for non-web URLs', () {
      final known = {'news.test': 'https://cdn.news.test/icon-192.png'};
      expect(faviconUrlFor(known, 'https://www.news.test/a'), 'https://cdn.news.test/icon-192.png');
      expect(faviconUrlFor(known, 'http://other.test/x?y'), 'http://other.test/favicon.ico');
      expect(faviconUrlFor(known, newTabUrl), isNull);
      expect(faviconUrlFor(known, 'about:blank'), isNull);
    });

    test('store learns, ignores non-web icons, stays bounded', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(faviconsProvider.notifier);
      n.learn('https://www.a.test/page', 'https://a.test/i.png');
      n.learn('https://b.test/', 'data:image/png;base64,xx');
      expect(c.read(faviconsProvider), {'a.test': 'https://a.test/i.png'});
      for (var i = 0; i < 520; i++) {
        n.learn('https://s$i.test/', 'https://s$i.test/i.png');
      }
      expect(c.read(faviconsProvider).length, 500);
    });
  });

  test('UI signals from the page', () {
    final s = parseBridgeMessage(jsonEncode({'type': 'ui', 'data': {'kind': 'scroll', 'dir': 'down'}}));
    expect((s as UiEventMessage).data['dir'], 'down');
    expect(parseBridgeMessage(jsonEncode({'type': 'ui', 'data': {'kind': 'evil'}})), isNull);
    final f = parseBridgeMessage(jsonEncode({'type': 'favicon', 'data': {'href': 'https://a.test/f.ico'}}));
    expect((f as BrowserActionMessage).kind, 'favicon');
    expect(parseBridgeMessage(jsonEncode({'type': 'favicon', 'data': {'href': 'javascript:x'}})), isNull);
  });

  group('backup & restore', () {
    test('rejects other files and newer versions', () {
      expect(inspectBackup({'hello': 1}).$2, isNotNull);
      expect(inspectBackup('x').$2, isNotNull);
      expect(inspectBackup({'format': backupFormat, 'version': 99, 'data': {}}).$2, contains('newer version'));
      expect(inspectBackup({'format': backupFormat, 'version': 1}).$2, isNotNull);
    });

    test('round trip into a fresh install merges and never leaks the proxy password', () {
      final a = ProviderContainer();
      addTearDown(a.dispose);
      a.read(bookmarksProvider.notifier).addBookmark('Docs', 'https://docs.test/');
      a.read(historyProvider.notifier).record('https://h.test/', 'H');
      a.read(browserSettingsProvider.notifier).update((s) => s.copyWith(engine: SearchEngine.duckDuckGo));
      a.read(extensionsProvider.notifier).update((s) => s.copyWith(dark: true));
      a.read(userScriptsProvider.notifier).upsert(const UserScript(id: 'u1', name: 'S', js: 'x()'));
      a.read(networkMocksProvider.notifier).upsert(const MockRule(id: 'm1', pattern: '/api'));
      a.read(proxySettingsProvider.notifier).save(const ProxySettings(
          enabled: true, host: 'p.test', port: 8080, username: 'u', password: 'secret'));

      final backup = buildBackup(a.read, includeHistory: true, now: DateTime.utc(2026, 11, 20));
      final text = jsonEncode(backup);
      expect(text.contains('secret'), isFalse, reason: 'password never written');
      final (summary, err) = inspectBackup(jsonDecode(text));
      expect(err, isNull);
      expect(summary!.describe(), containsAll(['1 bookmark', '1 history entry', '1 user script', '1 API mock rule']));

      final b = ProviderContainer();
      addTearDown(b.dispose);
      b.read(bookmarksProvider.notifier).addBookmark('Mine', 'https://mine.test/');
      restoreBackup(b.read, jsonDecode(text) as Map);
      restoreBackup(b.read, jsonDecode(text) as Map); // twice: no duplicates
      expect(b.read(bookmarksProvider).map((x) => x['url']), ['https://mine.test/', 'https://docs.test/']);
      expect(b.read(historyProvider).length, 1);
      expect(b.read(browserSettingsProvider).engine, SearchEngine.duckDuckGo);
      expect(b.read(extensionsProvider).dark, isTrue);
      expect(b.read(userScriptsProvider).single.name, 'S');
      expect(b.read(networkMocksProvider).single.pattern, '/api');
      final proxy = b.read(proxySettingsProvider);
      expect(proxy.host, 'p.test');
      expect(proxy.enabled, isFalse, reason: 'restored proxy starts off');
      expect(proxy.password, isEmpty);
    });

    test('history is optional', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(historyProvider.notifier).record('https://h.test/', 'H');
      expect((buildBackup(c.read)['data'] as Map).containsKey('history'), isFalse);
    });
  });
}
