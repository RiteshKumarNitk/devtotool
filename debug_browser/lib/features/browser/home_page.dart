import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';
import 'browser_page.dart';
import 'debug_bubble.dart';
import '../console/console_page.dart';
import '../network/network_page.dart';
import '../storage/storage_page.dart';
import '../performance/performance_page.dart';
import '../dom/dom_page.dart';
import '../more/more_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const _pages = <Widget>[
    BrowserPage(),
    ConsolePage(),
    NetworkPage(),
    StoragePage(),
    DOMPage(),
    PerformancePage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider);
    final errorCount = ref.watch(consoleLogsProvider.select((l) => l.where((x) => x.level == 'error').length));
    final failedCount =
        ref.watch(networkRequestsProvider.select((l) => l.where((r) => r.failed || r.status >= 400).length));

    return PopScope(
      // Android back: go back in the page first, then return to the Browser tab.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (index != AppTab.browser) {
          ref.read(homeTabProvider.notifier).select(AppTab.browser);
          return;
        }
        final c = ref.read(webViewControllerProvider);
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(index: index, children: _pages),
            if (index == AppTab.browser) const DebugBubble(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).select(i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.language), label: 'Browser'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: errorCount > 0,
                label: Text(errorCount > 99 ? '99+' : '$errorCount'),
                child: const Icon(Icons.terminal),
              ),
              label: 'Console',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: failedCount > 0,
                label: Text(failedCount > 99 ? '99+' : '$failedCount'),
                child: const Icon(Icons.wifi),
              ),
              label: 'Network',
            ),
            const NavigationDestination(icon: Icon(Icons.storage), label: 'Storage'),
            const NavigationDestination(icon: Icon(Icons.account_tree), label: 'DOM'),
            const NavigationDestination(icon: Icon(Icons.speed), label: 'Perf'),
            const NavigationDestination(icon: Icon(Icons.apps), label: 'More'),
          ],
        ),
      ),
    );
  }
}
