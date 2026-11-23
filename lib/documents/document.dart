import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

const _files = MethodChannel('imprenta/files');

/// Photos carry no physical size; treat them as 300 dpi for "100%".
// shortcut: ignores EXIF dpi, upgrade if 100% photo prints look wrong.
const imageDpi = 300.0;
const _thumbDpi = 96.0; // sharp enough for pinch-zoom on the main preview
const _sizeDpi = 36.0; // page sizes only: cheap, within ~0.7 mm

class PageInfo {
  final double widthMm, heightMm;
  PageInfo(this.widthMm, this.heightMm);
}

class LoadedDoc {
  final String name;
  final bool isPdf;
  final Uint8List bytes;
  final List<PageInfo> pages;
  LoadedDoc(this.name, this.isPdf, this.bytes, this.pages);

  final _thumbs = <int, Future<Uint8List>>{};

  /// Preview image of one page, drawn the first time it is shown (not all pages up front).
  Future<Uint8List> thumbnail(int index) => _thumbs[index] ??= isPdf
      ? Printing.raster(bytes, pages: [index], dpi: _thumbDpi).first.then((r) => r.toPng())
      : Future.value(bytes);

  /// Full-resolution page image at [dpi] (PDF) or the photo itself.
  Future<ui.Image> renderPage(int index, double dpi) async {
    if (isPdf) return (await Printing.raster(bytes, pages: [index], dpi: dpi).first).toImage();
    return (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  }
}

/// Files shared into the app ("Share → Imprenta"), waiting for the home screen.
final sharedFile = ValueNotifier<Map<Object?, Object?>?>(null);

void listenForSharedFiles() {
  _files.setMethodCallHandler((call) async {
    if (call.method == 'shared') sharedFile.value = call.arguments as Map<Object?, Object?>;
  });
  _files.invokeMethod<Map<Object?, Object?>>('takeShared').then((f) {
    if (f != null) sharedFile.value = f;
  });
}

Future<Map<Object?, Object?>?> pickFile() => _files.invokeMethod<Map<Object?, Object?>>('pickFile');

/// Reads the file map from Kotlin ({name, mime, bytes}) into a document with each page's size.
Future<LoadedDoc> loadDoc(Map<Object?, Object?> f) async {
  final name = f['name'] as String;
  final bytes = f['bytes'] as Uint8List;
  final isPdf = (f['mime'] as String) == 'application/pdf' || name.toLowerCase().endsWith('.pdf') ||
      (bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF');
  if (isPdf) {
    final pages = <PageInfo>[];
    // Low-res pass just for each page's size; previews are drawn later, page by page.
    await for (final r in Printing.raster(bytes, dpi: _sizeDpi)) {
      pages.add(PageInfo(r.width / _sizeDpi * 25.4, r.height / _sizeDpi * 25.4));
    }
    if (pages.isEmpty) throw const FormatException('This PDF has no pages');
    return LoadedDoc(name, true, bytes, pages);
  }
  final img = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  final page = PageInfo(img.width / imageDpi * 25.4, img.height / imageDpi * 25.4);
  img.dispose();
  return LoadedDoc(name, false, bytes, [page]);
}
