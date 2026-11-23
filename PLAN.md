# Imprenta: build plan

An Android app that prints PDFs and images to an HP 580 printer over WiFi Direct, at any paper size: Letter, A4, Legal (8.5x14 in), Long/Folio (8.5x13 in) and custom sizes.

## The problem
- The HP driver on the laptop prints Legal and 8.5x13 correctly, so the printer hardware supports those sizes.
- On the phone (HP Print Service Plugin, Mopria, HP Smart), long pages come out cut. Android's print service only offers the sizes the printer reports over IPP and often falls back to Letter or A4, so the bottom of the page gets cropped.
- Fix: the app builds the print job itself and sends it straight to the printer over IPP, with the exact paper size set. It skips Android's print service entirely.

## Stack
- **Flutter** (`D:\flutter`) for the UI, document handling and the IPP client (Dart).
- **Kotlin** (a small platform channel) for WiFi Direct and network binding only.
- Test on a **physical Android phone**. Emulators can't do WiFi Direct.
- Free stack only. No backend, no accounts. Everything runs on the phone.

## How it works
```
Phone app
 ├─ Kotlin: join the printer's WiFi Direct network (DIRECT-xx-HP ...), bind the app's traffic to it
 ├─ Dart IPP client: HTTP POST to http://<printer-ip>:631/ipp/print (Content-Type: application/ipp)
 │    1. Get-Printer-Attributes → which paper sizes and file formats the printer accepts
 │    2. Print-Job → document + media / media-col (exact size) + copies + orientation + scaling
 └─ Document pipeline: PDF/image → re-laid-out PDF at the exact page size (or raster if needed)
```

### Key technical facts
- WiFi Direct printer IP is usually `192.168.223.1`. Confirm on the printer's network config page or by mDNS (`_ipp._tcp`).
- IPP runs over plain HTTP on port 631, so the app needs a `network_security_config.xml` that allows cleartext to the printer's IP only.
- Paper size names (PWG):
  - Letter: `na_letter_8.5x11in`
  - Legal: `na_legal_8.5x14in`
  - Long/Folio 8.5x13: `na_foolscap_8.5x13in`
  - A4: `iso_a4_210x297mm`
  - Custom: `media-col` → `media-size` with `x-dimension` / `y-dimension` in hundredths of a mm (Legal = 21590 x 35560, 8.5x13 = 21590 x 33020)
- The document format must be one the printer lists in `document-format-supported`. Prefer `application/pdf`. If it isn't listed, render pages to `image/pwg-raster` or `image/urf` (Apple raster).
- Android permissions: `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`, `NEARBY_WIFI_DEVICES` (Android 13+), `ACCESS_FINE_LOCATION` (Android 12 and below).
- Two ways to reach the printer (Phase 1 decides which):
  - **A. Join its WiFi Direct hotspot** with `WifiNetworkSpecifier` (Android 10+) plus `ConnectivityManager.bindProcessToNetwork`. Simpler and works with most HP printers.
  - **B. Full WiFi P2P** with `WifiP2pManager` (discover peers, connect, read group-owner IP). Fallback if A fails.
  - Bonus: if the phone and printer are already on the same home WiFi, no WiFi Direct is needed. Just discover over mDNS.

## Phases
Confirm each phase with Dewdew before starting the next.

### Phase 1: Printer check (proof it can work)
Goal: find out what the printer accepts over IPP. This decides if the rest of the plan works.
- [x] `flutter create --org ph.dewdew --project-name imprenta .` in this folder
- [x] Add `kotlin.incremental=false` to `android/gradle.properties` (pub cache on C:, project on D:)
- [x] Kotlin channel `imprenta/wifi`: `connectToPrinter(ssid, passphrase)`, `disconnect()`, `getNetworkInfo()`
- [x] Permissions: none at runtime. `WifiNetworkSpecifier` only needs normal manifest permissions; Android shows its own "join network" dialog
- [x] Dart IPP encoder/decoder (`lib/ipp/ipp.dart`, tested in `test/ipp_test.dart`): request building, attribute groups, response parsing. Write it ourselves (~200–300 lines) so we control every attribute.
- [x] Screen "Printer check": connect → send Get-Printer-Attributes → show `media-supported`, `media-size-supported` (custom range), `document-format-supported`, `printer-make-and-model`, `sides-supported`, `print-scaling-supported`
- [x] Button to export the raw attribute list as text (for debugging)
- **Done when:** the phone lists the printer's real paper sizes and formats. Record the results under "Printer findings" below.

### Phase 2: Test print
- [x] Generate the test page in-app (rulers, a border 5 mm from each edge, the size label) at the selected size. Rendered as a 300 dpi grayscale image and sent as PWG raster (`lib/print/`), since the printer has no PDF support.
- [x] Print-Job with the matching `media` keyword. `media-col` custom size is built and unit-tested (custom sizes on the Paper screen use it) but not yet printed on paper.
- [x] Show the job status (Get-Job-Attributes) and printer errors (paper mismatch, out of paper), plus Cancel-Job
- **Done when:** a Legal and an 8.5x13 test page come out with the full border visible, nothing cut.
- **Result (2026-11-23):** 8.5x13 printed with all four borders, nothing cut. Legal skipped by Dewdew (no Legal paper loaded); it uses the same path with a different keyword.
- If the printer rejects the size over IPP: try `media-col` custom size, then raster format, then (last resort) research HP's PCL path like the laptop driver uses.

