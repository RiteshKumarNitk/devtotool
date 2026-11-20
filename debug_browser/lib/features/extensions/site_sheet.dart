import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
import '../../core/tabs_provider.dart';
import 'extensions_page.dart';

/// Per-site controls behind the shield in the address bar.
void showSiteControls(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => Consumer(builder: (sheet, ref, _) {
      final tab = ref.watch(tabsProvider).active;
      final s = ref.watch(extensionsProvider);
      final n = ref.read(extensionsProvider.notifier);
      final host = siteKey(tab.url);
      final exempt = isBlockerExempt(host);
      final site = s.site(host);
      final zoom = s.textZoom(host);
      final top = tab.blockedDomains.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      void setSite(SiteOverride Function(SiteOverride) f) => n.update((x) => x.withSite(host, f));

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(s.blockerOn(host) ? Icons.shield : Icons.shield_outlined,
                    color: s.blockerOn(host) ? Colors.green : null),
                title: Text(host.isEmpty ? 'This page' : host, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(exempt
                    ? 'Blocking is not available on this site'
                    : s.blockerOn(host)
                        ? '${tab.blockedCount} ad and tracker request${tab.blockedCount == 1 ? '' : 's'} blocked'
                        : 'Blocking is off here'),
              ),
              if (top.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in top.take(8))
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${e.key}  ${e.value}', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('Block ads and trackers on this site'),
                value: s.blockerOn(host),
                onChanged: (!s.blocker || exempt) ? null : (v) => setSite((o) => o.copyWith(blocker: () => v ? null : false)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.block),
                title: const Text('Block pop-ups and redirects on this site'),
                value: s.popupsOn(host),
                onChanged: !s.popups ? null : (v) => setSite((o) => o.copyWith(popups: () => v ? null : false)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode on this site'),
                value: s.darkOn(host),
                onChanged: !s.dark ? null : (v) => setSite((o) => o.copyWith(dark: () => v ? null : false)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cookie_outlined),
                title: const Text('Hide cookie banners on this site'),
                value: s.cookiesOn(host),
                onChanged: !s.cookies ? null : (v) => setSite((o) => o.copyWith(cookies: () => v ? null : false)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  const Icon(Icons.format_size),
                  const SizedBox(width: 16),
                  const Text('Text size'),
                  Expanded(
                    child: Slider(
                      value: zoom.toDouble(),
                      min: 50,
                      max: 200,
                      divisions: 15,
                      label: '$zoom%',
                      onChanged: (v) => setSite((o) => o.copyWith(textZoom: () => v.round() == 100 ? null : v.round())),
                    ),
                  ),
                  SizedBox(width: 48, child: Text('$zoom%', textAlign: TextAlign.end)),
                ]),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.javascript),
                title: const Text('JavaScript on this site'),
                subtitle: Text(s.jsOn(host) ? 'On' : 'Off: most pop-ups and trackers stop; some features may break'),
                value: s.jsOn(host),
                onChanged: (v) => setSite((o) => o.copyWith(js: () => v ? null : false)),
              ),
              if (site.hidden.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.highlight_alt),
                  title: Text('${site.hidden.length} hidden element${site.hidden.length == 1 ? '' : 's'}'),
                  children: [
                    for (final sel in site.hidden)
                      ListTile(
                        dense: true,
                        title: Text(sel, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        trailing: TextButton(
                          onPressed: () => setSite((o) => o.copyWith(hidden: [...o.hidden]..remove(sel))),
                          child: const Text('Show again'),
                        ),
                      ),
                  ],
                ),
              ListTile(
                leading: const Icon(Icons.chrome_reader_mode_outlined),
                title: const Text('Reader mode'),
                onTap: () {
                  Navigator.pop(sheet);
                  ref.read(tabsProvider.notifier).toggleReaderMode();
                },
              ),
              ListTile(
                leading: const Icon(Icons.extension_outlined),
                title: const Text('All extensions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExtensionsPage()));
                },
              ),
              if (!site.isEmpty)
                TextButton(
                  onPressed: () => n.update((x) => x.withSite(host, (_) => const SiteOverride())),
                  child: const Text('Reset settings for this site'),
                ),
            ],
          ),
        ),
      );
    }),
  );
}
