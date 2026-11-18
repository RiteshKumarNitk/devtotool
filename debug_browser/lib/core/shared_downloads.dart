import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android shared-storage bridge (see MainActivity.kt). Every call fails soft:
/// on Android 9 and below, other platforms and in tests it returns null/false
/// and callers keep using the app-private file.
abstract final class SharedDownloads {
  static const _channel = MethodChannel('com.innovatextechnology.debugbrowser/downloads');

  /// Copies [path] into the public Downloads folder; returns its content:// URI.
  static Future<String?> save(String path, String name, String? mimeType) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'path': path,
        'name': name,
        'mime': mimeType ?? 'application/octet-stream',
      });
    } on MissingPluginException {
      return null;
    } catch (e) {
      // Keep the private copy; the download itself succeeded.
      debugPrint('saveToDownloads failed: $e');
      return null;
    }
  }

  /// Opens with the default app. False if no app can open it.
  static Future<bool> open(String uri, String? mimeType) async {
    try {
      return await _channel.invokeMethod<bool>('open', {'uri': uri, 'mime': mimeType}) ?? false;
    } on Exception {
      return false;
    }
  }

  static Future<bool> share(String uri, String? mimeType) async {
    try {
      await _channel.invokeMethod<bool>('share', {'uri': uri, 'mime': mimeType});
      return true;
    } on Exception {
      return false;
    }
  }

  static Future<bool> delete(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('delete', {'uri': uri}) ?? false;
    } on Exception {
      return false;
    }
  }
}
