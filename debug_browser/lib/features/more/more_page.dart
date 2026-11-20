import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../services/bug_report_service.dart';
import '../console/snippets_page.dart';
import '../device/device_page.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/page_tools.dart';
import '../../core/tool_providers.dart';
import '../tools/audit_page.dart';
import 'a11y_page.dart';
import 'emulation_page.dart';
import 'environments_page.dart';
import 'history_page.dart';
import 'sessions_page.dart';

/// Asks for a short description, then shares the bug report bundle.
Future<void> showBugReportDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final description = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create bug report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bundles a screenshot, console errors, failed requests (as cURL), '
            'device info, Web Vitals and a HAR file.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What went wrong? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          icon: const Icon(Icons.ios_share),
          onPressed: () => Navigator.pop(context, ctrl.text),
          label: const Text('Share'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (description == null) return;
  final ok = await BugReportService.shareReport(ref, description);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create bug report')));
  }
}

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        children: [
          const _Header('Report'),
          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.redAccent),
            title: const Text('Create bug report'),
            subtitle: const Text('Screenshot + errors + failed requests + HAR'),
            onTap: () => showBugReportDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Saved sessions'),
            subtitle: const Text('Save, reload and share debugging sessions'),
            onTap: () => open(const SessionsPage()),
          ),
          const _Header('Audit'),
          ListTile(
            leading: const Icon(Icons.speed, color: Color(0xFF0CCE6B)),
            title: const Text('Page audit'),
            subtitle: const Text('Performance, accessibility, best practices and SEO scores'),
            onTap: () => open(const AuditPage()),
          ),
          ListTile(
            leading: const Icon(Icons.devices_other),
            title: const Text('Responsive screenshots'),
            subtitle: const Text('Capture the page at phone, tablet and desktop sizes'),
            onTap: () async {
              // This page closes now; keep app-wide handles for the capture.
              final read = ProviderScope.containerOf(context, listen: false).read;
              final messenger = ScaffoldMessenger.of(context);
              ref.read(homeTabProvider.notifier).select(AppTab.browser);
              messenger.showSnackBar(
                const SnackBar(content: Text('Capturing phone, tablet and desktop views…'), duration: Duration(seconds: 6)),
              );
              final shots = await captureResponsive(read);
              if (shots.isEmpty) return;
              final paths = await writeTempPngs(shots, 'responsive');
              await SharePlus.instance.share(ShareParams(
                files: [for (final p in paths) XFile(p, mimeType: 'image/png')],
                text: [for (final s in shots) s.$1].join(', '),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new, color: Colors.teal),
            title: const Text('Accessibility audit'),
            subtitle: const Text('Alt text, labels, contrast, tap targets, headings'),
            onTap: () => open(const A11yPage()),
          ),
          const _Header('Emulate'),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Device emulation'),
            subtitle: const Text('Viewport size and geolocation'),
            onTap: () => open(const EmulationPage()),
          ),
          ListTile(
            leading: const Icon(Icons.perm_device_information),
            title: const Text('Device info'),
            subtitle: const Text('What the page sees: UA, screen, locale'),
            onTap: () => open(const DevicePage()),
          ),
          const _Header('Navigate'),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Environments'),
            subtitle: const Text('Dev / staging / production shortcuts'),
            onTap: () => open(const EnvironmentsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () => open(const HistoryPage()),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('JS snippets'),
            onTap: () => open(const SnippetsPage()),
          ),
          const _Header('App'),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark theme'),
            value: isDark,
            onChanged: (_) => ref.read(themeProvider.notifier).toggle(current: Theme.of(context).brightness),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Debug Browser',
            applicationVersion: '1.0.0',
            applicationLegalese: '© InnovateX Technology',
            aboutBoxChildren: [
              SizedBox(height: 12),
              Text('All debugging data stays on this device. Nothing is uploaded; '
                  'data leaves the device only when you choose to share or export it.'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                )),
      );
}
