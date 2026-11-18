import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tabs_provider.dart';
import 'tool_providers.dart';

/// Scale of the preview relative to the screen (~1/3 keeps 30 tabs to a few MB).
const double thumbnailPixelRatio = 0.35;

/// True if a raw RGBA buffer is (nearly) one colour: a blank WebView capture
/// or a page that hasn't painted yet. Samples ~2000 pixels.
bool isBlankRgba(Uint8List rgba, {int tolerance = 6}) {
  final pixels = rgba.length ~/ 4;
  if (pixels == 0) return true;
  final step = (pixels / 2000).ceil().clamp(1, pixels);
  final r0 = rgba[0], g0 = rgba[1], b0 = rgba[2];
  for (var p = 0; p < pixels; p += step) {
    final i = p * 4;
    if ((rgba[i] - r0).abs() > tolerance ||
        (rgba[i + 1] - g0).abs() > tolerance ||
        (rgba[i + 2] - b0).abs() > tolerance) {
      return false;
    }
  }
  return true;
}

/// Captures the visible page into the active tab's thumbnail. Never throws.
Future<void> captureActiveTabThumbnail(WidgetRef ref) async {
  final tabId = ref.read(tabsProvider).activeId;
  ui.Image? image;
  try {
    image = await ref
        .read(screenshotControllerProvider)
        .captureAsUiImage(pixelRatio: thumbnailPixelRatio, delay: Duration.zero);
    if (image == null) return;
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null || isBlankRgba(raw.buffer.asUint8List())) return;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    ref.read(tabThumbnailsProvider.notifier).put(tabId, png.buffer.asUint8List());
  } catch (e) {
    debugPrint('Thumbnail capture skipped: $e');
  } finally {
    image?.dispose();
  }
}
