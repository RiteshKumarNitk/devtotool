import 'dart:convert';

import 'package:flutter/material.dart';

/// Returns the decoded JSON object/array if [text] (or a trailing part of it,
/// e.g. `label {"a":1}`) is JSON; null otherwise. Primitives return null.
({String prefix, Object json})? extractJson(String text) {
  final t = text.trim();
  for (final open in const ['{', '[']) {
    final i = t.indexOf(open);
    if (i < 0) continue;
    final candidate = t.substring(i);
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map || decoded is List) {
        return (prefix: t.substring(0, i).trim(), json: decoded as Object);
      }
    } on FormatException {
      // try the next opener
    }
  }
  return null;
}

/// Collapsible tree view for decoded JSON.
class JsonTree extends StatelessWidget {
  final Object? value;
  final String? name;
  final bool initiallyExpanded;
  const JsonTree({super.key, required this.value, this.name, this.initiallyExpanded = false});

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final v = value;
    final keyStyle = _mono.copyWith(color: Colors.purple.shade300, fontWeight: FontWeight.w600);
    final label = name == null ? null : TextSpan(text: '$name: ', style: keyStyle);

    if (v is Map || v is List) {
      final entries = v is Map
          ? v.entries.map((e) => MapEntry('${e.key}', e.value)).toList()
          : [for (var i = 0; i < (v as List).length; i++) MapEntry('$i', v[i])];
      final summary = v is Map ? '{…} ${entries.length} keys' : '[…] ${entries.length} items';
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          initiallyExpanded: initiallyExpanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 14),
          visualDensity: VisualDensity.compact,
          title: Text.rich(TextSpan(children: [
            if (label != null) label,
            TextSpan(text: summary, style: _mono.copyWith(color: Colors.grey)),
          ])),
          children: [
            for (final e in entries.take(500)) JsonTree(value: e.value, name: e.key),
            if (entries.length > 500)
              Text('… ${entries.length - 500} more', style: _mono.copyWith(color: Colors.grey)),
          ],
        ),
      );
    }

    final Color color;
    final String text;
    if (v is String) {
      color = Colors.green.shade400;
      text = jsonEncode(v);
    } else if (v is num) {
      color = Colors.blue.shade300;
      text = '$v';
    } else if (v is bool) {
      color = Colors.orange.shade400;
      text = '$v';
    } else {
      color = Colors.grey;
      text = 'null';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(TextSpan(children: [
        if (label != null) label,
        TextSpan(text: text, style: _mono.copyWith(color: color)),
      ])),
    );
  }
}
