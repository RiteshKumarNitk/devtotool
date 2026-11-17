import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/providers.dart';

class ExportService {
  /// Builds the exportable session document. Pure; easy to unit test.
  static Map<String, dynamic> buildSession({
    required List<ConsoleLog> logs,
    required List<NetworkRequest> network,
    required Map<String, dynamic> device,
    required Map<String, dynamic> storage,
  }) =>
      {
        'timestamp': DateTime.now().toIso8601String(),
        'deviceInfo': device,
        'storage': storage,
        'logs': logs.map((l) => l.toJson()).toList(),
        'network': network.map((n) => n.toJson()).toList(),
      };

  /// Exports the current session as JSON via the share sheet.
  /// Returns false on failure.
  static Future<bool> exportSession(WidgetRef ref) async {
    try {
      final session = buildSession(
        logs: ref.read(consoleLogsProvider),
        network: ref.read(networkRequestsProvider),
        device: ref.read(devicePerformanceProvider),
        storage: ref.read(storageProvider),
      );
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/debug_session_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(session));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'Debug Browser Session Export',
      ));
      return true;
    } catch (e, st) {
      debugPrint('Error exporting session: $e\n$st');
      return false;
    }
  }
}
