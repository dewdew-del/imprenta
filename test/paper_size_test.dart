import 'package:flutter_test/flutter_test.dart';
import 'package:imprenta/models/paper_size.dart';

void main() {
  test('custom sizes convert to hundredths of a mm', () {
    final inch = PaperSize.customInches(8.5, 13);
    expect([inch.width, inch.height], [PaperSize.long.width, PaperSize.long.height]);
    expect(inch.label, '8.5 × 13');
    final mm = PaperSize.customMm(216, 330);
    expect([mm.width, mm.height], [21600, 33000]);
  });
}
