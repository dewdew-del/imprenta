import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/paper_size.dart';
import 'pwg_raster.dart';
import 'render.dart';

/// Draws the Phase 2 test page at the paper's exact size: a border 5 mm in from every edge,
/// mm rulers along the border, the size label, and TOP/BOTTOM marks so any cut is obvious.
Future<RasterPage> renderTestPage(PaperSize paper, int dpi, {bool color = false}) async {
  final pxPerMm = dpi / 25.4;
  final (w, h) = sheetPixels(paper, dpi);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));

  final ink = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = dpi / 100
    ..style = PaintingStyle.stroke;
  final inset = 5 * pxPerMm;
  c.drawRect(Rect.fromLTRB(inset, inset, w - inset, h - inset), ink);

  // Ruler ticks every 5 mm along the left and top border, longer every 10 mm.
  for (var mm = 10; mm * pxPerMm < h - inset; mm += 5) {
    final y = mm * pxPerMm, len = (mm % 10 == 0 ? 4 : 2) * pxPerMm;
    c.drawLine(Offset(inset, y), Offset(inset + len, y), ink);
  }
  for (var mm = 10; mm * pxPerMm < w - inset; mm += 5) {
    final x = mm * pxPerMm, len = (mm % 10 == 0 ? 4 : 2) * pxPerMm;
    c.drawLine(Offset(x, inset), Offset(x, inset + len), ink);
  }

  void text(String s, double sizeMm, double centerY) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: const Color(0xFF000000), fontSize: sizeMm * pxPerMm)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((w - tp.width) / 2, centerY - tp.height / 2));
  }

  final wmm = paper.width / 100, hmm = paper.height / 100;
  text('TOP', 6, inset + 14 * pxPerMm);
  text(paper.label, 16, h / 2 - 10 * pxPerMm);
  text('${wmm.round()} × ${hmm.round()} mm · ${(wmm / 25.4).toStringAsFixed(2)} × ${(hmm / 25.4).toStringAsFixed(2)} in',
      5, h / 2 + 8 * pxPerMm);
  text('Border is 5 mm from every edge. All four sides should show.', 3.5, h / 2 + 18 * pxPerMm);
  text('BOTTOM', 6, h - inset - 14 * pxPerMm);
  // Color check: cyan, magenta, yellow, red, green, blue squares (gray when printing grayscale).
  const swatches = [0xFF00AEEF, 0xFFEC008C, 0xFFFFF200, 0xFFE53935, 0xFF43A047, 0xFF1E88E5];
  final side = 12 * pxPerMm, gap = 3 * pxPerMm;
  final x0 = (w - (swatches.length * side + (swatches.length - 1) * gap)) / 2, y0 = h / 2 + 28 * pxPerMm;
  for (var i = 0; i < swatches.length; i++) {
    c.drawRect(Rect.fromLTWH(x0 + i * (side + gap), y0, side, side), Paint()..color = Color(swatches[i]));
  }

  return pictureToRaster(rec.endRecording(), w, h, color: color);
}
