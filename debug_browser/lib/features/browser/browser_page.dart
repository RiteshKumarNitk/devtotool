import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/scripts/debug_sdk_string.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../services/export_service.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key});

  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController();
  static const String _homeUrl = 'https://flutter.dev';
  bool _isLoading = false;
  bool _sdkActive = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _urlController.text = _homeUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _progress = progress / 100.0);
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null && mounted) {
              setState(() => _urlController.text = change.url!);
            }
          },
          onPageStarted: (String url) {
            _sdkActive = false; // new document: SDK not injected yet
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _urlController.text = url;
            });
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _injectDebugSdk();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame != true) return;
            ref.read(consoleLogsProvider.notifier).addLog(ConsoleLog(
                  level: 'error',
                  message: '[Navigation] ${error.errorCode}: ${error.description}',
                  timestamp: DateTime.now(),
                ));
          },
        ),
      )
      ..addJavaScriptChannel(
        'DebugBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJsMessage(message.message);
        },
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage msg) {
        // Native console messages are only used before the SDK hooks the
        // page console, to avoid duplicates afterwards.
        if (_sdkActive) return;
        final level = switch (msg.level) {
          JavaScriptLogLevel.error => 'error',
          JavaScriptLogLevel.warning => 'warn',
          JavaScriptLogLevel.debug => 'debug',
          _ => 'info',
        };
        ref.read(consoleLogsProvider.notifier).addLog(
              ConsoleLog(
                level: level,
                message: '[System] ${msg.message}',
                timestamp: DateTime.now(),
              ),
            );
      })
      ..loadRequest(Uri.parse(_homeUrl));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webViewControllerProvider.notifier).setController(_controller);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _injectDebugSdk() async {
    try {
      await _controller.runJavaScript(debugSdkJs);
      _sdkActive = true;
      await _pushMocks(ref.read(networkMocksProvider));
    } catch (e) {
      debugPrint('Debug SDK injection failed: $e');
    }
  }

  Future<void> _pushMocks(Map<String, String> mocks) async {
    final payload = jsString(jsonEncode(mocks));
    try {
      await _controller.runJavaScript(
          'if (window.updateApiMocks) window.updateApiMocks($payload);');
    } catch (e) {
      debugPrint('Failed to push mocks: $e');
    }
  }

  void _handleJsMessage(String raw) {
    final msg = parseBridgeMessage(raw);
    switch (msg) {
      case ConsoleMessage(:final log):
        ref.read(consoleLogsProvider.notifier).addLog(log);
      case NetworkMessage(:final request):
        ref.read(networkRequestsProvider.notifier).addRequest(request);
      case StorageMessage(:final data):
        ref.read(storageProvider.notifier).updateStorage(data);
      case DeviceInfoMessage(:final kind, :final data):
        ref.read(devicePerformanceProvider.notifier).updateInfo({kind: data});
      case DomNodeMessage(:final data):
        ref.read(domTreeProvider.notifier).setTree(data);
      case null:
        debugPrint('Ignored malformed bridge message');
    }
  }

  void _loadUrl() {
    final uri = normaliseUrlInput(_urlController.text);
    _sdkActive = false;
    _controller.loadRequest(uri);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkMocksProvider, (prev, next) => _pushMocks(next));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'Enter URL',
            border: InputBorder.none,
            prefixIcon: IconButton(
              icon: const Icon(Icons.bookmarks, color: Colors.blueAccent),
              onPressed: _showBookmarksBottomSheet,
            ),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _loadUrl(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                _controller.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () async {
              if (await _controller.canGoForward()) {
                _controller.goForward();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _sdkActive = false;
              _controller.reload();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            onSelected: (value) async {
              if (value == 'theme') {
                ref.read(themeProvider.notifier).toggle();
              } else if (value == 'screenshot') {
                final image = await _screenshotController.capture();
                if (image != null) {
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
                  await file.writeAsBytes(image);
                  await SharePlus.instance.share(ShareParams(
                    files: [XFile(file.path)],
                    text: 'Screenshot from Debug Browser',
                  ));
                }
              } else if (value == 'export') {
                final ok = await ExportService.exportSession(ref);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export failed')));
                }
              } else if (value == 'hard_reload') {
                await _controller.clearCache();
                await _controller.clearLocalStorage();
                await WebViewCookieManager().clearCookies();
                ref.read(consoleLogsProvider.notifier).clear();
                ref.read(networkRequestsProvider.notifier).clear();
                _sdkActive = false;
                _controller.reload();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared & hard reloaded!')));
              } else if (value.startsWith('ua_')) {
                final agent = value.substring(3);
                ref.read(userAgentProvider.notifier).setAgent(agent);
                await _controller.setUserAgent(agent == 'default' ? null : agent);
                _sdkActive = false;
                _controller.reload();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User-Agent changed to \$agent')));
              } else if (value == 'bookmark') {
                final currentUrl = await _controller.currentUrl() ?? _urlController.text;
                final title = await _controller.getTitle();
                if (currentUrl.isNotEmpty) {
                  final added = ref.read(bookmarksProvider.notifier).addBookmark(
                      (title == null || title.isEmpty) ? currentUrl : title, currentUrl);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(added ? 'Bookmark added' : 'Already bookmarked')));
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'bookmark',
                child: Text('Bookmark this Page'),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: Text('Toggle Theme'),
              ),
              const PopupMenuItem(
                value: 'screenshot',
                child: Text('Capture Screenshot'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export Session Data'),
              ),
              const PopupMenuItem(
                value: 'hard_reload',
                child: Text('Hard Reload & Clear Data'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'ua_default',
                child: Text('UA: Default'),
              ),
              const PopupMenuItem(
                value: 'ua_Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                child: Text('UA: iPhone iOS 16'),
              ),
              const PopupMenuItem(
                value: 'ua_Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
                child: Text('UA: Desktop Chrome'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading
              ? LinearProgressIndicator(value: _progress)
              : const SizedBox(height: 4.0),
        ),
      ),
      body: SafeArea(
        child: Screenshot(
          controller: _screenshotController,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }

  void _showBookmarksBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final bookmarks = ref.watch(bookmarksProvider);
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Bookmarks & Fast Tabs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
                Expanded(
                  child: bookmarks.isEmpty
                      ? const Center(child: Text('No bookmarks saved.'))
                      : ListView.builder(
                          itemCount: bookmarks.length,
                          itemBuilder: (context, index) {
                            final b = bookmarks[index];
                            return ListTile(
                              leading: const Icon(Icons.tab),
                              title: Text(b['title'] ?? ''),
                              subtitle: Text(b['url'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  ref.read(bookmarksProvider.notifier).removeBookmark(b['url'] ?? '');
                                },
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _urlController.text = b['url'] ?? '';
                                _loadUrl();
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
