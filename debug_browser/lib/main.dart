import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/providers.dart';
import 'core/tool_providers.dart';
import 'branding/splash_page.dart';
import 'features/browser/home_page.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // Hook a crash reporter (e.g. Sentry/Crashlytics) here.
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught platform error: $error\n$stack');
      return true;
    };

    await Hive.initFlutter();
    try {
      await Hive.openBox(settingsBoxName);
    } catch (e) {
      // Corrupted box: reset rather than refuse to start.
      debugPrint('Settings box corrupted, resetting: $e');
      await Hive.deleteBoxFromDisk(settingsBoxName);
      await Hive.openBox(settingsBoxName);
    }

    runApp(const ProviderScope(child: DebugBrowserApp()));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class DebugBrowserApp extends ConsumerWidget {
  const DebugBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Debug Browser',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      navigatorKey: appNavigatorKey,
      home: const SplashPage(next: HomePage()),
      debugShowCheckedModeBanner: false,
    );
  }
}
