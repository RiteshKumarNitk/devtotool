import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/scripts/debug_sdk_string.dart';
import '../../core/scripts/debug_sdk_extras.dart';
import '../../core/js_bridge.dart';
import '../../core/providers.dart';
import '../../core/tool_providers.dart';
import '../../services/export_service.dart';

class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key});

  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends ConsumerState<BrowserPage> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  static const String _homeUrl = 'https://flutter.dev';
  bool _isLoading = false;
  bool _sdkActive = false;
  double _progress = 0.0;

  static const _userAgents = {
    'default': 'Default',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1':
        'iPhone (Safari)',
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36':
        'Android (Chrome)',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36':
        'Desktop Chrome',
  };

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
            ref.read(pageDataProvider.notifier).clear();
            ref.read(domTreeProvider.notifier).setTree({});
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _urlController.text = url;
            });
          },
          onPageFinished: (String url) async {
            if (mounted) setState(() => _isLoading = false);
            await _injectDebugSdk();
            final title = await _controller.getTitle() ?? '';
            ref.read(currentPageProvider.notifier).set(url, title);
            ref.read(historyProvider.notifier).record(url, title);
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
      await _controller.runJavaScript(debugSdkExtrasJs);
      _sdkActive = true;
      await _pushMocks(ref.read(networkMocksProvider));
      await _pushNetworkCondition(ref.read(networkConditionProvider));
      await _pushGeo(ref.read(geoOverrideProvider));
    } catch (e) {
      debugPrint('Debug SDK injection failed: $e');
    }
  }

  Future<void> _run(String js, String what) async {
    try {
      await _controller.runJavaScript(js);
    } catch (e) {
      debugPrint('Failed to $what: $e');
    }
  }

  Future<void> _pushMocks(List<MockRule> rules) {
    final payload = jsString(jsonEncode(rules.map((r) => r.toJson()).toList()));
    return _run('if (window.updateApiMocks) window.updateApiMocks($payload);', 'push mocks');
  }

  Future<void> _pushNetworkCondition(NetworkCondition condition) {
    final payload = jsString(jsonEncode(condition.toJson()));
    return _run('if (window.updateNetConfig) window.updateNetConfig($payload);', 'push network condition');
  }

  Future<void> _pushGeo(GeoOverride? geo) {
    final payload = geo == null ? 'null' : jsString(jsonEncode(geo.toJson()));
    return _run('if (window.__dbg && window.__dbg.setGeolocation) window.__dbg.setGeolocation($payload);',
        'push geolocation');
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
      case PageDataMessage(:final kind, :final data):
        ref.read(pageDataProvider.notifier).put(kind, data);
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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'theme':
        ref.read(themeProvider.notifier).toggle();
      case 'screenshot':
        final image = await ref.read(screenshotControllerProvider).capture();
        if (image == null) {
          _snack('Screenshot failed');
          return;
        }
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(image);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: 'Screenshot from Debug Browser',
        ));
      case 'export':
        final ok = await ExportService.exportSession(ref);
        if (!ok) _snack('Export failed');
      case 'hard_reload':
        await _controller.clearCache();
        await _controller.clearLocalStorage();
        await WebViewCookieManager().clearCookies();
        ref.read(consoleLogsProvider.notifier).clear();
        ref.read(networkRequestsProvider.notifier).clear();
        _sdkActive = false;
        _controller.reload();
        _snack('Cache cleared & hard reloaded');
      case 'bookmark':
        final currentUrl = await _controller.currentUrl() ?? _urlController.text;
        final title = await _controller.getTitle();
        if (currentUrl.isEmpty) return;
        final added = ref.read(bookmarksProvider.notifier).addBookmark(
            (title == null || title.isEmpty) ? currentUrl : title, currentUrl);
        _snack(added ? 'Bookmark added' : 'Already bookmarked');
      default:
        if (value.startsWith('ua_')) {
          final agent = value.substring(3);
          ref.read(userAgentProvider.notifier).setAgent(agent);
          await _controller.setUserAgent(agent == 'default' ? null : agent);
          _sdkActive = false;
          _controller.reload();
          _snack('User-Agent: ${_userAgents[agent] ?? 'Custom'}');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkMocksProvider, (prev, next) => _pushMocks(next));
    ref.listen(networkConditionProvider, (prev, next) => _pushNetworkCondition(next));
    ref.listen(geoOverrideProvider, (prev, next) => _pushGeo(next));
    final viewport = ref.watch(viewportProvider);
    final currentAgent = ref.watch(userAgentProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'Search or enter URL',
            border: InputBorder.none,
            prefixIcon: IconButton(
              icon: const Icon(Icons.bookmarks, color: Colors.blueAccent),
              tooltip: 'Bookmarks',
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
            tooltip: 'Back',
            onPressed: () async {
              if (await _controller.canGoBack()) _controller.goBack();
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'Forward',
            onPressed: () async {
              if (await _controller.canGoForward()) _controller.goForward();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              _sdkActive = false;
              _controller.reload();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'bookmark', child: Text('Bookmark this page')),
              const PopupMenuItem(value: 'theme', child: Text('Toggle theme')),
              const PopupMenuItem(value: 'screenshot', child: Text('Capture screenshot')),
              const PopupMenuItem(value: 'export', child: Text('Export session data')),
              const PopupMenuItem(value: 'hard_reload', child: Text('Hard reload & clear data')),
              const PopupMenuDivider(),
              for (final e in _userAgents.entries)
                CheckedPopupMenuItem(
                  value: 'ua_${e.key}',
                  checked: currentAgent == e.key,
                  child: Text('UA: ${e.value}'),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading ? LinearProgressIndicator(value: _progress) : const SizedBox(height: 4.0),
        ),
      ),
      body: SafeArea(
        child: Screenshot(
          controller: ref.watch(screenshotControllerProvider),
          child: _buildViewport(viewport),
        ),
      ),
    );
  }

  /// Constrains the WebView to the emulated device size (scaled down to fit).
  Widget _buildViewport(ViewportPreset preset) {
    final web = WebViewWidget(controller: _controller);
    if (preset.width == null) return web;
    return LayoutBuilder(builder: (context, box) {
      final w = preset.width!, h = preset.height!;
      final scale = [box.maxWidth / w, box.maxHeight / h, 1.0].reduce((a, b) => a < b ? a : b);
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${preset.label} • ${w.toInt()}×${h.toInt()}${scale < 1 ? ' • ${(scale * 100).round()}%' : ''}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey, width: 2)),
                      child: web,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showBookmarksBottomSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final bookmarks = ref.watch(bookmarksProvider);
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Bookmarks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: bookmarks.isEmpty
                      ? const Center(child: Text('No bookmarks saved.'))
                      : ListView.builder(
                          itemCount: bookmarks.length,
                          itemBuilder: (context, index) {
                            final b = bookmarks[index];
                            return ListTile(
                              leading: const Icon(Icons.bookmark_outline),
                              title: Text(b['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(b['url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () =>
                                    ref.read(bookmarksProvider.notifier).removeBookmark(b['url'] ?? ''),
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
