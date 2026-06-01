import '../models/media_info.dart';
import 'downloader_provider.dart';

class MockPlatformProvider implements DownloaderProvider {
  final String _platformName;

  MockPlatformProvider(this._platformName);

  @override
  String get platformName => _platformName;

  @override
  bool canHandle(String url) => true; // Accepts any URL for mock purposes

  @override
  Future<MediaInfo> analyze(String url) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    return MediaInfo(
      title: 'Mock $_platformName Video',
      thumbnailUrl: 'https://picsum.photos/400/300',
      author: 'MockUser_123',
      duration: const Duration(minutes: 1, seconds: 30),
      type: 'Video',
      uploadDate: DateTime.now().subtract(const Duration(days: 2)),
      platform: _platformName,
      formats: [
        DownloadFormat(
          id: '1',
          label: '1080p Video',
          url: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_1MB.mp4',
          fileExtension: 'mp4',
          sizeBytes: 1048576,
        ),
        DownloadFormat(
          id: '2',
          label: '720p Video',
          url: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
          fileExtension: 'mp4',
          sizeBytes: 524288,
        ),
        DownloadFormat(
          id: '3',
          label: 'Audio Only',
          url: 'https://test-audio.com/sample.mp3',
          fileExtension: 'mp3',
          sizeBytes: 256000,
        ),
      ],
    );
  }
}
