import 'package:flutter/material.dart';

import 'documents/document.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.load();
  listenForSharedFiles();
  runApp(MaterialApp(
    title: 'Imprenta',
    debugShowCheckedModeBanner: false,
    theme: appTheme,
    // Set up once: after the first connect, open straight on the print screen.
    home: Settings.printerIp == null ? const ConnectScreen() : HomeScreen(printerIp: Settings.printerIp!),
  ));
}
