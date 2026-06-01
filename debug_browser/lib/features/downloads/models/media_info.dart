class MediaInfo {
  final String title;
  final String thumbnailUrl;
  final String? author;
  final Duration? duration;
  final String? type; // 'Video', 'Audio', 'Carousel'
  final DateTime? uploadDate;
  final List<DownloadFormat> formats;
  final String platform; // 'YouTube', 'Instagram'

  // For Instagram Carousels
  final List<MediaInfo>? carouselItems;

  MediaInfo({
    required this.title,
    required this.thumbnailUrl,
    this.author,
    this.duration,
    this.type,
    this.uploadDate,
    required this.formats,
    required this.platform,
    this.carouselItems,
  });
}

class DownloadFormat {
  final String id;
  final String label; // e.g. "1080p MP4", "Audio 128kbps"
  final String url;
  final String fileExtension; // e.g. "mp4", "jpg"
  final int? sizeBytes;
  
  // Custom logic specific to the platform
  final dynamic customData; 

  DownloadFormat({
    required this.id,
    required this.label,
    required this.url,
    required this.fileExtension,
    this.sizeBytes,
    this.customData,
  });
}
