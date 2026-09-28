import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'services/database/database_service.dart';
import 'services/storage/storage_service.dart';
import 'services/playback/playback_coordinator.dart';
import 'services/share/share_intent_service.dart';
import 'features/navigation/main_navigation_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge system navigation & styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Storage, Hive DB, Playback and Share Intent services
  await StorageService.instance.init();
  await DatabaseService.instance.init();
  await PlaybackCoordinator.instance.init();
  await ShareIntentService.instance.init();

  runApp(const OfflineTubeApp());
}

class OfflineTubeApp extends StatefulWidget {
  const OfflineTubeApp({super.key});

  @override
  State<OfflineTubeApp> createState() => _OfflineTubeAppState();
}

class _OfflineTubeAppState extends State<OfflineTubeApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _updateThemeMode();
  }

  void _updateThemeMode() {
    final modeSetting = DatabaseService.instance.getSetting<String>('theme_mode', 'dark');
    setState(() {
      if (modeSetting == 'light') {
        _themeMode = ThemeMode.light;
      } else if (modeSetting == 'system') {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.dark;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: MainNavigationShell(
        onThemeChanged: _updateThemeMode,
      ),
    );
  }
}
