import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';

class DOMPage extends ConsumerStatefulWidget {
  const DOMPage({super.key});

  @override
  ConsumerState<DOMPage> createState() => _DOMPageState();
}

class _DOMPageState extends ConsumerState<DOMPage> {
  bool _inspectorActive = false;

  void _js(String code) => ref.read(webViewControllerProvider)?.runJavaScript(code);

  void _toggleInspector() {
    if (ref.read(webViewControllerProvider) == null) return;
    setState(() => _inspectorActive = !_inspectorActive);
    if (_inspectorActive) {
      _js('window.enableInspector && window.enableInspector()');
      ref.read(homeTabProvider.notifier).select(AppTab.browser);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap an element, then come back to the DOM tab')),
      );
    } else {
      _js('window.disableInspector && window.disableInspector()');
    }
  }

  void _loadTree() => _js('window.__dbg && window.__dbg.domTree(14)');

  void _select(String path) {
    _js('window.__dbg && window.__dbg.select(${jsString(path)})');
  }

  @override
  Widget build(BuildContext context) {
    final node = ref.watch(domTreeProvider);
    final tree = ref.watch(pageDataProvider)['dom_tree'];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DOM'),
          actions: [
            IconButton(
              tooltip: _inspectorActive ? 'Stop tap-to-inspect' : 'Tap-to-inspect',
              icon: Icon(Icons.ads_click, color: _inspectorActive ? Colors.redAccent : null),
              onPressed: _toggleInspector,
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Element'), Tab(text: 'Tree')]),
        ),
        body: Builder(
          // Builder: DefaultTabController.of needs a context below the controller.
          builder: (tabContext) => TabBarView(
            children: [
              (node == null || node.isEmpty)
                  ? _EmptyState(onInspect: _toggleInspector, onTree: () {
                      DefaultTabController.of(tabContext).animateTo(1);
                      _loadTree();
                    })
                  : _ElementDetails(node: node, onJs: _js),
              _TreeView(
                tree: tree,
                onRefresh: _loadTree,
                selectedPath: node?['path'] as String?,
                onSelect: (path) {
                  _select(path);
                  DefaultTabController.of(tabContext).animateTo(0);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onInspect;
  final VoidCallback onTree;
  const _EmptyState({required this.onInspect, required this.onTree});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_tree_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Pick an element by tapping it in the page, or browse the DOM tree.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: onInspect, icon: const Icon(Icons.ads_click), label: const Text('Tap to inspect')),
                OutlinedButton.icon(onPressed: onTree, icon: const Icon(Icons.account_tree), label: const Text('Browse tree')),
              ]),
            ],
          ),
        ),
      );
}

class _ElementDetails extends StatelessWidget {
  final Map<String, dynamic> node;
  final void Function(String js) onJs;
  const _ElementDetails({required this.node, required this.onJs});

  String? get _path => node['path'] as String?;

  Future<void> _editStyle(BuildContext context, String prop, String current) async {
    final path = _path;
    if (path == null) return;
    final result = await _prompt(context, title: prop, initial: current, hint: 'CSS value');
    if (result == null) return;
    onJs('window.__dbg && window.__dbg.setStyle(${jsString(path)}, ${jsString(prop)}, ${jsString(result)})');
  }

  Future<void> _addStyle(BuildContext context) async {
    final path = _path;
    if (path == null) return;
    final prop = await _prompt(context, title: 'Add CSS property', initial: '', hint: 'e.g. border');
    if (prop == null || prop.trim().isEmpty || !context.mounted) return;
    final value = await _prompt(context, title: prop.trim(), initial: '', hint: 'e.g. 2px solid red');
    if (value == null) return;
    onJs('window.__dbg && window.__dbg.setStyle(${jsString(path)}, ${jsString(prop.trim())}, ${jsString(value)})');
  }

  Future<void> _editAttr(BuildContext context, String name, String? current) async {
    final path = _path;
    if (path == null) return;
    final result = await _prompt(context,
        title: current == null ? 'Add attribute' : name,
        initial: current ?? '',
        hint: current == null ? 'name=value' : 'Value (empty to remove)');
    if (result == null) return;
    String attr = name, value = result;
    if (current == null) {
      final i = result.indexOf('=');
      if (i <= 0) return;
      attr = result.substring(0, i).trim();
      value = result.substring(i + 1).trim();
    }
    final v = value.isEmpty && current != null ? 'null' : jsString(value);
    onJs('window.__dbg && window.__dbg.setAttr(${jsString(path)}, ${jsString(attr)}, $v)');
  }

