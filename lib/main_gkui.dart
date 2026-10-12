import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'gkui/diagnostics.dart';
import 'gkui/plex_api.dart';

part 'gkui/app/shared.dart';
part 'gkui/app/controller.dart';
part 'gkui/app/playback.dart';
part 'gkui/app/start_screens.dart';
part 'gkui/app/shell.dart';
part 'gkui/app/settings_pane.dart';
part 'gkui/app/media_widgets.dart';
part 'gkui/app/details_screen.dart';
part 'gkui/app/common_widgets.dart';
part 'gkui/app/diagnostics_pane.dart';

const String buildLabel = 'Plezy GKUI 1.2.13 / GitHub certificate fix';
const String sourceLabel = 'Plezy 1.8.1 / GKUI compatibility fork';
const String toolchainLabel = 'Flutter 3.19.6 / ExoPlayer 2.19.1 / API 19';
const MethodChannel nativeChannel =
    MethodChannel('com.jialim.plezygkui/diagnostics');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlexApi.installLegacyTrust();
  PaintingBinding.instance.imageCache.maximumSize = 48;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 16 * 1024 * 1024;
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const PlezyGkuiApp());
}

/// The head unit's dark theme, shared by the app and the screen tests.
ThemeData gkuiTheme() {
  const scheme = ColorScheme.dark(
    primary: Color(0xFFE5A00D),
    secondary: Color(0xFFE5A00D),
    surface: Color(0xFF171717),
    background: Color(0xFF0B0B0B),
    error: Color(0xFFFF6B6B),
  );
  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    fontFamily: 'PlezySans',
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(minimumSize: const Size(96, 54)),
    ),
  );
}

class PlezyGkuiApp extends StatelessWidget {
  const PlezyGkuiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plezy GKUI',
      debugShowCheckedModeBanner: false,
      theme: gkuiTheme(),
      home: const GkuiRoot(),
    );
  }
}
