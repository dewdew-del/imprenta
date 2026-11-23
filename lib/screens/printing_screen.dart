import 'dart:async';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ipp/ipp.dart';
import '../models/paper_size.dart';
import '../print/errors.dart';
import '../print/pwg_raster.dart';
import '../theme.dart';

const printDpi = 300;

Uint8List _encode((RasterPage, String, int) a) =>
    encodePwgPage(a.$1, dpi: printDpi, pageSizeName: a.$2, totalPages: a.$3);

/// Renders [pageCount] sheets one by one, sends them as one job, and follows it until the printer is done.
class PrintingScreen extends StatefulWidget {
  final String printerIp;
  final PaperSize paper;
  final int copies;
  final String jobName;
  final int pageCount;
  final bool color;
  final int quality; // IPP print-quality: 3 draft, 4 normal, 5 high
  final Future<RasterPage> Function(int sheet) renderSheet;
  const PrintingScreen({super.key, required this.printerIp, required this.paper, required this.copies,
      required this.jobName, required this.pageCount, required this.renderSheet, this.color = false, this.quality = 4});
  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  late final ipp = IppClient(widget.printerIp);
  String title = 'Preparing';
  String? detail;
  String? warning;
  bool finished = false;
  int? jobId;
  Timer? poll;
  bool cancelled = false;
  int failedPolls = 0;

  /// Jobs this app sent while running. Never auto-cleared: they are real prints, just queued.
  static final _sentThisSession = <int>{};

  // job-state enum (RFC 8011)
  static const _states = {3: 'Waiting', 4: 'Held', 5: 'Printing', 6: 'Stopped', 7: 'Cancelled', 8: 'Failed', 9: 'Done'};

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final pwg = widget.paper.pwg ?? '';
      final n = widget.pageCount;
      // shortcut: the whole compressed job sits in memory; fine for text pages, may run out on many photo pages.
      final doc = BytesBuilder(copy: false)..add(pwgFileHeader);
      for (var i = 0; i < n; i++) {
        if (!mounted) return;
        setState(() => title = n > 1 ? 'Preparing ${i + 1} / $n' : 'Preparing');
        final page = await widget.renderSheet(i);
        // Top-level function, not a closure: a closure here drags the State into the isolate and fails.
        doc.add(await compute(_encode, (page, pwg, n)));
      }
      // A busy printer (e.g. a laptop job) holds our request open, so wait until it is idle first.
      for (var waited = 0;; waited++) {
        final pr = (await ipp.getPrinterAttributes(['printer-state'])).group(Tag.printer);
        if (!mounted) return;
        if (pr['printer-state']?.first != 4) break; // 3 idle, 4 processing, 5 stopped
        // After ~30 s, a job of ours left half-sent (e.g. an earlier timeout) is the usual culprit: clear it.
        if (waited == 10) {
          for (final id in await ipp.myActiveJobs()) {
            if (!_sentThisSession.contains(id)) await ipp.cancelJob(id);
          }
        }
        if (waited == 60) throw Exception('Printer stayed busy for 3 minutes. Press X on the printer, then try again.');
        setState(() { title = 'Printer is busy'; detail = 'Waiting for the current print to finish'; });
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (!mounted) return;
      setState(() { title = 'Sending'; detail = null; });
      final id = await ipp.printJob(doc.toBytes(),
          format: 'image/pwg-raster',
          name: widget.jobName,
          jobAttrs: [
            ...mediaAttrs(widget.paper.pwg, widget.paper.width, widget.paper.height),
            IppAttr(Tag.integer, 'copies', [widget.copies]),
            IppAttr(Tag.keyword, 'print-scaling', ['none']),
            IppAttr(Tag.keyword, 'print-color-mode', [widget.color ? 'color' : 'monochrome']),
            IppAttr(Tag.enumeration, 'print-quality', [widget.quality]),
          ]);
      _sentThisSession.add(id);
      // Cancel (or leaving the screen) during upload: the job id only exists now, so cancel it now.
      if (cancelled || !mounted) {
        _sentThisSession.remove(id);
        await ipp.cancelJob(id).catchError((_) {});
        return;
      }
      setState(() { jobId = id; title = 'Printing'; });
      poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (e) {
      _fail(friendlyError(e));
    }
  }

