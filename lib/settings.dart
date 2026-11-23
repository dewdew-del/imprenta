import 'package:shared_preferences/shared_preferences.dart';

import 'models/paper_size.dart';

/// Remembers the printer, the last print settings and saved custom sizes on this phone only.
class Settings {
  static late SharedPreferences _p;
  static Future<void> load() async => _p = await SharedPreferences.getInstance();

  static String get ssid => _p.getString('ssid') ?? '';
  static String get passphrase => _p.getString('pass') ?? '';
  static String? get printerIp => _p.getString('ip');
  static Future<void> savePrinter(String ssid, String pass, String ip) async {
    await _p.setString('ssid', ssid);
    await _p.setString('pass', pass);
    await _p.setString('ip', ip);
  }

  static bool get color => _p.getBool('color') ?? false;
  static set color(bool v) => _p.setBool('color', v);
  static bool get showSettings => _p.getBool('showSettings') ?? true;
  static set showSettings(bool v) => _p.setBool('showSettings', v);
  static int get quality => _p.getInt('quality') ?? 4;
  static set quality(int v) => _p.setInt('quality', v);

  static PaperSize get paper => _decode(_p.getString('paper')) ?? PaperSize.long;
  static set paper(PaperSize p) => _p.setString('paper', _encode(p));

  static List<PaperSize> get customSizes => (_p.getStringList('custom') ?? []).map(_decode).whereType<PaperSize>().toList();
  static Future<void> addCustom(PaperSize p) async {
    final list = [p, ...customSizes.where((s) => s.width != p.width || s.height != p.height)].take(6);
    await _p.setStringList('custom', list.map(_encode).toList());
  }

  static Future<void> removeCustom(PaperSize p) => _p.setStringList(
      'custom', customSizes.where((s) => s.width != p.width || s.height != p.height).map(_encode).toList());

  // "label|pwg|width|height"; pwg empty for custom sizes.
  static String _encode(PaperSize p) => '${p.label}|${p.pwg ?? ''}|${p.width}|${p.height}';
  static PaperSize? _decode(String? s) {
    final f = s?.split('|');
    if (f == null || f.length != 4) return null;
    final w = int.tryParse(f[2]), h = int.tryParse(f[3]);
    if (w == null || h == null) return null;
    return PaperSize(f[0], f[1].isEmpty ? null : f[1], w, h);
  }
}
