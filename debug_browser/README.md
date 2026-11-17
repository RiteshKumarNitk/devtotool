# Debug Browser

A Flutter mobile browser with built-in developer tools, for debugging web pages directly on a phone without a desktop DevTools connection.

## Features

| Panel | What it does |
|---|---|
| **Browser** | Address bar (URL or search), back/forward/reload, bookmarks (persisted), User-Agent switching, hard reload (clears cache, storage and cookies), screenshot, session export |
| **Console** | Captures `console.*`, uncaught errors and unhandled rejections; includes a JS REPL against the current page |
| **Network** | Logs `fetch` and `XMLHttpRequest` calls with method, status, timing and request/response bodies (text only, truncated at 100 KB) |
| **API Mocks** | Return a fixed response for any URL containing a pattern (fetch and XHR); persisted across launches |
| **Storage** | View, edit and delete `localStorage` / `sessionStorage`; view cookies |
| **DOM** | Tap-to-inspect elements: tag, id, classes and key computed styles |
| **Device / Performance** | User agent, screen, locale; load time, FCP, JS heap usage |

Session data (console + network + storage + device) exports as JSON through the share sheet.

## Architecture

```
lib/
  core/
    providers.dart        Riverpod state (capped buffers, Hive-persisted settings)
    js_bridge.dart        Pure parsing of messages from the page + JS-safe encoding
    scripts/debug_sdk_string.dart   JS SDK injected into each page
  features/<panel>/       One folder per panel
  services/export_service.dart
```

The JS SDK is injected after each page load. It hooks the console, errors, `fetch` and XHR, and sends JSON messages over the `DebugBridge` JavaScript channel. `parseBridgeMessage` validates every message, because page content is untrusted.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Release (Android)

1. Application ID: `com.innovatextechnology.debugbrowser` (Android `applicationId`/`namespace`, iOS bundle ID, Linux app ID). Don't change it after the first store release.
2. Create a keystore and `android/key.properties`:
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/absolute/path/to/upload-keystore.jks
   ```
   This file is git-ignored. Without it, release builds fall back to debug signing.
3. Build: `flutter build appbundle --release`.

## Known limitations

- Logs written before the page finishes loading are captured only through the native console fallback, not the SDK.
- Request/response **headers** are not captured yet; that needs native request interception.
- Screenshots of the WebView can come out blank on some Android devices (platform-view limitation).
