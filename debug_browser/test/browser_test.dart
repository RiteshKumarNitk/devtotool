import 'dart:convert';

import 'package:debug_browser/core/browser_settings.dart';
import 'package:debug_browser/core/js_bridge.dart';
import 'package:debug_browser/core/tabs_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('search engine', () {
    test('default homepage is Google', () {
      expect(const BrowserSettings().homepage, 'https://www.google.com');
    });

    test('custom homepage overrides engine home', () {
      expect(const BrowserSettings(customHomepage: ' https://x.dev ').homepage, 'https://x.dev');
    });

    test('address bar searches with the chosen engine', () {
      final uri = normaliseUrlInput('flutter tabs', search: SearchEngine.duckDuckGo.searchUri);
      expect(uri.toString(), 'https://duckduckgo.com/?q=flutter+tabs');
      // URLs are still opened directly.
      expect(normaliseUrlInput('example.com', search: SearchEngine.bing.searchUri).toString(), 'https://example.com');
    });

    test('settings JSON round-trip; desktop mode is not persisted', () {
      const s = BrowserSettings(engine: SearchEngine.brave, customHomepage: 'https://a.b', showDebugBubble: false, desktopMode: true);
      final back = BrowserSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.engine, SearchEngine.brave);
      expect(back.customHomepage, 'https://a.b');
      expect(back.showDebugBubble, isFalse);
      expect(back.desktopMode, isFalse);
      expect(BrowserSettings.fromJson('junk').engine, SearchEngine.google);
    });

    test('exit confirmation is on by default and persists when turned off', () {
      expect(const BrowserSettings().confirmExit, isTrue);
      expect(BrowserSettings.fromJson({}).confirmExit, isTrue);
      final off = const BrowserSettings().copyWith(confirmExit: false);
      expect(BrowserSettings.fromJson(jsonDecode(jsonEncode(off.toJson()))).confirmExit, isFalse);
    });
  });

  group('page-initiated tab actions', () {
    BridgeMessage? msg(String type, Object href) =>
        parseBridgeMessage(jsonEncode({'type': type, 'data': {'href': href}}));

    test('open_tab accepts web links', () {
      final m = msg('open_tab', 'https://example.com/a') as BrowserActionMessage;
      expect(m.kind, 'open_tab');
      expect(m.href, 'https://example.com/a');
    });

    test('rejects non-web schemes so pages cannot open javascript:/file: tabs', () {
      expect(msg('open_tab', 'javascript:alert(1)'), isNull);
      expect(msg('link_menu', 'file:///etc/passwd'), isNull);
      expect(msg('open_tab', 42), isNull);
    });
  });

  test('intent:// links fall back to browser_fallback_url', () {
    const url = 'intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fapp;end';
    expect(intentFallbackUrl(url), 'https://example.com/app');
    expect(intentFallbackUrl('intent://x#Intent;S.browser_fallback_url=javascript%3Aalert(1);end'), isNull);
    expect(intentFallbackUrl('intent://x#Intent;end'), isNull);
  });

  test('BrowserTab display helpers', () {
    const t = BrowserTab(id: '1', url: 'https://www.example.com/x');
    expect(t.isSecure, isTrue);
    expect(t.displayTitle, 'www.example.com');
    expect(const BrowserTab(id: '2', url: 'http://a.b', title: 'Hi').displayTitle, 'Hi');
    expect(const BrowserTab(id: '3', url: 'http://a.b').isSecure, isFalse);
  });
}
