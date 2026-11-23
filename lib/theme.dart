import 'package:flutter/material.dart';

// Colors from the "Imprenta screens" design canvas.
const ink = Color(0xFF2A2A28);
const muted = Color(0xFF6B6B66);
const line = Color(0xFFECECE7);
const ground = Color(0xFFFAFAF8);
const ok = Color(0xFF3E9B6A);
const mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: ink);

final appTheme = ThemeData(
  scaffoldBackgroundColor: ground,
  colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: ground),
  appBarTheme: const AppBarTheme(
    backgroundColor: ground,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: ink),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: ink)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: ground,
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: muted, minimumSize: const Size.fromHeight(44)),
  ),
);
