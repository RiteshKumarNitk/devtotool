import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup.dart' show ProviderReader;
import '../../core/tabs_provider.dart';
import '../../core/favicons.dart';
import 'tab_actions.dart';

/// Grid of open tabs with Chrome-style "Tabs" / "Private" sections.
class TabSwitcherPage extends ConsumerStatefulWidget {
  const TabSwitcherPage({super.key});

  @override
  ConsumerState<TabSwitcherPage> createState() => _TabSwitcherPageState();
}

class _TabSwitcherPageState extends ConsumerState<TabSwitcherPage> {
  late bool _private = ref.read(tabsProvider).active.isPrivate;
  String? _groupFilter;

  static const _groupColors = [
    Color(0xFF1A73E8),
    Color(0xFFE8710A),
    Color(0xFF188038),
    Color(0xFFD93025),
    Color(0xFF9334E6),
    Color(0xFF12B5CB),
    Color(0xFFE52592),
    Color(0xFF5F6368),
  ];

  /// App-wide reader that stays valid after this page closes (Undo).
  ProviderReader get _read =>
      ProviderScope.containerOf(context, listen: false).read;

  void _close(String id) => closeTabWithUndo(context, _read, id);

  static Color groupColor(String g) =>
      _groupColors[g.hashCode.abs() % _groupColors.length];

