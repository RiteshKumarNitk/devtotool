import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';

enum StorageKind { local, session, cookie }

/// Parses `document.cookie` ("a=1; b=x=y") into ordered name/value pairs.
List<MapEntry<String, String>> parseCookieString(String cookies) {
  return [
    for (final part in cookies.split(';'))
      if (part.trim().isNotEmpty)
        () {
          final p = part.trim();
          final i = p.indexOf('=');
          return i < 0 ? MapEntry(p, '') : MapEntry(p.substring(0, i), p.substring(i + 1));
        }(),
  ];
}

/// JS that re-sends storage state to Flutter after a change.
const _reportStorageJs = '''
  window.DebugBridge && window.DebugBridge.postMessage(JSON.stringify({
    type: 'storage',
    data: {
      localStorage: JSON.stringify(localStorage),
      sessionStorage: JSON.stringify(sessionStorage),
      cookies: document.cookie
    }
  }));
''';

class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  StorageKind get _kind => StorageKind.values[_tabs.index];

  WebViewController? get _controller => ref.read(webViewControllerProvider);

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _runAndRefresh(String js) async {
    final c = _controller;
    if (c == null) {
      _snack('WebView not ready');
      return;
    }
    try {
      await c.runJavaScript('(function(){ $js })(); $_reportStorageJs');
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  void _refresh() => _runAndRefresh('');

  String _obj(StorageKind k) => k == StorageKind.session ? 'sessionStorage' : 'localStorage';

  Future<void> _save(StorageKind kind, String key, String value, {String path = '/', int? maxAgeDays}) async {
    if (key.trim().isEmpty) return;
    if (kind == StorageKind.cookie) {
      final attrs = StringBuffer('; path=$path');
      if (maxAgeDays != null) attrs.write('; max-age=${maxAgeDays * 86400}');
      await _runAndRefresh('document.cookie = ${jsString('${key.trim()}=$value$attrs')};');
    } else {
      await _runAndRefresh('${_obj(kind)}.setItem(${jsString(key)}, ${jsString(value)});');
    }
  }

  Future<void> _delete(StorageKind kind, String key) async {
    if (kind == StorageKind.cookie) {
      // Expire on the root and current path, with and without the domain.
      final k = jsString(key);
      await _runAndRefresh('''
        var exp = '=; expires=Thu, 01 Jan 1970 00:00:00 GMT';
        var paths = ['/', location.pathname];
        var host = location.hostname;
        var domains = ['', '; domain=' + host, '; domain=.' + host.split('.').slice(-2).join('.')];
        paths.forEach(function (p) { domains.forEach(function (d) {
          document.cookie = $k + exp + '; path=' + p + d;
        }); });
      ''');
    } else {
      await _runAndRefresh('${_obj(kind)}.removeItem(${jsString(key)});');
    }
  }

  Future<void> _clearAll(StorageKind kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Clear all ${_label(kind)}?'),
        content: kind == StorageKind.cookie
            ? const Text('Clears every cookie in this WebView, including HttpOnly cookies on other sites.')
            : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    if (kind == StorageKind.cookie) {
      await WebViewCookieManager().clearCookies();
      await _runAndRefresh('');
    } else {
      await _runAndRefresh('${_obj(kind)}.clear();');
    }
  }

  String _label(StorageKind k) => switch (k) {
        StorageKind.local => 'localStorage',
        StorageKind.session => 'sessionStorage',
        StorageKind.cookie => 'cookies',
      };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(storageProvider);
    Map<String, dynamic> decode(Object? v) {
      if (v is! String) return const {};
      try {
        final d = jsonDecode(v);
        return d is Map ? Map<String, dynamic>.from(d) : const {};
      } catch (_) {
        return const {};
      }
    }

    final local = decode(data['localStorage']);
    final session = decode(data['sessionStorage']);
    final cookies = parseCookieString('${data['cookies'] ?? ''}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            tooltip: 'Clear all ${_label(_kind)}',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _clearAll(_kind),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Local (${local.length})'),
            Tab(text: 'Session (${session.length})'),
            Tab(text: 'Cookies (${cookies.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter keys and values',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _list(StorageKind.local, local.entries.map((e) => MapEntry(e.key, '${e.value}')).toList()),
                _list(StorageKind.session, session.entries.map((e) => MapEntry(e.key, '${e.value}')).toList()),
                Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      'HttpOnly cookies are hidden from page scripts, so they are not listed here.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  Expanded(child: _list(StorageKind.cookie, cookies)),
                ]),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to ${_label(_kind)}',
        child: const Icon(Icons.add),
        onPressed: () => _showEditor(_kind, '', ''),
      ),
    );
  }

  Widget _list(StorageKind kind, List<MapEntry<String, String>> entries) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? entries
        : entries.where((e) => e.key.toLowerCase().contains(q) || e.value.toLowerCase().contains(q)).toList();
    if (visible.isEmpty) {
      return Center(child: Text(entries.isEmpty ? 'No ${_label(kind)} for this page' : 'No matches'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = visible[i];
        return ListTile(
          title: Text(e.key,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: kind == StorageKind.cookie ? Colors.teal : Colors.blueAccent,
              )),
          subtitle: Text(e.value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          onTap: () => _showValue(kind, e.key, e.value),
          trailing: IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(kind, e.key),
          ),
        );
      },
    );
  }

  void _showValue(StorageKind kind, String key, String value) {
    String pretty = value;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map || decoded is List) pretty = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(key, style: const TextStyle(fontFamily: 'monospace')),
        content: SingleChildScrollView(child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              Navigator.pop(context);
              _snack('Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditor(kind, key, value);
            },
            child: const Text('Edit'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showEditor(StorageKind kind, String initialKey, String initialValue) {
    final keyCtrl = TextEditingController(text: initialKey);
    final valCtrl = TextEditingController(text: initialValue);
    final pathCtrl = TextEditingController(text: '/');
    final daysCtrl = TextEditingController();
    final isCookie = kind == StorageKind.cookie;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initialKey.isEmpty ? 'Add to ${_label(kind)}' : 'Edit ${_label(kind)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: InputDecoration(labelText: isCookie ? 'Name' : 'Key'),
                enabled: initialKey.isEmpty,
              ),
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                maxLines: 4,
                minLines: 1,
              ),
              if (isCookie) ...[
                TextField(controller: pathCtrl, decoration: const InputDecoration(labelText: 'Path')),
                TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Expires in days (empty = session cookie)'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (keyCtrl.text.trim().isEmpty) return;
              if (isCookie && (keyCtrl.text.contains(RegExp(r'[=;,\s]')) || valCtrl.text.contains(';'))) {
                _snack('Cookie names cannot contain = ; , or spaces, and values cannot contain ;');
                return;
              }
              _save(kind, keyCtrl.text, valCtrl.text,
                  path: pathCtrl.text.trim().isEmpty ? '/' : pathCtrl.text.trim(),
                  maxAgeDays: int.tryParse(daysCtrl.text.trim()));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() {
      for (final c in [keyCtrl, valCtrl, pathCtrl, daysCtrl]) {
        c.dispose();
      }
    });
  }
}
