import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:imprenta/print/pwg_raster.dart';

/// Reference decoder for the PWG line compression, to check the encoder round-trips.
Uint8List decode(Uint8List data, int w, int h, {int ch = 1}) {
  final s = w * ch;
  final out = Uint8List(s * h);
  var p = 4 + 1796, y = 0;
  while (y < h) {
    final rep = data[p++] + 1;
    final line = Uint8List(s);
    var x = 0;
    while (x < w) {
      final c = data[p++];
      if (c < 128) {
        for (var r = 0; r <= c; r++) {
          line.setRange((x + r) * ch, (x + r + 1) * ch, data, p);
        }
        p += ch;
        x += c + 1;
      } else {
        final n = 257 - c;
        line.setRange(x * ch, (x + n) * ch, data, p);
        p += n * ch;
        x += n;
      }
    }
    for (var r = 0; r < rep; r++) {
      out.setRange((y + r) * s, (y + r + 1) * s, line);
    }
    y += rep;
  }
  expect(p, data.length);
  return out;
}

void main() {
  test('round-trips runs, literals, single pixels and repeated lines', () {
    const w = 300, h = 400;
    final px = Uint8List(w * h)..fillRange(0, w * h, 255);
    for (var x = 0; x < w; x++) {
      px[10 * w + x] = x % 7 == 0 ? 0 : (x * 37) & 0xff; // literal-heavy line
    }
    px[20 * w + 299] = 0; // single pixel at line end
    for (var y = 100; y < 380; y++) {
      px[y * w + 5] = 0; // 280 identical lines: more than one 256-line repeat
    }
    final enc = encodePwgRaster([RasterPage(px, w, h)], dpi: 300, pageSizeName: 'na_foolscap_8.5x13in');
    expect(String.fromCharCodes(enc.sublist(0, 4)), 'RaS2');
    final hd = ByteData.sublistView(enc, 4, 4 + 1796);
    expect([hd.getUint32(372), hd.getUint32(376), hd.getUint32(400)], [w, h, 18]);
    expect(decode(enc, w, h), px);
  });

  test('RGB pages: runs compare whole pixels and the header says srgb', () {
    const w = 200, h = 50;
    final px = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 255);
    for (var x = 0; x < w; x++) {
      // pixels whose bytes repeat within a pixel but differ between neighbours
      px.setRange((7 * w + x) * 3, (7 * w + x) * 3 + 3, [x & 0xff, x & 0xff, 9]);
    }
    for (var x = 50; x < 120; x++) {
      px.setRange((20 * w + x) * 3, (20 * w + x) * 3 + 3, [200, 10, 10]); // one red run
    }
    final enc = encodePwgRaster([RasterPage(px, w, h, channels: 3)], dpi: 300);
    final hd = ByteData.sublistView(enc, 4, 4 + 1796);
    expect([hd.getUint32(388), hd.getUint32(392), hd.getUint32(400), hd.getUint32(420)], [24, w * 3, 19, 3]);
    expect(decode(enc, w, h, ch: 3), px);
  });
}
