import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';

/// "name: value" lines -> header map (blank/invalid lines ignored).
Map<String, String> parseHeaderLines(String text) => {
      for (final line in text.split('\n'))
        if (line.contains(':') && line.indexOf(':') > 0)
          line.substring(0, line.indexOf(':')).trim(): line.substring(line.indexOf(':') + 1).trim(),
    };

/// Edit a captured request and send it again from inside the page.
class ReplayPage extends ConsumerStatefulWidget {
  final NetworkRequest request;
  const ReplayPage({super.key, required this.request});

  @override
  ConsumerState<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends ConsumerState<ReplayPage> {
  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
  late String _method = _methods.contains(widget.request.method) ? widget.request.method : 'GET';
  late final _url = TextEditingController(text: widget.request.url);
  late final _headers = TextEditingController(text: [
    for (final e in widget.request.requestHeaders.entries)
      if (!const {'content-length', 'host', 'cookie'}.contains(e.key.toLowerCase())) '${e.key}: ${e.value}',
  ].join('\n'));
  late final _body = TextEditingController(text: widget.request.requestBody ?? '');
  String? _replayId;
  bool _sending = false;

  @override
  void dispose() {
    for (final c in [_url, _headers, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final controller = ref.read(webViewControllerProvider);
    if (controller == null) return;
    final id = 'r${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _replayId = id;
      _sending = true;
    });
    final req = jsonEncode({
      'method': _method,
      'url': _url.text.trim(),
      'headers': parseHeaderLines(_headers.text),
      'body': _body.text,
    });
    await controller.runJavaScript('window.__dbg && window.__dbg.replay(${jsString(id)}, $req)');
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(pageDataProvider)['replay_result'];
    final mine = result != null && result['id'] == _replayId ? result : null;
    if (mine != null && _sending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sending = false);
      });
    }
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit & resend')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            DropdownButton<String>(
              value: _method,
              items: [for (final m in _methods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _method = v ?? 'GET'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _url,
                style: mono,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL', isDense: true, border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _headers,
            minLines: 3,
            maxLines: 10,
            style: mono,
            decoration: const InputDecoration(
              labelText: 'Headers (one "Name: value" per line)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 14,
            style: mono,
            enabled: !(_method == 'GET' || _method == 'HEAD'),
            decoration: const InputDecoration(labelText: 'Body', alignLabelWithHint: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Send'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Sent from the page itself, with its cookies. Requests to other sites must allow it (CORS).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          if (mine != null) ...[
            const Divider(height: 32),
            if (mine['error'] != null)
              Text('Failed: ${mine['error']}', style: TextStyle(color: Theme.of(context).colorScheme.error))
            else ...[
              Row(children: [
                Chip(
                  label: Text('${mine['status']} ${mine['statusText'] ?? ''}'),
                  backgroundColor: ((mine['status'] as num?) ?? 0) < 400 ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                Text('${mine['ms']} ms', style: const TextStyle(color: Colors.grey)),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy body',
                  icon: const Icon(Icons.copy),
                  onPressed: () => Clipboard.setData(ClipboardData(text: '${mine['body'] ?? ''}')),
                ),
              ]),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Response headers (${(mine['headers'] as Map?)?.length ?? 0})'),
                children: [
                  for (final e in ((mine['headers'] as Map?) ?? const {}).entries)
                    Align(alignment: Alignment.centerLeft, child: SelectableText('${e.key}: ${e.value}', style: mono)),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SelectableText(_pretty('${mine['body'] ?? ''}'), style: mono),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _pretty(String body) {
    final t = body.trimLeft();
    if (!(t.startsWith('{') || t.startsWith('['))) return body;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
    } catch (_) {
      return body;
    }
  }
}
