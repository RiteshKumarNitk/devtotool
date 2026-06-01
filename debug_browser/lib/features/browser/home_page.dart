import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'browser_page.dart';
import '../console/console_page.dart';
import '../network/network_page.dart';
import '../storage/storage_page.dart';
import '../device/device_page.dart';
import '../performance/performance_page.dart';
import '../dom/dom_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const BrowserPage(),
    const ConsolePage(),
    const NetworkPage(),
    const StoragePage(),
    const DOMPage(),
    const DevicePage(),
    const PerformancePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.language),
            label: 'Browser',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.code),
            label: 'Console',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi),
            label: 'Network',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storage),
            label: 'Storage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree),
            label: 'DOM',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices),
            label: 'Device',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Perf',
          ),
        ],
      ),
    );
  }
}
