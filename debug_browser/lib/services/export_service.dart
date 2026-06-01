import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/providers.dart';

class ExportService {
  static Future<void> exportSession(WidgetRef ref) async {
    try {
      final logs = ref.read(consoleLogsProvider);
      final network = ref.read(networkRequestsProvider);
      final device = ref.read(devicePerformanceProvider);
      final storage = ref.read(storageProvider);

      final Map<String, dynamic> sessionData = {
        'timestamp': DateTime.now().toIso8601String(),
        'deviceInfo': device,
        'storage': storage,
        'logs': logs.map((l) => {
          'level': l.level,
          'message': l.message,
          'timestamp': l.timestamp.toIso8601String(),
        }).toList(),
        'network': network.map((n) => {
          'type': n.type,
          'url': n.url,
          'method': n.method,
          'status': n.status,
          'duration': n.duration,
          'requestBody': n.requestBody,
          'responseBody': n.responseBody,
          'error': n.error,
          'timestamp': n.timestamp.toIso8601String(),
        }).toList(),
      };

      final jsonString = jsonEncode(sessionData);
      
      final tempDir = await getTemporaryDirectory();
      final file = await File("${tempDir.path}/debug_session_${DateTime.now().millisecondsSinceEpoch}.json").create();
      await file.writeAsString(jsonString);

      await Share.shareXFiles([XFile(file.path)], text: 'Debug Browser Session Export');
    } catch (e) {
      print('Error exporting session: \$e');
    }
  }
}
