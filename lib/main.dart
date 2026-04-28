import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWeb;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'services/database_service.dart';
import 'services/notifications/alert_notifier.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'services/theme_service.dart';
import 'ui/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFactory();
  await AlertNotifier.instance.init();

  if (_isDesktop) {
    await _initWindowAndTray();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(databaseService: DatabaseService.instance)..init(),
      child: const RedmineMonitorApp(),
    ),
  );
}

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

Future<void> _initWindowAndTray() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'Redmine Monitor',
    minimumSize: Size(760, 520),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await trayManager.setIcon('assets/icon.png');
  final menu = Menu(
    items: [
      MenuItem(key: 'show', label: 'Abrir Redmine Monitor'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Sair'),
    ],
  );
  await trayManager.setContextMenu(menu);
  await trayManager.setToolTip('Redmine Monitor');
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

class RedmineMonitorApp extends StatefulWidget {
  const RedmineMonitorApp({super.key});

  @override
  State<RedmineMonitorApp> createState() => _RedmineMonitorAppState();
}

class _RedmineMonitorAppState extends State<RedmineMonitorApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMinimize() {
    windowManager.hide();
  }

  @override
  Future<void> onWindowClose() async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechar Redmine Monitor'),
        content: const Text('O que você deseja fazer?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              windowManager.hide();
            },
            child: const Text('Minimizar para o tray'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fechar completamente'),
          ),
        ],
      ),
    );

    if (shouldClose == true) {
      windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return MaterialApp(
      title: 'Redmine Monitor',
      debugShowCheckedModeBanner: false,
      themeMode: _resolveThemeMode(appState.settings.themeMode),
      theme: buildAppTheme(dark: false),
      darkTheme: buildAppTheme(dark: true),
      home: appState.loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : appState.needsOnboarding
              ? const OnboardingScreen()
              : const HomeScreen(),
    );
  }
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
