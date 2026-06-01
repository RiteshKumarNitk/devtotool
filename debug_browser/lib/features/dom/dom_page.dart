import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class DOMPage extends ConsumerStatefulWidget {
  const DOMPage({super.key});

  @override
  ConsumerState<DOMPage> createState() => _DOMPageState();
}

class _DOMPageState extends ConsumerState<DOMPage> {
  bool _isInspectorActive = false;

  void _toggleInspector() {
    final controller = ref.read(webViewControllerProvider);
    if (controller == null) return;

    setState(() {
      _isInspectorActive = !_isInspectorActive;
    });

    if (_isInspectorActive) {
      controller.runJavaScript('window.enableInspector()');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap any element in Browser to inspect')));
    } else {
      controller.runJavaScript('window.disableInspector()');
      ref.read(domTreeProvider.notifier).setTree({});
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodeInfo = ref.watch(domTreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DOM Inspector'),
        actions: [
          IconButton(
            icon: Icon(
              _isInspectorActive ? Icons.stop_screen_share : Icons.screen_share,
              color: _isInspectorActive ? Colors.redAccent : null,
            ),
            onPressed: _toggleInspector,
            tooltip: 'Toggle Element Inspector',
          ),
        ],
      ),
      body: nodeInfo == null || nodeInfo.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.touch_app, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Click the icon above to enable Inspector.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _toggleInspector,
                    child: Text(_isInspectorActive ? 'Disable Inspector' : 'Enable Inspector'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildHeader(nodeInfo),
                const Divider(height: 32),
                const Text('Computed Styles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                _buildStylesList(nodeInfo['styles'] as Map<String, dynamic>? ?? {}),
              ],
            ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> info) {
    return Card(
      color: Theme.of(context).colorScheme.primary.withAlpha(20),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "< ${info['tagName']} >",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.blueAccent, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            if (info['id'] != null && info['id'].toString().isNotEmpty)
              Text("ID: #${info['id']}", style: const TextStyle(fontSize: 16, fontFamily: 'monospace')),
            if (info['className'] != null && info['className'].toString().isNotEmpty)
              Text("Class: .${info['className']}", style: const TextStyle(fontSize: 16, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            if (info['text'] != null && info['text'].toString().isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black12,
                child: Text('"${info['text']}..."', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStylesList(Map<String, dynamic> styles) {
    return Column(
      children: styles.entries.map((e) {
        return ListTile(
          dense: true,
          title: Text(e.key, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          trailing: Text(e.value.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: "${e.key}: ${e.value};"));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied ${e.key}")));
          },
        );
      }).toList(),
    );
  }
}
