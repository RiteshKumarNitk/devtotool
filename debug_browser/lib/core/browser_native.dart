import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Native browser features (see BrowserBridge.kt). All calls fail soft and
/// report "unsupported" off Android, on old WebViews and in tests.
abstract final class BrowserNative {
  static const _channel = MethodChannel('com.innovatextechnology.debugbrowser/browser');

  static Future<bool> _bool(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (e) {
      debugPrint('BrowserNative.$method failed: $e');
      return false;
    }
  }

  static Future<bool> privateSupported() => _bool('privateSupported');

  /// Moves a new WebView into the private profile. Must run before it loads
  /// anything. Returns true only if verified on the native side.
  static Future<bool> makePrivate(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) return false;
    return _bool('setPrivateProfile', {'id': platform.webViewIdentifier});
  }

  static Future<bool> clearPrivateData() => _bool('clearPrivateData');

  static Future<bool> proxySupported() => _bool('proxySupported');

  static Future<bool> setProxy(String rule, {List<String> bypass = const [], bool bypassLocal = true}) =>
      _bool('setProxy', {'rule': rule, 'bypass': bypass, 'bypassLocal': bypassLocal});

  static Future<bool> clearProxy() => _bool('clearProxy');
}
