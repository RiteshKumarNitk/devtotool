import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';

class ConsolePage extends ConsumerStatefulWidget {
  const ConsolePage({super.key});

  @override
  ConsumerState<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends ConsumerState<ConsolePage> {
  String _filter = '';
  final TextEditingController _evalController = TextEditingController();

  Color _getColorForLevel(String level) {
    switch (level) {
      case 'error':
        return Colors.redAccent.withOpacity(0.1);
      case 'warn':
        return Colors.orangeAccent.withOpacity(0.1);
      default:
        return Colors.transparent;
    }
  }
  
  Color _getTextColorForLevel(String level) {
    switch (level) {
      case 'error':
        return Colors.redAccent;
      case 'warn':
        return Colors.orangeAccent;
      case 'info':
        return Colors.lightBlueAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(consoleLogsProvider);
    final filteredLogs = logs.where((log) => 
      log.message.toLowerCase().contains(_filter.toLowerCase()) || 
      log.level.toLowerCase().contains(_filter.toLowerCase())
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console Inspector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref.read(consoleLogsProvider.notifier).clear();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter logs...',
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
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: filteredLogs.isEmpty
                ? const Center(child: Text('No logs found'))
                : ListView.separated(
                    itemCount: filteredLogs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      return Container(
                        color: _getColorForLevel(log.level),
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('HH:mm:ss.SSS').format(log.timestamp),
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onLongPress: () {
                                  Clipboard.setData(ClipboardData(text: log.message));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied to clipboard')),
                                  );
                                },
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '[\${log.level.toUpperCase()}] ',
                                        style: TextStyle(
                                          color: _getTextColorForLevel(log.level),
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                        ),
                                      ),
                                      TextSpan(
                                        text: log.message,
                                        style: TextStyle(
                                          color: _getTextColorForLevel(log.level),
                                          fontFamily: 'monospace',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          _buildEvaluator(),
        ],
      ),
    );
  }

  Widget _buildEvaluator() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        children: [
          const Text('>', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _evalController,
              decoration: const InputDecoration(
                hintText: 'Evaluate Javascript...',
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              onSubmitted: (code) => _evaluateJs(code),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blueAccent),
            onPressed: () => _evaluateJs(_evalController.text),
          ),
        ],
      ),
    );
  }

  void _evaluateJs(String code) async {
    if (code.trim().isEmpty) return;
    
    final controller = ref.read(webViewControllerProvider);
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WebView not ready')));
      return;
    }
    
    _evalController.clear();
    
    ref.read(consoleLogsProvider.notifier).addLog(
      ConsoleLog(
        level: 'info',
        message: "> $code",
        timestamp: DateTime.now(),
      )
    );

    try {
      final result = await controller.runJavaScriptReturningResult(code);
      ref.read(consoleLogsProvider.notifier).addLog(
        ConsoleLog(
          level: 'debug',
          message: "< $result",
          timestamp: DateTime.now(),
        )
      );
    } catch (e) {
      ref.read(consoleLogsProvider.notifier).addLog(
        ConsoleLog(
          level: 'error',
          message: "Error: $e",
          timestamp: DateTime.now(),
        )
      );
    }
  }
}
