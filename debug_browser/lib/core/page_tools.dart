import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'backup.dart' show ProviderReader;
import 'browser_native.dart';
import 'browser_settings.dart';
import 'favicons.dart';
import 'home_stats.dart';
import 'providers.dart';
import 'tabs_provider.dart';
import 'tool_providers.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

/// Decodes a value from runJavaScriptReturningResult (Android JSON-encodes
/// strings).
String jsResultString(Object? r) {
  if (r == null) return '';
  final s = r is String ? r : '$r';
  if (s.startsWith('"') && s.endsWith('"')) {
    try {
      return jsonDecode(s) as String;
    } catch (_) {}
  }
  return s == 'null' ? '' : s;
}

// --------------------------------------------------------------- translate

/// Common translation targets: code -> name.
const translateLanguages = <String, String>{
  'en': 'English', 'hi': 'Hindi', 'bn': 'Bengali', 'ta': 'Tamil', 'te': 'Telugu', 'mr': 'Marathi',
  'gu': 'Gujarati', 'kn': 'Kannada', 'ml': 'Malayalam', 'pa': 'Punjabi', 'ur': 'Urdu', 'ar': 'Arabic',
  'zh-CN': 'Chinese (Simplified)', 'es': 'Spanish', 'fr': 'French', 'de': 'German', 'pt': 'Portuguese',
  'ru': 'Russian', 'ja': 'Japanese', 'ko': 'Korean', 'it': 'Italian', 'tr': 'Turkish', 'id': 'Indonesian',
};

String effectiveTranslateLang(BrowserSettings s) {
  if (s.translateTo.isNotEmpty) return s.translateTo;
  final phone = ui.PlatformDispatcher.instance.locale.languageCode;
  return translateLanguages.containsKey(phone) ? phone : 'en';
}

/// Google Translate's whole-page translation for [url].
Uri translateUri(String url, String lang) =>
    Uri.https('translate.google.com', '/translate', {'sl': 'auto', 'tl': lang, 'u': url});

// ------------------------------------------------------------ offline pages

@immutable
class OfflinePage {
  final String title;
  final String url;
  final String path;
  final int size;
  final DateTime savedAt;
  const OfflinePage(this.title, this.url, this.path, this.size, this.savedAt);

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, 'path': path, 'size': size, 'savedAt': savedAt.toIso8601String()};

  static OfflinePage? fromJson(Object? j) {
    if (j is! Map || j['path'] == null) return null;
    return OfflinePage('${j['title'] ?? ''}', '${j['url'] ?? ''}', '${j['path']}', (j['size'] as num?)?.toInt() ?? 0,
        DateTime.tryParse('${j['savedAt']}') ?? DateTime.now());
  }
}

class OfflinePagesNotifier extends Notifier<List<OfflinePage>> {
  static const _key = 'offlinePages';

  @override
  List<OfflinePage> build() {
    final saved = _box()?.get(_key);
    if (saved is! List) return const [];
    return saved.map(OfflinePage.fromJson).whereType<OfflinePage>().toList();
  }

  /// Saves the active page as an MHTML archive. Returns an error or null.
  Future<String?> saveActive() async {
    final tabs = ref.read(tabsProvider.notifier);
    final tab = ref.read(tabsProvider).active;
    if (tab.isNewTab || !tab.url.startsWith('http')) return 'Open a web page first.';
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/offline');
    await dir.create(recursive: true);
    final path = '${dir.path}/page_${DateTime.now().millisecondsSinceEpoch}.mht';
    final saved = await BrowserNative.saveWebArchive(tabs.activeController, path);
    if (saved == null || !File(saved).existsSync()) return 'This page could not be saved.';
    final page = OfflinePage(tab.displayTitle, tab.url, saved, File(saved).lengthSync(), DateTime.now());
    state = [page, ...state];
    _persist();
    return null;
  }

  Future<void> remove(OfflinePage p) async {
    try {
      await File(p.path).delete();
    } catch (_) {}
    state = state.where((x) => x.path != p.path).toList();
    _persist();
  }

  void _persist() => _box()?.put(_key, state.map((p) => p.toJson()).toList());
}

final offlinePagesProvider = NotifierProvider<OfflinePagesNotifier, List<OfflinePage>>(OfflinePagesNotifier.new);

// ------------------------------------------------------------ home screen

/// Pins the active site to the Home screen with its icon.
Future<bool> addActiveToHomeScreen(ProviderReader read) async {
  final tab = read(tabsProvider).active;
  if (!tab.url.startsWith('http')) return false;
  Uint8List? icon;
  final src = faviconUrlFor(read(faviconsProvider), tab.url);
  if (src != null) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final res = await (await client.getUrl(Uri.parse(src))).close().timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final bytes = await res.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d)).timeout(const Duration(seconds: 4));
        if (bytes.length < 512 * 1024) icon = bytes.takeBytes();
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }
  return SystemBrowser.pinShortcut(tab.url, tab.displayTitle, icon);
}

// ------------------------------------------------------------- screenshots

