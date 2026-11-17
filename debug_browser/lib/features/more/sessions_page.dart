import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/tool_providers.dart';

class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key});

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  late Future<List<SavedSession>> _sessions = SessionStore.list();

  void _reload() => setState(() => _sessions = SessionStore.list());

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _save() async {
    final page = ref.read(currentPageProvider);
    final ctrl = TextEditingController(text: page.title.isNotEmpty ? page.title : 'Session');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save current session'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null) return;
    try {
      await SessionStore.save(ref, name.trim().isEmpty ? 'Session' : name.trim());
      _snack('Session saved');
      _reload();
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _load(SavedSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Load "${s.name}"?'),
        content: const Text('This replaces the current Console and Network data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Load')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SessionStore.load(ref, s.file);
      _snack('Loaded ${s.logCount} logs and ${s.requestCount} requests');
    } catch (e) {
      _snack('Load failed: $e');
    }
  }

  Future<void> _delete(SavedSession s) async {
    try {
      await s.file.delete();
    } catch (_) {}
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Save current'),
      ),
      body: FutureBuilder<List<SavedSession>>(
        future: _sessions,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Could not read sessions: ${snap.error}'));
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Save the current console and network data to compare or revisit later. '
                  'Sessions are stored only on this device.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(s.name),
                subtitle: Text(
                    '${DateFormat('d MMM yyyy, HH:mm').format(s.savedAt)} • ${s.logCount} logs • ${s.requestCount} requests'),
                onTap: () => _load(s),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'share') {
                      await SharePlus.instance.share(ShareParams(
                        files: [XFile(s.file.path, mimeType: 'application/json')],
                        text: 'Debug Browser session: ${s.name}',
                      ));
                    } else if (v == 'delete') {
                      await _delete(s);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
