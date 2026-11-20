import 'dart:convert';

import 'package:debug_browser/core/backup.dart';
import 'package:debug_browser/core/extensions.dart';
import 'package:debug_browser/core/highlights.dart';
import 'package:debug_browser/core/page_tools.dart';
import 'package:debug_browser/core/providers.dart';
import 'package:debug_browser/core/search_shortcuts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('search shortcuts', () {
    test('keyword + query uses the template, encoded', () {
      final m = matchShortcut('w taj mahal', defaultSearchShortcuts)!;
      expect(m.$1.name, 'Wikipedia');
      expect(m.$1.uriFor(m.$2).toString(), 'https://en.wikipedia.org/wiki/Special:Search?search=taj+mahal');
      expect(matchShortcut('YT  cricket score', defaultSearchShortcuts)!.$2, 'cricket score');
    });

    test('no match for plain searches, bare keywords or unknown keywords', () {
      expect(matchShortcut('weather today', defaultSearchShortcuts), isNull);
      expect(matchShortcut('w', defaultSearchShortcuts), isNull);
      expect(matchShortcut('w   ', defaultSearchShortcuts), isNull);
      expect(matchShortcut('zz foo', defaultSearchShortcuts), isNull);
    });

    test('invalid shortcuts are rejected', () {
      expect(SearchShortcut.fromJson({'keyword': 'two words', 'template': 'https://x/?q=%s'}), isNull);
      expect(SearchShortcut.fromJson({'keyword': 'x', 'template': 'https://x/?q='}), isNull, reason: 'needs %s');
      expect(SearchShortcut.fromJson({'keyword': 'x', 'template': 'javascript:%s'}), isNull);
      expect(SearchShortcut.fromJson({'keyword': 'X', 'name': 'Ex', 'template': 'https://x/?q=%s'})!.keyword, 'x');
    });

    test('store: replace by keyword, remove, reset', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(searchShortcutsProvider.notifier);
      n.save(const SearchShortcut('w', 'Wiki Hindi', 'https://hi.wikipedia.org/w/index.php?search=%s'));
      expect(c.read(searchShortcutsProvider).where((s) => s.keyword == 'w').single.name, 'Wiki Hindi');
      n.remove('w');
      expect(c.read(searchShortcutsProvider).any((s) => s.keyword == 'w'), isFalse);
      n.reset();
      expect(c.read(searchShortcutsProvider).length, defaultSearchShortcuts.length);
    });
  });

  group('highlights', () {
    Highlight h(String id, String url) => Highlight(id: id, url: url, title: 'T', text: 'quick brown', prefix: 'The ', suffix: ' fox', created: DateTime.utc(2026));

    test('per page, ignoring #fragment; JSON for the page script', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(highlightsProvider.notifier);
      n.add(h('a', 'https://s.test/p#top'));
      n.add(h('b', 'https://s.test/other'));
      expect(n.forPage('https://s.test/p').map((x) => x.id), ['a']);
      final j = jsonDecode(n.pageJson('https://s.test/p#section')) as List;
      expect(j.single, {'id': 'a', 'text': 'quick brown', 'prefix': 'The ', 'suffix': ' fox', 'color': 'yellow'});
      n.update('a', (x) => x.copyWith(note: 'remember'));
      expect(c.read(highlightsProvider).firstWhere((x) => x.id == 'a').note, 'remember');
      n.remove('a');
      expect(n.forPage('https://s.test/p'), isEmpty);
      expect(n.importAll([h('b', 'x'), h('c', 'y')]), 1, reason: 'existing ids skipped');
    });
  });

  test('bookmark folders: add, move, rename, delete keeps bookmarks', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(bookmarksProvider.notifier);
    n.addBookmark('A', 'https://a.test', folder: 'Work');
    n.addBookmark('B', 'https://b.test');
    expect(n.folders, ['Work']);
    n.moveToFolder('https://b.test', 'Study');
    expect(n.folders, ['Study', 'Work']);
    n.renameFolder('Work', 'Office');
    expect(c.read(bookmarksProvider).firstWhere((b) => b['url'] == 'https://a.test')['folder'], 'Office');
    n.deleteFolder('Office');
    expect(c.read(bookmarksProvider).firstWhere((b) => b['url'] == 'https://a.test').containsKey('folder'), isFalse);
    expect(c.read(bookmarksProvider).length, 2, reason: 'deleting a folder never deletes bookmarks');
    n.moveToFolder('https://b.test', null);
    expect(n.folders, isEmpty);
  });

  test('picture-in-picture is refused on YouTube (policy)', () {
    for (final u in ['https://www.youtube.com/watch?v=x', 'https://m.youtube.com/', 'https://youtu.be/x', 'https://music.youtube.com/']) {
      expect(pipBlockedHost(u), isTrue, reason: u);
    }
    expect(pipBlockedHost('https://vimeo.com/1'), isFalse);
    expect(pipBlockedHost('https://notyoutube.com/'), isFalse);
  });

  test('per-site JavaScript and hidden elements; new switches persist', () {
    var s = const ExtensionSettings(readableText: true, dataSaver: true);
    expect(s.jsOn('https://a.test'), isTrue);
    s = s.withSite('a.test', (o) => o.copyWith(js: () => false, hidden: ['#ad', '.promo']));
    expect(s.jsOn('https://www.a.test/x'), isFalse);
    expect(s.hiddenOn('https://a.test'), ['#ad', '.promo']);
    final back = ExtensionSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.jsOn('https://a.test'), isFalse);
    expect(back.hiddenOn('https://a.test'), ['#ad', '.promo']);
    expect([back.readableText, back.dataSaver], [true, true]);
    expect((extensionConfig(s)['sites'] as Map)['a.test']['hidden'], ['#ad', '.promo']);
    // Removing everything clears the site entry.
    s = s.withSite('a.test', (o) => o.copyWith(js: () => null, hidden: const []));
    expect(s.sites, isEmpty);
  });

  test('backup carries highlights and search shortcuts', () {
    final a = ProviderContainer();
    addTearDown(a.dispose);
    a.read(highlightsProvider.notifier).add(Highlight(id: 'h1', url: 'https://s.test', title: 'S', text: 'x', created: DateTime.utc(2026)));
    a.read(searchShortcutsProvider.notifier).save(const SearchShortcut('np', 'npm', 'https://www.npmjs.com/search?q=%s'));
    final text = jsonEncode(buildBackup(a.read));
    final (summary, _) = inspectBackup(jsonDecode(text));
    expect(summary!.describe(), contains('1 highlight'));
    final b = ProviderContainer();
    addTearDown(b.dispose);
    restoreBackup(b.read, jsonDecode(text) as Map);
    expect(b.read(highlightsProvider).single.id, 'h1');
    expect(b.read(searchShortcutsProvider).any((s) => s.keyword == 'np'), isTrue);
  });
}
