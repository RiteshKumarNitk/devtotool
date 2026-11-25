import 'dart:convert';

import 'package:debug_browser/core/browser_settings.dart';
import 'package:debug_browser/core/home_stats.dart';
import 'package:debug_browser/core/tabs_provider.dart';
import 'package:debug_browser/features/newtab/new_tab_page.dart';
import 'package:debug_browser/features/onboarding/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> visit(String url, [String title = '']) => {'url': url, 'title': title, 'time': '2026-11-20T10:00:00'};

void main() {
  group('top sites', () {
    test('bookmarks first, then most visited; one tile per site; internal pages skipped', () {
      final history = [
        visit('https://news.example.com/a', 'News'),
        visit('https://news.example.com/b', 'News'),
        visit('https://www.news.example.com/c', 'News'),
        visit('https://shop.test/x', 'Shop'),
        visit('https://shop.test/y', 'Shop'),
        visit('https://once.test/', 'Once'),
        visit(newTabUrl),
        visit('about:blank'),
      ];
      final bookmarks = [
        {'title': 'Docs', 'url': 'https://docs.test/page'},
        {'title': 'Shop bookmark', 'url': 'https://shop.test/z'},
      ];
      final sites = topSites(history, bookmarks);
      expect(sites.map((s) => s.host).toList(), ['shop.test', 'docs.test', 'news.example.com', 'once.test']);
      expect(sites.first.bookmarked, isTrue);
      expect(sites[2].url, 'https://www.news.example.com/', reason: 'tiles open the root of the last-visited address');
    });

    test('respects the limit', () {
      final history = [for (var i = 0; i < 20; i++) visit('https://s$i.test/')];
      expect(topSites(history, const [], limit: 8).length, 8);
    });
  });

  test('stat formatting', () {
    expect(groupDigits(1234567), '1,234,567');
    expect(groupDigits(12), '12');
    expect(formatBytesShort(30 * 1024 * 1000), '29.3 MB');
    expect(formatDurationShort(const Duration(seconds: 45)), '45s');
    expect(formatDurationShort(const Duration(minutes: 125)), '2h 5m');
    const s = PrivacyStats(blocked: 1000);
    expect(s.bytesSaved, 1000 * bytesSavedPerBlock);
    expect(s.timeSaved, const Duration(seconds: 50));
  });

  test('New Tab state on tabs', () {
    const ntp = BrowserTab(id: '1', url: newTabUrl);
    expect(ntp.isNewTab, isTrue);
    expect(ntp.displayTitle, 'New tab');
    expect(ntp.isSecure, isFalse);
    expect(ntp.canNavigateBack, isFalse, reason: 'the New Tab page is the end of the Back chain');
    expect(ntp.copyWith(lastWebUrl: () => 'https://a.test').canNavigateBack, isFalse,
        reason: 'Back on the New Tab page asks to exit, even over an earlier page');
    const fromNtp = BrowserTab(id: '2', url: 'https://a.test', ntpBehind: true);
    expect(fromNtp.canNavigateBack, isTrue, reason: 'back returns to the New Tab page');
    expect(const BrowserTab(id: '3', url: newTabUrl, isPrivate: true).displayTitle, 'Private tab');
  });

  test('settings: New Tab options persist', () {
    const s = BrowserSettings(newTabTheme: NewTabTheme.ocean, showStats: false, showTopSites: false, newTabPage: false);
    final back = BrowserSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.newTabTheme, NewTabTheme.ocean);
    expect(back.showStats, isFalse);
    expect(back.showTopSites, isFalse);
    expect(back.newTabPage, isFalse);
    expect(BrowserSettings.fromJson({}).newTabTheme, NewTabTheme.aurora);
  });

  testWidgets('New Tab page shows greeting, stats, search and customize', (t) async {
    var searched = 0;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: NewTabPage(onSearchTap: () => searched++))),
    ));
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('Privacy stats'), findsOneWidget);
    expect(find.textContaining('Search with Google'), findsOneWidget);
    await t.tap(find.textContaining('Search with Google'));
    expect(searched, 1);
    await t.tap(find.text('Customize'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Customize New Tab'), findsOneWidget);
  });

  testWidgets('private New Tab explains private browsing', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: NewTabPage(onSearchTap: () {}, isPrivate: true))),
    ));
    expect(find.text('Private tab'), findsOneWidget);
    expect(find.text('Privacy stats'), findsNothing);
  });

  testWidgets('onboarding: next through all steps, then the app', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FirstRunGate(child: Text('APP'))),
    ));
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('Welcome to'), findsOneWidget);
    for (final title in ['Browse without', 'Choose your', 'Make it your']) {
      await t.tap(find.text('Next'));
      await t.pump(); // start the page slide
      await t.pump(const Duration(milliseconds: 600));
      expect(find.textContaining(title), findsOneWidget);
    }
    await t.tap(find.text('Start browsing'));
    await t.pumpAndSettle();
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('onboarding: skip goes straight to the app', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FirstRunGate(child: Text('APP'))),
    ));
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.text('APP'), findsOneWidget);
  });
}
