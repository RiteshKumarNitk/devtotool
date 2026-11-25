import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers.dart';
import 'scripts/extensions_js.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

/// Curated list of advertising and tracking domains (subdomains included).
/// Kept short and well-known on purpose: fewer false positives than big lists.
const defaultBlockDomains = <String>[
  // Google ads & analytics
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com', 'google-analytics.com',
  'googletagmanager.com', 'googletagservices.com', 'adservice.google.com', 'pagead2.googlesyndication.com',
  'imasdk.googleapis.com', 'app-measurement.com',
  // Ad exchanges / SSPs / DSPs
  'adnxs.com', 'pubmatic.com', 'rubiconproject.com', 'openx.net', 'casalemedia.com', 'criteo.com',
  'criteo.net', 'amazon-adsystem.com', 'adsrvr.org', 'smartadserver.com', 'yieldmo.com', 'sharethrough.com',
  'triplelift.com', 'indexww.com', 'contextweb.com', 'adform.net', 'teads.tv', 'media.net', 'bidswitch.net',
  '33across.com', 'gumgum.com', 'sovrn.com', 'lijit.com', 'adcolony.com', 'applovin.com', 'unityads.unity3d.com',
  'inmobi.com', 'mopub.com', 'admob.com', 'adsafeprotected.com', 'serving-sys.com', 'zedo.com', 'revcontent.com',
  'mgid.com', 'propellerads.com', 'popads.net', 'popcash.net', 'exoclick.com', 'adsterra.com', 'adroll.com',
  'quantcount.com', 'yieldlab.net', 'adition.com', 'onetag-sys.com', 'districtm.io', 'emxdgt.com',
  // Pop-under / redirect ad networks (common on streaming sites)
  'onclickads.net', 'onclkds.com', 'highperformanceformat.com', 'profitabledisplaynetwork.com',
  'juicyads.com', 'trafficjunky.net', 'hilltopads.net', 'clickadu.com', 'monetag.com', 'a-ads.com',
  'adcash.com', 'galaksion.com', 'ad-maven.com', 'admaven.com', 'richpush.co', 'pushground.com',
  'evadav.com', 'realsrv.com', 'tsyndicate.com', 'exdynsrv.com', 'magsrv.com', 'popmyads.com',
  'clickaine.com', 'trafficstars.com', 'adspyglass.com', 'whos.amung.us', 'histats.com',
  // Content recommendation widgets
  'taboola.com', 'outbrain.com', 'zergnet.com',
  // Measurement / tracking
  'scorecardresearch.com', 'quantserve.com', 'moatads.com', 'doubleverify.com', 'chartbeat.com',
  'chartbeat.net', 'hotjar.com', 'hotjar.io', 'mouseflow.com', 'crazyegg.com', 'fullstory.com',
  'luckyorange.com', 'clarity.ms', 'mixpanel.com', 'segment.io', 'segment.com', 'amplitude.com',
  'heap.io', 'heapanalytics.com', 'newrelic.com', 'nr-data.net', 'bugsnag.com', 'branch.io',
  'adjust.com', 'appsflyer.com', 'kochava.com', 'krxd.net', 'bluekai.com', 'demdex.net', 'omtrdc.net',
  'everesttech.net', 'rlcdn.com', 'tapad.com', 'agkn.com', 'exelator.com', 'eyeota.net', 'crwdcntrl.net',
  'mathtag.com', 'turn.com', 'addthis.com', 'sharethis.com', 'bounceexchange.com', 'yandex.ru/metrika',
  'mc.yandex.ru', 'statcounter.com', 'parsely.com', 'cxense.com', 'permutive.com', 'liveramp.com',
  'id5-sync.com', 'pippio.com', 'adsymptotic.com',
  // Social trackers / pixels
  'connect.facebook.net', 'facebook.com/tr', 'pixel.facebook.com', 'analytics.twitter.com',
  'static.ads-twitter.com', 'ads.linkedin.com', 'px.ads.linkedin.com', 'snap.licdn.com', 'analytics.tiktok.com',
  'ads.tiktok.com', 'sc-static.net', 'tr.snapchat.com', 'ct.pinterest.com', 'bat.bing.com',
];

/// Sites the blocker never touches. Keeps the app clear of "YouTube ad
/// blocking", which store policies and YouTube's terms don't allow.
const blockerExemptHosts = <String>['youtube.com', 'youtu.be', 'youtube-nocookie.com', 'youtubekids.com', 'music.youtube.com'];

