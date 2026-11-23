/// A paper size in hundredths of a millimetre, the unit IPP media-col uses.
class PaperSize {
  final String label;
  final String? pwg; // IPP media keyword; null for custom sizes
  final int width, height;
  const PaperSize(this.label, this.pwg, this.width, this.height);

  factory PaperSize.customInches(double w, double h) =>
      PaperSize('${_fmt(w)} × ${_fmt(h)}', null, (w * 2540).round(), (h * 2540).round());

  factory PaperSize.customMm(double w, double h) =>
      PaperSize('${_fmt(w)} × ${_fmt(h)} mm', null, (w * 100).round(), (h * 100).round());

  double get aspect => width / height;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static const letter = PaperSize('Letter', 'na_letter_8.5x11in', 21590, 27940);
  static const a4 = PaperSize('A4', 'iso_a4_210x297mm', 21000, 29700);
  static const long = PaperSize('8.5 × 13', 'na_foolscap_8.5x13in', 21590, 33020);
  static const legal = PaperSize('Legal', 'na_legal_8.5x14in', 21590, 35560);
  static const presets = [letter, a4, long, legal];
}
