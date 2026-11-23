import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ipp/ipp.dart';
import 'connect_screen.dart' show wifi;

/// Phase 1: join the printer's WiFi Direct and list what it accepts over IPP.
class PrinterCheckScreen extends StatefulWidget {
  final String initialIp;
  const PrinterCheckScreen({super.key, required this.initialIp});
  @override
  State<PrinterCheckScreen> createState() => _PrinterCheckScreenState();
}

class _PrinterCheckScreenState extends State<PrinterCheckScreen> {
  static const keyAttrs = [
    'printer-make-and-model',
    'media-supported',
    'media-size-supported',
    'media-default',
    'document-format-supported',
    'sides-supported',
    'print-scaling-supported',
    'print-color-mode-supported',
    'printer-resolution-supported',
  ];

  final ssid = TextEditingController(text: 'DIRECT-');
  final pass = TextEditingController();
  late final ip = TextEditingController(text: widget.initialIp);
  String status = 'Not connected. Skip "Connect" if phone and printer share your home WiFi.';
  bool busy = false;
  Map<String, List<Object?>>? attrs;

  Future<void> run(String label, Future<void> Function() job) async {
    setState(() { busy = true; status = '$label...'; });
    try {
      await job();
    } catch (e) {
      setState(() => status = '$label failed: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> connect() => run('Connecting', () async {
        final info = Map<String, Object?>.from(await wifi.invokeMethod('connectToPrinter', {'ssid': ssid.text.trim(), 'passphrase': pass.text}));
        if (info['gateway'] != null) ip.text = info['gateway'] as String;
        setState(() => status = 'Connected. Phone ${info['phoneIp']}, printer probably ${info['gateway'] ?? ip.text}');
      });

  Future<void> check() => run('Asking printer', () async {
        final r = await IppClient(ip.text.trim()).getPrinterAttributes();
        setState(() {
          attrs = r.group(Tag.printer);
          status = r.ok ? 'Got ${attrs!.length} attributes' : 'Printer replied with status 0x${r.status.toRadixString(16)}';
        });
      });

  String fmt(List<Object?> v) => v.map((e) => e is Map ? e.entries.map((m) => '${m.key}=${fmt(m.value as List<Object?>)}').join(' ') : '$e').join(', ');

  String rawText() => attrs!.entries.map((e) => '${e.key}: ${fmt(e.value)}').join('\n');

  @override
  Widget build(BuildContext context) {
    final a = attrs;
    return Scaffold(
      appBar: AppBar(title: const Text('Printer details')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: ssid, decoration: const InputDecoration(labelText: 'Printer WiFi Direct name')),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'WiFi Direct password')),
        TextField(controller: ip, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Printer IP')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton(onPressed: busy ? null : connect, child: const Text('Connect')),
          FilledButton(onPressed: busy ? null : check, child: const Text('Check printer')),
          OutlinedButton(
            onPressed: busy ? null : () => run('Disconnecting', () async {
                  await wifi.invokeMethod('disconnect');
                  setState(() => status = 'Disconnected');
                }),
            child: const Text('Disconnect'),
          ),
          if (a != null)
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rawText()));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All attributes copied')));
              },
              child: const Text('Copy all'),
            ),
        ]),
        const SizedBox(height: 12),
        Text(status, style: Theme.of(context).textTheme.bodyMedium),
        if (a != null)
          for (final k in keyAttrs)
            ListTile(dense: true, title: Text(k), subtitle: SelectableText(a[k] == null ? '(not reported)' : fmt(a[k]!))),
      ]),
    );
  }
}
