import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branding/logo_painter.dart';
import '../../core/browser_settings.dart';
import '../../core/home_stats.dart';
import '../../core/providers.dart';
import '../../core/tabs_provider.dart';
import '../../core/tool_providers.dart';
import 'aurora_background.dart';

/// Brave-style New Tab page: animated background, privacy stats, search and
/// top sites. Private tabs get a dedicated explanation page instead.
class NewTabPage extends ConsumerWidget {
  /// Focuses the real address bar (keeps suggestions in one place).
  final VoidCallback onSearchTap;
  final bool isPrivate;
  const NewTabPage({super.key, required this.onSearchTap, this.isPrivate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isPrivate) return _PrivateNewTab(onSearchTap: onSearchTap);
    final settings = ref.watch(browserSettingsProvider);
    final stats = ref.watch(privacyStatsProvider);
    final sites = topSites(ref.watch(historyProvider), ref.watch(bookmarksProvider));

    return AuroraBackground(
      theme: settings.newTabTheme,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, box) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 52),
              child: Column(
                children: [
                  _Entrance(delay: 0, child: _Greeting()),
                  if (settings.showStats) ...[
                    const SizedBox(height: 20),
                    _Entrance(delay: 80, child: _StatsCard(stats: stats)),
                  ],
                  const SizedBox(height: 20),
                  _Entrance(delay: 160, child: _SearchPill(engine: settings.engine, onTap: onSearchTap)),
                  if (settings.showTopSites && sites.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Entrance(delay: 240, child: _TopSitesGrid(sites: sites)),
                  ],
                  const SizedBox(height: 28),
                  _Entrance(
                    delay: 320,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      onPressed: () => showCustomizeSheet(context),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Customize'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Fades + slides children in, staggered.
class _Entrance extends StatelessWidget {
  final int delay;
  final Widget child;
  const _Entrance({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + delay),
      curve: Interval(delay / (450 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const _Glass({required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: child,
          ),
        ),
      );
}

class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greeting = h < 5
        ? 'Good night'
        : h < 12
            ? 'Good morning'
            : h < 17
                ? 'Good afternoon'
                : 'Good evening';
    return Row(
      children: [
        const SizedBox(width: 40, height: 40, child: CustomPaint(painter: LogoPainter())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              Text(MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final PrivacyStats stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    Widget stat(int value, String Function(int) fmt, String label, Color color) => Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(fmt(v.round()),
                      style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                ),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.2)),
              ],
            ),
          ),
        );

    return Semantics(
      label: '${stats.blocked} ads and trackers blocked',
      child: _Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.shield, color: Color(0xFF69F0AE), size: 18),
              SizedBox(width: 6),
              Text('Privacy stats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stat(stats.blocked, groupDigits, 'Ads & trackers\nblocked', const Color(0xFFFFAB40)),
                stat(stats.blocked, (n) => formatBytesShort(n * bytesSavedPerBlock), 'Data saved\n(estimated)',
                    const Color(0xFF69F0AE)),
                stat(stats.blocked, (n) => formatDurationShort(Duration(milliseconds: n * msSavedPerBlock)),
                    'Time saved\n(estimated)', const Color(0xFF80D8FF)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final SearchEngine engine;
  final VoidCallback onTap;
  const _SearchPill({required this.engine, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Search or type web address',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(27),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              const Icon(Icons.search, color: Color(0xFF5F6368)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Search with ${engine.label} or type a URL',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF5F6368), fontSize: 16)),
              ),
            ]),
          ),
        ),
      );
}

class _TopSitesGrid extends ConsumerWidget {
  final List<TopSite> sites;
  const _TopSitesGrid({required this.sites});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, box) {
      const perRow = 4;
      final w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (final s in sites)
            SizedBox(
              width: w,
              child: _SiteTile(
                site: s,
                onTap: () => ref.read(tabsProvider.notifier).loadUri(Uri.parse(s.url)),
                onLongPress: () => ref.read(tabsProvider.notifier).newTab(url: s.url),
              ),
            ),
        ],
      );
    });
  }
}

