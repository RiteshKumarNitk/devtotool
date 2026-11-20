import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network_export.dart';
import '../../core/providers.dart';
import '../../services/export_service.dart';
import 'replay_page.dart';

class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  String _query = '';
  String? _type; // null = all, 'fetch', 'xhr'
  StatusFilter _status = StatusFilter.all;

  static Color statusColor(NetworkRequest r) {
    if (r.failed) return Colors.grey;
    if (r.status >= 200 && r.status < 300) return Colors.green;
    if (r.status >= 300 && r.status < 400) return Colors.orange;
    return Colors.redAccent;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied');
  }

  Future<void> _exportHar(List<NetworkRequest> requests) async {
    if (requests.isEmpty) {
      _snack('Nothing to export');
      return;
    }
    final ok = await ExportService.exportHar(requests);
    if (!ok) _snack('HAR export failed');
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(networkRequestsProvider);
    final condition = ref.watch(networkConditionProvider);
    final filtered = filterRequests(requests, query: _query, type: _type, status: _status);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Network'),
          actions: [
            PopupMenuButton<NetworkCondition>(
              tooltip: 'Network conditions',
              icon: Icon(
                condition.isOffline ? Icons.cloud_off : Icons.network_check,
                color: condition == NetworkCondition.none ? null : Colors.orange,
              ),
              initialValue: condition,
              onSelected: (c) {
                ref.read(networkConditionProvider.notifier).set(c);
                _snack(c == NetworkCondition.none ? 'Throttling off' : 'Simulating: ${c.label}');
              },
              itemBuilder: (_) => [
                for (final c in NetworkCondition.values)
                  CheckedPopupMenuItem(value: c, checked: c == condition, child: Text(c.label)),
              ],
            ),
            IconButton(
              tooltip: 'Export HAR (filtered)',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _exportHar(filtered),
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(networkRequestsProvider.notifier).clear(),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Live Traffic'), Tab(text: 'API Mocks')]),
        ),
        body: TabBarView(
          children: [
            _buildLiveTraffic(context, requests.length, filtered, condition),
            _buildMocksTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTraffic(
    BuildContext context,
    int total,
    List<NetworkRequest> filtered,
    NetworkCondition condition,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (condition != NetworkCondition.none)
          MaterialBanner(
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
            leading: Icon(condition.isOffline ? Icons.cloud_off : Icons.speed, color: Colors.orange),
            content: Text('Simulating ${condition.label}. Applies to fetch/XHR in the page.'),
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(networkConditionProvider.notifier).set(NetworkCondition.none),
                child: const Text('TURN OFF'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Filter by URL, method or status',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final t in const [null, 'fetch', 'xhr'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t?.toUpperCase() ?? 'All types'),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
                ),
              const VerticalDivider(width: 12),
              for (final s in StatusFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.label),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${filtered.length} of $total requests', style: theme.textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(total == 0 ? 'No network requests yet' : 'No requests match the filters'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    // Newest first.
                    final req = filtered[filtered.length - 1 - index];
                    final color = statusColor(req);
                    return ListTile(
                      dense: true,
                      title: Text(req.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${req.method} • ${req.type.toUpperCase()} • ${req.duration} ms'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(req.failed ? 'ERR' : '${req.status}',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                      ),
                      onTap: () => _showDetails(req),
                      onLongPress: () => _copy(toCurl(req), 'cURL'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showDetails(NetworkRequest req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Request details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.terminal, size: 18),
                  label: const Text('Copy cURL'),
                  onPressed: () => _copy(toCurl(req), 'cURL'),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.javascript, size: 18),
                  label: const Text('Copy fetch'),
                  onPressed: () => _copy(toFetch(req), 'fetch()'),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Export HAR'),
                  onPressed: () => _exportHar([req]),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Edit & resend'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReplayPage(request: req)),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _DetailRow(title: 'URL', value: req.url),
            _DetailRow(title: 'Method', value: req.method),
            _DetailRow(title: 'Status', value: req.failed ? 'Failed (${req.status})' : '${req.status}'),
            _DetailRow(title: 'Duration', value: '${req.duration} ms'),
            _DetailRow(title: 'Type', value: req.type.toUpperCase()),
            if (req.error != null) _DetailRow(title: 'Error', value: req.error!),
            _HeadersSection(title: 'Request headers', headers: req.requestHeaders),
            _HeadersSection(title: 'Response headers', headers: req.responseHeaders),
            _BodySection(title: 'Request body', body: req.requestBody, onCopy: _copy),
            _BodySection(title: 'Response body', body: req.responseBody, onCopy: _copy),
          ],
        ),
      ),
    );
  }

  Widget _buildMocksTab(BuildContext context) {
    final rules = ref.watch(networkMocksProvider);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rules.where((r) => r.enabled).length} of ${rules.length} rules active',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Import'),
                  onPressed: _importMocks,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Export'),
                  onPressed: rules.isEmpty ? null : () => _exportMocks(rules),
                ),
              ],
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No mock rules yet.\nTap + to return a custom status, body and delay for matching requests.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final r = rules[index];
                      return ListTile(
                        leading: Switch(
                          value: r.enabled,
                          onChanged: (_) => ref.read(networkMocksProvider.notifier).toggle(r.id),
                        ),
                        title: Text(
                          '${r.method == 'ANY' ? '' : '${r.method} '}${r.isRegex ? '/${r.pattern}/' : r.pattern}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: r.enabled ? null : Colors.grey,
                          ),
                        ),
                        subtitle: Text(
                          '→ ${r.status}${r.delayMs > 0 ? ' after ${r.delayMs} ms' : ''} • ${r.contentType}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => ref.read(networkMocksProvider.notifier).remove(r.id),
                        ),
                        onTap: () => _showMockEditor(r),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add mock rule',
        child: const Icon(Icons.add),
        onPressed: () => _showMockEditor(null),
      ),
    );
  }

  Future<void> _exportMocks(List<MockRule> rules) async {
    final ok = await ExportService.shareJson(
      rules.map((r) => r.toJson()).toList(),
      fileName: 'mock_rules',
      text: 'Debug Browser mock rules',
    );
    if (!ok) _snack('Export failed');
  }

  Future<void> _importMocks() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final ctrl = TextEditingController(text: clip?.text ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import mock rules'),
        content: TextField(
          controller: ctrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Paste exported JSON (a list of rules)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Import')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;
    try {
      final rules = parseMockRules(jsonDecode(text));
      if (rules.isEmpty) {
        _snack('No valid rules found');
        return;
      }
      final n = ref.read(networkMocksProvider.notifier).importRules(rules);
      _snack('Imported $n rule${n == 1 ? '' : 's'}');
    } on FormatException {
      _snack('Not valid JSON');
    }
  }

  void _showMockEditor(MockRule? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MockEditor(
        initial: existing,
        onSave: (rule) => ref.read(networkMocksProvider.notifier).upsert(rule),
      ),
    );
  }
}

