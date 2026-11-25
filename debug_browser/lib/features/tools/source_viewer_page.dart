import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Breaks minified HTML into one tag per line (no reindenting of text).
String formatHtml(String html) {
  final out = StringBuffer();
  var depth = 0;
  for (final m in RegExp(r'(<[^>]+>)|([^<]+)').allMatches(html)) {
    final tag = m.group(1);
    final text = m.group(2);
    if (text != null) {
      final t = text.trim();
      if (t.isNotEmpty) out.writeln('${'  ' * depth}$t');
      continue;
    }
    final closing = tag!.startsWith('</');
    final selfClosing = tag.endsWith('/>') ||
        RegExp(r'^<(area|base|br|col|embed|hr|img|input|link|meta|source|track|wbr|!)', caseSensitive: false).hasMatch(tag);
    if (closing && depth > 0) depth--;
    out.writeln('${'  ' * depth}$tag');
    if (!closing && !selfClosing) depth++;
  }
  return out.toString();
}

/// Syntax colours for one line of HTML.
List<TextSpan> highlightHtmlLine(String line, {required bool dark}) {
  final tagC = dark ? const Color(0xFF7FB2FF) : const Color(0xFF1A56C4);
  final attrC = dark ? const Color(0xFFD49BFF) : const Color(0xFF8E24AA);
  final strC = dark ? const Color(0xFF8BD49C) : const Color(0xFF1E7B34);
  final comC = Colors.grey;
  final spans = <TextSpan>[];
  final re = RegExp(r'(<!--.*?-->)|(</?[a-zA-Z][\w:-]*)|(\s[\w:@.-]+)(?==)|("[^"]*"|' "'" r"[^']*')|(/?>)");
  var last = 0;
  for (final m in re.allMatches(line)) {
    if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
    final color = m.group(1) != null
        ? comC
        : m.group(2) != null || m.group(5) != null
            ? tagC
            : m.group(3) != null
                ? attrC
                : strC;
    spans.add(TextSpan(text: m.group(0), style: TextStyle(color: color)));
    last = m.end;
  }
  if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
  return spans;
}

class SourceViewerPage extends StatefulWidget {
  final String url;
  final String source;
  const SourceViewerPage({super.key, required this.url, required this.source});

  @override
  State<SourceViewerPage> createState() => _SourceViewerPageState();
}

class _SourceViewerPageState extends State<SourceViewerPage> {
  bool _formatted = true;
  bool _wrap = false;
  String _query = '';
  late List<String> _lines = _split();

  List<String> _split() => (_formatted ? formatHtml(widget.source) : widget.source).split('\n');

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final q = _query.toLowerCase();
    final hits = q.isEmpty ? 0 : _lines.where((l) => l.toLowerCase().contains(q)).length;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4);
    final gutter = '${_lines.length}'.length * 8.0 + 12;

    return Scaffold(
      appBar: AppBar(
        title: Text('Source: ${Uri.tryParse(widget.url)?.host ?? ''}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _formatted ? 'Show as received' : 'Format',
            icon: Icon(_formatted ? Icons.format_align_left : Icons.auto_fix_high),
            onPressed: () => setState(() {
              _formatted = !_formatted;
              _lines = _split();
            }),
          ),
          IconButton(
            tooltip: _wrap ? 'No wrap' : 'Wrap lines',
            icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
            onPressed: () => setState(() => _wrap = !_wrap),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.source));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Source copied')));
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Find in source',
              prefixIcon: const Icon(Icons.search),
              suffixText: q.isEmpty ? null : '$hits lines',
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                final hit = q.isNotEmpty && line.toLowerCase().contains(q);
                final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: gutter,
                    child: Text('${i + 1}', textAlign: TextAlign.right, style: mono.copyWith(color: Colors.grey)),
                  ),
                  const SizedBox(width: 10),
                  if (_wrap)
                    Expanded(child: Text.rich(TextSpan(children: highlightHtmlLine(line, dark: dark)), style: mono))
                  else
                    Text.rich(TextSpan(children: highlightHtmlLine(line, dark: dark)), style: mono, softWrap: false),
                ]);
                return Container(
                  color: hit ? Colors.amber.withValues(alpha: 0.25) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _wrap ? row : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
