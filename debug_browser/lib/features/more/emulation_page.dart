import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/tool_providers.dart';

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
          const SizedBox(height: 16),
          const Text(
            'User-Agent presets are in the browser menu (⋮). Network throttling is in the Network tab.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