/// "www.news.example.com" -> "news.example.com" (key for per-site settings).
String siteKey(String urlOrHost) {
  final host = Uri.tryParse(urlOrHost)?.host;
  final h = (host != null && host.isNotEmpty ? host : urlOrHost).toLowerCase();
  return h.startsWith('www.') ? h.substring(4) : h;
}

/// The blocklist entry matching [host] (or a parent domain), else null.
String? matchBlockedHost(String host) {
  var h = host.toLowerCase();
  final set = _blockSet;
  while (h.isNotEmpty) {
    if (set.contains(h)) return h;
    final dot = h.indexOf('.');
    if (dot < 0) return null;
    h = h.substring(dot + 1);
  }
  return null;
}

final Set<String> _blockSet = defaultBlockDomains.where((d) => !d.contains('/')).toSet();

bool isBlockerExempt(String host) {
  final h = siteKey(host);
  return blockerExemptHosts.any((e) => h == e || h.endsWith('.$e'));
}

@immutable
class SiteOverride {
  final bool? blocker;
  final bool? dark;
  final bool? cookies;
  final bool? popups;

  /// JavaScript for this site (false = off, NoScript-style).
  final bool? js;

  /// Elements the user chose to hide on this site (CSS selectors).
  final List<String> hidden;

  /// Text size in percent (100 = default).
  final int? textZoom;
  const SiteOverride({
    this.blocker,
    this.dark,
    this.cookies,
    this.popups,
    this.js,
    this.hidden = const [],
    this.textZoom,
  });

  bool get isEmpty =>
      blocker == null &&
      dark == null &&
      cookies == null &&
      popups == null &&
      js == null &&
      hidden.isEmpty &&
      (textZoom == null || textZoom == 100);

  SiteOverride copyWith({
    bool? Function()? blocker,
    bool? Function()? dark,
    bool? Function()? cookies,
    bool? Function()? popups,
    bool? Function()? js,
    List<String>? hidden,
    int? Function()? textZoom,
  }) =>
      SiteOverride(
        blocker: blocker != null ? blocker() : this.blocker,
        dark: dark != null ? dark() : this.dark,
        cookies: cookies != null ? cookies() : this.cookies,
        popups: popups != null ? popups() : this.popups,
        js: js != null ? js() : this.js,
        hidden: hidden ?? this.hidden,
        textZoom: textZoom != null ? textZoom() : this.textZoom,
      );

  Map<String, dynamic> toJson() => {
        if (blocker != null) 'blocker': blocker,
        if (dark != null) 'dark': dark,
        if (cookies != null) 'cookies': cookies,
        if (popups != null) 'popups': popups,
        if (js != null) 'js': js,
        if (hidden.isNotEmpty) 'hidden': hidden,
        if (textZoom != null) 'textZoom': textZoom,
      };

  static SiteOverride fromJson(Object? j) {
    if (j is! Map) return const SiteOverride();
    bool? b(Object? v) => v is bool ? v : null;
    return SiteOverride(
      blocker: b(j['blocker']),
      dark: b(j['dark']),
      cookies: b(j['cookies']),
      popups: b(j['popups']),
      js: b(j['js']),
      hidden: (j['hidden'] as List?)?.map((e) => '$e').where((e) => e.isNotEmpty).toList() ?? const [],
      textZoom: (j['textZoom'] as num?)?.toInt(),
    );
  }
}

@immutable
class ExtensionSettings {
  final bool blocker;
  final bool cosmetic;
  final bool dark;
  final bool cookies;

  /// Pop-up, pop-under and invisible-overlay blocking.
  final bool popups;

  /// Easier-to-read text on all sites (system font, more spacing).
  final bool readableText;

  /// Don't load images (saves data).
  final bool dataSaver;
  final Map<String, SiteOverride> sites;

  const ExtensionSettings({
    this.blocker = true,
    this.cosmetic = true,
    this.dark = false,
    this.cookies = false,
    this.popups = true,
    this.readableText = false,
    this.dataSaver = false,
    this.sites = const {},
  });

  SiteOverride site(String host) => sites[siteKey(host)] ?? const SiteOverride();

