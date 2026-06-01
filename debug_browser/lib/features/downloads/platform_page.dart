import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/media_info.dart';
import 'providers/downloader_provider.dart';
import 'providers/youtube_provider.dart';
import 'providers/terabox_provider.dart';
import 'providers/mock_providers.dart';
import 'providers/download_manager_provider.dart';

class PlatformPage extends ConsumerStatefulWidget {
  final String platform;

  const PlatformPage({super.key, required this.platform});

  @override
  ConsumerState<PlatformPage> createState() => _PlatformPageState();
}

class _PlatformPageState extends ConsumerState<PlatformPage> {
  final _urlController = TextEditingController();
  bool _isAnalyzing = false;
  MediaInfo? _mediaInfo;
  late DownloaderProvider _provider;

  @override
  void initState() {
    super.initState();
    if (widget.platform == 'YouTube') {
      _provider = YouTubeProvider();
    } else if (widget.platform == 'Terabox') {
      _provider = TeraboxProvider();
    } else {
      _provider = MockPlatformProvider(widget.platform);
    }
  }

  void _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    
    if (!_provider.canHandle(url) && widget.platform == 'YouTube') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid YouTube URL')));
      return;
    }
    
    setState(() {
      _isAnalyzing = true;
      _mediaInfo = null;
    });

    try {
      final info = await _provider.analyze(url);
      if (mounted) {
        setState(() {
          _mediaInfo = info;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.platform} Downloader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Paste ${widget.platform} URL here',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _urlController.clear(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isAnalyzing ? null : _analyzeUrl,
                child: _isAnalyzing
                    ? const CircularProgressIndicator()
                    : const Text('Analyze', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
            if (_mediaInfo != null)
              Expanded(child: _buildPreviewCard(_mediaInfo!))
            else
              const Expanded(
                child: Center(
                  child: Text('Enter a URL and tap Analyze to see media formats.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(MediaInfo info) {
    return ListView(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.network(
                info.thumbnailUrl,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey, child: const Icon(Icons.broken_image, size: 50)),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (info.author != null) Text('Author: ${info.author}', style: const TextStyle(color: Colors.grey)),
                    if (info.duration != null) Text('Duration: ${info.duration!.inMinutes}:${(info.duration!.inSeconds % 60).toString().padLeft(2, "0")}', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Available Formats', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...info.formats.map((format) => ListTile(
              leading: Icon(format.fileExtension == 'mp3' ? Icons.audio_file : Icons.video_file),
              title: Text(format.label),
              subtitle: format.sizeBytes != null ? Text('${(format.sizeBytes! / 1024 / 1024).toStringAsFixed(2)} MB') : null,
              trailing: IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  final fileName = "${info.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.${format.fileExtension}";
                  ref.read(downloadManagerProvider.notifier).enqueueDownload(
                        format.url,
                        fileName,
                        widget.platform,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${format.label} to Download Queue')));
                },
              ),
            )),
      ],
    );
  }
}
