import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';

const userAgentPresets = {
  'Default (this device)': 'default',
  'iPhone (Safari)':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  'Android (Chrome)':
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
  'Desktop Chrome':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  'Googlebot': 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
};

class EmulationPage extends ConsumerStatefulWidget {
  const EmulationPage({super.key});

  @override
  ConsumerState<EmulationPage> createState() => _EmulationPageState();
}

class _EmulationPageState extends ConsumerState<EmulationPage> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  String? _geoError;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _applyCustomGeo() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _geoError = 'Latitude must be -90…90 and longitude -180…180');
      return;
    }
    setState(() => _geoError = null);
    ref.read(geoOverrideProvider.notifier).set(GeoOverride(lat, lng, 'Custom'));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = ref.watch(viewportProvider);
    final geo = ref.watch(geoOverrideProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Device emulation')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Viewport', style: theme.textTheme.titleMedium),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Renders the page at the device width (scaled to fit) so media queries and layouts behave as on that device.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          for (final p in ViewportPreset.values)
            ListTile(
              dense: true,
              selected: p == viewport,
              leading: Icon(p == viewport ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(p.label),
              subtitle: p.width == null ? null : Text('${p.width!.toInt()} × ${p.height!.toInt()}'),
              onTap: () => ref.read(viewportProvider.notifier).set(p),
            ),
          const Divider(height: 32),
          Row(children: [
            Expanded(child: Text('Geolocation', style: theme.textTheme.titleMedium)),
            if (geo != null)
              TextButton(
                onPressed: () => ref.read(geoOverrideProvider.notifier).set(null),
                child: const Text('Use real location'),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              geo == null
                  ? 'Not overridden. Pages get the real device location (with permission).'
                  : 'Pages receive ${geo.label} (${geo.lat}, ${geo.lng}). Session-only.',
              style: TextStyle(fontSize: 12, color: geo == null ? Colors.grey : Colors.orange),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in GeoOverride.presets)
                ChoiceChip(
                  label: Text(g.label),
                  selected: geo?.label == g.label,
                  onSelected: (_) => ref.read(geoOverrideProvider.notifier).set(g),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _applyCustomGeo, child: const Text('Set')),
          ]),
          if (_geoError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_geoError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ),
          const Divider(height: 32),
          Text('User-Agent', style: theme.textTheme.titleMedium),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text('Applies to all tabs and reloads the page. "Desktop site" in the browser menu is a shortcut.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          for (final e in userAgentPresets.entries)
            ListTile(
              dense: true,
              selected: ref.watch(userAgentProvider) == e.value,
              leading: Icon(ref.watch(userAgentProvider) == e.value ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(e.key),
              subtitle: e.value == 'default' ? null : Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => ref.read(userAgentProvider.notifier).setAgent(e.value),
            ),
          const SizedBox(height: 8),
          const Text('Network throttling is in Developer tools → Network.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
