import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:imprenta/ipp/ipp.dart';

/// Builds raw attribute bytes the way a printer would send them.
List<int> attr(int tag, String name, List<int> value) =>
    [tag, name.length >> 8, name.length & 0xff, ...name.codeUnits, value.length >> 8, value.length & 0xff, ...value];
List<int> i32(int v) => [v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff];

void main() {
  test('encodes Get-Printer-Attributes header, multi-value attr and end tag', () {
    final b = encodeRequest(Op.getPrinterAttributes, 7, {
      Tag.operation: [IppAttr(Tag.keyword, 'requested-attributes', ['all', 'media-col-database'])],
    });
    expect(b.sublist(0, 8), [1, 1, 0, 0x0B, 0, 0, 0, 7]);
    expect(b[8], Tag.operation);
    expect(b.last, Tag.end);
    // second value carries an empty name (0x0000)
    final second = attr(Tag.keyword, '', 'media-col-database'.codeUnits);
    expect(b.sublist(b.length - 1 - second.length, b.length - 1), second);
  });

  test('media-col for a custom size encodes and decodes back to the same size', () {
    final b = encodeRequest(Op.printJob, 1, {Tag.job: mediaAttrs(null, 21590, 33020)});
    // Reuse the response decoder: swap the op bytes for a status of 0 (it reads the same layout).
    final r = decodeResponse(Uint8List.fromList([...b.sublist(0, 2), 0, 0, ...b.sublist(4)]));
    final col = r.group(Tag.job)['media-col']!.single as Map<String, List<Object?>>;
    final size = col['media-size']!.single as Map<String, List<Object?>>;
    expect([size['x-dimension'], size['y-dimension']], [[21590], [33020]]);
  });

  test('decodes printer attributes incl. multi-values, range and nested collection', () {
    final data = Uint8List.fromList([
      1, 1, 0, 0, 0, 0, 0, 7, // version, status ok, request id
      Tag.printer,
      ...attr(Tag.keyword, 'media-supported', 'na_legal_8.5x14in'.codeUnits),
      ...attr(Tag.keyword, '', 'na_foolscap_8.5x13in'.codeUnits),
      ...attr(Tag.begCollection, 'media-size-supported', []),
      ...attr(Tag.memberName, '', 'x-dimension'.codeUnits),
      ...attr(Tag.range, '', [...i32(7620), ...i32(21590)]),
      ...attr(Tag.memberName, '', 'y-dimension'.codeUnits),
      ...attr(Tag.integer, '', i32(35560)),
      ...attr(Tag.endCollection, '', []),
      ...attr(Tag.boolean, 'color-supported', [1]),
      Tag.end,
    ]);
    final r = decodeResponse(data);
    expect(r.ok, isTrue);
    final p = r.group(Tag.printer);
    expect(p['media-supported'], ['na_legal_8.5x14in', 'na_foolscap_8.5x13in']);
    final size = p['media-size-supported']!.single as Map<String, List<Object?>>;
    expect(size['x-dimension']!.single.toString(), '7620-21590');
    expect(size['y-dimension'], [35560]);
    expect(p['color-supported'], [true]);
  });
}
