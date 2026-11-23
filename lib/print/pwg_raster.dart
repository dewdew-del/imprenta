// PWG Raster (PWG 5102.4) writer for 8-bit grayscale or RGB pages. The printer takes this instead of PDF.
import 'dart:convert';
import 'dart:typed_data';

/// One page of pixels: [channels] = 1 (gray, 0 black … 255 white) or 3 (RGB), row by row.
class RasterPage {
  final Uint8List pixels;
  final int width, height, channels;
  RasterPage(this.pixels, this.width, this.height, {this.channels = 1})
      : assert(channels == 1 || channels == 3),
        assert(pixels.length == width * height * channels);
}

Uint8List encodePwgRaster(List<RasterPage> pages, {required int dpi, String pageSizeName = ''}) {
  final out = BytesBuilder(copy: false)..add(pwgFileHeader);
  for (final p in pages) {
    out.add(encodePwgPage(p, dpi: dpi, pageSizeName: pageSizeName, totalPages: pages.length));
  }
  return out.toBytes();
}

/// The 4-byte sync word every PWG raster stream starts with.
final pwgFileHeader = ascii.encode('RaS2');

/// One compressed page (header + lines), so pages can be encoded one at a time and the raw pixels dropped.
Uint8List encodePwgPage(RasterPage p, {required int dpi, String pageSizeName = '', int totalPages = 1}) {
  final out = BytesBuilder(copy: false)..add(_header(p, dpi, pageSizeName, totalPages));
  _encodeLines(out, p);
  return out.toBytes();
}

Uint8List _header(RasterPage p, int dpi, String sizeName, int total) {
  final h = ByteData(1796);
  void str(int off, String s) {
    final b = ascii.encode(s);
    for (var i = 0; i < b.length && i < 63; i++) {
      h.setUint8(off + i, b[i]);
    }
  }

  str(0, 'PwgRaster');
  h.setUint32(276, dpi);
  h.setUint32(280, dpi);
  h.setUint32(340, 1); // NumCopies: copies are asked for in the IPP job instead
  h.setUint32(352, (p.width * 72 / dpi).round()); // PageSize in points
  h.setUint32(356, (p.height * 72 / dpi).round());
  h.setUint32(372, p.width);
  h.setUint32(376, p.height);
  h.setUint32(384, 8); // BitsPerColor
  h.setUint32(388, 8 * p.channels); // BitsPerPixel
  h.setUint32(392, p.width * p.channels); // BytesPerLine
  h.setUint32(400, p.channels == 3 ? 19 : 18); // ColorSpace srgb / sgray
  h.setUint32(420, p.channels); // NumColors
  h.setUint32(452, total);
  h.setInt32(456, 1); // CrossFeedTransform
  h.setInt32(460, 1); // FeedTransform
  str(1732, sizeName);
  return h.buffer.asUint8List();
}

// Each line: a repeat byte (identical following lines), then PackBits-style runs of whole pixels.
void _encodeLines(BytesBuilder out, RasterPage p) {
  final w = p.width, c = p.channels, px = p.pixels, stride = w * c;
  bool samePx(int a, int b) {
    for (var k = 0; k < c; k++) {
      if (px[a + k] != px[b + k]) return false;
    }
    return true;
  }

  bool sameLine(int a, int b) {
    for (var x = 0; x < stride; x++) {
      if (px[a * stride + x] != px[b * stride + x]) return false;
    }
    return true;
  }

  var y = 0;
  while (y < p.height) {
    var rep = 1;
    while (y + rep < p.height && rep < 256 && sameLine(y, y + rep)) {
      rep++;
    }
    out.addByte(rep - 1);
    final row = y * stride;
    int at(int x) => row + x * c;
    var i = 0;
    while (i < w) {
      var j = i + 1;
      while (j < w && j - i < 128 && samePx(at(j), at(i))) {
        j++;
      }
      if (j - i > 1) {
        out.addByte(j - i - 1);
        out.add(Uint8List.sublistView(px, at(i), at(i) + c));
        i = j;
        continue;
      }
      final start = i;
      while (i < w && i - start < 128 && (i + 1 >= w || !samePx(at(i), at(i + 1)))) {
        i++;
      }
      final n = i - start;
      out.addByte(n == 1 ? 0 : 257 - n);
      out.add(Uint8List.sublistView(px, at(start), at(i)));
    }
    y += rep;
  }
}
