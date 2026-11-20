import 'package:debug_browser/core/providers.dart';
import 'package:debug_browser/core/tabs_provider.dart';
import 'package:debug_browser/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClosedTab closed(String url, [int index = 0]) =>
      ClosedTab(url: url, title: url, index: index, closedAt: DateTime.utc(2026));

  group('recently closed tabs', () {
    test('newest first, de-duplicated by URL, capped', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(recentlyClosedProvider.notifier);
      n.push(closed('https://a.test'));
      n.push(closed('https://b.test'));
      n.push(closed('https://a.test', 3));
      expect(c.read(recentlyClosedProvider).map((t) => t.url), ['https://a.test', 'https://b.test']);
      expect(c.read(recentlyClosedProvider).first.index, 3);
      for (var i = 0; i < 40; i++) {
        n.push(closed('https://s$i.test'));
      }
      expect(c.read(recentlyClosedProvider).length, RecentlyClosedNotifier.max);
      expect(c.read(recentlyClosedProvider).first.url, 'https://s39.test');
    });

    test('pop takes the newest, or a chosen one; empty gives null', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(recentlyClosedProvider.notifier);
      expect(n.pop(), isNull);
      n.push(closed('https://a.test'));
      n.push(closed('https://b.test'));
      final a = c.read(recentlyClosedProvider).last;
      expect(n.pop(a)!.url, 'https://a.test');
      expect(n.pop()!.url, 'https://b.test');
      expect(c.read(recentlyClosedProvider), isEmpty);
      n.push(closed('https://c.test'));
      n.clear();
      expect(c.read(recentlyClosedProvider), isEmpty);
    });
  });

  group('appearance', () {
    test('theme follows the system by default; set and toggle', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(themeProvider), ThemeMode.system);
      final n = c.read(themeProvider.notifier);
      n.toggle(current: Brightness.dark);
      expect(c.read(themeProvider), ThemeMode.light);
      n.toggle();
      expect(c.read(themeProvider), ThemeMode.dark);
      n.set(ThemeMode.system);
      expect(c.read(themeProvider), ThemeMode.system);
    });

    test('accent colour accepts only offered colours', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(accentColorProvider), accentColors['Blue']);
      c.read(accentColorProvider.notifier).set(accentColors['Teal']!);
      expect(c.read(accentColorProvider), accentColors['Teal']);
      c.read(accentColorProvider.notifier).set(0xFF123456);
      expect(c.read(accentColorProvider), accentColors['Teal']);
    });

    test('themes build for every accent in both brightnesses', () {
      for (final v in accentColors.values) {
        for (final b in Brightness.values) {
          final t = AppTheme.build(b, seed: Color(v));
          expect(t.colorScheme.brightness, b);
          expect(t.useMaterial3, isTrue);
        }
      }
    });
  });
}
