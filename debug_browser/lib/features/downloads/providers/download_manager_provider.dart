import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

enum DownloadState { queued, downloading, completed, failed, paused }

class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String platform;
  int totalBytes;
  int receivedBytes;
  DownloadState state;
  String? savePath;
  String? error;
  CancelToken? cancelToken;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.platform,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.state = DownloadState.queued,
    this.savePath,
    this.error,
    this.cancelToken,
  });

  double get progress => totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
}

class DownloadManagerNotifier extends Notifier<List<DownloadTask>> {
  final Dio _dio = Dio();

  @override
  List<DownloadTask> build() => [];

  Future<void> enqueueDownload(String url, String fileName, String platform) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: id,
      url: url,
      fileName: fileName,
      platform: platform,
      cancelToken: CancelToken(),
    );

    state = [...state, task];
    _startDownload(task);
  }

  Future<void> _startDownload(DownloadTask task) async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final platformDir = Directory('${dir.path}/Downloads/${task.platform}');
      if (!await platformDir.exists()) {
        await platformDir.create(recursive: true);
      }
      
      final savePath = '${platformDir.path}/${task.fileName}';
      _updateTask(task.id, (t) {
        t.state = DownloadState.downloading;
        t.savePath = savePath;
      });

      await _dio.download(
        task.url,
        savePath,
        cancelToken: task.cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _updateTask(task.id, (t) {
              t.receivedBytes = received;
              t.totalBytes = total;
            });
          }
        },
      );

      _updateTask(task.id, (t) => t.state = DownloadState.completed);
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _updateTask(task.id, (t) => t.state = DownloadState.paused);
      } else {
        _updateTask(task.id, (t) {
          t.state = DownloadState.failed;
          t.error = e.toString();
        });
      }
    }
  }

  void pauseDownload(String id) {
    final task = state.firstWhere((t) => t.id == id);
    if (task.state == DownloadState.downloading) {
      task.cancelToken?.cancel('User paused');
    }
  }

  void resumeDownload(String id) {
    final task = state.firstWhere((t) => t.id == id);
    if (task.state == DownloadState.paused || task.state == DownloadState.failed) {
      task.cancelToken = CancelToken();
      task.receivedBytes = 0; // Simplified resume (starts over)
      _startDownload(task);
    }
  }

  void cancelDownload(String id) {
    final task = state.firstWhere((t) => t.id == id);
    task.cancelToken?.cancel('User cancelled');
    state = state.where((t) => t.id != id).toList();
  }

  void _updateTask(String id, void Function(DownloadTask) update) {
    state = [
      for (final task in state)
        if (task.id == id)
          ...[
            task..applyUpdate(update) // Applying update directly to the instance
          ]
        else
          task
    ];
  }
}

extension on DownloadTask {
  void applyUpdate(void Function(DownloadTask) update) {
    update(this);
  }
}

final downloadManagerProvider = NotifierProvider<DownloadManagerNotifier, List<DownloadTask>>(() {
  return DownloadManagerNotifier();
});