  /// Effective value for [host], honouring per-site overrides and exemptions.
  bool blockerOn(String host) => blocker && !isBlockerExempt(host) && (site(host).blocker ?? true);
  bool darkOn(String host) => dark && (site(host).dark ?? true);
  bool cookiesOn(String host) => cookies && (site(host).cookies ?? true);
  bool popupsOn(String host) => popups && (site(host).popups ?? true);
  bool jsOn(String host) => site(host).js ?? true;
  List<String> hiddenOn(String host) => site(host).hidden;
  int textZoom(String host) => site(host).textZoom ?? 100;

  ExtensionSettings copyWith({
    bool? blocker,
    bool? cosmetic,
    bool? dark,
    bool? cookies,
    bool? popups,
    bool? readableText,
    bool? dataSaver,
    Map<String, SiteOverride>? sites,
  }) =>
      ExtensionSettings(
        blocker: blocker ?? this.blocker,
        cosmetic: cosmetic ?? this.cosmetic,
        dark: dark ?? this.dark,
        cookies: cookies ?? this.cookies,
        popups: popups ?? this.popups,
        readableText: readableText ?? this.readableText,
        dataSaver: dataSaver ?? this.dataSaver,
        sites: sites ?? this.sites,
      );

  ExtensionSettings withSite(String host, SiteOverride Function(SiteOverride) change) {
    final key = siteKey(host);
    final next = Map<String, SiteOverride>.from(sites);
    final updated = change(next[key] ?? const SiteOverride());
    if (updated.isEmpty) {
      next.remove(key);
    } else {
      next[key] = updated;
    }
    return copyWith(sites: next);
  }

  Map<String, dynamic> toJson() => {
        'blocker': blocker,
        'cosmetic': cosmetic,
        'dark': dark,
        'cookies': cookies,
        'popups': popups,
        'readableText': readableText,
        'dataSaver': dataSaver,
        'sites': {for (final e in sites.entries) e.key: e.value.toJson()},
      };

  static ExtensionSettings fromJson(Object? j) {
    if (j is! Map) return const ExtensionSettings();
    final sites = j['sites'];
    return ExtensionSettings(
      blocker: j['blocker'] != false,
      cosmetic: j['cosmetic'] != false,
      dark: j['dark'] == true,
      cookies: j['cookies'] == true,
      popups: j['popups'] != false,
      readableText: j['readableText'] == true,
      dataSaver: j['dataSaver'] == true,
      sites: sites is Map ? {for (final e in sites.entries) '${e.key}': SiteOverride.fromJson(e.value)} : const {},
    );
  }
}

class ExtensionsNotifier extends Notifier<ExtensionSettings> {
  static const _key = 'extensions';
  @override
  ExtensionSettings build() => ExtensionSettings.fromJson(_box()?.get(_key));

  void update(ExtensionSettings Function(ExtensionSettings) change) {
    state = change(state);
    _box()?.put(_key, jsonDecode(jsonEncode(state.toJson())));
  }
}

final extensionsProvider = NotifierProvider<ExtensionsNotifier, ExtensionSettings>(ExtensionsNotifier.new);

// ----------------------------------------------------------------- user scripts

@immutable
class UserScript {
  final String id;
  final String name;

  /// URL globs, e.g. "https://*.example.com/*". "*" matches anything.
  final List<String> matches;
  final String js;
  final String css;
  final bool enabled;

  /// 'start' (before page scripts) or 'end' (after DOMContentLoaded).
  final String runAt;

  const UserScript({
    required this.id,
    required this.name,
    this.matches = const ['*'],
    this.js = '',
    this.css = '',
    this.enabled = true,
    this.runAt = 'end',
  });

  UserScript copyWith({String? name, List<String>? matches, String? js, String? css, bool? enabled, String? runAt}) =>
      UserScript(
        id: id,
        name: name ?? this.name,
        matches: matches ?? this.matches,
        js: js ?? this.js,
        css: css ?? this.css,
        enabled: enabled ?? this.enabled,
        runAt: runAt ?? this.runAt,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'matches': matches, 'js': js, 'css': css, 'enabled': enabled, 'runAt': runAt};

  static UserScript? fromJson(Object? j) {
    if (j is! Map || j['name'] == null) return null;
    final m = (j['matches'] as List?)?.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    return UserScript(
      id: '${j['id'] ?? newId()}',
      name: '${j['name']}',
      matches: (m == null || m.isEmpty) ? const ['*'] : m,
      js: '${j['js'] ?? ''}',
      css: '${j['css'] ?? ''}',
      enabled: j['enabled'] != false,
      runAt: j['runAt'] == 'start' ? 'start' : 'end',
    );
  }

