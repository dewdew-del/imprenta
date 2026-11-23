import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart';
import '../theme.dart';
import 'home_screen.dart';

const wifi = MethodChannel('imprenta/wifi');
const defaultPrinterIp = '192.168.223.1';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  // Remembered from the last successful connect (stored on this phone only).
  final ssid = TextEditingController(text: Settings.ssid);
  final pass = TextEditingController(text: Settings.passphrase);
  bool busy = false;
  String? error;

  void openHome(String ip) =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(printerIp: ip)));

  Future<void> connect() async {
    if (ssid.text.trim().isEmpty) {
      setState(() => error = "Type the printer's WiFi Direct name. Press (i) on the printer to print it.");
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final info = Map<String, Object?>.from(
          await wifi.invokeMethod('connectToPrinter', {'ssid': ssid.text.trim(), 'passphrase': pass.text}));
      final ip = info['gateway'] as String? ?? defaultPrinterIp;
      await Settings.savePrinter(ssid.text.trim(), pass.text, ip);
      if (mounted) openHome(ip);
    } on PlatformException catch (e) {
      setState(() => error = e.code == 'UNAVAILABLE'
          ? "Couldn't join ${ssid.text.trim()}. Check the password, or join it in Android WiFi settings and tap \"Already connected\"."
          : e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scrolls when the keyboard leaves too little room; Spacer still pins buttons to the bottom otherwise.
        child: CustomScrollView(slivers: [SliverFillRemaining(hasScrollBody: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 96),
            const Text('Connect printer', style: TextStyle(fontSize: 26, color: ink, letterSpacing: -0.3)),
            const SizedBox(height: 36),
            TextField(
              controller: ssid,
              autocorrect: false,
              style: mono.copyWith(fontSize: 14),
              decoration: const InputDecoration(hintText: 'DIRECT-xx-HP Smart Tank'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pass,
              obscureText: true,
              style: mono.copyWith(fontSize: 14),
              decoration: const InputDecoration(hintText: 'Password'),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412))),
            ],
            const Spacer(),
            FilledButton(
              onPressed: busy ? null : connect,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ground))
                  : const Text('Connect'),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final ip = Settings.printerIp ?? defaultPrinterIp;
                        await Settings.savePrinter(ssid.text.trim(), pass.text, ip);
                        openHome(ip);
                      },
                child: const Text('Already connected')),
          ]),
        ))]),
      ),
    );
  }
}
