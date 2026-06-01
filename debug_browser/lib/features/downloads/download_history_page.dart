import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/download_manager_provider.dart';

class DownloadHistoryPage extends ConsumerWidget {
  const DownloadHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadManagerProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Download Manager'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Queued'),
              Tab(text: 'Completed'),
              Tab(text: 'Failed'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTaskList(tasks.where((t) => t.state == DownloadState.downloading || t.state == DownloadState.paused).toList()),
            _buildTaskList(tasks.where((t) => t.state == DownloadState.queued).toList()),
            _buildTaskList(tasks.where((t) => t.state == DownloadState.completed).toList()),
            _buildTaskList(tasks.where((t) => t.state == DownloadState.failed).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return const Center(child: Text('No downloads in this category.'));
    }

    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _DownloadTaskTile(task: task);
      },
    );
  }
}

class _DownloadTaskTile extends ConsumerWidget {
  final DownloadTask task;

  const _DownloadTaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadManagerProvider.notifier);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  task.platform,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.state == DownloadState.downloading || task.state == DownloadState.paused) ...[
              LinearProgressIndicator(value: task.progress),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(task.receivedBytes / 1024 / 1024).toStringAsFixed(2)} MB / ${(task.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
                  Text('${(task.progress * 100).toStringAsFixed(1)}%'),
                ],
              ),
            ],
            if (task.state == DownloadState.failed)
              Text('Error: ${task.error}', style: const TextStyle(color: Colors.red)),
            if (task.state == DownloadState.completed)
              Text('Saved to: ${task.savePath}', style: const TextStyle(color: Colors.green, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.state == DownloadState.downloading)
                  IconButton(
                    icon: const Icon(Icons.pause),
                    onPressed: () => notifier.pauseDownload(task.id),
                  ),
                if (task.state == DownloadState.paused || task.state == DownloadState.failed)
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => notifier.resumeDownload(task.id),
                  ),
                if (task.state != DownloadState.completed)
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => notifier.cancelDownload(task.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
