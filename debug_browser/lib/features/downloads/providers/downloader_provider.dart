import '../models/media_info.dart';

abstract class DownloaderProvider {
  /// The name of the platform (e.g., 'YouTube', 'Instagram')
  String get platformName;

  /// Returns true if this provider can handle the given URL.
  bool canHandle(String url);

  /// Analyzes the URL and returns media metadata and download formats.
  Future<MediaInfo> analyze(String url);
}
