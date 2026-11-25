import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'extensions.dart' show siteKey;
import 'providers.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

/// Site -> icon URL, learned from pages as they load (never in private tabs).
class FaviconsNotifier extends Notifier<Map<String, String>> {
  static const _key = 'favicons';
  static const _max = 500;

  @override
  Map<String, String> build() {
    final saved = _box()?.get(_key);
    if (saved is! Map) return const {};
    return saved.map((k, v) => MapEntry('$k', '$v'));
  }

  void learn(String pageUrl, String iconUrl) {
    final host = siteKey(pageUrl);
    if (host.isEmpty || !(iconUrl.startsWith('https://') || iconUrl.startsWith('http://'))) return;
    if (state[host] == iconUrl) return;
    final next = Map<String, String>.from(state)..[host] = iconUrl;
    // Keep the store bounded (oldest insertions first out).
    while (next.length > _max) {
      next.remove(next.keys.first);
    }
    state = next;
    _box()?.put(_key, state);
  }

  void clear() {
    state = const {};
    _box()?.delete(_key);
  }
}

final faviconsProvider = NotifierProvider<FaviconsNotifier, Map<String, String>>(FaviconsNotifier.new);

/// Icon URL to try for [url]: the learned one, else the site's /favicon.ico.
String? faviconUrlFor(Map<String, String> known, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
  return known[siteKey(url)] ?? '${uri.scheme}://${uri.host}/favicon.ico';
}

/// A site's icon with a coloured-letter fallback (while loading, on error,
/// or for non-web URLs).
class SiteIcon extends ConsumerWidget {
  final String url;
  final double size;
  final double radius;
  const SiteIcon({super.key, required this.url, this.size = 24, this.radius = 6});

  static const _colors = [
    Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFEF5350), Color(0xFFAB47BC),
    Color(0xFFFFA726), Color(0xFF42A5F5), Color(0xFF66BB6A), Color(0xFF8D6E63),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = siteKey(url);
    final letter = host.isEmpty ? '?' : host[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colors[host.hashCode.abs() % _colors.length],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(letter,
          style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w700, height: 1)),
    );
    final src = faviconUrlFor(ref.watch(faviconsProvider), url);
    if (src == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        src,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Decode small: icons can be large PNGs.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => fallback,
        frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
      ),
    );
  }
}
