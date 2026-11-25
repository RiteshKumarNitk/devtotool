import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/tool_providers.dart';
import '../console/console_page.dart';
import '../dom/dom_page.dart';
import '../more/more_page.dart';
import '../network/network_page.dart';
import '../performance/performance_page.dart';
import '../storage/storage_page.dart';

/// Developer tools for the active tab. Opened from the browser menu or the
/// debug bubble; the back arrow returns to the page.
class DevToolsPage extends ConsumerWidget {
  const DevToolsPage({super.key});

  static const _panels = <Widget>[
    ConsolePage(),
    NetworkPage(),
    StoragePage(),
    DOMPage(),
    PerformancePage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    // homeTabProvider: 1..6 are dev-tools panels (0 = browser).
    final index = (tab - 1).clamp(0, _panels.length - 1);
    final errors = ref.watch(consoleLogsProvider.select((l) => l.where((x) => x.level == 'error').length));
    final failed = ref.watch(networkRequestsProvider.select((l) => l.where((r) => r.failed || r.status >= 400).length));

    Widget badged(IconData icon, int n) => Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          child: Icon(icon),
        );

    return Scaffold(
      body: IndexedStack(index: index, children: _panels),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).select(i + 1),
        destinations: [
          NavigationDestination(icon: badged(Icons.terminal, errors), label: 'Console'),
          NavigationDestination(icon: badged(Icons.wifi, failed), label: 'Network'),
          const NavigationDestination(icon: Icon(Icons.storage), label: 'Storage'),
          const NavigationDestination(icon: Icon(Icons.account_tree), label: 'DOM'),
          const NavigationDestination(icon: Icon(Icons.speed), label: 'Perf'),
          const NavigationDestination(icon: Icon(Icons.apps), label: 'Tools'),
        ],
      ),
    );
  }
}