  static int _seq = 0;
  static String newId() => 'us${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

/// Converts a URL glob to a regex, like Chrome match patterns: in the host
/// part `*` can't cross `/ ? #` (so `https://*.example.com/*` never matches
/// `https://evil.com/?.example.com/`); in the path `*` matches anything.
/// A pattern without a path matches every path. Mirrors the injected JS.
RegExp globToRegExp(String glob) {
  final g = glob.trim();
  if (g == '*') return RegExp('.*');
  String conv(String part, String star) => part.split('*').map(RegExp.escape).join(star);
  final schemeEnd = g.indexOf('://');
  if (schemeEnd < 0) return RegExp('^${conv(g, '.*')}\$', caseSensitive: false);
  final hostStart = schemeEnd + 3;
  final pathStart = g.indexOf(RegExp(r'[/?#]'), hostStart);
  final hostPart = pathStart < 0 ? g : g.substring(0, pathStart);
  final rest = pathStart < 0 ? '' : g.substring(pathStart);
  final re = conv(hostPart, '[^/?#]*') + (rest.isEmpty ? '(?:[/?#].*)?' : conv(rest, '.*'));
  return RegExp('^$re\$', caseSensitive: false);
}

bool userScriptMatches(UserScript s, String url) => s.matches.any((g) => globToRegExp(g).hasMatch(url));

class UserScriptsNotifier extends Notifier<List<UserScript>> {
  static const _key = 'userScripts';
  @override
  List<UserScript> build() {
    final saved = _box()?.get(_key);
    if (saved is! List) return const [];
    return saved.map(UserScript.fromJson).whereType<UserScript>().toList();
  }

  void upsert(UserScript s) {
    final i = state.indexWhere((x) => x.id == s.id);
    if (i < 0) {
      state = [...state, s];
    } else {
      final next = [...state];
      next[i] = s;
      state = next;
    }
    _persist();
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList();
    _persist();
  }

  void toggle(String id) {
    state = [for (final s in state) s.id == id ? s.copyWith(enabled: !s.enabled) : s];
    _persist();
  }

  int importAll(List<UserScript> scripts) {
    final byId = {for (final s in state) s.id: s};
    for (final s in scripts) {
      byId[s.id] = s;
    }
    state = byId.values.toList();
    _persist();
    return scripts.length;
  }

  void _persist() => _box()?.put(_key, jsonDecode(jsonEncode(state.map((s) => s.toJson()).toList())));
}

final userScriptsProvider = NotifierProvider<UserScriptsNotifier, List<UserScript>>(UserScriptsNotifier.new);

// ------------------------------------------------------------------- builders

/// JSON config read by the injected core extension script.
Map<String, dynamic> extensionConfig(ExtensionSettings s) => {
      'blocker': s.blocker,
      'cosmetic': s.cosmetic,
      'dark': s.dark,
      'cookies': s.cookies,
      'popups': s.popups,
      'readable': s.readableText,
      'blockDomains': defaultBlockDomains.where((d) => !d.contains('/')).toList(),
      'sites': {
        for (final e in s.sites.entries) e.key: e.value.toJson(),
        // Forced, not user-overridable.
        for (final h in blockerExemptHosts) h: {...?s.sites[h]?.toJson(), 'blocker': false},
      },
    };

String buildCoreScript(ExtensionSettings s) => extensionsCoreJs.replaceFirst('__CONFIG__', jsonEncode(extensionConfig(s)));

/// Wraps one user script. The body is inserted verbatim, so a syntax error
/// only breaks this script (each is registered separately).
String buildUserScript(UserScript s) {
  final meta = jsonEncode({'name': s.name, 'matches': s.matches, 'css': s.css, 'runAt': s.runAt});
  final parts = userScriptTemplate.split('__BODY__');
  return parts[0] + s.js + parts[1].replaceFirst('__META__', meta);
}

/// All document-start scripts for a tab, in order. Private tabs get the same
/// protections; user scripts only run where the user enabled them.
List<String> buildStartScripts(ExtensionSettings s, List<UserScript> scripts) => [
      buildCoreScript(s),
      for (final u in scripts)
        if (u.enabled && (u.js.trim().isNotEmpty || u.css.trim().isNotEmpty)) buildUserScript(u),
    ];
