import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/models/settings_model.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/media_kit_setup.dart';
import 'core/services/settings_service.dart';
import 'features/update/data/update_provider.dart';
import 'features/update/data/update_service.dart';
import 'features/update/presentation/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait on launch; video player overrides per-screen.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Boot order matters:
  //  1. media_kit native engine (MPV/FFmpeg) — must be before runApp.
  MediaKitSetup.init();

  //  2. Persisted settings (synchronous after first init).
  await SettingsService.init();

  //  3. Clean up any leftover OTA APK from a previous update.
  //     SAFETY: only deletes files matching "Phantek_Gallery_v*.apk" pattern.
  await UpdateService.instance.cleanupAllApks();

  runApp(const ProviderScope(child: PhantekGalleryApp()));
}

class PhantekGalleryApp extends ConsumerStatefulWidget {
  const PhantekGalleryApp({super.key});

  @override
  ConsumerState<PhantekGalleryApp> createState() => _PhantekGalleryAppState();
}

class _PhantekGalleryAppState extends ConsumerState<PhantekGalleryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-check for OTA update once on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsNotifierProvider);
      if (settings.autoCheckUpdate) {
        ref
            .read(updateNotifierProvider.notifier)
            .checkForUpdate(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Clean up leftover APK whenever user returns to app after an install.
    if (state == AppLifecycleState.resumed) {
      UpdateService.instance.cleanupAllApks();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);

    final darkTheme = switch (settings.themeMode) {
      AppThemeMode.amoled => AppTheme.amoled,
      AppThemeMode.amoledSakura => AppTheme.amoledSakura,
      _ => AppTheme.dark,
    };

    final flutterThemeMode = switch (settings.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.dark ||
      AppThemeMode.amoled ||
      AppThemeMode.amoledSakura =>
        ThemeMode.dark,
    };

    return MaterialApp(
      title: 'Phantek Gallery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: darkTheme,
      themeMode: flutterThemeMode,
      onGenerateRoute: generateRoute,
      initialRoute: AppRoutes.gallery,
      builder: (context, child) => AnimatedTheme(
        data: Theme.of(context),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        child: UpdateListener(
          // Wraps the entire widget tree so update dialogs can appear
          // over any screen without needing a navigator key.
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
