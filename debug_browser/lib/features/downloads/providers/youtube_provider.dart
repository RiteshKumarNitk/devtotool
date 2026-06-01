import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/media_info.dart';
import 'downloader_provider.dart';

class YouTubeProvider implements DownloaderProvider {
  @override
  String get platformName => 'YouTube';

  @override
  bool canHandle(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  @override
  Future<MediaInfo> analyze(String url) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(url);
      
      final formats = <DownloadFormat>[];
      
      // Muxed (Video + Audio)
      for (final stream in manifest.muxed) {
        formats.add(DownloadFormat(
          id: stream.url.toString(),
          label: '${stream.videoQuality.name} Video + Audio',
          url: stream.url.toString(),
          fileExtension: 'mp4',
          sizeBytes: stream.size.totalBytes,
          customData: stream,
        ));
      }

      // Video only
      for (final stream in manifest.videoOnly) {
        formats.add(DownloadFormat(
          id: stream.url.toString(),
          label: '${stream.videoQuality.name} Video (No Audio)',
          url: stream.url.toString(),
          fileExtension: 'mp4',
          sizeBytes: stream.size.totalBytes,
          customData: stream,
        ));
      }
      
      // Audio only
      for (final stream in manifest.audioOnly) {
        formats.add(DownloadFormat(
          id: stream.url.toString(),
          label: 'Audio ${stream.audioCodec}',
          url: stream.url.toString(),
          fileExtension: 'mp3',
          sizeBytes: stream.size.totalBytes,
          customData: stream,
        ));
      }

      return MediaInfo(
        title: video.title,
        thumbnailUrl: video.thumbnails.highResUrl,
        author: video.author,
        duration: video.duration,
        type: 'Video',
        uploadDate: video.uploadDate,
        formats: formats,
        platform: 'YouTube',
      );
    } finally {
      yt.close();
    }
  }
}
