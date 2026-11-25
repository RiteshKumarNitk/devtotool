import 'dart:convert';

import 'package:debug_browser/core/browser_settings.dart';
import 'package:debug_browser/core/page_audit.dart';
import 'package:debug_browser/core/page_tools.dart';
import 'package:debug_browser/core/read_aloud.dart';
import 'package:debug_browser/core/search_suggest.dart';
import 'package:debug_browser/core/tabs_provider.dart';
import 'package:debug_browser/features/network/replay_page.dart';
import 'package:debug_browser/features/tools/source_viewer_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Back button order', () {
    BackStep d({bool ntp = false, bool history = false, bool opener = false, bool ntpOn = true}) =>
        decideBack(onNewTabPage: ntp, hasHistory: history, hasOpener: opener, newTabPageEnabled: ntpOn);

    test('history first, then opener tab, then New Tab page, then exit prompt', () {
      expect(d(history: true, opener: true), BackStep.history);
      expect(d(opener: true), BackStep.opener);
      expect(d(), BackStep.newTab);
      expect(d(ntp: true), BackStep.exit, reason: 'the New Tab page is the end of the chain');
      expect(d(ntp: true, history: true), BackStep.exit);
    });

    test('with the New Tab page turned off, the start of a tab asks to exit', () {
      expect(d(ntpOn: false), BackStep.exit);
    });

    test('toolbar Back is enabled everywhere except the New Tab page', () {
      expect(const BrowserTab(id: '1', url: 'https://a.test').canNavigateBack, isTrue);
      expect(const BrowserTab(id: '2', url: newTabUrl).canNavigateBack, isFalse);
    });
  });

  test('new settings persist', () {
    const s = BrowserSettings(clearOnExit: true, lockPrivateTabs: true, searchSuggestions: false, translateTo: 'hi');
    final back = BrowserSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect([back.clearOnExit, back.lockPrivateTabs, back.searchSuggestions, back.translateTo], [true, true, false, 'hi']);
    const d = BrowserSettings();
    expect([d.clearOnExit, d.lockPrivateTabs, d.searchSuggestions], [false, false, true]);
  });

  group('search suggestions', () {
    test('parses OpenSearch and DuckDuckGo formats', () {
      expect(parseSuggestions('["flut",["flutter","flutter dev","flutter tts"]]'), ['flutter', 'flutter dev', 'flutter tts']);
      expect(parseSuggestions('[{"phrase":"dart lang"},{"phrase":"dart pad"}]'), ['dart lang', 'dart pad']);
      expect(parseSuggestions('not json'), isEmpty);
      expect(parseSuggestions('["q",["a","b","c","d","e","f","g"]]').length, 5);
    });

    test('endpoints per engine', () {
      expect(suggestUri(SearchEngine.google, 'a b').toString(), contains('suggestqueries.google.com'));
      expect(suggestUri(SearchEngine.duckDuckGo, 'x').host, 'duckduckgo.com');
      expect(suggestUri(SearchEngine.bing, 'x').queryParameters['query'], 'x');
    });
  });

  test('read aloud splits long text at sentence boundaries', () {
    final long = List.generate(60, (i) => 'Sentence number $i is here.').join(' ');
    final chunks = chunkForSpeech('Title\n$long', max: 300);
    expect(chunks.first, 'Title');
    expect(chunks.every((c) => c.length <= 301), isTrue);
    expect(chunks.skip(1).every((c) => c.endsWith('.')), isTrue, reason: 'cut after a full stop');
    expect(chunks.join(' ').replaceAll(RegExp(r'\s+'), ' '), 'Title $long');
  });

  test('translate URL', () {
    final u = translateUri('https://site.test/a?b=1', 'hi');
    expect(u.host, 'translate.google.com');
    expect(u.queryParameters, {'sl': 'auto', 'tl': 'hi', 'u': 'https://site.test/a?b=1'});
    expect(effectiveTranslateLang(const BrowserSettings(translateTo: 'ta')), 'ta');
    expect(jsResultString('"a\\nb"'), 'a\nb');
    expect(jsResultString('null'), '');
  });

  group('page audit scoring', () {
    final goodSeo = {
      'https': true, 'title': 'A well chosen page title', 'description': 'Something', 'h1Count': 1,
      'viewport': 'width=device-width', 'lang': 'en', 'canonical': true, 'noindex': false, 'ogTags': 3,
      'structuredData': 1, 'images': 4, 'imagesMissingAlt': 0, 'genericLinks': 0, 'mixedContent': 0,
      'doctype': true, 'charset': true, 'domNodes': 800, 'fontSizeSmall': 0.05,
    };
    final goodVitals = {
      'vitals': {'lcp': 1200, 'cls': 0.01, 'fcp': 900, 'ttfb': 200},
      'resources': {'totalBytes': 600 * 1024, 'count': 20},
    };

    test('a healthy page scores 100 everywhere', () {
      final r = scorePage(seo: goodSeo, vitals: goodVitals, a11y: const {'counts': {}});
      expect({for (final c in r) c.name: c.score},
          {'Performance': 100, 'Accessibility': 100, 'Best practices': 100, 'SEO': 100});
    });

    test('problems lower the right category', () {
      final r = scorePage(
        seo: {...goodSeo, 'https': false, 'noindex': true, 'title': ''},
        vitals: {'vitals': {'lcp': 5000, 'cls': 0.3, 'fcp': 900, 'ttfb': 200}, 'resources': goodVitals['resources']},
        a11y: const {'counts': {'critical': 2, 'serious': 1}},
        consoleErrors: 3,
      );
      final s = {for (final c in r) c.name: c.score};
      expect(s['Performance']!, lessThan(60));
      expect(s['Accessibility'], 100 - 16 - 4);
      expect(s['Best practices'], 100 - 30 - 15);
      expect(s['SEO'], 100 - 20 - 5 - 25);
    });

    test('metricScore is linear between good and poor', () {
      expect(metricScore(100, 200, 400), 100);
      expect(metricScore(300, 200, 400), 50);
      expect(metricScore(500, 200, 400), 0);
      expect(metricScore(null, 1, 2), 100);
    });
  });

  test('view source: formats and highlights HTML', () {
    final f = formatHtml('<html><head><meta charset="utf-8"><title>T</title></head><body><p>Hi</p><br></body></html>');
    final lines = f.trim().split('\n');
    expect(lines.first, '<html>');
    expect(lines, contains('    <meta charset="utf-8">'));
    expect(lines, contains('      T'));
    expect(lines.last, '</html>');
    final spans = highlightHtmlLine('<a href="x">link</a>', dark: false);
    expect(spans.map((s) => s.text).join(), '<a href="x">link</a>');
    expect(spans.length, greaterThan(3));
  });

  test('edit & resend: header lines', () {
    expect(parseHeaderLines('Accept: application/json\nX-Token:  abc:def\n\nbad line\n: novalue'),
        {'Accept': 'application/json', 'X-Token': 'abc:def'});
  });
}