### Phase 3: Real documents
- [x] Pick a file: PDF, JPG, PNG. Android's own picker via Kotlin (`imprenta/files` channel), no `file_picker` package
- [x] Also accept files shared from other apps (Share / Open with → Imprenta). Built, not yet tested on the phone
- [x] Re-layout to the target page: fit, fill, or 100% (`lib/documents/layout.dart`). Margins skipped: the printer's own hardware margin applies
- [x] Page range ("1-3, 5") and copies
- [x] Preview each page at the real paper aspect ratio (`printing` package renders PDF pages)
- [x] Rasterize to PWG (grayscale, 300 dpi) since the printer has no PDF support
- **Result (2026-11-23):** 2-page Letter PDF printed on 8.5x13 from the phone, both pages. A busy printer holds the request open, so the app now waits for "idle", clears its own stuck jobs after 30 s, and waits up to 3 min for the reply.
- Word (.doc/.docx) → PDF converter: **cancelled by Dewdew.** Offline conversion isn't faithful and online needs mobile data. Users export to PDF from Word/Docs.
- Known limits: grayscale only (color is Phase 4); whole job is held in memory (many photo pages could run out); photos treated as 300 dpi for "100%".

### Phase 4: Custom size UI and settings
- [x] Paper presets: Letter, A4, Legal, Long 8.5x13, plus "Custom" (width x height in inches or mm), checked against the printer's range
- [x] Save custom sizes (up to 6, long-press to forget), last paper, color, quality and the printer's WiFi name/password/IP (`shared_preferences`, on the phone only)
- [x] Orientation (automatic: landscape pages turn sideways), color/grayscale (PWG srgb_8 / sgray_8), quality draft/normal/high (`print-quality`)
- [x] Clear error messages (`lib/print/errors.dart`): can't reach printer, printer slow (may still print), unsupported setting, busy
- Built 2026-11-23. Final test: release APK, color test page on 8.5x13 printed correctly (color squares and full border, confirmed by Dewdew); app reopens straight on the print screen with settings kept.

### Phase 5: Portfolio polish
- [x] App icon and name (adaptive vector icon: a tall 8.5x13 sheet; label "Imprenta")
- [ ] README with screenshots and "Problem I solved" (text written; screenshots after the final test)
- [ ] Release APK on GitHub Releases (APK builds, 47.6 MB, signed with the debug key; GitHub push pending)
- [ ] 30-second demo video (Dewdew records)

## Project structure (target)
```
lib/
  main.dart
  app.dart
  ipp/            ipp_encoder.dart, ipp_decoder.dart, ipp_client.dart, ipp_attributes.dart
  printer/        printer_connection.dart (platform channel), printer_capabilities.dart
  documents/      document_loader.dart, page_layout.dart, rasterizer.dart
  models/         paper_size.dart, print_settings.dart
  screens/        printer_check_screen.dart, home_screen.dart, print_settings_screen.dart, preview_screen.dart
android/app/src/main/kotlin/.../
  MainActivity.kt
  WifiPrinterPlugin.kt
android/app/src/main/res/xml/network_security_config.xml
```

## Packages (planned)
`http`, `file_picker`, `pdf`, `printing` (preview/rasterizing only, not its print dialog), `shared_preferences`, `permission_handler`, `receive_sharing_intent`. Check each one is current on pub.dev before adding.

## Decisions (locked 2026-11-23)
- [x] App name: **Imprenta**
- [x] Printer: **HP Smart Tank 580**
- [x] Test phone: **Android 13+** → use `NEARBY_WIFI_DEVICES`; route A (`WifiNetworkSpecifier`) first
- [x] State: **plain `setState`** (no Riverpod)
- [ ] Printer's WiFi Direct name/password: Dewdew types it into the app at test time. Never written to any repo file.

## Printer findings
Read from the real printer on 2026-11-23 (Phase 1 passed).
- Model: `HP Smart Tank 580-590 series`
- WiFi Direct: `DIRECT-5B-HP Smart Tank 580-590`, printer IP `192.168.223.1`, IPP at `/ipp/print` port 631
- media-supported includes `na_letter_8.5x11in`, `iso_a4_210x297mm`, **`na_foolscap_8.5x13in`**, **`na_legal_8.5x14in`** (24 sizes total), `media-default` = A4
- Custom size range: width 88.9–215.9 mm, height 127–355.6 mm (`custom_min_3.5x5in` … `custom_max_8.5x14in`)
- document-format-supported: `application/vnd.hp-PCL`, `image/jpeg`, `application/PCLm`, `image/urf`, `image/pwg-raster`, `application/octet-stream`. **No `application/pdf`**: Phase 2 must send PWG raster (or JPEG for a quick first test).
- One-sided only. Scaling: auto, auto-fit, fill, fit, none. Color: color, monochrome and others. Resolution: 300/600/1200 dpi.
- Networking: Dart sockets don't follow `bindProcessToNetwork` on this phone (Oppo CPH2773), so IPP goes over Kotlin `Network.openConnection`. If the app's WiFi join fails, joining the printer WiFi in Android settings works too.

## Known limits
- If the printer's firmware or tray can't take a size, no app can force it. The app works within what the printer reports.
- WiFi Direct disconnects the phone from regular WiFi while printing (Android limitation on most phones).

## Git
- Repo: `dewdew-del/imprenta` (create when Phase 2 works)
- No AI attribution in commits, PRs or pushed files. Keep `CLAUDE.md` and `.claude/` out of the repo (add to `.gitignore` after `flutter create`).
