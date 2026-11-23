import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../documents/document.dart';
import '../documents/layout.dart';
import '../models/paper_size.dart';
import '../print/render.dart';
import '../print/test_page.dart';
import '../settings.dart';
import '../theme.dart';
import '../ipp/ipp.dart';
import 'connect_screen.dart';
import 'paper_screen.dart';
import 'printer_check_screen.dart';
import 'printing_screen.dart';

class HomeScreen extends StatefulWidget {
  final String printerIp;
  const HomeScreen({super.key, required this.printerIp});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  PaperSize paper = Settings.paper;
  bool color = Settings.color;
  int quality = Settings.quality;
  bool expanded = Settings.showSettings;
  Scale scale = Scale.fit;
  int copies = 1;
  LoadedDoc? doc;
  bool loading = false;
  int shown = 0;
  final pages = TextEditingController();
  bool? reachable; // null while checking

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sharedFile.addListener(_takeShared);
    _takeShared();
    _checkPrinter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sharedFile.removeListener(_takeShared);
    super.dispose();
  }

  // Re-check when the user comes back to the app (they may have switched WiFi meanwhile).
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkPrinter();
  }

  Future<void> _checkPrinter() async {
    setState(() => reachable = null);
    try {
      await IppClient(widget.printerIp).getPrinterAttributes(['printer-state']);
      if (mounted) setState(() => reachable = true);
    } catch (_) {
      if (mounted) setState(() => reachable = false);
    }
  }

  void _takeShared() {
    final f = sharedFile.value;
    if (f == null) return;
    sharedFile.value = null;
    _load(f);
  }

  Future<void> _pick() async {
    try {
      final f = await pickFile();
      if (f != null) await _load(f);
    } catch (e) {
      _say('Could not open file: $e');
    }
  }

  Future<void> _load(Map<Object?, Object?> f) async {
    setState(() => loading = true);
    try {
      final d = await loadDoc(f);
      setState(() {
        doc = d;
        shown = 0;
        pages.clear();
      });
    } catch (e) {
      _say('Could not open ${f['name']}: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// All pages, or a typed range like "1-3, 5".
  Future<void> _choosePages(int count) async {
    final custom = TextEditingController(text: pages.text);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ground,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pages to print',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: ink),
            ),
            const SizedBox(height: 8),
            ListTile(contentPadding: EdgeInsets.zero, title: Text('All $count pages'), onTap: () => Navigator.pop(ctx, '')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: custom,
                    style: mono,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(hintText: 'e.g. 1-3, 5', labelText: 'Custom (1 to $count)'),
                    onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                // The theme's full-width button minimum would squeeze the text field to nothing in a Row.
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: () => Navigator.pop(ctx, custom.text.trim()),
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      parsePages(picked, count); // check now so the mistake shows here, not at Print
      setState(() => pages.text = picked);
    } on FormatException catch (e) {
      _say(e.message);
    }
  }

  void _say(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickPaper() async {
    final p = await Navigator.of(context).push<PaperSize>(MaterialPageRoute(builder: (_) => PaperScreen(selected: paper)));
    if (p != null) {
      Settings.paper = p;
      setState(() => paper = p);
    }
  }

  void _print() {
    final d = doc, sheet = paper, sc = scale, col = color;
    late final List<int> list;
    if (d != null) {
      try {
        list = parsePages(pages.text, d.pages.length);
      } on FormatException catch (e) {
        _say(e.message);
        return;
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrintingScreen(
          printerIp: widget.printerIp,
          paper: sheet,
          copies: copies,
          jobName: d?.name ?? 'Imprenta test ${sheet.label}',
          pageCount: d == null ? 1 : list.length,
          color: col,
          quality: quality,
          renderSheet: d == null
              ? (_) => renderTestPage(sheet, printDpi, color: col)
              : (i) => renderDocPage(d, list[i], sheet, sc, printDpi, color: col),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: loading ? null : _pick,
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: ink,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text(
                          loading ? 'Opening…' : d?.name ?? 'Choose a PDF or photo',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: d == null ? muted : ink),
                        ),
                      ),
                    ),
                    if (reachable == false)
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: const Color(0xFF9A3412)),
                        onPressed: () => Navigator.of(context)
                            .pushReplacement(MaterialPageRoute(builder: (_) => const ConnectScreen())),
                        child: const Text('Reconnect'),
                      ),
                    IconButton(
                      tooltip: switch (reachable) {
                        true => 'Printer connected · details',
                        false => 'Printer not reachable · check again',
                        null => 'Checking printer…',
                      },
                      onPressed: reachable == false
                          ? _checkPrinter
                          : () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => PrinterCheckScreen(initialIp: widget.printerIp))),
                      icon: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: switch (reachable) { true => ok, false => const Color(0xFFC2410C), null => const Color(0xFFC9C9C4) },
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final h = (box.maxHeight - 16).clamp(80.0, 340.0);
                        // Pinch to zoom right here; tap for the sharper full-screen view. Keyed by page so zoom resets on page change.
                        return InteractiveViewer(
                          key: ValueKey(shown),
                          maxScale: 5,
                          child: Center(
                            child: GestureDetector(
                              onTap: d == null ? null : _openZoom,
                              child: _sheet(h * paper.aspect > box.maxWidth - 40 ? (box.maxWidth - 40) / paper.aspect : h),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (d != null && d.pages.length > 1)
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: shown > 0 ? () => setState(() => shown--) : null,
                          icon: const Icon(Icons.chevron_left, color: muted),
                        ),
                      Text(
                        d != null && d.pages.length > 1 ? '${shown + 1} / ${d.pages.length}' : paper.label,
                        style: mono.copyWith(fontSize: 12, color: muted),
                      ),
                      if (d != null && d.pages.length > 1)
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: shown < d.pages.length - 1 ? () => setState(() => shown++) : null,
                          icon: const Icon(Icons.chevron_right, color: muted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Swipe the settings down to fold them away, up to bring them back (tapping the header works too).
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (e) {
                final v = e.primaryVelocity ?? 0;
                if (v > 150 && expanded) _setExpanded(false);
                if (v < -150 && !expanded) _setExpanded(true);
              },
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: expanded ? 'Print settings, swipe down or tap to hide' : 'Print settings, swipe up or tap to show',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => _setExpanded(!expanded),
                          child: Container(
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: line)),
                            ),
                            padding: const EdgeInsets.only(top: 6, bottom: 10),
                            child: Column(
                              children: [
                                // Grab handle: says "drag me".
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(color: const Color(0xFFD4D4CF), borderRadius: BorderRadius.circular(2)),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Text(
                                      'Print settings',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ink),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: expanded
                                          ? const SizedBox()
                                          : Text(
                                              _summary(),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                              style: mono.copyWith(fontSize: 12, color: muted),
                                            ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (expanded) ...[
                        _row(
                          'Paper',
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(paper.label, style: mono),
                          ),
                          onTap: _pickPaper,
                        ),
                        _row(
                          'Scale',
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (s, l) in [(Scale.fit, 'Fit'), (Scale.fill, 'Fill'), (Scale.actual, '100%')])
                                _pill(l, scale == s, () => setState(() => scale = s)),
                            ],
                          ),
                        ),
                        _row(
                          'Color',
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (c, l) in [(false, 'Gray'), (true, 'Color')])
                                _pill(l, color == c, () {
                                  Settings.color = c;
                                  setState(() => color = c);
                                }),
                            ],
                          ),
                        ),
                        _row(
                          'Quality',
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (q, l) in [(3, 'Draft'), (4, 'Normal'), (5, 'High')])
                                _pill(l, quality == q, () {
                                  Settings.quality = q;
                                  setState(() => quality = q);
                                }),
                            ],
                          ),
                        ),
                        if (d != null && d.pages.length > 1)
                          _row(
                            'Pages',
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(pages.text.isEmpty ? 'All ${d.pages.length}' : pages.text, style: mono),
                                const Icon(Icons.chevron_right, size: 18, color: muted),
                              ],
                            ),
                            onTap: () => _choosePages(d.pages.length),
                          ),
                        _row(
                          'Copies',
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Fewer copies',
                                onPressed: copies > 1 ? () => setState(() => copies--) : null,
                                icon: const Icon(Icons.remove, size: 18, color: muted),
                              ),
                              SizedBox(
                                width: 16,
                                child: Text('$copies', textAlign: TextAlign.center, style: mono),
                              ),
                              IconButton(
                                tooltip: 'More copies',
                                onPressed: copies < 99 ? () => setState(() => copies++) : null,
                                icon: const Icon(Icons.add, size: 18, color: muted),
                              ),
                            ],
                          ),
                          last: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: FilledButton(onPressed: loading ? null : _print, child: Text(d == null ? 'Print test page' : 'Print')),
            ),
          ],
        ),
      ),
    );
  }

  void _setExpanded(bool v) {
    Settings.showSettings = v;
    setState(() => expanded = v);
  }

  String _summary() => [
    paper.label,
    switch (scale) {
      Scale.fit => 'Fit',
      Scale.fill => 'Fill',
      Scale.actual => '100%',
    },
    color ? 'Color' : 'Gray',
    const {3: 'Draft', 4: 'Normal', 5: 'High'}[quality]!,
    if (doc != null && doc!.pages.length > 1) pages.text.isEmpty ? 'All pages' : 'Pages ${pages.text}',
    copies == 1 ? '1 copy' : '$copies copies',
  ].join(' · ');

  /// Full-screen preview of the current page, sharp enough to pinch-zoom (rendered at 150 dpi).
  Future<void> _openZoom() async {
    final d = doc!;
    final page = shown;
    final img = await d.renderPage(page, 150);
    if (!mounted) {
      img.dispose();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Page ${page + 1} · ${paper.label}'), titleSpacing: 0),
          body: InteractiveViewer(
            maxScale: 6,
            child: LayoutBuilder(
              builder: (context, box) {
                final h = box.maxHeight - 32;
                return Center(
                  child: _sheet(
                    h * paper.aspect > box.maxWidth - 32 ? (box.maxWidth - 32) / paper.aspect : h,
                    image: RawImage(image: img, fit: BoxFit.fill),
                    pageIndex: page,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    img.dispose();
  }

  /// The sheet at the real paper ratio with the current page placed exactly as it will print.
  Widget _sheet(double height, {Widget? image, int? pageIndex}) {
    final d = doc;
    final width = height * paper.aspect;
    Widget? content;
    if (d != null) {
      final p = d.pages[pageIndex ?? shown];
      final k = width / (paper.width / 100); // px per mm
      final rot = shouldRotate(p, paper);
      final r = placePage(rot ? p.heightMm : p.widthMm, rot ? p.widthMm : p.heightMm, paper.width / 100, paper.height / 100, scale);
      content = Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: r.left * k,
            top: r.top * k,
            width: r.width * k,
            height: r.height * k,
            child: RotatedBox(
              quarterTurns: rot ? 1 : 0,
              // Gray preview when printing grayscale, so the screen matches the paper.
              child: ColorFiltered(
                colorFilter: color
                    ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                    : const ColorFilter.matrix([0.3, 0.59, 0.11, 0, 0, 0.3, 0.59, 0.11, 0, 0, 0.3, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0]),
                child: image ??
                    FutureBuilder<Uint8List>(
                      future: d.thumbnail(pageIndex ?? shown),
                      builder: (_, snap) => snap.hasData
                          ? Image.memory(snap.data!, fit: BoxFit.fill, gaplessPlayback: true)
                          : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: muted))),
                    ),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      label: d == null ? 'Blank page on ${paper.label} paper' : 'Page ${(pageIndex ?? shown) + 1} on ${paper.label} paper. Tap to zoom',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        width: width,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(2),
        ),
        child: content,
      ),
    );
  }

  Widget _row(String label, Widget trailing, {VoidCallback? onTap, bool last = false}) => InkWell(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        border: Border(
          top: const BorderSide(color: line),
          bottom: last ? const BorderSide(color: line) : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: muted)),
          const Spacer(),
          trailing,
        ],
      ),
    ),
  );

  Widget _pill(String label, bool on, VoidCallback tap) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Semantics(
      selected: on,
      button: true,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? ink : Colors.transparent),
          ),
          child: Text(label, style: TextStyle(fontSize: 13, color: on ? ink : muted)),
        ),
      ),
    ),
  );
}
