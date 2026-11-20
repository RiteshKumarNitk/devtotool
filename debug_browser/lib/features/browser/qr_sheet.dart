import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/backup.dart' show ProviderReader;
import '../../core/home_stats.dart';
import '../../core/tabs_provider.dart';

/// Shows the current page as a QR code, with a button to scan one.
/// Scanning uses Google's code scanner: no camera permission for this app.
void showQrSheet(BuildContext context, ProviderReader read) {
  final tab = read(tabsProvider).active;
  final url = tab.isNewTab ? null : tab.url;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (url != null) ...[
            Text(tab.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(url, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Scan with another phone to open this page there.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(c);
              await scanAndOpen(context, read);
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan a QR code'),
          ),
        ]),
      ),
    ),
  );
}

Future<void> scanAndOpen(BuildContext context, ProviderReader read) async {
  String? value;
  try {
    value = await SystemBrowser.scanQr();
  } on StateError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanner unavailable: ${e.message}')));
    return;
  }
  if (value == null || value.isEmpty || !context.mounted) return;
  final uri = Uri.tryParse(value.trim());
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    read(tabsProvider.notifier).newTab(url: uri.toString());
    return;
  }
  // Not a web link (Wi-Fi, text, contact…): show it, never auto-open.
  final scanned = value;
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Scanned'),
      content: SelectableText(scanned),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: scanned));
            Navigator.pop(d);
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(d);
            read(tabsProvider.notifier).loadInput(scanned);
          },
          child: const Text('Search'),
        ),
      ],
    ),
  );
}
