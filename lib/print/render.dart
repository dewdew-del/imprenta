import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../documents/document.dart';
import '../documents/layout.dart';
import '../models/paper_size.dart';
import 'pwg_raster.dart';

/// Sheet size in pixels at [dpi].
(int, int) sheetPixels(PaperSize paper, int dpi) =>
    ((paper.width / 2540 * dpi).round(), (paper.height / 2540 * dpi).round());

/// Landscape pages go sideways on portrait paper so they use the whole sheet.
bool shouldRotate(PageInfo p, PaperSize paper) => (p.widthMm > p.heightMm) != (paper.width > paper.height);

/// Draws one document page onto a white sheet of [paper], placed per [scale].
Future<RasterPage> renderDocPage(LoadedDoc doc, int index, PaperSize paper, Scale scale, int dpi, {bool color = false}) async {
  final info = doc.pages[index];
  final rot = shouldRotate(info, paper);
  final sw = rot ? info.heightMm : info.widthMm, sh = rot ? info.widthMm : info.heightMm;
  final (w, h) = sheetPixels(paper, dpi);
  final dst = placePage(sw, sh, paper.width / 100, paper.height / 100, scale);
  final pxPerMm = dpi / 25.4;
  // Render the source at the resolution it will land at on paper, never above the output dpi
  // (Fill/100% would otherwise ask for 600 dpi pages that only waste memory).
  final srcDpi = (dpi * dst.width / sw).clamp(36.0, dpi.toDouble());
  final src = await doc.renderPage(index, srcDpi);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  final box = Rect.fromLTRB(dst.left * pxPerMm, dst.top * pxPerMm, dst.right * pxPerMm, dst.bottom * pxPerMm);
  if (rot) {
    // Turn the page 90° clockwise into the box: its width becomes the box height.
    c.save();
    c.translate(box.right, box.top);
    c.rotate(1.5707963267948966);
  }
  c.drawImageRect(
    src,
    Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    rot ? Rect.fromLTWH(0, 0, box.height, box.width) : box,
    Paint()..filterQuality = FilterQuality.medium,
  );
  if (rot) c.restore();
  src.dispose();
  return pictureToRaster(rec.endRecording(), w, h, color: color);
}

/// Rasterises a picture into 8-bit gray (luma) or RGB.
Future<RasterPage> pictureToRaster(ui.Picture picture, int w, int h, {bool color = false}) async {
  final img = await picture.toImage(w, h);
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  img.dispose();
  final n = w * h;
  if (color) {
    final rgb = Uint8List(n * 3);
    for (var i = 0, j = 0, k = 0; i < n; i++, j += 4, k += 3) {
      rgb[k] = rgba[j];
      rgb[k + 1] = rgba[j + 1];
      rgb[k + 2] = rgba[j + 2];
    }
    return RasterPage(rgb, w, h, channels: 3);
  }
  final gray = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    gray[i] = (rgba[j] * 77 + rgba[j + 1] * 150 + rgba[j + 2] * 29) >> 8;
  }
  return RasterPage(gray, w, h);
}
