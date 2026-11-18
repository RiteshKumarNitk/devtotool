import 'dart:typed_data';

import 'package:debug_browser/core/tabs_provider.dart';
import 'package:debug_browser/core/thumbnails.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List solid(int pixels, int r, int g, int b) {
  final out = Uint8List(pixels * 4);
  for (var i = 0; i < pixels; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = 255;
  }
  return out;
}

void main() {
  group('isBlankRgba', () {
    test('single-colour captures are blank', () {
      expect(isBlankRgba(solid(10000, 255, 255, 255)), isTrue);
      expect(isBlankRgba(solid(10000, 0, 0, 0)), isTrue);
      expect(isBlankRgba(Uint8List(0)), isTrue);
    });

    test('tiny compression noise still counts as blank', () {
      final img = solid(10000, 250, 250, 250);
      img[4000] = 253; // within tolerance
      expect(isBlankRgba(img), isTrue);
    });

    test('real content is not blank', () {
      final img = solid(10000, 255, 255, 255);
      // A dark text-like stripe across sampled pixels.
      for (var p = 0; p < 10000; p += 3) {
        img[p * 4] = 20;
      }
      expect(isBlankRgba(img), isFalse);
    });
  });

  test('thumbnail store: put, remove, retain', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(tabThumbnailsProvider.notifier);
    n.put('a', Uint8List.fromList([1]));
    n.put('b', Uint8List.fromList([2]));
    n.remove('a');
    expect(c.read(tabThumbnailsProvider).keys, ['b']);
    n.put('c', Uint8List.fromList([3]));
    n.retain(['c']);
    expect(c.read(tabThumbnailsProvider).keys, ['c']);
  });
}
