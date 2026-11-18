import 'dart:convert';

import 'package:debug_browser/core/extensions.dart';
import 'package:debug_browser/core/js_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('site settings', () {
    test('siteKey normalises hosts and URLs', () {
      expect(siteKey('https://www.News.example.com/a?b'), 'news.example.com');
      expect(siteKey('example.com'), 'example.com');
    });

    test('per-site overrides beat global switches; empty overrides are dropped', () {
      var s = const ExtensionSettings(blocker: true, dark: true);
      expect(s.blockerOn('https://site.test'), isTrue);
      s = s.withSite('https://www.site.test/x', (o) => const SiteOverride(blocker: false, textZoom: 130));
      expect(s.blockerOn('https://site.test/page'), isFalse);
      expect(s.textZoom('https://site.test'), 130);
      expect(s.blockerOn('https://other.test'), isTrue);
      s = s.withSite('site.test', (_) => const SiteOverride(textZoom: 100));
      expect(s.sites, isEmpty, reason: 'override equal to defaults is removed');
    });

    test('YouTube is always exempt from blocking, whatever the settings say', () {
      var s = const ExtensionSettings(blocker: true);
      expect(s.blockerOn('https://m.youtube.com/watch?v=1'), isFalse);
      expect(s.blockerOn('https://youtu.be/x'), isFalse);
      s = s.withSite('youtube.com', (_) => const SiteOverride(blocker: true));
      expect(s.blockerOn('https://www.youtube.com/'), isFalse);
      final cfg = extensionConfig(s);
      expect((cfg['sites'] as Map)['youtube.com']['blocker'], isFalse, reason: 'forced off in the injected config');
      // Not a look-alike host.
      expect(isBlockerExempt('notyoutube.com'), isFalse);
    });

    test('settings JSON round-trip', () {
      final s = const ExtensionSettings(blocker: false, cosmetic: false, dark: true, cookies: true)
          .withSite('a.test', (_) => const SiteOverride(dark: false, textZoom: 150));
      final back = ExtensionSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.toJson(), s.toJson());
      expect(ExtensionSettings.fromJson(null).blocker, isTrue, reason: 'blocker on by default');
    });
  });

  group('user scripts', () {
    test('glob matching', () {
      const s = UserScript(id: '1', name: 'x', matches: ['https://*.example.com/*', 'http://localhost*']);
      expect(userScriptMatches(s, 'https://shop.example.com/cart'), isTrue);
      expect(userScriptMatches(s, 'http://localhost:3000/'), isTrue);
      expect(userScriptMatches(s, 'https://example.org/'), isFalse);
      expect(userScriptMatches(s, 'https://evil.com/?x=.example.com/'), isFalse);
    });

    test('builder keeps code verbatim and escapes metadata', () {
      const s = UserScript(id: '1', name: 'Has "quotes" and __BODY__', js: 'var a = "__META__";', css: 'p{}');
      final js = buildUserScript(s);
      expect(js, contains('var a = "__META__";'), reason: 'body untouched');
      expect(js, contains(r'"name":"Has \"quotes\" and __BODY__"'), reason: 'metadata JSON-encoded');
      expect('__BODY__'.allMatches(js).length, 1, reason: 'only the name contains the token');
    });

    test('disabled or empty scripts are not injected', () {
      final scripts = buildStartScripts(const ExtensionSettings(), const [
        UserScript(id: 'a', name: 'off', js: 'x()', enabled: false),
        UserScript(id: 'b', name: 'empty'),
        UserScript(id: 'c', name: 'on', js: 'y()'),
      ]);
      expect(scripts.length, 2, reason: 'core + one user script');
    });

    test('JSON round-trip', () {
      const s = UserScript(id: 'x', name: 'n', matches: ['*'], js: 'a', css: 'b', enabled: false, runAt: 'start');
      expect(UserScript.fromJson(s.toJson())!.toJson(), s.toJson());
      expect(UserScript.fromJson({'name': 'n', 'matches': <String>[]})!.matches, ['*']);
    });
  });

  test('blocked messages from the page', () {
    final m = parseBridgeMessage(jsonEncode({
      'type': 'blocked',
      'data': {'n': 3, 'domains': {'doubleclick.net': 2, 'criteo.com': 1, 'bad': 'x'}},
    })) as BlockedMessage;
    expect(m.count, 3);
    expect(m.domains, {'doubleclick.net': 2, 'criteo.com': 1});
    expect(parseBridgeMessage(jsonEncode({'type': 'blocked', 'data': {'n': 'lots'}})), isNull);
  });
}
