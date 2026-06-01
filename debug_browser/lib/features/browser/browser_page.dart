import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/scripts/debug_sdk_string.dart';
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
  bool _isLoading = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _urlController.text = 'https://flutter.dev';
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100.0;
            });
            if (progress == 100) {
              _injectDebugSdk();
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              setState(() {
                _urlController.text = change.url!;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _urlController.text = url;
            });
            _injectDebugSdk();
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _injectDebugSdk();
          },
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..addJavaScriptChannel(
        'DebugBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _handleJsMessage(message.message);
        },
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage msg) {
        String level = 'info';
        if (msg.level.name == 'error') {
          level = 'error';
        } else if (msg.level.name == 'warning') {
          level = 'warn';
        } else if (msg.level.name == 'debug') {
          level = 'debug';
        }
        ref.read(consoleLogsProvider.notifier).addLog(
          ConsoleLog(
            level: level,
            message: '[System] \${msg.message}',
            timestamp: DateTime.now(),
          ),
        );
      })
      ..loadRequest(Uri.parse(_urlController.text));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(webViewControllerProvider.notifier).setController(_controller);
    });
  }

  void _injectDebugSdk() {
    _controller.runJavaScript(debugSdkJs);
    final mocks = ref.read(networkMocksProvider);
    final jsonStr = jsonEncode(mocks).replaceAll("'", "\\'");
    _controller.runJavaScript("window.updateApiMocks('$jsonStr');");
  }

  void _handleJsMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      final type = decoded['type'];
      final data = decoded['data'];
      final timestamp = DateTime.fromMillisecondsSinceEpoch(decoded['timestamp'] ?? DateTime.now().millisecondsSinceEpoch);

      if (type == 'console') {
        ref.read(consoleLogsProvider.notifier).addLog(
          ConsoleLog(
            level: data['level'],
            message: data['message'],
            timestamp: timestamp,
          ),
        );
      } else if (type == 'error') {
        ref.read(consoleLogsProvider.notifier).addLog(
          ConsoleLog(
            level: 'error',
            message: data['message'] + (data['stack'] != null ? "\\n\${data['stack']}" : ''),
            timestamp: timestamp,
          ),
        );
      } else if (type == 'network') {
        ref.read(networkRequestsProvider.notifier).addRequest(
          NetworkRequest(
            type: data['type'],
            url: data['url'],
            method: data['method'],
            status: data['status'],
            duration: data['duration'],
            requestBody: data['requestBody'],
            responseBody: data['responseBody'],
            error: data['error'],
            timestamp: timestamp,
          ),
        );
      } else if (type == 'storage') {
        ref.read(storageProvider.notifier).updateStorage(data);
      } else if (type == 'device' || type == 'performance') {
        ref.read(devicePerformanceProvider.notifier).updateInfo({type: data});
      } else if (type == 'dom_node') {
        ref.read(domTreeProvider.notifier).setTree(data);
      }
    } catch (e) {
      debugPrint('Error parsing JS message: \$e');
    }
  }

  void _loadUrl() {
    String url = _urlController.text.trim();
    if (!url.startsWith('http')) {
      url = 'https://\$url';
    }
    _controller.loadRequest(Uri.parse(url));
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkMocksProvider, (prev, next) {
      final jsonStr = jsonEncode(next).replaceAll("'", "\\'");
      _controller.runJavaScript("window.updateApiMocks('$jsonStr');");
    });
    
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
            onPressed: () => _controller.reload(),
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
                  final file = await File("${tempDir.path}/screenshot.png").create();
                  await file.writeAsBytes(image);
                  await Share.shareXFiles([XFile(file.path)], text: 'Screenshot from Debug Browser');
                }
              } else if (value == 'export') {
                await ExportService.exportSession(ref);
              } else if (value == 'hard_reload') {
                await _controller.clearCache();
                await _controller.clearLocalStorage();
                await WebViewCookieManager().clearCookies();
                ref.read(consoleLogsProvider.notifier).clear();
                ref.read(networkRequestsProvider.notifier).clear();
                _controller.reload();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared & hard reloaded!')));
              } else if (value.startsWith('ua_')) {
                final agent = value.substring(3);
                ref.read(userAgentProvider.notifier).setAgent(agent);
                await _controller.setUserAgent(agent == 'default' ? null : agent);
                _controller.reload();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User-Agent changed to \$agent')));
              } else if (value == 'bookmark') {
                final currentUrl = _urlController.text;
                if (currentUrl.isNotEmpty) {
                  ref.read(bookmarksProvider.notifier).addBookmark('Bookmark', currentUrl);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmarked added!')));
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
                                _urlController.text = b['url'] ?? '';
                                _loadUrl();
                                Navigator.pop(context);
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
