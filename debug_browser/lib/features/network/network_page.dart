import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';

class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  String _filter = '';

  Color _getStatusColor(int status) {
    if (status >= 200 && status < 300) return Colors.greenAccent;
    if (status >= 300 && status < 400) return Colors.orangeAccent;
    if (status >= 400) return Colors.redAccent;
    return Colors.grey;
  }

  void _showDetails(NetworkRequest req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                controller: scrollController,
                children: [
                  Text('Request Details', style: Theme.of(context).textTheme.titleLarge),
                  const Divider(),
                  _DetailRow(title: 'URL', value: req.url),
                  _DetailRow(title: 'Method', value: req.method),
                  _DetailRow(title: 'Status', value: req.status.toString()),
                  _DetailRow(title: 'Duration', value: '\${req.duration} ms'),
                  _DetailRow(title: 'Type', value: req.type.toUpperCase()),
                  if (req.error != null) _DetailRow(title: 'Error', value: req.error!),
                  const SizedBox(height: 16),
                  const Text('Request Body', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    padding: const EdgeInsets.all(8),
                    color: Colors.black26,
                    child: Text(req.requestBody ?? 'None', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                  const Text('Response Body', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 16),
                    padding: const EdgeInsets.all(8),
                    color: Colors.black26,
                    child: Text(req.responseBody ?? 'None', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(networkRequestsProvider);
    final filtered = requests.where((req) => 
      req.url.toLowerCase().contains(_filter.toLowerCase()) || 
      req.method.toLowerCase().contains(_filter.toLowerCase())
    ).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Network Inspector'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Live Traffic'),
              Tab(text: 'API Mocks'),
            ],
          ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref.read(networkRequestsProvider.notifier).clear();
            },
          ),
        ],
        ),
        body: TabBarView(
          children: [
            _buildLiveTraffic(context, filtered),
            _buildMocksTab(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTraffic(BuildContext context, List<NetworkRequest> filtered) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Filter requests...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: (value) {
              setState(() {
                _filter = value;
              });
            },
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No network requests'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, index) {
                    final req = filtered[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        req.url, 
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('\${req.method} • \${req.duration} ms'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(req.status).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          req.status.toString(),
                          style: TextStyle(color: _getStatusColor(req.status), fontWeight: FontWeight.bold),
                        ),
                      ),
                      onTap: () => _showDetails(req),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMocksTab(BuildContext context, WidgetRef ref) {
    final mocks = ref.watch(networkMocksProvider);
    
    return Scaffold(
      body: mocks.isEmpty
          ? const Center(child: Text('No API Mocks. Add one below.'))
          : ListView.builder(
              itemCount: mocks.length,
              itemBuilder: (context, index) {
                final pattern = mocks.keys.elementAt(index);
                final response = mocks[pattern]!;
                return ListTile(
                  title: Text(pattern, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  subtitle: Text(response, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      ref.read(networkMocksProvider.notifier).removeMock(pattern);
                    },
                  ),
                  onTap: () => _showAddMockDialog(context, ref, initialPattern: pattern, initialResponse: response),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddMockDialog(context, ref),
      ),
    );
  }

  void _showAddMockDialog(BuildContext context, WidgetRef ref, {String initialPattern = '', String initialResponse = ''}) {
    final patternCtrl = TextEditingController(text: initialPattern);
    final responseCtrl = TextEditingController(text: initialResponse);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add API Mock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: patternCtrl,
                decoration: const InputDecoration(labelText: 'URL Pattern (e.g. /api/login)'),
              ),
              TextField(
                controller: responseCtrl,
                decoration: const InputDecoration(labelText: 'JSON Response Body'),
                maxLines: 5,
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
                if (patternCtrl.text.isNotEmpty) {
                  ref.read(networkMocksProvider.notifier).addMock(patternCtrl.text, responseCtrl.text);
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String title;
  final String value;
  
  const _DetailRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: value));
              },
              child: Text(value),
            ),
          ),
        ],
      ),
    );
  }
}
