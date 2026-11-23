import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imprenta/ipp/ipp.dart';
import 'package:imprenta/print/errors.dart';

void main() {
  test('network and printer errors read as plain sentences', () {
    expect(friendlyError(PlatformException(code: 'NETWORK', message: 'SocketTimeoutException: timeout')),
        startsWith(slowPrinterMessage));
    expect(friendlyError(PlatformException(code: 'NETWORK', message: 'ConnectException: Failed to connect')),
        contains("printer's WiFi"));
    expect(friendlyError(IppException(0x040B, ['media'], null)), contains('(media)'));
    expect(friendlyError(Exception('Printer stayed busy')), 'Printer stayed busy');
  });
}
