import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/models/settings_model.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/media_kit_setup.dart';
import 'core/services/settings_service.dart';
import 'core/services/thumbnail_service.dart';
import 'core/services/trash_service.dart';
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

  //  4. Clean up any expired items in trash (> 30 days old).
  TrashService().purgeExpired().catchError((_) {});

  //  5. Balanced imageCache: 256 MB and 100 entries for instant high-res swiping.
  //     RAM is trimmed immediately on AppLifecycleState.paused / hidden.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

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
    if (state == AppLifecycleState.resumed) {
      UpdateService.instance.cleanupAllApks();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Trim RAM cache when app is minimized to save battery and prevent OS kill
      ThumbnailService.instance.trimMemory();
      PaintingBinding.instance.imageCache.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );

    final darkTheme = switch (themeMode) {
      AppThemeMode.amoled => AppTheme.amoled,
      AppThemeMode.amoledSakura => AppTheme.amoledSakura,
      _ => AppTheme.dark,
    };

    final flutterThemeMode = switch (themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.dark ||
      AppThemeMode.amoled ||
      AppThemeMode.amoledSakura =>
        ThemeMode.dark,
    };

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
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