class _MockEditor extends StatefulWidget {
  final MockRule? initial;
  final void Function(MockRule) onSave;
  const _MockEditor({required this.initial, required this.onSave});

  @override
  State<_MockEditor> createState() => _MockEditorState();
}

class _MockEditorState extends State<_MockEditor> {
  late final _pattern = TextEditingController(text: widget.initial?.pattern ?? '');
  late final _status = TextEditingController(text: '${widget.initial?.status ?? 200}');
  late final _delay = TextEditingController(text: '${widget.initial?.delayMs ?? 0}');
  late final _body = TextEditingController(text: widget.initial?.body ?? '');
  late final _contentType = TextEditingController(text: widget.initial?.contentType ?? 'application/json');
  late bool _isRegex = widget.initial?.isRegex ?? false;
  late String _method = widget.initial?.method ?? 'ANY';
  String? _error;

  @override
  void dispose() {
    for (final c in [_pattern, _status, _delay, _body, _contentType]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final rule = MockRule(
      id: widget.initial?.id ?? MockRule.newId(),
      pattern: _pattern.text.trim(),
      isRegex: _isRegex,
      method: _method,
      status: int.tryParse(_status.text.trim()) ?? -1,
      delayMs: int.tryParse(_delay.text.trim()) ?? -1,
      body: _body.text,
      contentType: _contentType.text.trim().isEmpty ? 'application/json' : _contentType.text.trim(),
      enabled: widget.initial?.enabled ?? true,
    );
    final err = rule.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    widget.onSave(rule);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initial == null ? 'New mock rule' : 'Edit mock rule',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _pattern,
              decoration: InputDecoration(
                labelText: _isRegex ? 'URL regex (e.g. /api/users/\\d+)' : 'URL contains (e.g. /api/login)',
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Regular expression'),
              value: _isRegex,
              onChanged: (v) => setState(() => _isRegex = v),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
                    items: [for (final m in MockRule.methods) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => _method = v ?? 'ANY'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _status,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _delay,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Delay ms', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final s in const [200, 201, 204, 400, 401, 403, 404, 429, 500, 503])
                  ActionChip(label: Text('$s'), onPressed: () => setState(() => _status.text = '$s')),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentType,
              decoration: const InputDecoration(labelText: 'Content-Type', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _body,
              maxLines: 8,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(labelText: 'Response body', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _save, child: const Text('Save rule')),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String title;
  final String value;

  const _DetailRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _HeadersSection extends StatelessWidget {
  final String title;
  final Map<String, String> headers;

  const _HeadersSection({required this.title, required this.headers});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('$title (${headers.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
      children: headers.isEmpty
          ? [const ListTile(dense: true, title: Text('None captured'))]
          : [
              for (final e in headers.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText.rich(
                    TextSpan(children: [
                      TextSpan(text: '${e.key}: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: e.value),
                    ]),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
            ],
    );
  }
}

class _BodySection extends StatelessWidget {
  final String title;
  final String? body;
  final Future<void> Function(String text, String what) onCopy;

  const _BodySection({required this.title, required this.body, required this.onCopy});

  /// Pretty-prints JSON bodies; leaves anything else untouched.
  static String pretty(String text) {
    final t = text.trimLeft();
    if (!(t.startsWith('{') || t.startsWith('['))) return text;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = body;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (value != null && value.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => onCopy(value, title),
                ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              (value == null || value.isEmpty) ? 'None' : pretty(value),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