/// Encodes [image] as PNG and disposes it.
Future<Uint8List?> _png(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

/// Captures the whole scrolling page by scrolling one screen at a time and
/// stitching the shots (fixed headers hidden after the first screen).
/// Capped at [maxScreens] screens.
Future<Uint8List?> captureFullPage(ProviderReader read, {int maxScreens = 12}) async {
  final tabs = read(tabsProvider.notifier);
  final c = tabs.activeController;
  final shooter = read(screenshotControllerProvider);
  Future<Map> metrics() async =>
      jsonDecode(jsResultString(await c.runJavaScriptReturningResult('window.__dbg ? window.__dbg.pageMetrics() : "{}"'))) as Map;

  tabs.freezeToolbars(true);
  final shots = <(ui.Image, double)>[];
  double? startY;
  try {
    final m = await metrics();
    final height = (m['height'] as num?)?.toDouble() ?? 0;
    final vp = (m['viewport'] as num?)?.toDouble() ?? 0;
    startY = (m['y'] as num?)?.toDouble() ?? 0;
    if (height <= 0 || vp <= 0) return null;
    final limit = height.clamp(vp, vp * maxScreens);
    for (var y = 0.0; y < limit; y += vp) {
      await c.runJavaScript('window.scrollTo(0, $y)');
      await Future<void>.delayed(const Duration(milliseconds: 380));
      final actual = ((await metrics())['y'] as num?)?.toDouble() ?? y;
      final img = await shooter.captureAsUiImage(pixelRatio: 1.5, delay: Duration.zero);
      if (img == null) break;
      shots.add((img, actual));
      if (shots.length == 1) await c.runJavaScript('window.__dbg && window.__dbg.hideFixed(true)');
      if (actual + vp >= height) break; // reached the bottom
    }
    if (shots.isEmpty) return null;
    final first = shots.first.$1;
    final scale = first.height / vp; // image px per CSS px
    final totalH = ((shots.last.$2 + vp) * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final (img, y) in shots) {
      canvas.drawImage(img, ui.Offset(0, y * scale), ui.Paint());
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(first.width, totalH);
    picture.dispose();
    return await _png(out);
  } finally {
    for (final (img, _) in shots) {
      img.dispose();
    }
    await c.runJavaScript('window.__dbg && window.__dbg.hideFixed(false)').catchError((Object _) {});
    if (startY != null) await c.runJavaScript('window.scrollTo(0, $startY)').catchError((Object _) {});
    tabs.freezeToolbars(false);
  }
}

/// Presets used for responsive screenshots.
const responsivePresets = [ViewportPreset.iphone15, ViewportPreset.ipadMini, ViewportPreset.laptop];

/// Captures the page at phone, tablet and desktop widths. Returns
/// (label, png) pairs; restores the previous viewport.
Future<List<(String, Uint8List)>> captureResponsive(ProviderReader read) async {
  final viewport = read(viewportProvider.notifier);
  final previous = read(viewportProvider);
  final shooter = read(screenshotControllerProvider);
  final tabs = read(tabsProvider.notifier);
  final out = <(String, Uint8List)>[];
  tabs.freezeToolbars(true);
  try {
    for (final p in responsivePresets) {
      viewport.set(p);
      // Let the page re-layout for the new width (media queries, images).
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final img = await shooter.captureAsUiImage(pixelRatio: 1.5, delay: Duration.zero);
      final png = img == null ? null : await _png(img);
      if (png != null) out.add(('${p.label} (${p.width!.toInt()}×${p.height!.toInt()})', png));
    }
  } finally {
    viewport.set(previous);
    tabs.freezeToolbars(false);
  }
  return out;
}

/// Writes images to temp files for sharing.
Future<List<String>> writeTempPngs(List<(String, Uint8List)> images, String prefix) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final paths = <String>[];
  for (var i = 0; i < images.length; i++) {
    final safe = images[i].$1.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final f = File('${dir.path}/${prefix}_${stamp}_${i}_$safe.png');
    await f.writeAsBytes(images[i].$2);
    paths.add(f.path);
  }
  return paths;
}

// ------------------------------------------------- picture-in-picture

/// Sites where PiP is a paid feature of the service (YouTube Premium), so the
/// browser doesn't offer it there (Play policy / YouTube terms).
bool pipBlockedHost(String url) {
  final h = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  return h == 'youtube.com' || h.endsWith('.youtube.com') || h == 'youtu.be' || h.endsWith('.youtube-nocookie.com');
}

/// Focuses the playing video and shrinks the app into a floating window.
/// Returns an error message, or null on success.
Future<String?> startPictureInPicture(ProviderReader read) async {
  final tab = read(tabsProvider).active;
  if (tab.isNewTab) return 'Open a page with a video first.';
  if (pipBlockedHost(tab.url)) return 'Picture-in-picture is not available for YouTube.';
  final c = read(tabsProvider.notifier).activeController;
  final res = jsResultString(await c.runJavaScriptReturningResult('window.__dbg ? window.__dbg.focusVideo(true) : "{}"'));
  Map j = const {};
  try {
    j = jsonDecode(res) as Map;
  } catch (_) {}
  if (j['ok'] != true) return 'Start playing a video first.';
  final ok = await SystemBrowser.enterPip((j['w'] as num?)?.toInt() ?? 16, (j['h'] as num?)?.toInt() ?? 9);
  if (!ok) {
    await c.runJavaScript('window.__dbg && window.__dbg.focusVideo(false)');
    return 'Picture-in-picture is not supported on this phone.';
  }
  return null;
}

/// Opens Android's print dialog ("Save as PDF") for the active page.
Future<bool> printActivePage(ProviderReader read) async {
  final tab = read(tabsProvider).active;
  final id = BrowserNative.webViewId(read(tabsProvider.notifier).activeController);
  if (id == null || tab.isNewTab) return false;
  return SystemBrowser.printPage(id, tab.displayTitle);
}
