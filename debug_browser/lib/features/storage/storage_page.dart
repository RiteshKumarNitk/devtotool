import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';

class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  @override
  Widget build(BuildContext context) {
    final storageData = ref.watch(storageProvider);

    Map<String, dynamic> local = {};
    Map<String, dynamic> session = {};
    String cookies = '';

    try {
      if (storageData['localStorage'] != null) {
        local = jsonDecode(storageData['localStorage']);
      }
      if (storageData['sessionStorage'] != null) {
        session = jsonDecode(storageData['sessionStorage']);
      }
      cookies = storageData['cookies'] ?? '';
    } catch (e) {
      debugPrint('Error parsing storage data');
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Storage Inspector'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Local'),
              Tab(text: 'Session'),
              Tab(text: 'Cookies'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStorageList(local, 'localStorage'),
            _buildStorageList(session, 'sessionStorage'),
            _buildCookiesList(cookies),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () => _showEditDialog('localStorage', '', ''),
        ),
      ),
    );
  }

  Widget _buildStorageList(Map<String, dynamic> data, String storageType) {
    if (data.isEmpty) {
      return const Center(child: Text('No data found'));
    }

    final keys = data.keys.toList();
    return ListView.separated(
      itemCount: keys.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final key = keys[index];
        final value = data[key].toString();
        return ListTile(
          title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            _showValueDialog(storageType, key, value);
          },
        );
      },
    );
  }

  Widget _buildCookiesList(String cookies) {
    if (cookies.isEmpty) {
      return const Center(child: Text('No cookies found'));
    }

    final cookieList = cookies.split(';');
    return ListView.separated(
      itemCount: cookieList.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final cookie = cookieList[index].trim();
        final parts = cookie.split('=');
        final key = parts[0];
        final value = parts.length > 1 ? parts.sublist(1).join('=') : '';

        return ListTile(
          title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
          subtitle: Text(value),
          onTap: () {
            _showValueDialog('cookies', key, value);
          },
        );
      },
    );
  }

  void _showValueDialog(String type, String key, String value) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(key),
          content: SingleChildScrollView(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteKey(type, key);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showEditDialog(type, key, value);
              },
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showEditDialog(String type, String initialKey, String initialValue) {
    final keyCtrl = TextEditingController(text: initialKey);
    final valCtrl = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(initialKey.isEmpty ? 'Add to \$type' : 'Edit \$type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Key'),
                enabled: initialKey.isEmpty,
              ),
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _saveKey(type, keyCtrl.text, valCtrl.text);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  /// Whitelists the storage object name so it can't inject script.
  String _storageObject(String type) =>
      type == 'sessionStorage' ? 'sessionStorage' : 'localStorage';

  void _saveKey(String type, String key, String value) {
    final controller = ref.read(webViewControllerProvider);
    if (controller != null) {
      controller.runJavaScript("""
        ${_storageObject(type)}.setItem(${jsString(key)}, ${jsString(value)});
        window.DebugBridge.postMessage(JSON.stringify({
          type: 'storage', 
          data: {
            localStorage: JSON.stringify(localStorage),
            sessionStorage: JSON.stringify(sessionStorage),
            cookies: document.cookie
          }
        }));
      """);
    }
  }

  void _deleteKey(String type, String key) {
    final controller = ref.read(webViewControllerProvider);
    if (controller != null) {
      controller.runJavaScript("""
        ${_storageObject(type)}.removeItem(${jsString(key)});
        window.DebugBridge.postMessage(JSON.stringify({
          type: 'storage', 
          data: {
            localStorage: JSON.stringify(localStorage),
            sessionStorage: JSON.stringify(sessionStorage),
            cookies: document.cookie
          }
        }));
      """);
    }
  }
}