class _SiteTile extends StatelessWidget {
  final TopSite site;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SiteTile({required this.site, required this.onTap, required this.onLongPress});

  static const _tileColors = [
    Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFEF5350), Color(0xFFAB47BC),
    Color(0xFFFFA726), Color(0xFF42A5F5), Color(0xFF66BB6A), Color(0xFF8D6E63),
  ];

  @override
  Widget build(BuildContext context) {
    final letter = site.host.isEmpty ? '?' : site.host[0].toUpperCase();
    final color = _tileColors[site.host.hashCode.abs() % _tileColors.length];
    final fallback = Container(
      alignment: Alignment.center,
      color: color,
      child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
    );
    return Semantics(
      button: true,
      label: site.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _Glass(
              padding: const EdgeInsets.all(10),
              radius: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Image.network(
                    'https://${site.host}/favicon.ico',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => fallback,
                    frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (site.bookmarked) const Icon(Icons.star, size: 11, color: Colors.amber),
              Flexible(
                child: Text(site.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _PrivateNewTab extends ConsumerWidget {
  final VoidCallback onSearchTap;
  const _PrivateNewTab({required this.onSearchTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const body = TextStyle(color: Colors.white70, fontSize: 14, height: 1.5);
    final engine = ref.watch(browserSettingsProvider).engine;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B1036), Color(0xFF0E0A1F)],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.privacy_tip, color: Color(0xFFB39DDB), size: 48),
            const SizedBox(height: 16),
            const Text('Private tab',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text(
              'Pages you open here are not saved to history, and their cookies and site data '
              'are deleted when you close your last private tab.',
              style: body,
            ),
            const SizedBox(height: 16),
            _bullet(Icons.check_circle_outline, 'Separate cookies: you are signed out of everything here'),
            _bullet(Icons.check_circle_outline, 'Ads and trackers are blocked, as in normal tabs'),
            _bullet(Icons.info_outline, 'Downloads and bookmarks you create are kept'),
            _bullet(Icons.info_outline, 'Websites, your employer or internet provider can still see your activity'),
            const SizedBox(height: 28),
            _SearchPill(engine: engine, onTap: onSearchTap),
          ],
        ),
      ),
    );
  }

  static Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: const Color(0xFFB39DDB)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14))),
        ]),
      );
}

/// Theme / stats / top-sites options for the New Tab page.
void showCustomizeSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheet) => Consumer(builder: (sheet, ref, _) {
      final s = ref.watch(browserSettingsProvider);
      final n = ref.read(browserSettingsProvider.notifier);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('Customize New Tab', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in NewTabTheme.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => n.update((x) => x.copyWith(newTabTheme: t)),
                          child: Column(children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: t == s.newTabTheme ? Theme.of(sheet).colorScheme.primary : Colors.transparent,
                                  width: 3,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: newTabPalettes[t]!.sublist(1),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(t.label, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Show privacy stats'),
                value: s.showStats,
                onChanged: (v) => n.update((x) => x.copyWith(showStats: v)),
              ),
              SwitchListTile(
                title: const Text('Show top sites'),
                subtitle: const Text('Bookmarks and your most-visited sites'),
                value: s.showTopSites,
                onChanged: (v) => n.update((x) => x.copyWith(showTopSites: v)),
              ),
              SwitchListTile(
                title: const Text('Use New Tab page as home'),
                subtitle: Text(s.newTabPage ? 'Home and new tabs open this page' : 'Home opens ${s.engine.label}'),
                value: s.newTabPage,
                onChanged: (v) => n.update((x) => x.copyWith(newTabPage: v)),
              ),
              ListTile(
                title: const Text('Reset privacy stats'),
                leading: const Icon(Icons.restart_alt),
                onTap: () => ref.read(privacyStatsProvider.notifier).reset(),
              ),
            ],
          ),
        ),
      );
    }),
  );
}
