import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/browser_settings.dart';
import '../../core/tabs_provider.dart';

/// Routes all browser traffic through a user-supplied proxy, e.g. the
/// HTTP/SOCKS5 proxy offered by most VPN providers. Not a system VPN.
class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  late final ProxySettings _initial = ref.read(proxySettingsProvider);
  late ProxyType _type = _initial.type;
  late final _host = TextEditingController(text: _initial.host);
  late final _port = TextEditingController(text: _initial.host.isEmpty ? '' : '${_initial.port}');
  late final _user = TextEditingController(text: _initial.username);
  late final _pass = TextEditingController(text: _initial.password);
  late final _bypass = TextEditingController(text: _initial.bypass.join(', '));
  final _paste = TextEditingController();
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass, _bypass, _paste]) {
      c.dispose();
    }
    super.dispose();
  }

  ProxySettings _fromForm({required bool enabled}) => ProxySettings(
        enabled: enabled,
        type: _type,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? -1,
        username: _user.text.trim(),
        password: _pass.text,
        bypass: _bypass.text.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList(),
      );

  void _applyPaste() {
    final p = parseProxyString(_paste.text);
    if (p == null) {
      setState(() => _error = 'Could not read that. Use host:port or user:pass@host:port.');
      return;
    }
    setState(() {
      _type = p.type;
      _host.text = p.host;
      _port.text = '${p.port}';
      _user.text = p.username;
      _pass.text = p.password;
      _paste.clear();
      _error = null;
    });
  }

  void _connect() {
    final p = _fromForm(enabled: true);
    final err = p.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (p.type == ProxyType.socks5 && p.hasCredentials) {
      setState(() => _error = 'Android WebView cannot sign in to SOCKS5 proxies. '
          'Use the provider\'s HTTP proxy, or an IP-whitelisted SOCKS5 proxy.');
      return;
    }
    setState(() => _error = null);
    ref.read(proxySettingsProvider.notifier).save(p);
    FocusScope.of(context).unfocus();
  }

  void _disconnect() => ref.read(proxySettingsProvider.notifier).save(_fromForm(enabled: false));

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(proxySettingsProvider);
    final status = ref.watch(proxyStatusProvider);
    final scheme = Theme.of(context).colorScheme;
    final (statusText, statusColor, statusIcon) = switch (status) {
      ProxyStatus.active => ('Connected through ${saved.type.label} proxy ${saved.host}:${saved.port}', Colors.green, Icons.vpn_lock),
      ProxyStatus.unsupported => ('This device\'s Android System WebView doesn\'t support proxies. Update it from the Play Store.', Colors.orange, Icons.warning_amber),
      ProxyStatus.failed => ('The proxy could not be applied. Check the address and try again.', scheme.error, Icons.error_outline),
      ProxyStatus.off => ('Off. Browsing uses your normal connection.', Colors.grey, Icons.vpn_lock_outlined),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Proxy / VPN')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: statusColor.withValues(alpha: 0.12),
            child: ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: Text(status == ProxyStatus.active ? 'Protected' : 'Not connected'),
              subtitle: Text(statusText),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sends all pages you open in this browser through a proxy server, for example the HTTP or SOCKS5 '
            'proxy your VPN provider gives you. Only this browser is affected, not other apps. '
            'This app does not provide proxy servers itself.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _paste,
            decoration: InputDecoration(
              labelText: 'Paste from your provider (optional)',
              hintText: 'socks5://user:pass@host:1080',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.auto_fix_high), tooltip: 'Fill in', onPressed: _applyPaste),
            ),
            onSubmitted: (_) => _applyPaste(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ProxyType>(
            segments: [for (final t in ProxyType.values) ButtonSegment(value: t, label: Text(t.label))],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _host,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Host', hintText: 'proxy.example.com', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Password (optional)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bypass,
            decoration: const InputDecoration(
              labelText: 'Don\'t use proxy for (optional)',
              hintText: '*.local, 192.168.0.0/16',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.vpn_lock),
                label: Text(saved.enabled ? 'Update' : 'Connect'),
              ),
            ),
            if (saved.enabled) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect')),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.travel_explore),
            label: const Text('Check my IP address'),
            onPressed: () {
              ref.read(tabsProvider.notifier).newTab(url: 'https://api.ipify.org/?format=json');
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Your proxy password is stored on this device only.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
