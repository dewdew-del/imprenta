import 'package:flutter/material.dart';

import '../models/paper_size.dart';
import '../settings.dart';
import '../theme.dart';

class PaperScreen extends StatefulWidget {
  final PaperSize selected;
  const PaperScreen({super.key, required this.selected});
  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> {
  final w = TextEditingController();
  final h = TextEditingController();
  bool inches = true;

  void useCustom() {
    final wv = double.tryParse(w.text.trim()), hv = double.tryParse(h.text.trim());
    if (wv == null || hv == null || wv <= 0 || hv <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter width and height')));
      return;
    }
    final size = inches ? PaperSize.customInches(wv, hv) : PaperSize.customMm(wv, hv);
    // Printer range from Phase 1: 88.9–215.9 mm wide, 127–355.6 mm tall.
    if (size.width < 8890 || size.width > 21590 || size.height < 12700 || size.height > 35560) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Must be 3.5–8.5 in wide and 5–14 in tall')));
      return;
    }
    Settings.addCustom(size);
    Navigator.pop(context, size);
  }

  @override
  Widget build(BuildContext context) {
    final field = InputDecoration(hintStyle: mono.copyWith(color: muted, fontSize: 15));
    return Scaffold(
      appBar: AppBar(title: const Text('Paper'), titleSpacing: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            for (final p in PaperSize.presets) _tile(p, p.pwg != null && p.pwg == widget.selected.pwg),
            for (final p in Settings.customSizes)
              _tile(p, p.pwg == null && p.width == widget.selected.width && p.height == widget.selected.height, saved: true),
          ],
        ),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(child: TextField(controller: w, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: mono.copyWith(fontSize: 15), decoration: field.copyWith(hintText: 'W'))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×', style: TextStyle(color: muted))),
          Expanded(child: TextField(controller: h, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: mono.copyWith(fontSize: 15), decoration: field.copyWith(hintText: 'H'), onSubmitted: (_) => useCustom())),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(52, 48)),
            onPressed: () => setState(() => inches = !inches),
            child: Text(inches ? 'in' : 'mm', semanticsLabel: inches ? 'Unit inches, tap for millimetres' : 'Unit millimetres, tap for inches', style: mono.copyWith(color: muted)),
          ),
        ]),
        const SizedBox(height: 12),
        TextButton(onPressed: useCustom, child: const Text('Use custom size')),
      ]),
    );
  }

  Widget _tile(PaperSize p, bool on, {bool saved = false}) => Semantics(
        selected: on,
        button: true,
        label: p.label,
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? ink : line, width: on ? 1.5 : 1)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context, p),
            // Saved custom sizes: long-press to forget.
            onLongPress: saved ? () async { await Settings.removeCustom(p); setState(() {}); } : null,
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                width: 34,
                height: 34 / p.aspect,
                decoration: BoxDecoration(border: Border.all(color: on ? ink : const Color(0xFFC9C9C4)), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 10),
              Text(p.label, style: TextStyle(fontSize: 14, color: ink, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
              const SizedBox(height: 14),
            ]),
          ),
        ),
      );
}
