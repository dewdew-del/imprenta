import 'package:flutter/services.dart';

import '../ipp/ipp.dart';

const slowPrinterMessage = 'The printer took too long to answer';

/// Turns network, printer and file errors into one plain sentence for the screen.
String friendlyError(Object e) {
  if (e is PlatformException) {
    final m = e.message ?? '';
    if (m.contains('Timeout') || m.contains('timeout')) {
      return '$slowPrinterMessage. It may still print, so check the tray before trying again.';
    }
    if (m.contains('ConnectException') || m.contains('NoRouteToHost') || m.contains('Unreachable')) {
      return "Can't reach the printer. Is the phone on the printer's WiFi (DIRECT-…)?";
    }
    if (e.code == 'HTTP') return 'The printer refused the connection ($m).';
    return m.isEmpty ? e.code : m;
  }
  if (e is IppException) {
    return switch (e.status) {
      0x040A => "The printer doesn't accept this kind of document.",
      0x040B => "The printer doesn't support one of the settings${e.unsupported.isEmpty ? '' : ' (${e.unsupported.join(', ')})'}.",
      0x0503 || 0x0507 => 'The printer is busy. Try again in a moment.',
      0x0506 => 'The printer is not accepting jobs right now.',
      _ => e.toString(),
    };
  }
  if (e is FormatException) return e.message;
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
