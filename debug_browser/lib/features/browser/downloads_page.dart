import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/downloads.dart';

String formatSize(int bytes) {
  if (bytes < 0) return '?';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

IconData iconForFile(String name, String? mime) {
  final m = (mime ?? '').toLowerCase();
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('video/')) return Icons.movie_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m == 'application/pdf' || ext == 'pdf') return Icons.picture_as_pdf_outlined;
  if (ext == 'apk') return Icons.android;
  if (['zip', 'rar', '7z', 'gz', 'tar'].contains(ext)) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  Future<void> _open(BuildContext context, DownloadItem d) async {
    final path = d.path;
    if (path == null || !await File(path).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File no longer exists')));
      }
      return;
    }
    // The share sheet lets the user pick an app to open the file with.
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: d.mimeType)], title: d.fileName));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);
    final notifier = ref.read(downloadsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (items.any((d) => d.status != DownloadStatus.running))
            TextButton(onPressed: notifier.clearFinished, child: const Text('Clear list')),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Files you download appear here.', textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return FutureBuilder<Directory>(
                    future: DownloadsNotifier.downloadDir(),
                    builder: (context, snap) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        snap.hasData ? 'Saved in ${snap.data!.path}' : '',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  );
                }
                final d = items[i];
                final running = d.status == DownloadStatus.running;
                final subtitle = switch (d.status) {
                  DownloadStatus.running => d.total > 0
                      ? '${formatSize(d.received)} of ${formatSize(d.total)}'
                      : '${formatSize(d.received)} downloaded',
                  DownloadStatus.completed =>
                    '${formatSize(d.total)} • ${Uri.tryParse(d.url)?.host ?? ''} • ${DateFormat('d MMM, HH:mm').format(d.startedAt)}',
                  DownloadStatus.failed => 'Failed: ${d.error ?? 'unknown error'}',
                  DownloadStatus.cancelled => 'Cancelled',
                };
                return ListTile(
                  leading: Icon(iconForFile(d.fileName, d.mimeType),
                      color: d.status == DownloadStatus.failed ? Theme.of(context).colorScheme.error : null),
                  title: Text(d.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (running)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(value: d.progress),
                        ),
                    ],
                  ),
                  onTap: d.status == DownloadStatus.completed ? () => _open(context, d) : null,
                  trailing: running
                      ? IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => notifier.cancel(d.id))
                      : PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'open':
                                await _open(context, d);
                              case 'retry':
                                await notifier.retry(d.id);
                              case 'copy':
                                await Clipboard.setData(ClipboardData(text: d.url));
                              case 'remove':
                                await notifier.remove(d.id);
                              case 'delete':
                                await notifier.remove(d.id, deleteFile: true);
                            }
                          },
                          itemBuilder: (_) => [
                            if (d.status == DownloadStatus.completed)
                              const PopupMenuItem(value: 'open', child: Text('Open / share')),
                            if (d.status != DownloadStatus.completed && !d.url.startsWith('data:'))
                              const PopupMenuItem(value: 'retry', child: Text('Retry')),
                            const PopupMenuItem(value: 'copy', child: Text('Copy link')),
                            const PopupMenuItem(value: 'remove', child: Text('Remove from list')),
                            if (d.status == DownloadStatus.completed)
                              const PopupMenuItem(value: 'delete', child: Text('Delete file')),
                          ],
                        ),
                );
              },
            ),
    );
  }
}
