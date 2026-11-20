import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'extensions.dart';
import 'providers.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

// ------------------------------------------------------------------ stats

/// Estimates per blocked request, in the spirit of Brave's counters: the
/// average ad/tracker response is tens of KB and costs tens of ms.
const int bytesSavedPerBlock = 30 * 1024;
const int msSavedPerBlock = 50;

@immutable
class PrivacyStats {
  final int blocked;
  final DateTime? since;
  const PrivacyStats({this.blocked = 0, this.since});

  int get bytesSaved => blocked * bytesSavedPerBlock;
  Duration get timeSaved => Duration(milliseconds: blocked * msSavedPerBlock);
}

/// Lifetime totals (persisted, throttled writes).
class PrivacyStatsNotifier extends Notifier<PrivacyStats> {
  static const _key = 'privacyStats';
  Timer? _save;

  @override
  PrivacyStats build() {
    ref.onDispose(() {
      _save?.cancel();
      _persist();
    });
    final j = _box()?.get(_key);
    if (j is Map) {
      return PrivacyStats(
        blocked: (j['blocked'] as num?)?.toInt() ?? 0,
        since: DateTime.tryParse('${j['since']}'),
      );
    }
    return PrivacyStats(since: DateTime.now());
  }

  void add(int n) {
    if (n <= 0) return;
    state = PrivacyStats(blocked: state.blocked + n, since: state.since ?? DateTime.now());
    _save ??= Timer(const Duration(seconds: 3), () {
      _save = null;
      _persist();
    });
  }

  void reset() {
    state = PrivacyStats(since: DateTime.now());
    _persist();
  }

  void _persist() => _box()?.put(_key, {'blocked': state.blocked, 'since': state.since?.toIso8601String()});
}

final privacyStatsProvider = NotifierProvider<PrivacyStatsNotifier, PrivacyStats>(PrivacyStatsNotifier.new);

String formatBytesShort(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatDurationShort(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d ${d.inHours % 24}h';
}

/// "12,345" style grouping without intl formatting overhead.
String groupDigits(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// -------------------------------------------------------------- onboarding

class OnboardedNotifier extends Notifier<bool> {
  static const _key = 'onboarded';
  @override
  bool build() => _box()?.get(_key) == true;
  void complete() {
    state = true;
    _box()?.put(_key, true);
  }
}

final onboardedProvider = NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

// --------------------------------------------------------------- top sites

@immutable
class TopSite {
  final String title;
  final String url;
  final bool bookmarked;
  const TopSite(this.title, this.url, {this.bookmarked = false});
  String get host => siteKey(url);
}

/// Bookmarks first (most recent first), then the most-visited sites from
/// history, one tile per site, skipping internal pages.
List<TopSite> topSites(List<Map<String, String>> history, List<Map<String, String>> bookmarks, {int limit = 8}) {
  final out = <TopSite>[];
  final seen = <String>{};
  bool usable(String url) => url.startsWith('http://') || url.startsWith('https://');

  for (final b in bookmarks.reversed) {
    final url = b['url'] ?? '';
    if (!usable(url) || !seen.add(siteKey(url))) continue;
    out.add(TopSite((b['title'] ?? '').isEmpty ? siteKey(url) : b['title']!, url, bookmarked: true));
    if (out.length >= (limit / 2).ceil()) break;
  }

  final counts = <String, int>{};
  final latest = <String, Map<String, String>>{};
  for (final h in history) {
    final url = h['url'] ?? '';
    if (!usable(url)) continue;
    final key = siteKey(url);
    counts[key] = (counts[key] ?? 0) + 1;
    latest[key] = h;
  }
  final ranked = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  for (final key in ranked) {
    if (out.length >= limit) break;
    if (!seen.add(key)) continue;
    final h = latest[key]!;
    final origin = Uri.parse(h['url']!).replace(path: '/', query: null, fragment: null).toString();
    final title = (h['title'] ?? '').trim();
    out.add(TopSite(title.isEmpty || title.length > 24 ? key : title, origin));
  }
  return out;
}

// ------------------------------------------- links from other apps, default

/// Android integration: links opened from other apps, default-browser role.
abstract final class SystemBrowser {
  static const _channel = MethodChannel('com.innovatextechnology.debugbrowser/links');

  /// Link the app was launched with (once), e.g. tapped in WhatsApp.
  static Future<String?> takeInitialUrl() async {
    try {
      return await _channel.invokeMethod<String>('takeInitialUrl');
    } catch (_) {
      return null;
    }
  }

  /// Links opened from other apps while running.
  static void listen(void Function(String url) onUrl) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openUrl' && call.arguments is String) onUrl(call.arguments as String);
    });
  }

  static Future<bool> isDefault() async {
    try {
      return await _channel.invokeMethod<bool>('isDefaultBrowser') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system "set as default browser" prompt. True if now default.
  static Future<bool> requestDefault() async {
    try {
      return await _channel.invokeMethod<bool>('requestDefaultBrowser') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Re-checked when Settings / onboarding are shown.
final isDefaultBrowserProvider = FutureProvider.autoDispose<bool>((ref) => SystemBrowser.isDefault());