  @override
  Widget build(BuildContext context) {
    final styles = (node['styles'] as Map?)?.cast<String, dynamic>() ?? const {};
    final attrs = (node['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final box = node['box'] as Map?;
    final editable = _path != null;
    const mono = TextStyle(fontFamily: 'monospace');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('<${node['tagName']}>',
                    style: mono.copyWith(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                if ('${node['id'] ?? ''}'.isNotEmpty) Text('#${node['id']}', style: mono),
                if ('${node['className'] ?? ''}'.isNotEmpty) Text('.${'${node['className']}'.trim().replaceAll(RegExp(r'\s+'), ' .')}', style: mono),
                if (box != null)
                  Text('${box['w']} × ${box['h']} at (${box['x']}, ${box['y']})',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                if ('${node['text'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('"${node['text']}"', maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                if (!editable)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Select this element from the Tree tab to edit it.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
        Row(children: [
          Text('Computed styles', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (editable)
            TextButton.icon(onPressed: () => _addStyle(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
        ]),
        if ('${node['inlineStyle'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText('style="${node['inlineStyle']}"', style: mono.copyWith(fontSize: 12, color: Colors.orange)),
          ),
        for (final e in styles.entries)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(e.key, style: const TextStyle(color: Colors.grey)),
            trailing: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
              child: Text('${e.value}', style: mono.copyWith(fontSize: 13), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
            ),
            onTap: editable ? () => _editStyle(context, e.key, '${e.value}') : null,
            onLongPress: () => Clipboard.setData(ClipboardData(text: '${e.key}: ${e.value};')),
          ),
        if (attrs.isNotEmpty || editable) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text('Attributes', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (editable)
              TextButton.icon(onPressed: () => _editAttr(context, '', null), icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
          ]),
          for (final e in attrs.entries)
            ListTile(
              dense: true,
              title: Text(e.key, style: mono.copyWith(color: Colors.purple.shade300)),
              subtitle: Text('${e.value}', style: mono.copyWith(fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
              onTap: editable ? () => _editAttr(context, e.key, '${e.value}') : null,
            ),
        ],
        if ('${node['outerHTML'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('outerHTML'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText('${node['outerHTML']}', style: mono.copyWith(fontSize: 11)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<String?> _prompt(BuildContext context, {required String title, required String initial, required String hint}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontFamily: 'monospace')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        autocorrect: false,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Apply')),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}

class _TreeView extends StatelessWidget {
  final Map<String, dynamic>? tree;
  final VoidCallback onRefresh;
  final String? selectedPath;
  final void Function(String path) onSelect;
  const _TreeView({required this.tree, required this.onRefresh, required this.selectedPath, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final root = tree?['root'] as Map?;
    if (root == null) {
      return Center(
        child: FilledButton.icon(onPressed: onRefresh, icon: const Icon(Icons.account_tree), label: const Text('Load DOM tree')),
      );
    }
    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text(tree?['truncated'] == true ? 'Large page: tree truncated to 1500 nodes' : 'Tap a node to select and highlight it'),
          trailing: IconButton(tooltip: 'Reload tree', icon: const Icon(Icons.refresh), onPressed: onRefresh),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [_DomNode(node: root, depth: 0, selectedPath: selectedPath, onSelect: onSelect)],
          ),
        ),
      ],
    );
  }
}

class _DomNode extends StatefulWidget {
  final Map node;
  final int depth;
  final String? selectedPath;
  final void Function(String path) onSelect;
  const _DomNode({required this.node, required this.depth, required this.selectedPath, required this.onSelect});

  @override
  State<_DomNode> createState() => _DomNodeState();
}

class _DomNodeState extends State<_DomNode> {
  late bool _open = widget.depth < 2 || (widget.selectedPath?.startsWith('${widget.node['path']}') ?? false);

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final children = (n['children'] as List?) ?? const [];
    final childCount = (n['childCount'] as num?)?.toInt() ?? children.length;
    final path = '${n['path'] ?? ''}';
    final selected = widget.selectedPath == path;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => widget.onSelect(path),
          child: Container(
            color: selected ? Colors.blueAccent.withValues(alpha: 0.15) : null,
            padding: EdgeInsets.only(left: 8.0 + widget.depth * 14, top: 4, bottom: 4, right: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: childCount > 0
                      ? InkWell(
                          onTap: () => setState(() => _open = !_open),
                          child: Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18),
                        )
                      : null,
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '<${n['tag']}', style: mono.copyWith(color: Colors.blueAccent)),
                      if ('${n['id'] ?? ''}'.isNotEmpty)
                        TextSpan(text: ' #${n['id']}', style: mono.copyWith(color: Colors.orange)),
                      if ('${n['cls'] ?? ''}'.isNotEmpty)
                        TextSpan(text: ' .${'${n['cls']}'.replaceAll(' ', ' .')}', style: mono.copyWith(color: Colors.purple.shade300)),
                      TextSpan(text: '>', style: mono.copyWith(color: Colors.blueAccent)),
                      if (childCount > 0 && !_open)
                        TextSpan(text: '  $childCount', style: mono.copyWith(color: Colors.grey, fontSize: 11)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final c in children)
            if (c is Map)
              _DomNode(node: c, depth: widget.depth + 1, selectedPath: widget.selectedPath, onSelect: widget.onSelect),
        if (_open && childCount > children.length)
          Padding(
            padding: EdgeInsets.only(left: 40.0 + widget.depth * 14, bottom: 4),
            child: Text('… ${childCount - children.length} more (depth limit)',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ],
    );
  }
}
