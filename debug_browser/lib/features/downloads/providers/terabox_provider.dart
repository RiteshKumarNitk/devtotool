import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/media_info.dart';
import 'downloader_provider.dart';

class TeraboxProvider implements DownloaderProvider {
  HeadlessInAppWebView? _headlessWebView;
  
  @override
  String get platformName => 'Terabox';

  @override
  bool canHandle(String url) {
    return url.contains('terabox.com') || url.contains('terabox.app') || url.contains('1024terabox.com') || url.contains('teraboxlink.com');
  }

  @override
  Future<MediaInfo> analyze(String url) async {
    final completer = Completer<MediaInfo>();

    // Extract shorturl from url
    // Terabox URLs usually end with /s/1<shorturl>
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    String? shortUrl;
    if (pathSegments.contains('s')) {
      final index = pathSegments.indexOf('s');
      if (index + 1 < pathSegments.length) {
        shortUrl = pathSegments[index + 1];
        // Sometimes it has '1' prepended, API usually just takes the whole thing
      }
    }
    
    // If not found in path, try query parameter (e.g. ?surl=...)
    if (shortUrl == null && uri.queryParameters.containsKey('surl')) {
      shortUrl = uri.queryParameters['surl'];
    }

    if (shortUrl == null) {
      throw Exception("Could not extract Terabox shorturl from link.");
    }

    // We open the main page just to establish the context and execute our API call
    _headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://www.terabox.com')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ),
      onLoadStop: (controller, loadedUrl) async {
        try {
          // Inject JS to fetch the file info directly from Terabox's internal API.
          // Because this runs inside the WebView, it automatically attaches any session cookies.
          final jsResult = await controller.evaluateJavascript(source: '''
            (async function() {
              try {
                // Fetch info
                let res = await fetch('/api/shorturlinfo?app_id=250528&shorturl=$shortUrl');
                let data = await res.json();
                
                if (data.errno !== 0) {
                  return JSON.stringify({ error: 'API Error: ' + data.errno, raw: data });
                }

                // data.list usually contains the files
                if (!data.list || data.list.length === 0) {
                  return JSON.stringify({ error: 'No files found in this link' });
                }

                let file = data.list[0];
                
                return JSON.stringify({
                  title: file.server_filename,
                  image: file.thumbs ? file.thumbs.url3 : "",
                  dLink: file.dlink,
                  size: file.size,
                  fs_id: file.fs_id
                });
              } catch(e) {
                return JSON.stringify({ error: e.toString() });
              }
            })();
          '''.replaceAll('$shortUrl', shortUrl!));
          
          if (jsResult != null) {
            final data = jsonDecode(jsResult as String);
            
            if (data['error'] != null) {
              completer.completeError("Extraction failed: ${data['error']}");
              return;
            }

            final fileTitle = data['title'] ?? 'Terabox File';
            final thumbUrl = data['image'] ?? 'https://picsum.photos/400/300';
            final downloadUrl = data['dLink'];
            final sizeStr = data['size'];
            final sizeInt = sizeStr != null ? int.tryParse(sizeStr.toString()) : null;

            if (downloadUrl == null) {
              completer.completeError("Could not find direct download link. Are you logged in?");
              return;
            }

            if (!completer.isCompleted) {
              completer.complete(MediaInfo(
                title: fileTitle,
                thumbnailUrl: thumbUrl,
                author: 'Terabox Share',
                type: 'File',
                platform: 'Terabox',
                formats: [
                  DownloadFormat(
                    id: 'terabox_direct',
                    label: 'Direct File Download',
                    url: downloadUrl,
                    fileExtension: fileTitle.split('.').last, 
                    sizeBytes: sizeInt,
                  )
                ],
              ));
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.completeError("JS Error: $e");
        }
      },
    );

    await _headlessWebView?.run();
    
    // Timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.completeError('Timeout analyzing Terabox URL');
        _headlessWebView?.dispose();
      }
    });

    try {
      final info = await completer.future;
      return info;
    } finally {
      await _headlessWebView?.dispose();
      _headlessWebView = null;
    }
  }
}