  Future<void> _tabMenu(BrowserTab t) async {
    final tabs = ref.read(tabsProvider.notifier);
    final groups = tabs.groups;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                t.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final g in groups)
              if (g != t.group)
                ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: groupColor(g),
                  ),
                  title: Text('Add to "$g"'),
                  onTap: () {
                    Navigator.pop(c);
                    tabs.setGroup(t.id, g);
                  },
                ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('New group…'),
              onTap: () async {
                final name = await _ask('New tab group', '');
                if (c.mounted) Navigator.pop(c);
                if (name != null) tabs.setGroup(t.id, name);
              },
            ),
            if (t.group != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text('Remove from "${t.group}"'),
                onTap: () {
                  Navigator.pop(c);
                  tabs.setGroup(t.id, null);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close tab'),
              onTap: () {
                Navigator.pop(c);
                _close(t.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _ask(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Work, Study, Shopping',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (r == null || r.trim().isEmpty) ? null : r.trim();
  }

  Future<void> _groupMenu(String g) async {
    final tabs = ref.read(tabsProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                g,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename group'),
              onTap: () async {
                Navigator.pop(c);
                final name = await _ask('Rename group', g);
                if (name != null) {
                  tabs.renameGroup(g, name);
                  if (_groupFilter == g) setState(() => _groupFilter = name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Ungroup tabs'),
              onTap: () {
                Navigator.pop(c);
                tabs.ungroup(g);
                setState(() => _groupFilter = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tabsProvider);
    final kind = all.tabs.where((t) => t.isPrivate == _private).toList();
    final groupNames = <String>{
      for (final t in kind)
        if (t.group != null) t.group!,
    }.toList();
    if (_groupFilter != null && !groupNames.contains(_groupFilter)) {
      _groupFilter = null;
    }
    final shown = _groupFilter == null
        ? kind
        : kind.where((t) => t.group == _groupFilter).toList();
    final state = TabsState(shown, all.activeId);
    final privateCount = all.tabs.where((t) => t.isPrivate).length;
    final normalCount = all.tabs.length - privateCount;
    final thumbs = ref.watch(tabThumbnailsProvider);
    final tabs = ref.read(tabsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        bottom: groupNames.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('All ${kind.length}'),
                          selected: _groupFilter == null,
                          onSelected: (_) =>
                              setState(() => _groupFilter = null),
                        ),
                      ),
                      for (final g in groupNames)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onLongPress: () => _groupMenu(g),
                            child: ChoiceChip(
                              avatar: CircleAvatar(
                                radius: 6,
                                backgroundColor: groupColor(g),
                              ),
                              label: Text(
                                '$g ${kind.where((t) => t.group == g).length}',
                              ),
                              selected: _groupFilter == g,
                              onSelected: (_) =>
                                  setState(() => _groupFilter = g),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        title: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.tab),
              label: Text('$normalCount'),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text('$privateCount'),
            ),
          ],
          selected: {_private},
          onSelectionChanged: (s) {
            HapticFeedback.selectionClick();
            setState(() => _private = s.first);
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'recent') {
                await showRecentlyClosed(
                  context,
                  _read,
                  onReopened: () {
                    if (context.mounted) Navigator.pop(context);
                  },
                );
                return;
              }
              if (v == 'close_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(
                      _private ? 'Close all private tabs?' : 'Close all tabs?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Close all'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  if (_private) {
                    tabs.closePrivateTabs();
                  } else {
                    tabs.closeAll();
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'recent',
                child: ListTile(
                  leading: Icon(Icons.restore_page_outlined),
                  title: Text('Recently closed'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'close_all',
                child: ListTile(
                  leading: Icon(Icons.close_fullscreen),
                  title: Text('Close all'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          final id = tabs.newTab(private: _private);
          // A new tab opened while viewing a group joins that group.
          if (_groupFilter != null) tabs.setGroup(id, _groupFilter);
          Navigator.pop(context);
        },
        icon: const Icon(Icons.add),
        label: Text(_private ? 'New private tab' : 'New tab'),
      ),
      body: shown.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _private
                          ? Icons.privacy_tip_outlined
                          : Icons.tab_unselected,
                      size: 56,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _private
                          ? "Private tabs don't save history, and their cookies and site data "
                                'are deleted when you close the last private tab. Downloads and '
                                'bookmarks are kept.'
                          : 'No open tabs',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: state.tabs.length,
              itemBuilder: (context, i) {
                final t = state.tabs[i];
                final active = t.id == state.activeId;
                // Locked private tabs don't reveal what's open.
                final masked = t.isPrivate && ref.watch(privateLockProvider);
                final host = masked ? '' : (Uri.tryParse(t.url)?.host ?? '');
                final dismissBg = Container(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.delete_outline,
                    color: scheme.onErrorContainer,
                    size: 32,
                  ),
                );
                return _Entrance(
                  index: i,
                  child: Dismissible(
                    key: ValueKey(t.id),
                    background: dismissBg,
                    onDismissed: (_) => _close(t.id),
                    child: Material(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          tabs.activate(t.id);
                          Navigator.pop(context);
                        },
                        onLongPress: () => _tabMenu(t),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: active
                                  ? scheme.primary
                                  : (t.group != null
                                        ? groupColor(
                                            t.group!,
                                          ).withValues(alpha: 0.8)
                                        : Colors.transparent),
                              width: 2.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                                child: Row(
                                  children: [
                                    if (t.isNewTab || masked)
                                      Icon(
                                        t.isPrivate
                                            ? Icons.privacy_tip_outlined
                                            : Icons.home_outlined,
                                        size: 16,
                                      )
                                    else
                                      SiteIcon(url: t.url, size: 16, radius: 3),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        masked
                                            ? 'Private tab (locked)'
                                            : t.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Close tab',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => _close(t.id),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: thumbs[t.id] != null
                                    ? Image.memory(
                                        thumbs[t.id]!,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                        gaplessPlayback: true,
                                        filterQuality: FilterQuality.medium,
                                      )
                                    : Container(
                                        color: scheme.surface,
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor:
                                                  scheme.primaryContainer,
                                              child: Text(
                                                host
                                                        .replaceFirst(
                                                          'www.',
                                                          '',
                                                        )
                                                        .isEmpty
                                                    ? '?'
                                                    : host
                                                          .replaceFirst(
                                                            'www.',
                                                            '',
                                                          )[0]
                                                          .toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  color:
                                                      scheme.onPrimaryContainer,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              host,
                                              maxLines: 2,
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (!t.loaded)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Text(
                                                  'Not loaded',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Cards fade and rise in one after another when the switcher opens.
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const _Entrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final ms = 260 + (index.clamp(0, 8) * 45);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Interval(
        (index.clamp(0, 8) * 45) / ms,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
        ),
      ),
      child: child,
    );
  }
}
