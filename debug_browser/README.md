# Debug Browser

A Flutter mobile browser with built-in developer tools, for debugging web pages directly on a phone without a desktop DevTools connection. By InnovateX Technology.

## Features

| Area | What it does |
|---|---|
| **Browser** | Chrome/Firefox-style: opens to Google (or your homepage). Address bar with padlock/site info, suggestions from bookmarks and history, and your choice of search engine (Google, DuckDuckGo, Bing, Brave). Bottom toolbar: back, forward, home, tabs, menu. |
| **New Tab page** | Brave-style home for new tabs: animated aurora background (6 themes), lifetime privacy stats (ads & trackers blocked, estimated data and time saved), search pill, top sites (bookmarks + most visited) and a Customize sheet. Private tabs get their own explanation page. Can be turned off (Home then opens the search engine). |
| **First-run welcome** | Four animated steps: welcome, privacy (blocker/cookie/dark switches), search engine, and "Set as default browser" via Android's system prompt. Skippable. |
| **Default browser** | Declares http/https links, so it can be the default browser; links from other apps open in a new tab. |
| **Browsing comfort** | Site icons in tabs, history, bookmarks, suggestions and New Tab tiles (learned from each page, never in private tabs); pull to refresh; toolbars that hide while scrolling down. |
| **HTTPS-only mode** | http:// sites load over https://; if that fails, a clear page offers "Continue to site (not secure)". Local/private-network addresses are never upgraded; https-to-http redirect loops are detected. |
| **Backup & restore** | One JSON file with bookmarks, settings, extensions, user scripts, mock rules, environments, snippets (history optional; proxy password never included). Restore merges and never deletes; a restored proxy starts off. |
| **Back button** | Browser-like: page history, then the tab that opened this one, then the New Tab page, then "Exit Debug Browser?". |
| **More browser tools** | Live search suggestions (off in private tabs / with a proxy), swipe the address bar to switch tabs, Add to Home screen, View page source (formatted, highlighted, searchable), Translate page (Google Translate), Read aloud (on-device TTS with player), Save for offline (MHTML) and Offline pages, full-page screenshots. |
| **Privacy extras** | Lock private tabs with fingerprint/screen lock; private tabs hidden from Recents and screenshots; clear data when exiting. |
| **More developer tools** | Edit & resend network requests (from the page, with its cookies), JSON viewer for API responses, Lighthouse-style page audit (performance, accessibility, best practices, SEO), responsive screenshots at phone/tablet/desktop sizes. |
| **More extensions** | Block this element (tap to pick, "Bigger", preview; per site), JavaScript on/off per site, data saver (no images), readable text, video speed for any web player (all frames), picture-in-picture for web video (not YouTube), highlighter & notes (re-applied on revisit by text context), night light, Save as PDF / Print, QR code show & scan (Google Code Scanner: no camera permission), search shortcuts ("w taj mahal"). |
| **Organisation** | Bookmark folders; tab groups with colours and filters; tablet tab strip (≥ 840dp); home-screen search widget; Quick Settings "Private tab" tile. |
| **Tabs** | Multiple tabs with a tab switcher showing page previews (swipe to close, close all); restored on restart and loaded lazily. Links with `target=_blank` and `window.open` open new tabs; long-press a link for open in new/background tab, copy, share. |
| **Private tabs** | Chrome-style private browsing: a separate WebView profile with its own cookies and site data (Android System WebView 110+), no history, not restored, no previews; all private data is wiped when the last private tab closes. Dark private theme; separate section in the tab switcher. On older WebViews private tabs are refused rather than silently shared. |
| **Proxy / VPN** | Route all browser traffic through your VPN provider's HTTP, HTTPS or SOCKS5 proxy (paste `user:pass@host:port`), with bypass list, HTTP proxy sign-in and a "Check my IP" button. Uses WebView proxy override: only this browser is affected, it is not a system VPN, and the app provides no servers. |
| **History** | Grouped by day, search, swipe to delete, clear last hour / today / all time, open in new or private tab. |
| **Extensions** | Built in, with an Extensions page and a per-site shield in the address bar: **ad & tracker blocker** (~140 known networks; fetch/XHR/beacons, scripts, iframes, images and empty ad slots; per-site off switch and blocked counter; YouTube is always excluded), **dark mode for all websites** (skips sites that are already dark), **pop-up & redirect blocker** (Chrome-style: new windows only from a tap on a real link to that site; invisible full-screen click-stealing layers are removed; page jumps to known pop-under networks are stopped; "Open anyway" on each blocked pop-up), **cookie-banner hiding**, **reader mode**, **text size per site**, and **user scripts** (your own JS/CSS on URL patterns, Chrome-style host-safe matching, import/export, errors isolated per script). Runs at document start via WebView document-start scripts (falls back to after-load on old WebViews). |
| **Site sign-in** | Pages that require HTTP authentication show a username/password dialog. |
| **Menu** | Site card, new tab, bookmark, share, reload, history, bookmarks, find in page, desktop site, copy link, screenshot, **Developer tools**, hard reload, settings. |
| **Downloads** | Files the page serves as downloads (PDFs, APKs, archives), `<a download>` links, script-generated `blob:`/`data:` files (up to 25 MB) and long-press "Download link / image" are saved with progress, cancel, retry, open, share and delete. On Android 10+ finished files go to the phone's shared **Downloads** folder (MediaStore; no storage permission) and open in their default app. File names come from `Content-Disposition` (RFC 6266) or the URL and are sanitised. |
| **Find in page** | Highlights all matches with a match count and next/previous. |
| **Other apps** | `tel:`, `mailto:`, `sms:`, maps, Play Store and `intent://` links open the right app (or the intent's fallback URL). |
| **Settings** | Grouped cards with colour-coded icons: search engine, homepage, reopen tabs, clear browsing data, floating debug bubble on/off. |
| **Appearance** | Theme follows the phone (System) or is fixed Light/Dark; six accent colours restyle the whole app with a smooth theme animation. Android predictive-back page transitions. |
| **Tab comfort** | Closing a tab shows **Undo**; **Recently closed** (menu or tab switcher) reopens tabs closed this session at their old position (never private tabs). Long-press the tabs button for New tab / New private tab / Reopen / Close. Tab cards animate in, and swiping one away shows a delete background. |
| **Feel** | Haptic ticks on tab swipe, pull-to-refresh threshold, bookmark, close and theme choices; the address bar lifts and outlines while you type; "Paste and go" chip when the clipboard has text (read only when tapped, no clipboard toast). Menu opens with a site card (title, host, padlock; tap to copy the link). |
| **Developer tools** | Opened from the menu or the bubble, never shown in the footer. Panels below. |
| **Floating debug bubble** | Draggable bubble over the page showing live error/request counts; opens Console, Network, Performance or a bug report. An orange ring means network throttling is on. Can be turned off in Settings. |
| **Console** | Captures `console.*`, uncaught errors and rejections. Level filters with counts, search, JSON shown as an expandable tree, copy all. JS REPL with command history. |
| **JS snippets** | Saved scripts (starter set included) you can run against the page in one tap. |
| **Network** | `fetch`/XHR with method, status, timing, request/response headers and bodies (text only, truncated at 100 KB). Filter by text, type and status class. Copy as cURL / fetch, HAR export. |
| **Network conditions** | Fast 3G, Slow 3G or Offline for the page's fetch/XHR (session-only, with a banner). |
| **API mocks** | Rules matching URL substring or regex, plus HTTP method; custom status, delay, content type and body; on/off per rule; import/export as JSON. Persisted. |
| **Storage** | View, search, add, edit and delete `localStorage`, `sessionStorage` and cookies (path and expiry for cookies); clear all. |
| **DOM** | Tap-to-inspect or browse the element tree; select to highlight in the page. Edit CSS properties and attributes live; view outerHTML. |
| **Performance** | Core Web Vitals (LCP, INP*, CLS, FCP, TTFB) with good/needs-work/poor ratings, load timing, JS heap, resource breakdown and a waterfall of the slowest resources. |
| **Accessibility audit** | Missing alt text, unlabelled controls and form fields, colour contrast (WCAG AA), tap-target size, heading order, duplicate ids, missing lang/title, zoom blocking. Tap an issue to highlight the element. |
| **Device emulation** | Viewport presets (iPhone SE/15, Pixel 8, Galaxy Fold, iPad mini, laptop) and geolocation override (presets or custom). |
| **Environments** | Saved dev/staging/prod base URLs; "open current path here" switches environment while keeping the path and query. |
| **Saved sessions** | Save console + network data on the device, reload it later, or share it as JSON. |
| **Bug report** | One tap bundles a Markdown report (URL, device, description, errors, failed requests as cURL, Web Vitals), a screenshot and a HAR file into the share sheet. |

\*INP is approximated from the slowest interaction observed so far.

**Privacy:** all data stays on the device. The app has no analytics, accounts or servers; data leaves the device only when the user shares or exports it.

## Architecture

```
lib/
  core/
    providers.dart          Core state: console/network buffers, mock rules, theme, bookmarks
    browser_settings.dart   Search engine, homepage, desktop mode, bubble
    tabs_provider.dart      Tab engine: one WebView per tab, bridge, external links
    tool_providers.dart     Tools state: tabs, page data, emulation, history, environments,
                            snippets, saved sessions
    js_bridge.dart          Validated parsing of page messages + JS-safe string encoding
    network_export.dart     cURL / fetch / HAR builders and network filters (pure)
    scripts/
      debug_sdk_string.dart   Injected SDK: console, errors, fetch/XHR, mocks, throttling
      debug_sdk_extras.dart   Injected SDK: Web Vitals, DOM tree/editing, a11y audit, geolocation
  features/<panel>/         One folder per panel; more/ holds the tools hub
  services/                 Export (JSON/HAR) and bug-report bundling
```

The SDK is injected after each page load. It reports over the `DebugBridge` JavaScript channel, and `parseBridgeMessage` validates every message because page content is untrusted. Values passed from Dart into page JavaScript always go through `jsString()` (JSON encoding), never string concatenation.

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

## Performance

- **Memory:** only the 5 most recently used tabs keep a live page; older background tabs are unloaded and reload (from their saved address) when opened, like Chrome's tab discarding. Private tabs are never unloaded. On Android low-memory warnings every background tab is unloaded. Tab previews are decoded at card size.
- **Smooth loading:** page-load progress updates only the progress bar, not the whole browser screen.
- **Busy pages:** console lines and network requests are published in batches (at most every 100 ms); REPL input and results show immediately.
- **Start-up:** the full splash animation plays on the first run; afterwards it runs in under a second (tap skips it).
- **Download size:** upload the App Bundle (`flutter build appbundle`); Play then serves each phone only its own CPU code. For side-loading tests use `flutter build apk --split-per-abi` (pick `app-arm64-v8a-release.apk` for modern phones).

## Known limitations

- Logs written before the page finishes loading are captured only through the native console fallback, not the SDK.
- Only `fetch`/XHR traffic is captured, mocked and throttled. Images, CSS, scripts and navigations need native request interception.
- Headers that browsers hide from JavaScript (`Set-Cookie`, most cross-origin response headers) are not visible, and HttpOnly cookies are not listed.
- The geolocation override applies to calls made after the page loads.
- Developer tools show the active tab only; background tabs are not recorded.
- The blocker runs inside the page (WebView doesn't let apps cancel arbitrary network requests), so ad requests written directly into a page's HTML may still load; dynamic ads, trackers and beacons are blocked.
- Proxy sign-in works for HTTP/HTTPS proxies only (Android WebView can't authenticate to SOCKS5). The proxy password is stored unencrypted in the app's private storage.
- Downloads use the page's readable cookies only; files behind HttpOnly-cookie logins may fail. On Android 7–9 files stay in the app's folder (`Android/data/<app>/files/Download`) and open via the share sheet.
- Screenshots of the WebView can come out blank on some Android devices (platform-view limitation).
