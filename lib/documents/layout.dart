import 'dart:math' as math;
import 'dart:ui';

enum Scale { fit, fill, actual }

/// Where a source page of [srcW]×[srcH] mm lands on a [paperW]×[paperH] mm sheet, centred.
/// fit: whole page visible; fill: sheet covered (edges may be cropped); actual: 100% size.
Rect placePage(double srcW, double srcH, double paperW, double paperH, Scale scale) {
  final k = switch (scale) {
    Scale.fit => math.min(paperW / srcW, paperH / srcH),
    Scale.fill => math.max(paperW / srcW, paperH / srcH),
    Scale.actual => 1.0,
  };
  final w = srcW * k, h = srcH * k;
  return Rect.fromLTWH((paperW - w) / 2, (paperH - h) / 2, w, h);
}

/// Parses "1-3, 5" into 0-based page indexes. Empty or "all" = every page.
/// Throws [FormatException] for bad input or pages outside 1..[count].
List<int> parsePages(String input, int count) {
  final s = input.trim().toLowerCase();
  if (s.isEmpty || s == 'all') return List.generate(count, (i) => i);
  final out = <int>[];
  for (final part in s.split(',')) {
    final m = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(part);
    if (m == null) throw FormatException('Not a page range: "${part.trim()}"');
    final a = int.parse(m[1]!), b = int.parse(m[2] ?? m[1]!);
    if (a < 1 || b > count || a > b) throw FormatException('Pages go from 1 to $count');
    for (var p = a; p <= b; p++) {
      out.add(p - 1);
    }
  }
  return out;
}
