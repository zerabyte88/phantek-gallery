// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/enums/trash_cleanup_interval.dart';
import 'core/localization/app_language.dart';
import 'core/localization/app_localizations.dart';
import 'core/models/settings_model.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/license_service.dart';
import 'core/services/screen_keeper_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/thumbnail_service.dart';
import 'core/services/trash_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock portrait orientation by default.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  LicenseService.registerLicenses();
  await SettingsService.init();
  await ThumbnailService.init();

  final initialCleanup =
      SettingsService.instance.settings.autoTrashCleanup.inDays;
  if (initialCleanup != null) {
    TrashService().purgeExpired(maxDays: initialCleanup).catchError((_) {});
  }

  // High-capacity imageCache for fast swiping (elevated for 60 FPS performance).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 320 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 1200;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsNotifierProvider);
      if (settings.secureScreen) {
        ScreenKeeperService.setSecure(true);
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    ThumbnailService.instance.trimMemory();
    PaintingBinding.instance.imageCache.clear();
    super.didHaveMemoryPressure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      settingsNotifierProvider.select((s) => s.secureScreen),
      (_, secure) => ScreenKeeperService.setSecure(secure),
    );

    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );
    final language = ref.watch(
      settingsNotifierProvider.select((s) => s.language),
    );

    final darkTheme = switch (themeMode) {
      AppThemeMode.amoledMidnight => AppTheme.amoledMidnight,
      AppThemeMode.amoledSnowfall => AppTheme.amoledSnowfall,
      AppThemeMode.amoledSakura => AppTheme.amoledSakura,
      AppThemeMode.amoledPure ||
      AppThemeMode.system ||
      _ =>
        AppTheme.amoledPure,
    };

    final lightTheme = switch (themeMode) {
      AppThemeMode.light => AppTheme.light,
      AppThemeMode.cleanLight ||
      AppThemeMode.system ||
      _ =>
        AppTheme.cleanLight,
    };

    final flutterThemeMode = switch (themeMode) {
      AppThemeMode.light || AppThemeMode.cleanLight => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.amoledSnowfall ||
      AppThemeMode.amoledMidnight ||
      AppThemeMode.amoledPure ||
      AppThemeMode.amoledSakura =>
        ThemeMode.dark,
    };

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Phantek Gallery',
      debugShowCheckedModeBanner: false,
      locale: language.locale ?? const Locale('en'),
      supportedLocales: AppLanguage.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: flutterThemeMode,
      onGenerateRoute: generateRoute,
      initialRoute: AppRoutes.gallery,
      builder: (context, child) => AnimatedTheme(
        data: Theme.of(context),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
