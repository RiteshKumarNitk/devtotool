import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';
import 'json_tree.dart';
import 'snippets_page.dart';

/// Level groups shown as filter chips. 'input'/'result' are REPL entries.
enum LogLevelFilter {
  error('Errors', {'error'}),
  warn('Warnings', {'warn'}),
  info('Info', {'info', 'log'}),
  debug('Debug', {'debug'}),
  repl('REPL', {'input', 'result'});

  const LogLevelFilter(this.label, this.levels);
  final String label;
  final Set<String> levels;

  static LogLevelFilter of(String level) =>
      values.firstWhere((f) => f.levels.contains(level), orElse: () => info);
}

List<ConsoleLog> filterLogs(List<ConsoleLog> logs, Set<LogLevelFilter> enabled, String query) {
  final q = query.trim().toLowerCase();
  return logs.where((l) {
    if (!enabled.contains(LogLevelFilter.of(l.level))) return false;
    return q.isEmpty || l.message.toLowerCase().contains(q);
  }).toList();
}

class ConsolePage extends ConsumerStatefulWidget {
  const ConsolePage({super.key});

  @override
  ConsumerState<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends ConsumerState<ConsolePage> {
  String _query = '';
  Set<LogLevelFilter> _enabled = LogLevelFilter.values.toSet();
  final TextEditingController _evalController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<String> _replHistory = [];
  int _historyIndex = -1;
  bool _autoScroll = true;

  @override
  void dispose() {
    _evalController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Color _color(String level) => switch (level) {
        'error' => Colors.redAccent,
        'warn' => Colors.orange,
        'info' => Colors.lightBlue,
        'debug' => Colors.purple.shade300,
        'input' => Colors.blueAccent,
        'result' => Colors.teal,
        _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
      };

  IconData _icon(String level) => switch (level) {
        'error' => Icons.error_outline,
        'warn' => Icons.warning_amber,
        'input' => Icons.chevron_right,
        'result' => Icons.chevron_left,
        _ => Icons.circle_outlined,
      };

  void _evaluate(String code) {
    if (code.trim().isEmpty) return;
    _evalController.clear();
    _replHistory.remove(code);
    _replHistory.add(code);
    _historyIndex = -1;
    _autoScroll = true;
    runJsInPage(ref, code);
  }

  void _historyStep(int delta) {
    if (_replHistory.isEmpty) return;
    var i = _historyIndex == -1 ? _replHistory.length : _historyIndex;
    i = (i + delta).clamp(0, _replHistory.length - 1);
    _historyIndex = i;
    _evalController.text = _replHistory[i];
    _evalController.selection = TextSelection.collapsed(offset: _evalController.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(consoleLogsProvider);
    final filtered = filterLogs(logs, _enabled, _query);
    final counts = {
      for (final f in LogLevelFilter.values) f: logs.where((l) => f.levels.contains(l.level)).length,
    };

    if (_autoScroll && filtered.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(
            tooltip: 'Snippets',
            icon: const Icon(Icons.code),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SnippetsPage()),
            ),
          ),
          IconButton(
            tooltip: 'Copy visible logs',
            icon: const Icon(Icons.copy_all),
            onPressed: filtered.isEmpty
                ? null
                : () {
                    final text = filtered
                        .map((l) => '[${DateFormat('HH:mm:ss.SSS').format(l.timestamp)}] '
                            '${l.level.toUpperCase()}: ${l.message}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied ${filtered.length} entries')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ref.read(consoleLogsProvider.notifier).clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search logs',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final f in LogLevelFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('${f.label} ${counts[f]}'),
                      selected: _enabled.contains(f),
                      onSelected: (on) => setState(() {
                        _enabled = {..._enabled};
                        on ? _enabled.add(f) : _enabled.remove(f);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(logs.isEmpty ? 'No logs yet' : 'No logs match the filters'))
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is UserScrollNotification) {
                        _autoScroll = n.metrics.pixels >= n.metrics.maxScrollExtent - 40;
                      }
                      return false;
                    },
                    child: ListView.separated(
                      controller: _scroll,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _LogTile(
                        log: filtered[index],
                        color: _color(filtered[index].level),
                        icon: _icon(filtered[index].level),
                      ),
                    ),
                  ),
          ),
          _buildEvaluator(),
        ],
      ),
    );
  }

  Widget _buildEvaluator() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous command',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _historyStep(-1),
              ),
              IconButton(
                tooltip: 'Next command',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _historyStep(1),
              ),
              Expanded(
                child: TextField(
                  controller: _evalController,
                  decoration: const InputDecoration(
                    hintText: 'Evaluate JavaScript…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _evaluate,
                ),
              ),
              IconButton(
                tooltip: 'Run',
                icon: const Icon(Icons.play_arrow, color: Colors.blueAccent),
                onPressed: () => _evaluate(_evalController.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final ConsoleLog log;
  final Color color;
  final IconData icon;
  const _LogTile({required this.log, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final json = extractJson(log.message);
    final bg = switch (log.level) {
      'error' => Colors.red.withValues(alpha: 0.08),
      'warn' => Colors.orange.withValues(alpha: 0.08),
      _ => Colors.transparent,
    };
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: log.message));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
      },
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(icon, size: 14, color: color),
            ),
            Expanded(
              child: json == null
                  ? Text(log.message, style: mono.copyWith(color: color))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (json.prefix.isNotEmpty) Text(json.prefix, style: mono.copyWith(color: color)),
                        JsonTree(value: json.json),
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            Text(
              DateFormat('HH:mm:ss').format(log.timestamp),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
