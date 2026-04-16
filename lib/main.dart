import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWeb;

import 'services/database_service.dart';
import 'services/notifications/alert_notifier.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFactory();
  await AlertNotifier.instance.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(databaseService: DatabaseService.instance)..init(),
      child: const RedmineMonitorApp(),
    ),
  );
}

Future<void> _initDatabaseFactory() async {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

class RedmineMonitorApp extends StatelessWidget {
  const RedmineMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A3A6B),
      secondary: const Color(0xFFF59E0B),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      secondary: const Color(0xFFF59E0B),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Redmine Monitor',
      debugShowCheckedModeBanner: false,
      themeMode: _resolveThemeMode(appState.settings.themeMode),
      theme: _buildTheme(lightScheme, isDark: false),
      darkTheme: _buildTheme(darkScheme, isDark: true),
      home: const HomeScreen(),
    );
  }
}

ThemeData _buildTheme(ColorScheme scheme, {required bool isDark}) {
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF2F7F8),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? const Color(0xFF111827) : scheme.surface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF111827) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.45 : 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}

ThemeMode _resolveThemeMode(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
