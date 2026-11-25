import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
import '../../core/tabs_provider.dart';
import 'user_scripts_page.dart';

class ExtensionsPage extends ConsumerWidget {
  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(extensionsProvider);
    final n = ref.read(extensionsProvider.notifier);
    final total = ref.watch(blockedTotalProvider);
    final scripts = ref.watch(userScriptsProvider);
    final active = scripts.where((x) => x.enabled).length;
    final overrides = s.sites.length;

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(t.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  )),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: ListView(
        children: [
          if (s.blocker)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              color: Colors.green.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.shield, color: Colors.green),
                title: Text('$total ad and tracker request${total == 1 ? '' : 's'} blocked'),
                subtitle: const Text('Since the app started'),
              ),
            ),
          header('Privacy'),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Block ads and trackers'),
            subtitle: Text('${defaultBlockDomains.length} known ad and tracking networks, on every site'),
            value: s.blocker,
            onChanged: (v) => n.update((x) => x.copyWith(blocker: v)),
          ),
          SwitchListTile(
            secondary: const SizedBox(width: 24),
            title: const Text('Hide empty ad spaces'),
            subtitle: const Text('Removes leftover ad boxes from the page'),
            value: s.cosmetic,
            onChanged: s.blocker ? (v) => n.update((x) => x.copyWith(cosmetic: v)) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.block),
            title: const Text('Block pop-ups and redirects'),
            subtitle: const Text('Stops pop-unders, ad redirects and invisible click-stealing layers'),
            value: s.popups,
            onChanged: (v) => n.update((x) => x.copyWith(popups: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.image_not_supported_outlined),
            title: const Text('Data saver'),
            subtitle: const Text('Don’t load images. Pages load faster on slow or expensive connections.'),
            value: s.dataSaver,
            onChanged: (v) => n.update((x) => x.copyWith(dataSaver: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.text_fields),
            title: const Text('Readable text'),
            subtitle: const Text('Clearer font with more letter and line spacing on every site'),
            value: s.readableText,
            onChanged: (v) => n.update((x) => x.copyWith(readableText: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.cookie_outlined),
            title: const Text('Hide cookie banners'),
            subtitle: const Text('Hides common consent pop-ups. Sites still see no consent given.'),
            value: s.cookies,
            onChanged: (v) => n.update((x) => x.copyWith(cookies: v)),
          ),
          header('Appearance'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode for all websites'),
            subtitle: const Text('Sites that are already dark are left alone'),
            value: s.dark,
            onChanged: (v) => n.update((x) => x.copyWith(dark: v)),
          ),
          const ListTile(
            leading: Icon(Icons.chrome_reader_mode_outlined),
            title: Text('Reader mode'),
            subtitle: Text('Open any article, then ⋮ → Reader mode'),
          ),
          const ListTile(
            leading: Icon(Icons.format_size),
            title: Text('Text size per site'),
            subtitle: Text('Tap the shield in the address bar on any site'),
          ),
          header('Power users'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('User scripts'),
            subtitle: Text(scripts.isEmpty ? 'Run your own JavaScript and CSS on sites you choose' : '$active of ${scripts.length} enabled'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserScriptsPage())),
          ),
          if (overrides > 0)
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Per-site settings'),
              subtitle: Text('$overrides site${overrides == 1 ? '' : 's'} with custom settings'),
              trailing: TextButton(
                onPressed: () => n.update((x) => x.copyWith(sites: const {})),
                child: const Text('Reset all'),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              'Extensions run inside this browser only. YouTube is always excluded from blocking. '
              'If a site breaks, turn extensions off for that site from the shield in the address bar.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
