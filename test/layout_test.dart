import 'package:flutter_test/flutter_test.dart';
import 'package:imprenta/documents/layout.dart';

void main() {
  // Letter page (215.9 x 279.4) onto 8.5x13 (215.9 x 330.2)
  test('fit keeps the whole page and centres it', () {
    final r = placePage(215.9, 279.4, 215.9, 330.2, Scale.fit);
    expect(r.width, closeTo(215.9, 0.01));
    expect(r.top, closeTo((330.2 - 279.4) / 2, 0.01));
  });

  test('fill covers the sheet, cropping the sides', () {
    final r = placePage(215.9, 279.4, 215.9, 330.2, Scale.fill);
    expect(r.height, closeTo(330.2, 0.01));
    expect(r.left, lessThan(0));
  });

  test('actual size is untouched', () {
    final r = placePage(100, 100, 215.9, 330.2, Scale.actual);
    expect(r.width, closeTo(100, 1e-9));
    expect(r.height, closeTo(100, 1e-9));
  });

  test('page ranges', () {
    expect(parsePages('', 3), [0, 1, 2]);
    expect(parsePages('1-2, 4', 5), [0, 1, 3]);
    expect(() => parsePages('0', 3), throwsFormatException);
    expect(() => parsePages('2-9', 3), throwsFormatException);
    expect(() => parsePages('abc', 3), throwsFormatException);
  });
}
