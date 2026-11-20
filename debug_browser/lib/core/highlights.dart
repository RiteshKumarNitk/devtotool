import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers.dart';

Box? _box() => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

/// Highlights belong to a page; the fragment (#…) doesn't matter.
String highlightPageKey(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return url;
  return u.removeFragment().toString();
}

@immutable
class Highlight {
  final String id;
  final String url;
  final String title;
  final String text;

  /// Text around the highlight, used to find it again on the page.
  final String prefix;
  final String suffix;
  final String color;
  final String note;
  final DateTime created;

  const Highlight({
    required this.id,
    required this.url,
    required this.title,
    required this.text,
    this.prefix = '',
    this.suffix = '',
    this.color = 'yellow',
    this.note = '',
    required this.created,
  });

  Highlight copyWith({String? note, String? color, String? title}) => Highlight(
        id: id,
        url: url,
        title: title ?? this.title,
        text: text,
        prefix: prefix,
        suffix: suffix,
        color: color ?? this.color,
        note: note ?? this.note,
        created: created,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'text': text,
        'prefix': prefix,
        'suffix': suffix,
        'color': color,
        'note': note,
        'created': created.toIso8601String(),
      };

  static Highlight? fromJson(Object? j) {
    if (j is! Map || j['id'] == null || j['text'] == null) return null;
    return Highlight(
      id: '${j['id']}',
      url: '${j['url'] ?? ''}',
      title: '${j['title'] ?? ''}',
      text: '${j['text']}',
      prefix: '${j['prefix'] ?? ''}',
      suffix: '${j['suffix'] ?? ''}',
      color: '${j['color'] ?? 'yellow'}',
      note: '${j['note'] ?? ''}',
      created: DateTime.tryParse('${j['created']}') ?? DateTime.now(),
    );
  }
}

/// All highlights, newest first. Never stores private-tab highlights.
class HighlightsNotifier extends Notifier<List<Highlight>> {
  static const _key = 'highlights';

  @override
  List<Highlight> build() {
    final saved = _box()?.get(_key);
    if (saved is! List) return const [];
    return saved.map(Highlight.fromJson).whereType<Highlight>().toList();
  }

  List<Highlight> forPage(String url) {
    final key = highlightPageKey(url);
    return state.where((h) => highlightPageKey(h.url) == key).toList();
  }

  /// JSON the page script uses to re-apply highlights.
  String pageJson(String url) => jsonEncode([
        for (final h in forPage(url)) {'id': h.id, 'text': h.text, 'prefix': h.prefix, 'suffix': h.suffix, 'color': h.color},
      ]);

  void add(Highlight h) {
    state = [h, ...state.where((x) => x.id != h.id)];
    _persist();
  }

  void update(String id, Highlight Function(Highlight) change) {
    state = [for (final h in state) h.id == id ? change(h) : h];
    _persist();
  }

  void remove(String id) {
    state = state.where((h) => h.id != id).toList();
    _persist();
  }

  int importAll(List<Highlight> list) {
    final ids = {for (final h in state) h.id};
    final added = list.where((h) => ids.add(h.id)).toList();
    state = [...state, ...added]..sort((a, b) => b.created.compareTo(a.created));
    _persist();
    return added.length;
  }

  void _persist() => _box()?.put(_key, state.map((h) => h.toJson()).toList());
}

final highlightsProvider = NotifierProvider<HighlightsNotifier, List<Highlight>>(HighlightsNotifier.new);
