import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';
import '../more/more_page.dart';

/// Draggable floating bubble over the page: live error / request counts,
/// latest error preview, and one-tap access to the panels.
class DebugBubble extends ConsumerStatefulWidget {
  const DebugBubble({super.key});

  @override
  ConsumerState<DebugBubble> createState() => _DebugBubbleState();
}

class _DebugBubbleState extends ConsumerState<DebugBubble> {
  Offset? _pos; // top-left, relative to the Stack
  static const double _size = 56;

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(builder: (context, ref, _) {
        final logs = ref.watch(consoleLogsProvider);
        final requests = ref.watch(networkRequestsProvider);
        final errors = logs.where((l) => l.level == 'error').toList();
        final failed = requests.where((r) => r.failed || r.status >= 400).toList();

        void go(int tab) {
          Navigator.pop(sheetContext);
          ref.read(homeTabProvider.notifier).select(tab);
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errors.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    errors.last.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.terminal),
                title: const Text('Console'),
                trailing: Text('${logs.length} logs • ${errors.length} errors'),
                onTap: () => go(AppTab.console),
              ),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Network'),
                trailing: Text('${requests.length} requests • ${failed.length} failed'),
                onTap: () => go(AppTab.network),
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('Performance'),
                onTap: () => go(AppTab.performance),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.redAccent),
                title: const Text('Create bug report'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showBugReportDialog(this.context, ref);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errors = ref.watch(consoleLogsProvider.select((l) => l.where((x) => x.level == 'error').length));
    final requests = ref.watch(networkRequestsProvider.select((l) => l.length));
    final throttled = ref.watch(networkConditionProvider) != NetworkCondition.none;

    return LayoutBuilder(builder: (context, box) {
      final maxX = (box.maxWidth - _size).clamp(0.0, double.infinity);
      final maxY = (box.maxHeight - _size).clamp(0.0, double.infinity);
      final pos = _pos ?? Offset(maxX - 8, maxY - 24);
      final clamped = Offset(pos.dx.clamp(0.0, maxX), pos.dy.clamp(0.0, maxY));
      final color = errors > 0 ? Colors.redAccent : Theme.of(context).colorScheme.primary;

      return Stack(
        children: [
          Positioned(
            left: clamped.dx,
            top: clamped.dy,
            child: Semantics(
              button: true,
              label: 'Debug tools: $errors errors, $requests requests',
              child: GestureDetector(
                onTap: _openMenu,
                onPanUpdate: (d) => setState(() => _pos = clamped + d.delta),
                onPanEnd: (_) => setState(() {
                  // Snap to the nearest horizontal edge.
                  final p = _pos ?? clamped;
                  _pos = Offset(p.dx + _size / 2 < box.maxWidth / 2 ? 8 : maxX - 8, p.dy);
                }),
                child: Opacity(
                  opacity: 0.92,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: throttled ? Border.all(color: Colors.orange, width: 3) : null,
                      boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 2))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(errors > 0 ? Icons.error : Icons.bug_report, color: Colors.white, size: 20),
                        Text(
                          errors > 0 ? '$errors' : '$requests',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