  Future<void> _check() async {
    try {
      final job = await ipp.jobStatus(jobId!);
      final state = job['job-state']?.first as int? ?? 0;
      final reasons = (job['job-state-reasons'] ?? []).whereType<String>().where((r) => r != 'none').toList();
      final printer = (await ipp.getPrinterAttributes(['printer-state-reasons'])).group(Tag.printer);
      final pReasons = (printer['printer-state-reasons'] ?? []).whereType<String>().where((r) => r != 'none').toList();
      if (!mounted) return;
      failedPolls = 0;
      setState(() {
        title = _states[state] ?? 'Printing';
        warning = _warning(pReasons);
        detail = [...reasons, ...pReasons].join(' · ');
        if (state >= 7) {
          finished = true;
          poll?.cancel();
        }
      });
    } catch (e) {
      // A missed poll is fine (the printer can be busy feeding paper), but ~10 s of failures means
      // the job is gone or the phone left the printer's WiFi: stop instead of spinning forever.
      if (!mounted) return;
      if (++failedPolls >= 5) {
        poll?.cancel();
        setState(() { title = 'Check the printer'; detail = "Lost track of this print. ${friendlyError(e)}"; finished = true; });
      } else {
        setState(() => detail = friendlyError(e));
      }
    }
  }

  String? _warning(List<String> reasons) {
    bool has(String s) => reasons.any((r) => r.startsWith(s));
    if (has('media-empty') || has('media-needed')) return 'Load ${widget.paper.label} paper';
    if (has('media-jam')) return 'Paper jam';
    if (has('door-open') || has('cover-open')) return 'Close the printer cover';
    if (has('marker-supply-empty')) return 'Ink is empty';
    return null;
  }

  void _fail(String msg) {
    poll?.cancel();
    // A timeout means the printer got the job but never answered: it can still come out.
    final unsure = msg.startsWith(slowPrinterMessage);
    if (mounted) setState(() { title = unsure ? 'Check the printer' : 'Not printed'; detail = msg; finished = true; });
  }

  Future<void> _cancel() async {
    cancelled = true;
    if (jobId != null && !finished) {
      try {
        await ipp.cancelJob(jobId!);
      } catch (_) {
        // shortcut: if cancel fails the job may already be done; we just leave the screen.
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paper;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                // printer slot with the sheet coming out at the real paper ratio
                Container(width: 200, height: 6, decoration: BoxDecoration(color: const Color(0xFFD4D4CF), borderRadius: BorderRadius.circular(3))),
                Container(
                  width: 130,
                  height: 130 / p.aspect * 0.75,
                  decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: line), right: BorderSide(color: line), bottom: BorderSide(color: line))),
                ),
                const SizedBox(height: 32),
                Semantics(liveRegion: true, child: Text(title, style: const TextStyle(fontSize: 20, color: ink))),
                const SizedBox(height: 6),
                Text('${p.label}${widget.copies > 1 ? ' · ${widget.copies} copies' : ''}', style: mono.copyWith(fontSize: 12, color: muted)),
                const SizedBox(height: 32),
                if (!finished) const SizedBox(width: 160, child: LinearProgressIndicator(minHeight: 2, color: ink, backgroundColor: line)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(detail!, textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 11, color: muted)),
                ],
              ]),
            ),
            if (warning != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFFBF1E6), borderRadius: BorderRadius.circular(10)),
                child: Text(warning!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF7A4210))),
              ),
            TextButton(onPressed: _cancel, child: Text(finished ? 'Done' : 'Cancel')),
          ]),
        ),
      ),
    );
  }
}
